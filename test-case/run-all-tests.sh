#!/bin/bash
set -e

# This entire script is a hack. We need to re-use some existing test
# runner from some existing test framework eventually

# These can also be overriden by the environment
very_short_tests()
{
	small_loop=1
	medium_loop=1
	large_loop=1

	medium_count=5
	large_count=10

	long_duration=3

	large_round=3
}


testlist="
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

# Requires Octave
testlist="$testlist volume_levels"

# To focus on some particular tests edit and rename this to
# 'testlist'. Last definition wins.
# shellcheck disable=SC2034
shorter_testlist='
firmware-presence
speaker
firmware-load
playback-d100l1r1
capture_d1l100r1
tplg-binary
sof-logger
'

main()
{
	# Default values overriden by the environment if any
	: "${small_loop:=15}"
	: "${medium_loop:=50}"
	: "${large_loop:=100}"

	: "${medium_count:=50}"
	: "${large_count:=100}"

	: "${long_duration:=100}"

	: "${large_round:=50}"

	local mydir
	mydir=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)

	local failures=()
	local passed=()

	# On Ctrl-C
	trap interrupted_results INT

	local tests_length=10 time_delay=3 exit_first=false

	while getopts "l:T:xh" OPTION; do
	case "$OPTION" in
		l) tests_length="$OPTARG" ;;
		T) time_delay="$OPTARG"
		   export SOF_TEST_INTERVAL="$OPTARG"
		   ;;
		x) exit_first=true ;;
		*) usage; exit 1 ;;
		esac
	done
	if [ -z "$TPLG" ]; then
		printf "Please specify topology path with TPLG env\n"
		exit 1
	fi

	case "$tests_length" in
	    1) very_short_tests ;;
	    10) ;; # default
	    *) usage; exit 1 ;;
	esac

	declare -A durations
	local start_time
	for t in $testlist;
	do
		start_time=$(date +%s)
		printf "\033[40;32m ---------- \033[0m\n"
		printf "\033[40;32m ---------- \033[0m\n"
		printf "\033[40;32m starting test_%s \033[0m\n" "$t"
		# set -x logs the test parameters
		local ret=0
		( set -x; "test_$t" ) || ret=$?
		case "$ret" in
			0) passed+=( "$t" ) ;;
			2) skipped+=( "$t" ) ;;
			*) failures+=( "$t" )
			   if $exit_first; then break; fi
			   ;;
		esac
		durations["$t"]=$(($(date +%s) - start_time))

		sleep "$time_delay"
	done

	print_results
	exit "${#failures[@]}"
}

print_results()
{
	printf "\n\nDurations in seconds:\n\t"
	declare -p durations | sed -e 's/^declare -A//'

	printf "\n\nPASS:"; printf ' %s;' "${passed[@]}"

	if [ "${#failures[@]}" -gt 0 ]; then
	    printf "\nFAIL:"; printf ' %s;' "${failures[@]}"
	fi
	if [ "${#skipped[@]}" -gt 0 ]; then
	    printf "\nSKIP:"; printf ' %s;' "${skipped[@]}"
	fi

	printf "\n\n\033[40;32m test end with %d failed tests\033[0m\n\n" "${#failures[@]}"
}

interrupted_results()
{
	# Users often hit Ctrl-C multiple times which would interrupt
	# this function too.
	trap '' INT

	# Give subprocesses some time to avoid mixed up output
	sleep 3

	print_results
	printf 'Testing was INTERRUPTED, results are incomplete!\n'
	exit 1
}

test_firmware-presence()
{
	"$mydir"/verify-firmware-presence.sh
}
test_firmware-load()
{
	"$mydir"/verify-sof-firmware-load.sh
}
test_tplg-binary()
{
	"$mydir"/verify-tplg-binary.sh
}
test_pcm_list()
{
	"$mydir"/verify-pcm-list.sh
}
test_sof-logger()
{
	( set +x
	if [ "$SOF_LOGGING" = 'none' ]; then
	    printf '$''SOF_LOGGING=none, skipping check-sof-logger.sh\n'
	fi )
	return 2

	"$mydir"/check-sof-logger.sh
}
test_ipc-flood()
{
	"$mydir"/check-ipc-flood.sh -l "$small_loop"
}
test_playback-d100l1r1()
{
	"$mydir"/check-playback.sh -d "${long_duration}" -l 1 -r 1
}
test_capture-d100l1r1()
{
	"$mydir"/check-capture.sh -d "${long_duration}" -l 1 -r 1
}
test_playback-d1l100r1()
{
	"$mydir"/check-playback.sh -d 1 -l "$large_loop" -r 1
}
test_capture_d1l100r1()
{
	"$mydir"/check-capture.sh -d 1 -l "$large_loop" -r 1
}
test_playback_d1l1r50()
{
	"$mydir"/check-playback.sh -d 1 -l 1 -r "$large_round"
}
test_capture_d1l1r50()
{
	"$mydir"/check-capture.sh -d 1 -l 1 -r "$large_round"
}
test_speaker()
{
	"$mydir"/test-speaker.sh -l "$medium_loop"
}
test_pause-resume-playback()
{
	"$mydir"/check-pause-resume.sh -c "$large_count" -m playback
}
test_pause-resume-capture()
{
	"$mydir"/check-pause-resume.sh -c "$large_count" -m capture
}
test_volume()
{
	"$mydir"/volume-basic-test.sh -l "$large_loop"
}
test_volume_levels()
{
	"$mydir"/check-volume-levels.sh
}
test_signal-stop-start-playback()
{
	"$mydir"/check-signal-stop-start.sh -m playback -c "$medium_count"
}
test_signal-stop-start-capture()
{
	"$mydir"/check-signal-stop-start.sh -m capture -c "$medium_count"
}
test_xrun-injection-playback()
{
	"$mydir"/check-xrun-injection.sh -m playback -c "$medium_count"
}
test_xrun-injection-capture()
{
	"$mydir"/check-xrun-injection.sh -m capture -c "$medium_count"
}
test_simultaneous-playback-capture()
{
	"$mydir"/simultaneous-playback-capture.sh -l "$medium_loop"
}
test_multiple-pipeline-playback()
{
	"$mydir"/multiple-pipeline-playback.sh -l "$medium_loop"
}
test_multiple-pipeline-capture()
{
	"$mydir"/multiple-pipeline-capture.sh -l "$medium_loop"
}
test_multiple-pause-resume()
{
	"$mydir"/multiple-pause-resume.sh -l "$small_loop" -r 25
}
test_kmod-load-unload()
{
	"$mydir"/check-kmod-load-unload.sh -l "$medium_loop"
}
test_kmod-load-unload-after-playback()
{
	"$mydir"/check-kmod-load-unload-after-playback.sh -l "$small_loop"
}
test_suspend-resume()
{
	"$mydir"/check-suspend-resume.sh -l "$medium_loop"
}
test_suspend-resume-with-playback()
{
	"$mydir"/check-suspend-resume-with-audio.sh -l "$small_loop" -m playback
}
test_suspend-resume-with-capture()
{
	"$mydir"/check-suspend-resume-with-audio.sh -l "$small_loop" -m capture
}

usage()
{
	cat <<EOF
Wrapper script to run all test cases. Please use TPLG env to
pass-through topology path to test caess.

usage: $0 [options]
		-h Show script usage
		-x exit on first failure
		-l 1 Very small test counts/loops/rounds (< 20 min)
		-T time Delay between cases, default: 3s
EOF
}

main "$@"
