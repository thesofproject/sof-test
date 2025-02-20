function test_passed = check_wav_file_snr(bat_fn, test_tone_f, min_snr, log_dir)

% check_wav_file_snr(bat_fn, test_tone_f, min_snr, log_dir)
%
% Inputs
%   bat_fn        Input wav file to analyze
%   test_tone_f   Sine frequency in test, use 0 for automatic, default 0
%   min_snr       Minimum SNR to pass test, default 46 dB (recommend 80 dB)
%   log_dir       Directory for plot files, default /tmp
%
% Output
%   test_passed   Returns 1 if passed, 0 if failed
%

% SPDX-License-Identifier: BSD-3-Clause
% Copyright(c) 2023 Intel Corporation. All rights reserved.

if nargin < 4
	log_dir = '/tmp';
end

if nargin < 3
	param.min_snr = 46;
else
	param.min_snr = min_snr;
end

if nargin < 2
	% Automatic find of tone frequency
	test_tone_f = 0;
end

if nargin < 1
	error('Need to provide file name to analyze');
end

if exist('OCTAVE_VERSION', 'builtin')
	pkg load signal;
end

param.t_ignore_from_start = 10e-3;
param.t_ignore_from_end = 0;
param.t_step = 1e-3;
param.n_fft = 1024;
param.max_snr_drop = 6;
param.level_differential_tol = 1e-3;
param.visible = 'off';
param.do_plot = 1;
param.do_print = 1;
param.print_dir = log_dir;
test_passed = true;

fprintf(1, 'Used parameters:\n');
fprintf(1, 't_ignore_from_start %.1f ms\n', param.t_ignore_from_start * 1e3);
fprintf(1, 't_ignore_from_end %.1f ms\n', param.t_ignore_from_end * 1e3);
fprintf(1, 't_step %.1f ms\n', param.t_step * 1e3);
fprintf(1, 'n_fft %d\n', param.n_fft);
fprintf(1, 'max_snr_drop %.1f dB\n', param.max_snr_drop);
fprintf(1, 'min_snr %.1f dB\n', param.min_snr);
fprintf(1, 'level_differential_tol %g\n', param.level_differential_tol);
fprintf(1, '\n');

% Read audio
fprintf(1, 'Loading file %s\n', bat_fn);
[x, fs, channels] = read_audio(bat_fn);
[~, basefn, extfn] = fileparts(bat_fn);
fn = sprintf('%s%s', basefn, extfn);

for ch = 1 : channels
	%s Sanity check
	if ~signal_found(x(:, ch))
		fprintf(1, 'Error: Channel %d has no signal\n', ch);
		error('Failed.');
	end

	% STFT
	[stft, param] = compute_stft(x(:, ch), fs, param);

	% Check frequency, get STFT frequency index
	[signal_idx, tone_f] = find_test_tone(stft, param, test_tone_f);

	% Get levels and SNR estimates
	meas = get_tone_levels(stft, param, signal_idx);

	% Checks for levels data from FFTs, after stable level
	% and time to ignore
	meas = check_tone_levels(param, meas);

	% Check begin of wav file, before stable level
	meas = check_time_domain(x(:,ch), param, meas);

	% If poor SNR check if there's periodic glitches
	meas = check_glitch_periodicity(x(:,ch), param, meas, ch);

	% Plot
	fnstr = sprintf('%s_ch%d', fn, ch);
	idstr = sprintf('%s ch%d', fn, ch);
	if meas.num_glitches > 0
		plot_glitch(param, x(:, ch), meas, idstr, fnstr);
	end

	all_stft(ch, :, :) = stft;
	all_meas(ch) = meas;
	if meas.success == false
		test_passed = false;
	end
end

plot_specgram(param, all_stft, fn, channels);
plot_levels(param, all_meas, fn, channels);


fprintf(1, 'Ch, Pass, Frequency, SNR min, SNR avg, Signal avg, Noise avg, Noise max, Num glitch, 1st glitch\n');

for ch = 1 : channels
	meas = all_meas(ch);
	fprintf(1, '%d, %2d,     %5.0f,  %6.1f,  %6.1f,     %6.1f,    %6.1f,    %6.1f,     %6d,  %8.3f\n', ...
		ch, meas.success, tone_f, meas.min_snr_db, meas.mean_snr_db, ...
		meas.mean_signal_db, meas.mean_noise_db, ...
		meas.max_noise_db, meas.num_glitches, meas.t_glitch);
end

if test_passed
	fprintf(1, 'Passed\n');
else
	error('Failed');
end

end

%
% Helper functions
%

function meas = check_time_domain(x, param, meas)

% High-pass filter to find glitches
idx_end = round(1 + meas.t_start * param.fs);
[b, a] = butter(2, 0.5, 'high');
y = x(1 : idx_end);
z = abs(filter(b, a, y));

% Skip start transient
s = max(abs(y));
idx1 = find(z < 0.01 * s, 1, 'first');
idx2 = find(z(idx1 : end) > 0.02 * s);

if ~isempty(idx2)
	meas.success = false;
	meas.num_glitches = meas.num_glitches + 1;
	meas.t_glitch = (idx1 + idx2(1) - 1) / param.fs;
end

end

function meas = check_glitch_periodicity(x, param, meas, ch)

if meas.success
	return
end

i1 = round(param.fs * param.t_ignore_from_start);
i2 = length(x) - round(param.fs * param.t_ignore_from_end);
[b, a] = butter(2, 0.95, 'high');
y = abs(filter(b, a, x));
z = y(i1:i2);
thr = mean(z) + std(z);
[~, locs]= findpeaks(z, 'MinPeakHeight', thr);
dlocs = diff(locs);
if isempty(dlocs)
	return
end

[counts, centers] = hist(dlocs);
[counts, i] = sort(counts, 'descend');
centers = centers(i) * 1e3 / param.fs;
thr = mean(counts) + std(counts);
idx = find(counts > thr);
if ~isempty(idx)
	fprintf(1, 'Ch%d periodic glitches possibly every', ch)
	for i = 1 : length(idx)
		fprintf(' %.1f ms (n = %d)', centers(idx(i)), counts(idx(i)));
	end
	fprintf(1, '\n');
end

end

function success = signal_found(x)

% All zeros or DC
if abs(min(x) - max(x)) < eps
	success = 0;
else
	success = 1;
end

end

function meas = get_tone_levels(stft, param, signal_idx)

signal_i1 = signal_idx - param.win_spread;
signal_i2 = signal_idx + param.win_spread;
if signal_i1 < 1
	error('Too low tone frequency, increase FFT length');
end

signal_db = zeros(param.n_stft, 1);
noise_db = zeros(param.n_stft, 1);
snr_db = zeros(param.n_stft, 1);
for i = 1 : param.n_stft
	% Integrate signal power
	p_signal = sum(stft(signal_i1 : signal_i2, i));

	% Integrate noise power, but replace DC and signal with
	% average noise level.
	noise = stft(:, i);
	noise_avg = mean(noise(signal_i2 : end));
	noise(1 : param.win_spread) = noise_avg;
	noise(signal_i1 : signal_i2) = noise_avg;
	p_noise = sum(noise);

	% Sign, noise, and "SNR" as dB
	signal_db(i) = 10*log10(p_signal);
	noise_db(i) = 10*log10(p_noise);
	snr_db(i) = signal_db(i) - noise_db(i);
end

meas.noise_db = noise_db - param.win_gain;
meas.signal_db = signal_db - param.win_gain;
meas.snr_db = signal_db - noise_db;

end

function meas = check_tone_levels(param, meas)

meas.t_glitch = 0;
meas.num_glitches = 0;
meas.success = true;

% Find when level stabilizes, from start ramp. Signal level is
% stable where differential of level is less than required
% tolerance.
da = abs(diff(meas.signal_db));
i0 = find(da < param.level_differential_tol, 1, 'first');
if isempty(i0)
	error('Signal level is not stable');
end

i1 = i0 + param.t_ignore_from_start / param.t_step;
i2 = param.n_stft - param.t_ignore_from_end / param.t_step;

meas.t_start = (i1 - 1) * param.t_step;
meas.t_end = (i2 - 1) * param.t_step;
meas.mean_signal_db = mean(meas.signal_db(i1 :i2));
meas.mean_noise_db = mean(meas.noise_db(i1 :i2));
meas.mean_snr_db = mean(meas.snr_db(i1 :i2));
meas.max_noise_db = max(meas.noise_db(i1 :i2));
meas.min_snr_db = min(meas.snr_db(i1 :i2));

% Find glitches from SNR curve drops
idx = find(meas.snr_db(i1:i2) < meas.mean_snr_db - param.max_snr_drop);

if ~isempty(idx)
	idx = idx + i1 - 1;
	didx = diff(idx);
	meas.num_glitches = 1 + length(find(didx > 2));
	start_idx = idx(1);
	cidx = find(didx(1:end) > 1, 1, 'first');
	if isempty(cidx)
		end_idx = idx(end);
	else
		end_idx = idx(cidx);
	end
	meas.t_glitch = param.t_step * mean([start_idx end_idx] - 1) + ...
		0.5 * param.n_fft / param.fs;
	meas.success = false;
end

if meas.min_snr_db < param.min_snr
	meas.success = false;
end

end

function [signal_idx, tone_f] = find_test_tone(stft, param, test_tone_f)

if test_tone_f > 0
	err_ms = (param.f - test_tone_f) .^ 2;
	signal_idx = find(err_ms == min(err_ms));
	tone_f = param.f(signal_idx);
	return
end

i1 = 1 + param.t_ignore_from_start / param.t_step;
i2 = param.n_stft - param.t_ignore_from_end / param.t_step;
signal_idx_all = zeros(i2 - i1 + 1, 1);
for i = i1 : i2
	signal_idx_all(i - i1 + 1) = find(stft(:, i) == max(stft(:, i)),1, 'first');
end

signal_idx = round(mean(signal_idx_all));
tone_f = param.f(signal_idx);

end

function [x, fs, channels] = read_audio(fn)

[x, fs] = audioread(fn);
sx = size(x);
channels = sx(2);

end

function [stft, param] = compute_stft(x, fs, param)

sx = size(x);
if sx(2) > 1
	error('One channel only');
end

frames = sx(1);
win = kaiser(param.n_fft, 20);
param.win_spread = 7;
param.win_gain = -13.0379;
param.fs = fs;

param.n_step = fs * param.t_step;
param.n_stft = floor((frames - param.n_fft) / param.n_step);
n_half_fft = param.n_fft / 2 + 1;
scale = 1 / param.n_fft;
param.f = linspace(0, fs/2, n_half_fft);
param.t = (0 : (param.n_stft - 1)) * param.t_step;
stft = zeros(n_half_fft, param.n_stft);

for i = 1 : param.n_stft
	i1 = (i - 1) * param.n_step + 1;
	i2 = i1 + param.n_fft - 1;
	s1 = fft(x(i1 : i2) .* win) * scale;
	s2 = s1(1 : n_half_fft);
	s = s2 .* conj(s2);
	stft(:, i) = s;
end

end

function fh = plot_glitch(param, x, meas, idstr, fnstr)

if param.do_plot
	fh = figure('Visible', param.visible);
	t_ms = 1e3 * (0:(length(x) - 1)) / param.fs;
	plot(t_ms, x);
	t_start = max(meas.t_glitch - 2 * param.t_step, 0);
	t_end = t_start + 4 * param.t_step;
	ax = axis();
	axis([1e3 * t_start 1e3 * t_end ax(3:4)]);
	grid on;
	title(idstr, 'interpreter', 'none');
	xlabel('Time (ms)');
	ylabel('PCM sample values');
	if param.do_print
		pfn = sprintf('%s/%s_glitch.png', param.print_dir, fnstr);
		print(pfn, '-dpng');
	end
end

end

function fh = plot_specgram(param, all_stft, fnstr, channels)

if param.do_plot
	fh = figure('Visible', param.visible);
	for n = 1 : channels
		subplot(channels, 1, n);
		clims = [-140 0];
		stft = squeeze(all_stft(n, :, :));
		imagesc(1e3 * param.t, param.f, 10*log10(stft + eps), clims);
		set(gca, 'ydir', 'normal');
		colorbar;
		grid on;
		if n == 1
			title(fnstr, 'interpreter', 'none');
		end
		lstr = sprintf('Ch%d freq (Hz)', n);
		ylabel(lstr);
	end
	xlabel('Time (ms)');
	if param.do_print
		pfn = sprintf('%s/%s_specgram.png', param.print_dir, fnstr);
		print(pfn, '-dpng');
	end

end

end

function fh = plot_levels(param, meas, fnstr, channels)

if param.do_plot
	t_ms = 1e3 * param.t;
	fh = figure('Visible', param.visible);
	subplot(3, 1, 1);
	hold on;
	vmin = 1000;
	vmax = -1000;
	for n = 1 : channels
		plot(t_ms, meas(n).snr_db);
		vmin = min(min(meas(n).snr_db), vmin);
		vmax = max(max(meas(n).snr_db, vmin));
	end
	plot(1e3 * [meas(1).t_start meas(1).t_end], [param.min_snr param.min_snr], '--');
	hold off
	y_min = floor(vmin / 10) * 10;
	y_max = ceil(vmax / 10) * 10 + 40;
	axis([0 t_ms(end) y_min y_max]);
	grid on;
	ylabel('SNR (dB)');
	title(fnstr, 'interpreter', 'none');
	ch1 = sprintf('ch1 %.0f dB avg %.0f dB min', ...
		meas(1).mean_snr_db, meas(1).min_snr_db);
	switch channels
		case 1
			legend(ch1);
		otherwise
			ch2 = sprintf('ch1 %.0f dB avg %.0f dB min', ...
				meas(2).mean_snr_db, meas(2).min_snr_db);
			legend(ch1, ch2);
	end

	subplot(3, 1, 2);
	hold on
	vmin = 1000;
	vmax = -1000;
	for n = 1 : channels
		plot(t_ms, meas(n).signal_db);
		vmax = max(max(meas(n).signal_db), vmax);
		vmin = min(min(meas(n).signal_db), vmin);
	end
	hold off
	y_min = floor(vmin) - 1;
	y_max = ceil(vmax) + 1;
	axis([0 t_ms(end) y_min y_max]);
	grid on;
	ylabel('Signal (dBFS)');
	subplot(3, 1, 3);
	hold on
	vmin = 1000;
	vmax = -1000;
	for n = 1 : channels
		plot(t_ms, meas(n).noise_db);
		vmax = max(max(meas(n).noise_db), vmax);
		vmin = min(min(meas(n).noise_db), vmin);
	end
	hold off
	y_min = floor(vmin / 10) * 10;
	y_max = ceil(vmax / 10) * 10;
	axis([0 t_ms(end) y_min y_max]);
	grid on;
	ylabel('Noise (dBFS)');
	xlabel('Time (ms)');

	if param.do_print
		pfn = sprintf('%s/%s_level.png', param.print_dir, fnstr);
		print(pfn, '-dpng');
	end

end

end
