#!/bin/bash
set -e

testlist="
firmware-presence
firmware-load
tplg-binary
pcm_list
sof-logger
ipc-flood
playback-d100l1r1
capture-d100l1r1
playback-d1l100r1
capture_d1l100r1
playback_d1l1r50
capture_d1l1r50
speaker
pause-resume-playback
pause-resume-capture
volume
signal-stop-start-playback
signal-stop-start-capture
xrun-injection-playback
xrun-injection-capture
simultaneous-playback-capture
multiple-pipeline-playback
multiple-pipeline-capture
multiple-pause-resume
kmod-load-unload
kmod-load-unload-after-playback
suspend-resume
suspend-resume-with-playback
suspend-resume-with-capture"

main()
{
	local failures=0
	local time_delay=3

	while getopts "hT:" OPTION; do
	case "$OPTION" in
		T) time_delay="$OPTARG" ;;
		*) usage; exit 1 ;;
		esac
	done
	if [ -z "$TPLG" ]; then
		printf "Please specify topology path with TPLG env\n"
		exit 1
	fi

	for t in $testlist;
	do
		printf "\033[40;32m ---------- \033[0m\n"
		printf "\033[40;32m ---------- \033[0m\n"
		printf "\033[40;32m starting test_%s \033[0m\n" "$t"
		"test_$t" || : $((failures++))
		
		sleep "$time_delay"
	done

	printf "\033[40;32m test end with %d failed\033[0m\n" "$failures"
	exit "$failures"
}

test_firmware-presence()
{
	./verify-firmware-presence.sh
}
test_firmware-load()
{
	./verify-sof-firmware-load.sh
}
test_tplg-binary()
{
	./verify-tplg-binary.sh
}
test_pcm_list()
{
	./verify-pcm-list.sh
}
test_sof-logger()
{
	./check-sof-logger.sh
}
test_ipc-flood()
{
	./check-ipc-flood.sh -l 10
}
test_playback-d100l1r1()
{
	./check-playback.sh -d 100 -l 1 -r 1
}
test_capture-d100l1r1()
{
	./check-capture.sh -d 100 -l 1 -r 1
}
test_playback-d1l100r1()
{
	./check-playback.sh -d 1 -l 100 -r 1
}
test_capture_d1l100r1()
{
	./check-capture.sh -d 1 -l 100 -r 1
}
test_playback_d1l1r50()
{
	./check-playback.sh -d 1 -l 1 -r 50
}
test_capture_d1l1r50()
{
	./check-capture.sh -d 1 -l 1 -r 50
}
test_speaker()
{
	./test-speaker.sh -l 50
}
test_pause-resume-playback()
{
	./check-pause-resume.sh -c 100 -m playback
}
test_pause-resume-capture()
{
	./check-pause-resume.sh -c 100 -m capture
}
test_volume()
{
	./volume-basic-test.sh -l 100
}
test_signal-stop-start-playback()
{
	./check-signal-stop-start.sh -m playback -c 50
}
test_signal-stop-start-capture()
{
	./check-signal-stop-start.sh -m capture -c 50
}
test_xrun-injection-playback()
{
	./check-xrun-injection.sh -m playback -c 50
}
test_xrun-injection-capture()
{
	./check-xrun-injection.sh -m capture -c 50
}
test_simultaneous-playback-capture()
{
	./simultaneous-playback-capture.sh -l 50
}
test_multiple-pipeline-playback()
{
	./multiple-pipeline-playback.sh -l 50
}
test_multiple-pipeline-capture()
{
	./multiple-pipeline-capture.sh -l 50
}
test_multiple-pause-resume()
{
	./multiple-pause-resume.sh -r 25
}
test_kmod-load-unload()
{
	./check-kmod-load-unload.sh -l 50
}
test_kmod-load-unload-after-playback()
{
	./check-kmod-load-unload-after-playback.sh -l 15
}
test_suspend-resume()
{
	./check-suspend-resume.sh -l 50
}
test_suspend-resume-with-playback()
{
	./check-suspend-resume-with-audio.sh -l 15 -m playback
}
test_suspend-resume-with-capture()
{
	./check-suspend-resume-with-audio.sh -l 15 -m capture
}

usage()
{
	cat <<EOF
Wrapper script to run all test cases. Please use TPLG env to
pass-through topology path to test caess.

usage: run-all-tests.sh [options]
		-h Show script usage
		-T time Delay between cases, default: 3s
EOF
}

main "$@"
