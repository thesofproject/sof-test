function check_volume_levels(cmd, fn1, fn2, fn3, do_plot)

% check_volume_levels(cmd, fn1, fn2, fn3)
%
% Inputs
%   cmd - Use 'generate' or 'analyze'
%   fn1 - File name for sine wave to generate or first record file name to analyze
%   fn2 - File name to analyze 2nd
%   fn3 - File name to analyze 3rd
%   do_plot - Plot figure of levels if 1, defaults to 0
%
% E.g.
%   check_volume_levels('generate','sine.wav');
%   check_volume_levels('measure','rec1.wav','rec2.wav','rec3.wav');
%   check_volume_levels('measure','rec1.wav','rec2.wav','rec3.wav', 1);

% SPDX-License-Identifier: BSD-3-Clause
% Copyright(c) 2016 Intel Corporation. All rights reserved.
% Author: Seppo Ingalsuo <seppo.ingalsuo@linux.intel.com>

	if nargin < 5
		do_plot = 0;
	end

	addpath('../../sof/tools/test/audio/std_utils');
	addpath('../../sof/tools/test/audio/test_utils');

	if exist('OCTAVE_VERSION', 'builtin')
		pkg load signal
	end

	switch lower(cmd)
		case 'generate'
			pass = generate(fn1);
			if pass
				fprintf(1, 'done\n');
			else
				error('FAIL');
			end
		case 'measure'
			pass = measure(fn1, fn2, fn3, do_plot);
			if pass
				fprintf(1, 'PASS\n');
			else
				error('FAIL');
			end
		otherwise
			error('Invalid cmd')
	end

end

% Generate a 701 Hz and 1297 Hz -40 dBFS stereo sine wave
% to test volume gain and muting

function pass = generate(fn)
	fprintf('Create sine wave file %s\n', fn)
	fs = 48e3;
	f1 = 701;
	f2 = 1297;
	a = 10^(-40/20);
	t = 60;
	x1 = multitone(fs, f1, a, t);
	x2 = multitone(fs, f2, a, t);
	x = [x1'; x2']';
	sx = size(x);
	d = (rand(sx(1), sx(2)) - 0.5)/2^15;
	audiowrite(fn, x + d, fs);
	pass = 1;
end


function pass = measure(fn1, fn2, fn3, do_plot)

	% General test defaults
	lm.tgrid = 5e-3;              % Return level per every 5ms
	lm.tlength = 10e-3;           % Use 10 ms long measure window
	lm.sine_freqs = [701 1297];   % The stimulus wav frequencies
	lm.sine_dbfs = [-40 -40];     % The stimulus wav dBFS levels

	% Default gains for test 1
	v1 = [+10   0 -10 -30];
	v2 = [-10 +10   0 -20];
	vmax = +30;
	vnom = 0;
	vmut = -100;
	vmin = -49;
	vol_ch1    = [ vmax v1(1) vnom vmut vnom vmut vmut vmax vmut vmin v2(1) ];
	vol_ch2    = [ vmax v1(2) vnom vmut vnom vmut vmut vmax vmut vmin v2(2) ];
	t1.vctimes = [ 0    1     2    3    4    5    6    7    8    9    10    ];
	t1.volumes = [vol_ch1 ; vol_ch2 ]'; % Merge channels to matrix
	t1.meas = [0.5 0.9]; % Measure levels 0.5s after transition until 0.9s
	t1.vtol = 0.5; % Pass test with max +/- 0.5 dB mismatch

	% Check test 1
	pass1 = level_vs_time_checker(fn1, t1, lm, '1/3', do_plot);

	% Default gains for test 2
	m1 = [vmut vnom vnom vmut];
	m2 = [vnom vmut vmut vnom];
	vol_ch1    = [ v2(1) m1(1) vmut ];
	vol_ch2    = [ v2(2) m1(2) vmut ];
	t2.vctimes = [ 0     1     2    ];
	t2.volumes = [ vol_ch1 ; vol_ch2 ]'; % Merge channels to matrix
	t2.meas = t1.meas; % Same as previous
	t2.vtol = t1.vtol; % Same as previous

	% Check test 2
	pass2 = level_vs_time_checker(fn2, t2, lm, '2/3', do_plot);

	% Default gains for test 3
	vol_ch1    = [ vmut vmut m2(1) vnom ];
	vol_ch2    = [ vmut vmut m2(2) vnom ];
	t3.vctimes = [ 0    1    2     3    ];
	t3.volumes = [ vol_ch1 ; vol_ch2 ]';
	t3.meas = t1.meas; % Same as previous
	t3.vtol = t1.vtol; % Same as previous

	% Check test 3
	pass3 = level_vs_time_checker(fn3, t3, lm, '3/3', do_plot);

	if pass1 == 1 && pass2 == 1 && pass3 == 1
		pass = 1;
	else
		pass = 0;
	end

end

function pass = level_vs_time_checker(fn, tc, lm, id, do_plot)
	fprintf(1, 'File %s:\n', fn);

	lev = level_vs_time(fn, lm);
	if do_plot
		plot_levels(lev, tc, lm);
	end
	pass = check_levels(lev, tc, lm, 1);
	if pass
		fprintf(1, 'pass (%s)\n', id);
	else
		fprintf(1, 'fail (%s)\n', id);

		% Swapped channels?
		sine_freqs_orig = lm.sine_freqs;
		lm.sine_freqs = sine_freqs_orig(end:-1:1);
		lev = level_vs_time(fn, lm);
		pass_test = check_levels(lev, tc, lm, 0);
		if pass_test
			fprintf(1,'Note: The test would pass with swapped channels.\n');
			return
		end

		% Swapped controls?
		lm.sine_freqs = sine_freqs_orig;
		volumes_orig = tc.volumes;
		tc.volumes = volumes_orig(:, end:-1:1);
		lev = level_vs_time(fn, lm);
		pass_test = check_levels(lev, tc, lm, 0);
		if pass_test
			fprintf(1,'Note: The test would pass with swapped controls.\n')
			return
		end

		% Swapped controls and swapped channels
		lm.sine_freqs = sine_freqs_orig(end:-1:1);
		lev = level_vs_time(fn, lm);
		pass_test = check_levels(lev, tc, lm, 0);
		if pass_test
			fprintf(1,'Note: The test would pass with swapped controls and swapped channels.\n')
		end
	end
end

function plot_levels(meas, tc, lm)
	figure
	plot(meas.t, meas.levels - lm.sine_dbfs);
	grid on;

	sv = size(tc.volumes);
	hold on;
	for j = 1:sv(2)
		for i = 1:sv(1)
			plot([tc.vctimes(i)+tc.meas(1) tc.vctimes(i)+tc.meas(2)], ...
			     [tc.volumes(i,j)+tc.vtol tc.volumes(i,j)+tc.vtol], 'r--');
			if tc.volumes(i,j) > -100
				plot([tc.vctimes(i)+tc.meas(1) tc.vctimes(i)+tc.meas(2)], ...
				     [tc.volumes(i,j)-tc.vtol tc.volumes(i,j)-tc.vtol], 'r--');
			end
		end
	end
	hold off;
	xlabel('Time (s)');
	ylabel('Gain (dB)');
	grid on;
end

function pass = check_levels(meas, tc, lm, verbose)
	pass = 1;
	dg_tol = 0.1;
	gains =  meas.levels - lm.sine_dbfs;
	sv = size(tc.volumes);
	for j = 1:sv(2)
		for i = 1:sv(1)
			% Initial location to test
			ts = tc.vctimes(i)+tc.meas(1);
			te = tc.vctimes(i)+tc.meas(2);
			idx0 = find(meas.t < te);
			idx = find(meas.t(idx0) > ts);

			% Delay if settled gain is later in the window,
			% this adds more robustness to test for controls
			% apply delay.
			dg = diff(gains(idx,j));
			if max(abs(dg)) > dg_tol
				n_idx = length(idx);
				dg_rev = dg(end:-1:1);
				idx_add = length(dg) - find(abs(dg_rev) > dg_tol, 1, 'first') + 1;
			        idx = idx + idx_add;
				if idx(end) > size(gains, 1)
					idx = idx(1):size(gains, 1);
				end
				if idx(1) > size(gains, 1) || length(idx) < 0.5 * n_idx
					fprintf(1, 'Channel %d controls impact is delayed too much ', j);
					fprintf(1, 'from %4.1f - %4.1fs\n', ts, te);
					pass = 0;
					return;
				end
			end
			avg_gain = mean(gains(idx, j));
			max_gain = tc.volumes(i,j) + tc.vtol;
			min_gain = tc.volumes(i,j) - tc.vtol;
			if avg_gain > max_gain
				if verbose
					fprintf(1, 'Channel %d Failed upper gain limit at ', j);
					fprintf(1, '%4.1f - %4.1fs, gain %5.1f dB, max %5.1f dB\n', ...
						ts, te, avg_gain, max_gain);
				end
				pass = 0;
			end
			if tc.volumes(i,j) > -100
				if avg_gain < min_gain
					if verbose
						fprintf(1, 'Channel %d failed lower gain limit at ', j);
						fprintf(1, '%4.1f - %4.1fs, gain %5.1f dB, min %5.1f dB\n', ...
							ts, te, avg_gain, min_gain);
					end
					pass = 0;
				end
			end
		end
	end
end

function ret = level_vs_time(fn, lm)
	[x, fs] = audioread(fn);
	x = bandpass_filter(x, lm.sine_freqs, fs);
	sx = size(x);
	tclip = sx(1) / fs;
	nch = sx(2);

	nlev = floor(tclip / lm.tgrid);
	ngrid = lm.tgrid * fs;
	nlength = lm.tlength * fs;
	nmax = nlev - round(nlength / ngrid) + 1;
	ret.t = (0:(nmax-1)) * lm.tgrid;
	ret.levels = zeros(nmax, nch);
	for i = 1:nmax
		i1 = floor((i - 1) * ngrid + 1);
		i2 = floor(i1 + nlength -1);
		ret.levels(i, :) = level_dbfs(x(i1:i2, :));
	end
	ret.levels_lin = 10.^(ret.levels/20);
end

function y = bandpass_filter(x, f, fs)
	sx = size(x);
	y = zeros(sx(1), sx(2));
	c1 = 0.8;
	c2 = 1/c1;
	for j = 1:sx(2)
		[b, a] = butter(4, 2*[c1*f(j) c2*f(j)]/fs);
		y(:,j) = filter(b, a, x(:,j));
	end
end
