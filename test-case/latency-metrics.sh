#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

##
## Case Name: latency baseline statistics collection on a signal path
##
## Preconditions:
##    - JACK Audio Connection Kit is installed.
##    - loopback connection to measure latency over its signal path.
##
## Description:
##    Run `jackd` audio server; execute `jack_iodelay` with its in/out ports
##    connected to the loopback-ed ports and give it some time ot collect
##    latency measurements (on each 0.5 sec.)
##
## Case step:
##    1. Probe to start `jackd` with parameters given and read configuration.
##    2. Start `jackd` again for latency measurements.
##    3. Start `jack_iodelay` which awaits for its ports connected to loopback.
##    4. Connect `jack_iodelay` ports to signal path ports with the loopback.
##    5. Wait for the period given to collect enough latency measurements.
##    6. Calculate latency statistics and save into a JSON file.
##
## Expect result:
##    Latency statistics collected and saved in `test_result.json` file.
##    Exit status 0.
##

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTLIB="${TESTDIR}/case-lib"

# shellcheck source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"

OPT_NAME['R']='run-period'      OPT_DESC['R']='Time period (in seconds) to measure latency.'
OPT_HAS_ARG['R']=1              OPT_VAL['R']="30"

OPT_NAME['d']='device'          OPT_DESC['d']='ALSA pcm device to use by JACK'
OPT_HAS_ARG['d']=1              OPT_VAL['d']="hw:0"

OPT_NAME['r']='rate'            OPT_DESC['r']='Sample rate to try latency with'
OPT_HAS_ARG['r']=1              OPT_VAL['r']=48000

OPT_NAME['S']='shorts'          OPT_DESC['S']='Try to use 16-bit samples instead of 32-bit, if possible.'
OPT_HAS_ARG['S']=0              OPT_VAL['S']=0

OPT_NAME['p']='port_p'          OPT_DESC['p']='Jack playback port with loopback. Example: system:playback_1'
OPT_HAS_ARG['p']=1              OPT_VAL['p']=''

OPT_NAME['c']='port_c'          OPT_DESC['c']='Jack capture port with loopback. Example: system:capture_1'
OPT_HAS_ARG['c']=1              OPT_VAL['c']=''

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

OPT_NAME['v']='verbose'         OPT_DESC['v']='Verbose logging.'
OPT_HAS_ARG['v']=0              OPT_VAL['v']=0

OPT_NAME['X']='is-xrun-error'   OPT_DESC['X']="An 'xrun' detected is the test's error."
OPT_HAS_ARG['X']=0              OPT_VAL['X']=1

func_opt_parse_option "$@"

alsa_device=${OPT_VAL['d']}
alsa_shorts=$([ "${OPT_VAL['S']}" -eq 1 ] && echo '--shorts' || echo '')
port_playback=${OPT_VAL['p']}
port_capture=${OPT_VAL['c']}
rate=${OPT_VAL['r']}
run_period=${OPT_VAL['R']}
run_verbose=$([ "${OPT_VAL['v']}" -eq 1 ] && echo '--verbose' || echo '')
xrun_error=${OPT_VAL['X']}

RESULT_JSON="${LOG_ROOT}/test_result.json"
RUN_PERIOD_MAX="$((run_period + 30))s"
JACKD_TIMEOUT="$((run_period + 15))s"
JACKD_OPTIONS="${run_verbose} --realtime --temporary"
JACKD_BACKEND="alsa"
JACKD_BACKEND_OPTIONS="-d ${alsa_device} -r ${rate} ${alsa_shorts}"
WAIT_JACKD="2s"
IODELAY_TIMEOUT="${run_period}s"
WAIT_IODELAY="2s"

if [ "$port_playback" == "" ] || [ "$port_capture" == "" ]; then
  skip_test "No playback or capture Jack port is specified. Skip the test."
fi

check_jackd_configured()
{
  dlogi "Check Jack server can be started"
  dlogc "jackd ${JACKD_OPTIONS} -d ${JACKD_BACKEND} ${JACKD_BACKEND_OPTIONS}"
  # shellcheck disable=SC2086
  JACK_NO_AUDIO_RESERVATION=1 timeout --kill-after ${RUN_PERIOD_MAX} ${run_verbose} ${JACKD_TIMEOUT} \
      jackd ${JACKD_OPTIONS} -d ${JACKD_BACKEND} ${JACKD_BACKEND_OPTIONS} & jackdPID=$!

  sleep ${WAIT_JACKD}

  dlogc "jack_lsp"
  jack_lsp -AclLpt

  dlogi "Waiting Jackd to stop without a client"
  wait ${jackdPID}
}

collect_latency_data()
{
  dlogi "Start collecting latency data"
  dlogc "jackd ${JACKD_OPTIONS} -d ${JACKD_BACKEND} ${JACKD_BACKEND_OPTIONS}"
  # shellcheck disable=SC2086
  JACK_NO_AUDIO_RESERVATION=1 timeout --kill-after ${RUN_PERIOD_MAX} ${run_verbose} ${JACKD_TIMEOUT} \
      jackd ${JACKD_OPTIONS} -d ${JACKD_BACKEND} ${JACKD_BACKEND_OPTIONS} & jackdPID=$!

  sleep ${WAIT_JACKD}
  dlogc "jack_iodelay"
  # shellcheck disable=SC2086
  timeout --kill-after ${RUN_PERIOD_MAX} ${run_verbose} ${IODELAY_TIMEOUT} \
      stdbuf -oL -eL jack_iodelay | \
      tee >(AWKPATH="${TESTLIB}:${AWKPATH}" \
          gawk -f "${TESTLIB}/jack_iodelay_metrics.awk" > "${LOG_ROOT}/metrics.json") & iodelayPID="$!"

  sleep ${WAIT_IODELAY}
  dlogi "jack_connect:  ${port_capture} ==>[jack_delay]==> ${port_playback}"
  jack_connect jack_delay:out "${port_playback}" && jack_connect jack_delay:in "${port_capture}"

  dlogi "Latency data collection"
  wait ${jackdPID} ${iodelayPID}

  if [ ! -f "${LOG_ROOT}/metrics.json" ] || [ "$(grep -ce 'metrics' "${LOG_ROOT}/metrics.json")" -lt 1 ]; then
    skip_test "No metrics collected"
  fi

  dlogi "Latency data collection completed."
}

compose_report()
{
  dlogi "Compose ${RESULT_JSON}"
  echo -n "{\"options\":{$(options2json)}," > "${RESULT_JSON}"
  cat "${LOG_ROOT}/metrics.json" >> "${RESULT_JSON}" && rm "${LOG_ROOT}/metrics.json"
  echo "}" >> "${RESULT_JSON}"
  cat "${RESULT_JSON}"
}

check_test_result()
{
  dlogi "Check test result in ${RESULT_JSON}"
  xruns=$(jq '.metrics[] | select(.xruns > 0).xruns' "${RESULT_JSON}")
  if [ -n "$xruns" ] && [ "$xrun_error" ]; then
    skip_test "XRuns ${xruns} detected!"
  fi
}

main()
{
  setup_kernel_check_point

  start_test

  logger_disabled || func_lib_start_log_collect

  # TODO: should we set volume to some pre-defined level (parameterized)
  # reset_sof_volume
  # set_alsa_settings

  check_jackd_configured

  collect_latency_data

  compose_report

  check_test_result
}

{
  main "$@"; exit "$?"
}
