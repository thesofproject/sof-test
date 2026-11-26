function noise_capture_check(fn)

t_min = 2.0; % Min 2.0s long clip
t_skip = 1.0; % Trim out first 1.0s
n_fft = 1024; % 1024 bits FFT
clipped_db = -0.01; % Max. PCM code value in dB
max_offset_db = -80; % Max. DC offset in dB
mask.low_f   = [   0 1000 5000 7000 96000];
mask.low_db  = [-160 -180 -200 -250  -250];
mask.high_f  = [   0 7000 24000 96000];
mask.high_db = [ -20  -30   -50   -60];

%% Octave packages, skip for Matlab
if exist('OCTAVE_VERSION', 'builtin')
	pkg load signal;
end

%% Get audio recording
[x0, fs] = audioread(fn);
n_samples = size(x0, 1);
n_channels = size(x0, 2);
t_clip = n_samples / fs;
if t_clip < t_min
	fprintf(1, 'Error: The clip needs to be at least %.1fs long\n', t_min);
	fail_check(1);
end

%% Trim sample, skip the beginning
x = x0(t_skip * fs + 1:end,:);
n_samples = size(x, 1);

%% Check that all channels contain signal, fail for zero or DC value
failed = 0;
for i = 1:n_channels
	abs_max_diff = max(abs(diff(x(:,i))));
	if abs_max_diff < eps
		fprintf(1, 'Error: Channel %d does not contain signal\n', i);
		failed = 1;
	end
end
fail_check(failed);

%% Check for excessive offset
failed = 0;
for i = 1:n_channels
	offset = 20*log10(abs(mean(x(:,i))));
	if offset > max_offset_db
		fprintf(1, 'Error: Channel %d offset %5.2f is too high\n', i, offset);
		failed = 1;
	end
end
fail_check(failed);

%% Check that channels are unique
failed = 0;
for i = 1:n_channels
	for j = 1:n_channels
		if i == j
			continue
		end
		delta = x(:,i) - x(:,j);
		max_abs_delta = max(abs(delta));
		if max_abs_delta < eps
			fprintf(1, 'Error: Channels %d and %d are identical\n', i, j);
			failed = 1;
		end
	end
end
fail_check(failed);

%% Check that PCM code values are not saturated
failed = 0;
for i = 1:n_channels
	if max(abs(x(:,i))) > 10^(clipped_db/20)
		fprintf(1, 'Error: Channel %d contains clipped samples\n', i);
		failed = 1;
	end
end
fail_check(failed);

%% Check for normal spectra shape
failed = 0;
for i = 1:n_channels
	if fft_check_channel(x, i, fs, mask)
		failed = 1;
	end
end
fail_check(failed);


end

%% Helper functions

function fail_check(fail)

if fail
	quit(1);
end

end

function failed = fft_check_channel(x, ch, fs, mask)

failed = 0;
do_plot = 0;
[f, mdb] = get_fft(x(:,ch), fs);
mask_low = interp1(mask.low_f, mask.low_db, f)';
mask_high = interp1(mask.high_f, mask.high_db, f)';
if do_plot
	figure
	plot(f, mdb);
	hold on
	plot(f, mask_low, '--', f, mask_high, '--');
	hold off
	grid on;
end

idx = find(mdb < mask_low);
if ~isempty(idx)
	f_min = f(idx(1));
	f_max = f(idx(end));
	fprintf(1, 'Error: Channel %d is below mask in %.0f - %0.f Hz\n', ...
		ch, f_min, f_max);
	failed = 1;
end
idx = find(mdb > mask_high);
if ~isempty(idx)
	f_min = f(idx(1));
	f_max = f(idx(end));
	fprintf(1, 'Error: Channel %d is above mask in %.0f - %0.f Hz\n', ...
		ch, f_min, f_max);
	failed = 1;
end

end

function [f, mdb] = get_fft(x, fs)

n_fft = 8192;
win = kaiser(n_fft, 20);
idx = length(x) - n_fft + 1;
s = fft(x(idx:end) .* win) / n_fft;
s = s(1:n_fft/2 + 1);
f = linspace(0, fs/2, length(s));
mdb = 20*log10(abs(s));

end
