#!/bin/bash

# Copyright(c) 2025 Intel Corporation.
# SPDX-License-Identifier: BSD-3-Clause

##
## Case Name: Execute ALSA conformance tests.
##
## Preconditions:
##    - ChromeOS Audio Test package is installed
##      https://chromium.googlesource.com/chromiumos/platform/audiotest
##
## Description:
##    Run `alsa_conformance_test.py` for the playback devices
##    and the capture devices with the test suite paramenters given.
##    Compose resulting JSON reports.
##
##    To select PCMs use either -d, or -p with or without -c parameters.
##    If a PCM id has no device id (e.g. 'hw:sofnocodec' instead of 'hw:sofnocodec,0')
##    then all devices on that card will be selected for the test run.
##    To select all available PCMs omit any -d, -p, -c parameters.
##
##    Pass multiple values of the test parameters -d, -p, -c, -r, -F enclosing them
##    in quotes, eg. `-F 'U8 S16_LE'` or `-p 'sofnocodec,1 sofnocodec,2'`
##
## Case steps:
##    0. Set ALSA parameters.
##    1. For each PCM selected:
##    1.1 Try to start `alsa_conformance_test` in device info mode.
##    1.2 Start `alsa conformance_test.py` for playback devices.
##    1.3 Start `alsa conformance_test.py` for capture devices.
##    2. Compose the resulting JSON report.
##
## Expect result:
##    ALSA conformance results collected and saved in `test_result.json` file.
##    Exit status 0.
##    In case of errors this test tries to continue and have its JSON report correctly structured.
##

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTLIB="${TESTDIR}/case-lib"

# shellcheck source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"

OPT_NAME['d']='device'          OPT_DESC['d']='ALSA pcm device for playback and capture. Example: hw:0'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=''

OPT_NAME['p']='pcm_p'           OPT_DESC['p']='ALSA pcm device for playback only. Example: hw:soundwire,0'
OPT_HAS_ARG['p']=1              OPT_VAL['p']=''

OPT_NAME['c']='pcm_c'           OPT_DESC['c']='ALSA pcm device for capture only. Example: hw:soundwire,1'
OPT_HAS_ARG['c']=1              OPT_VAL['c']=''

OPT_NAME['r']='rates'           OPT_DESC['r']='Sample ratis to try. Default: check all available rates.'
OPT_HAS_ARG['r']=1              OPT_VAL['r']=''

OPT_NAME['F']='formats'         OPT_DESC['F']='Data formats to try. Default: check all available formats.'
OPT_HAS_ARG['F']=1              OPT_VAL['F']=''

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

OPT_NAME['v']='verbose'         OPT_DESC['v']='Verbose logging.'
OPT_HAS_ARG['v']=0              OPT_VAL['v']=0

OPT_NAME['E']='rate-diff'       OPT_DESC['E']="ALSA conformance --rate-criteria-diff-pct (difference, %)."
OPT_HAS_ARG['E']=1              OPT_VAL['E']=''

OPT_NAME['e']='rate-err'        OPT_DESC['e']="ALSA conformance --rate-err-criteria (max rate error)."
OPT_HAS_ARG['e']=1              OPT_VAL['e']=''

OPT_NAME['a']='avail-delay'     OPT_DESC['a']="ALSA conformance --avail-delay"
OPT_HAS_ARG['a']=0              OPT_VAL['a']=0

OPT_NAME['T']='test-suites'     OPT_DESC['T']="ALSA conformance --test-suites (Default: all)."
OPT_HAS_ARG['T']=1              OPT_VAL['T']=''

OPT_NAME['t']='timeout'         OPT_DESC['t']="ALSA conformance --timeout (Default: none)."
OPT_HAS_ARG['t']=1              OPT_VAL['t']=''

OPT_NAME['A']='allow-channels'  OPT_DESC['A']="ALSA conformance --allow-channels (Default: all)."
OPT_HAS_ARG['A']=1              OPT_VAL['A']=''

OPT_NAME['S']='skip-channels'   OPT_DESC['S']="ALSA conformance --skip-channels (Default: none skipped)."
OPT_HAS_ARG['S']=1              OPT_VAL['S']=''

func_opt_parse_option "$@"

# Options for the ALSA conformance test script call
CMD_OPTS=()

# Recompose OPT_VAL[$1] option as ALSA test script option $2
add_cmd_option()
{
  local opt_val="${OPT_VAL[$1]}"
  local prefix=$2

  if [ -n "${opt_val}" ]; then
    # Split list parameters to separate values
    opt_val=("${opt_val//[ ,]/ }")
    # shellcheck disable=SC2206
    CMD_OPTS+=("${prefix}" ${opt_val[@]})
  fi
}

init_globals()
{
  add_cmd_option 'r' '--allow-rates'
  add_cmd_option 'F' '--allow-formats'
  add_cmd_option 'E' '--rate-criteria-diff-pct'
  add_cmd_option 'e' '--rate-err-criteria'
  add_cmd_option 't' '--timeout'
  add_cmd_option 'T' '--test-suites'
  add_cmd_option 'A' '--allow-channels'
  add_cmd_option 'S' '--skip-channels'

  run_verbose=0
  if [[ "${OPT_VAL['v']}" -eq 1 ]]; then
    run_verbose=1
    CMD_OPTS+=("--log-file" "/dev/stdout")
  fi

  if [[ "${OPT_VAL['a']}" -eq 1 ]]; then
    CMD_OPTS+=('--avail-delay')
  fi

  AUDIOTEST_OUT="${LOG_ROOT}/alsa_conformance"
  RESULT_JSON="${LOG_ROOT}/test_result.json"

  ALSA_CONFORMANCE_PATH=$([ -n "$ALSA_CONFORMANCE_PATH" ] || realpath "${TESTDIR}/../audiotest")
  ALSA_CONFORMANCE_TEST="${ALSA_CONFORMANCE_PATH}/alsa_conformance_test"
}

check_alsa_conformance_suite()
{
  if [ -d "${ALSA_CONFORMANCE_PATH}" ]; then
    if [ -x "${ALSA_CONFORMANCE_TEST}" ] && [ -x "${ALSA_CONFORMANCE_TEST}.py" ]; then
      dlogi "Use ALSA conformance test suite: ${ALSA_CONFORMANCE_TEST}"
      return
    fi
  fi
  skip_test "ALSA conformance test suite is missing at: ${ALSA_CONFORMANCE_PATH}"
}

# Returns the PCM's full id if it is found as playback or capture device.
# If only card id is given, then all its devices will be returned.
# Empty output if the device is not found.
get_card_devices()
{
  local mode=$1 
  local arg_pcm=$2

  # select all devices by default
  [ -z "${arg_pcm}" ] && arg_pcm="[^ ]+"

  local alsa_list=''
  local res_devs=("${arg_pcm}")

  if [ "${mode}" == 'playback' ]; then
    alsa_list=('aplay' '-l')
  elif [ "${mode}" == 'capture' ]; then
    alsa_list=('arecord' '-l')
  else
    return
  fi

  if [ -n "${arg_pcm}" ]; then
    # check is only card name is given or exact device
    if [ "${arg_pcm}" == "${arg_pcm##*,}" ]; then
      # strip 'hw:' prefix
      arg_pcm="${arg_pcm#*:}"
      # shellcheck disable=SC2016
      local gawk_script='match($0, /^card [0-9]+: ('"${arg_pcm}"') .+ device ([0-9]+): /, arr) { print "hw:" arr[1] "," arr[2] }'
      mapfile -t res_devs < <( "${alsa_list[@]}" | gawk "${gawk_script}" )
    fi
    printf '%s\n' "${res_devs[@]}"
  fi
}

select_PCMs()
{
  # Don't quote to split into separate items:
  # shellcheck disable=SC2206
  alsa_device=(${OPT_VAL['d']//[ ]/ })
  # shellcheck disable=SC2206
  pcm_p=(${OPT_VAL['p']//[ ]/ })
  # shellcheck disable=SC2206
  pcm_c=(${OPT_VAL['c']//[ ]/ })

  if [ -n "${alsa_device[*]}" ]; then
    if [ -n "${pcm_p[*]}" ] || [ -n "${pcm_c[*]}" ]; then
      die "Give either an ALSA device (-d), or ALSA playback(-p) and/or capture(-c) PCMs."
    fi
    # we got only -d 
    pcm_p=("${alsa_device[@]}")
    pcm_c=("${alsa_device[@]}")
  elif [ -z "${pcm_p[*]}" ] && [ -z "${pcm_c[*]}" ]; then
    dlogi "No ALSA PCM is specified - scan all playback and capture devices"
    pcm_p=('')
    pcm_c=('')
  fi
  dlogi "pcm_p=(${pcm_p[*]})"
  dlogi "pcm_c=(${pcm_c[*]})"

  local p_dev_expanded=()
  PLAYBACK_DEVICES=()

  for p_dev in "${pcm_p[@]}"
  do
    mapfile -t p_dev_expanded < <(get_card_devices 'playback' "${p_dev}")
    PLAYBACK_DEVICES+=( "${p_dev_expanded[@]}" )
  done
  dlogi "Playback devices: ${PLAYBACK_DEVICES[*]}"

  CAPTURE_DEVICES=()
  for c_dev in "${pcm_c[@]}"
  do
    mapfile -t p_dev_expanded < <(get_card_devices 'capture' "${c_dev}")
    CAPTURE_DEVICES+=( "${p_dev_expanded[@]}" )
  done
  dlogi "Capture devices: ${CAPTURE_DEVICES[*]}"
}
  
set_alsa()
{
  reset_sof_volume

  # If MODEL is defined, set proper gain for the platform
  if [ -z "$MODEL" ]; then
    dlogw "No MODEL is defined. Please define MODEL to run alsa_settings/\${MODEL}.sh"
  else
    set_alsa_settings "$MODEL"
  fi
}

alsa_conformance_device_info()
{
  local mode=$1
  local device=$2
  local opt=()
  [ "${mode}" == 'playback' ] && opt=("-P" "${device}")
  [ "${mode}" == 'capture' ] && opt=("-C" "${device}")
  [ -z "${opt[*]}" ] && die "No ALSA PCM parameter."

  local run_cmd=("${ALSA_CONFORMANCE_TEST}" "${opt[@]}" "--dev_info_only")
  dlogc "${run_cmd[@]}"
  local rc=0
  "${run_cmd[@]}" || rc=$?
  [[ "${rc}" -ne 0 ]] && dloge "Failed to get device info, rc=${rc}"
}

alsa_conformance_test()
{
  local mode=$1
  local device=$2
  local opt=()
  [ "${mode}" == 'playback' ] && opt=("-P" "${device}")
  [ "${mode}" == 'capture' ] && opt=("-C" "${device}")
  [ -z "${opt[*]}" ] && die "No ALSA PCM parameter."

  local run_prefix=("export" "PATH=${ALSA_CONFORMANCE_PATH}:${PATH}")
  local run_cmd=()
  run_cmd+=("${ALSA_CONFORMANCE_TEST}.py" "${CMD_OPTS[@]}" "${opt[@]}")
  run_cmd+=("--json-file" "${AUDIOTEST_OUT}_${mode}.json")
  dlogc "${run_cmd[@]}"
  local rc=0
  "${run_prefix[@]}" && "${run_cmd[@]}" || rc=$?
  [[ "${rc}" -ne 0 ]] && dloge "Failed ${mode} tests, rc=${rc}"
}

report_start()
{
  dlogi "Compose ${RESULT_JSON}"
  printf '{"options":{%s}, "alsa_conformance":[' "$(options2json)" > "${RESULT_JSON}"
}

json_next_sep=""

report_conformance()
{
  local report_type=$1
  local report_device=$2
  local report_file="${AUDIOTEST_OUT}_${report_type}.json"
  if [ -s "${report_file}" ]; then
    printf '%s{"device":"%s","%s":' \
      "${json_next_sep}" "${report_device}" "${report_type}" >> "${RESULT_JSON}"
    jq --compact-output . "${report_file}" >> "${RESULT_JSON}" && rm "${report_file}"
    printf '}' >> "${RESULT_JSON}"
    json_next_sep=","
  else
    dlogw "No conformance report for ${report_type}"
  fi
}

report_end()
{
  printf ']}\n' >> "${RESULT_JSON}"
  [[ "${run_verbose}" -ne 0 ]] && cat "${RESULT_JSON}"
}

assert_failures()
{
  local report_type=$1
  [ -z "${report_type}" ] && return

  local report_key="alsa_conformance[].${report_type}"
  local failures=""

  failures=$(jq "[.${report_key}.fail // 0] | add" "${RESULT_JSON}")
  if [ -z "${failures}" ] || [ "${failures}" -ne "${failures}" ]; then
    die "${report_type} has invalid ${RESULT_JSON}"
  fi
  if [ "${failures}" -ne 0 ]; then
    die "${report_type} has ${failures} failures."
  fi

  # we must have something reported as passed, even zero
  passes=$(jq "[.${report_key}.pass] | add // empty" "${RESULT_JSON}")
  if [ -z "${passes}" ] || [ "${passes}" -ne "${passes}" ]; then
    die "${report_type} has no results."
  fi
}

run_test()
{
    local t_mode=$1
    local t_dev=$2

    dlogi "Test ${t_mode} ${t_dev}"
    alsa_conformance_device_info "${t_mode}" "${t_dev}"
    alsa_conformance_test "${t_mode}" "${t_dev}"
    report_conformance "${t_mode}" "${t_dev}"
}

main()
{
  init_globals

  setup_kernel_check_point

  start_test

  check_alsa_conformance_suite

  select_PCMs

  logger_disabled || func_lib_start_log_collect

  set_alsa

  report_start

  for p_dev in "${PLAYBACK_DEVICES[@]}"
  do
    run_test 'playback' "${p_dev}"
  done

  for c_dev in "${CAPTURE_DEVICES[@]}"
  do
    run_test 'capture' "${c_dev}"
  done

  report_end

  [ -n "${PLAYBACK_DEVICES[*]}" ] && assert_failures 'playback'
  [ -n "${CAPTURE_DEVICES[*]}" ] && assert_failures 'capture'
}

{
  main "$@"; exit "$?"
}
