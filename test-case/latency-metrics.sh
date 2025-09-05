#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

##
## Case Name: collect latency statistics on a signal path using JACK
##
## Preconditions:
##    - JACK Audio Connection Kit is installed.
##    - loopback connection is set to measure latency over the signal path.
##
## Description:
##    Run `jackd` audio server and execute `jack_iodelay` with its in/out ports
##    connected to the loopback-ed ports giving it some time to collect latency
##    measurements (every 0.5 sec.) and 'xrun' errors, if any.
##    The 'xrun' errors can be ignored if there are less than a threshold given.
##    Optionally, run in 'triial' mode repeating latency measurements reducing
##    buffer size to find the smallest/fastest possible.
##
## Case steps:
##    0. Set ALSA parameters.
##    1. Try to start `jackd` with parameters given and read its configuration.
##    2. Start `jackd` again for the latency measurements.
##    3. Start `jack_iodelay` which awaits for its ports connected to a loopback.
##    4. Connect `jack_iodelay` ports to the loopback signal path ports.
##    5. Run and wait for the time given collecting latency measurements.
##    6. Calculate latency statistics and save them into a JSON file.
##    7. Optionally, repeat the above latency measurements with decreased buffer
##       size to find the smallest latency possible.
##
## Expect result:
##    Latency statistics collected and saved in `test_result.json` file.
##    Exit status 0.
##

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTLIB="${TESTDIR}/case-lib"

# shellcheck source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"

OPT_NAME['R']='running-time'    OPT_DESC['R']='Test running time (in seconds) to collect latency probes.'
OPT_HAS_ARG['R']=1              OPT_VAL['R']="30"

OPT_NAME['d']='device'          OPT_DESC['d']='ALSA pcm device for playback and capture. Example: hw:0'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=''

OPT_NAME['p']='pcm_p'           OPT_DESC['p']='ALSA pcm device for playback only. Example: hw:soundwire,0'
OPT_HAS_ARG['p']=1              OPT_VAL['p']=''

OPT_NAME['c']='pcm_c'           OPT_DESC['c']='ALSA pcm device for capture only. Example: hw:soundwire,1'
OPT_HAS_ARG['c']=1              OPT_VAL['c']=''

OPT_NAME['r']='rate'            OPT_DESC['r']='Sample rate to try latency with'
OPT_HAS_ARG['r']=1              OPT_VAL['r']=48000

OPT_NAME['f']='frames'          OPT_DESC['f']='jackd alsa --period, number of frames.'
OPT_HAS_ARG['f']=1              OPT_VAL['f']=1024  # JACK's default

OPT_NAME['n']='nperiods'        OPT_DESC['n']='jackd alsa --nperiods, periods in the buffer.'
OPT_HAS_ARG['n']=1              OPT_VAL['n']=2  # JACK's default and min value.

OPT_NAME['S']='shorts'          OPT_DESC['S']='Try to use 16-bit samples instead of 32-bit, if possible.'
OPT_HAS_ARG['S']=0              OPT_VAL['S']=0

OPT_NAME['P']='port_p'          OPT_DESC['P']='JACK playback port with loopback.'
OPT_HAS_ARG['P']=1              OPT_VAL['P']='system:playback_1'

OPT_NAME['C']='port_c'          OPT_DESC['C']='JACK capture port with loopback.'
OPT_HAS_ARG['C']=1              OPT_VAL['C']='system:capture_1'

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

OPT_NAME['v']='verbose'         OPT_DESC['v']='Verbose logging.'
OPT_HAS_ARG['v']=0              OPT_VAL['v']=0

OPT_NAME['X']='xruns-ignore'    OPT_DESC['X']="How many 'xrun' errors to ignore."
OPT_HAS_ARG['X']=1              OPT_VAL['X']=0

OPT_NAME['L']='loopback'        OPT_DESC['L']="Set internal loopback at JACK instead of ports."
OPT_HAS_ARG['L']=0              OPT_VAL['L']=0

OPT_NAME['t']='trial'           OPT_DESC['t']="Trial mode: repeat measurements decreasing buffer."
OPT_HAS_ARG['t']=0              OPT_VAL['t']=0

OPT_NAME['T']='trial-until'     OPT_DESC['T']="Trial mode: repeat until this value."
OPT_HAS_ARG['T']=1              OPT_VAL['T']=2

func_opt_parse_option "$@"

alsa_device=${OPT_VAL['d']}
pcm_p=${OPT_VAL['p']}
pcm_c=${OPT_VAL['c']}
alsa_shorts=$([ "${OPT_VAL['S']}" -eq 1 ] && echo '--shorts' || echo '')
port_playback=${OPT_VAL['P']}
port_capture=${OPT_VAL['C']}
rate=${OPT_VAL['r']}
run_period=${OPT_VAL['R']}
run_verbose=$([ "${OPT_VAL['v']}" -eq 1 ] && echo '--verbose' || echo '')
max_xruns=${OPT_VAL['X']}
set_loopback=${OPT_VAL['L']}
jackd_frames=${OPT_VAL['f']}
jackd_period=${jackd_frames}
jackd_nperiods=${OPT_VAL['n']}
trial_mode=${OPT_VAL['t']}
trial_until=${OPT_VAL['T']}

METRICS_JSON="${LOG_ROOT}/metrics_iodelay.json"
EVENTS_JSON="${LOG_ROOT}/events_jackd.json"
RESULT_JSON="${LOG_ROOT}/test_result.json"
RUN_PERIOD_MAX="$((run_period + 30))s"
JACKD_TIMEOUT="$((run_period + 15))s"
JACKD_OPTIONS=("--realtime" "--temporary")
JACKD_BACKEND="alsa"
JACKD_BACKEND_OPTIONS=("-n" "${jackd_nperiods}" "-r" "${rate}" "${alsa_shorts}")
WAIT_JACKD="2s"
IODELAY_TIMEOUT="${run_period}s"
WAIT_IODELAY="2s"

check_latency_options()
{
  if [ -n "${alsa_device}" ]; then
    if [ -n "${pcm_p}" ] || [ -n "${pcm_c}" ]; then
      skip_test "Give either ALSA device, or ALSA playback/capture pcm-s."
    fi
    JACKD_BACKEND_OPTIONS=("-d" "${alsa_device}" "${JACKD_BACKEND_OPTIONS[@]}")
  elif [ -z "${pcm_p}" ] || [ -z "${pcm_c}" ]; then
      skip_test "No playback or capture ALSA PCM is specified."
  else
    JACKD_BACKEND_OPTIONS=("-P" "${pcm_p}" "-C" "${pcm_c}" "${JACKD_BACKEND_OPTIONS[@]}")
  fi

  if [ "${set_loopback}" == 1 ]; then
    port_playback="${set_loopback}"
    port_capture="${set_loopback}"
  fi

  if [ -z "${port_playback}" ] || [ -z "${port_capture}" ]; then
    skip_test "No playback or capture JACK port is specified."
  fi
}

# set/update commands in case the test iterates or sweep over a range
compose_commands()
{
  TIMEOUT_RUN=(timeout "--kill-after" "${RUN_PERIOD_MAX}")
  [ -z "${run_verbose}" ] || TIMEOUT_RUN+=("${run_verbose}")

  [ -z "${run_verbose}" ] || JACKD_OPTIONS+=("${run_verbose}")
  JACKD_RUN=(jackd "${JACKD_OPTIONS[@]}" -d "${JACKD_BACKEND}" "${JACKD_BACKEND_OPTIONS[@]}" -p "${jackd_period}")

  TIMEOUT_JACKD_RUN=("${TIMEOUT_RUN[@]}" "${JACKD_TIMEOUT}" "${JACKD_RUN[@]}")
}

check_jackd_configured()
{
  dlogi "Check JACK audio server can be started"

  compose_commands

  dlogc "${TIMEOUT_JACKD_RUN[*]}"
  "${TIMEOUT_JACKD_RUN[@]}" & jackdPID=$!

  sleep ${WAIT_JACKD}

  dlogc "jack_lsp -AclLpt"
  jack_lsp -AclLpt

  dlogi "Waiting jackd to stop without a client"
  wait ${jackdPID}
}

collect_latency_data()
{
  dlogi "Start collecting latency data"

  compose_commands

  dlogc "${TIMEOUT_JACKD_RUN[*]}"
  "${TIMEOUT_JACKD_RUN[@]}" 2>&1 | \
      tee >(AWKPATH="${TESTLIB}:${AWKPATH}" \
          gawk -f "${TESTLIB}/jackd_events.awk" > "${EVENTS_JSON}") & jackdPID="$!"

  sleep ${WAIT_JACKD}

  dlogc "jack_iodelay"
  "${TIMEOUT_RUN[@]}" "${IODELAY_TIMEOUT}" \
      stdbuf -oL -eL jack_iodelay 2>&1 | \
      tee >(AWKPATH="${TESTLIB}:${AWKPATH}" \
          gawk -f "${TESTLIB}/jack_iodelay_metrics.awk" > "${METRICS_JSON}") & iodelayPID="$!"

  sleep ${WAIT_IODELAY}
  if [ "${set_loopback}" == 1 ]; then
      dlogi "jack_connect: [JACK loopback]<==>[jack_delay]"
      jack_connect jack_delay:out jack_delay:in
  else
      dlogi "jack_connect: [${port_capture}]==>[jack_delay]==>[${port_playback}]"
      jack_connect jack_delay:out "${port_playback}" && jack_connect jack_delay:in "${port_capture}"
  fi

  dlogi "Latency data collection"
  wait ${jackdPID} ${iodelayPID}

  dlogi "Latency data collection completed for period=${jackd_period} frames."
}

report_start()
{
  dlogi "Compose ${RESULT_JSON}"
  printf '{"options":{%s}, "metrics":[' "$(options2json)" > "${RESULT_JSON}"
}

json_next_sep=""

report_metric()
{
  printf '%s{"period_frames":%d, "periods":%d, "rate":%d, ' \
    "${json_next_sep}" "${jackd_period}" "${jackd_nperiods}" "${rate}" >> "${RESULT_JSON}"

  if [ ! -f "${METRICS_JSON}" ] || [ "$(grep -ce 'metric_name' "${METRICS_JSON}")" -lt 1 ]; then
    printf '"probes":0, "xruns":0}' >> "${RESULT_JSON}"
    [ -f "${METRICS_JSON}" ] && rm "${METRICS_JSON}"
    [ -f "${EVENTS_JSON}" ] && rm "${EVENTS_JSON}"
    if [ "${trial_mode}" -eq 0 ]; then
      printf ']}' >> "${RESULT_JSON}"
      skip_test "No latency metrics collected"
    fi
  else
    local metrics_
    metrics_=$(cat "${METRICS_JSON}")
    dlogi "latency metrics: ${metrics_}"

    if [ -f "${EVENTS_JSON}" ]; then
      local events_
      events_=$(cat "${EVENTS_JSON}")
      dlogi "jackd events: ${events_}"
      rm "${EVENTS_JSON}"
      metrics_="${metrics_}, ${events_}"
    fi

    printf '%s}' "${metrics_}" >> "${RESULT_JSON}" && rm "${METRICS_JSON}"

    xruns=$(echo "{${metrics_}}" | jq 'select(.xruns > 0).xruns')
    if [ -n "${xruns}" ] && [ "${xruns}" -gt "${max_xruns}" ]; then
      printf ']}' >> "${RESULT_JSON}"
      skip_test "XRuns: ${xruns} detected!"
    fi
  fi
  json_next_sep=","
}

report_end()
{
  [ -n "${json_next_sep}" ] && printf ']' >> "${RESULT_JSON}"
  printf '}\n' >> "${RESULT_JSON}"
  cat "${RESULT_JSON}"
}

main()
{
  pkill jackd || True
  check_latency_options

  setup_kernel_check_point

  start_test

  logger_disabled || func_lib_start_log_collect

  set_alsa

  check_jackd_configured

  report_start

  while [ "${jackd_period}" -ge "${trial_until}" ]; do

    dlogi "Measuring latency with period=${jackd_period} frames."

    collect_latency_data

    report_metric

    jackd_period="$((jackd_period / 2))"

    [ "${trial_mode}" -ne 0 ] || break

  done

  report_end
}

{
  main "$@"; exit "$?"
}
