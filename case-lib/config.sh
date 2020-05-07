#!/bin/bash

# this file is used for defining global variables

# Some variables need manual configuration
# Some commands need to access system node, so they need the sudo password
SUDO_PASSWD=${SUDO_PASSWD:-}

# global define
TPLG_ROOT=${TPLG_ROOT:-/lib/firmware/intel/sof-tplg}

# ignore the target keyword for tplg
# example: ignore 'pipeline ids equal to 2'
# TPLG_IGNORE_LST['id']='2'
# example: ignore 'pcms that are HDA Digital & HDA Analog'
# TPLG_IGNORE_LST['pcm']='HDA Digital,HDA Analog'
declare -A TPLG_IGNORE_LST
TPLG_IGNORE_LST['pcm']='HDA Digital,Media Playback,DMIC16k'

# If not set will be automatically set by logging_ctl function
# Test case log root
# EXAMPLE: the log for test-case/check-ipc-flood.sh will be stored at
#   logs/check-ipc-flood/last
# logs/check-ipc-flood is the link for logs/check-ipc-flood/$(run script date)
LOG_ROOT=${LOG_ROOT:-}

# If not set will be automatically set by log function
# store the sof-logger collect data into LOG_ROOT/case-name/last/
# EXAMPLE: the sof-logger will collect the data into this folder
SOFLOGGER=${SOFLOGGER:-}

# If not set will be automatically set by log function
# Target Sound Card ID, it will be used in func_pipeline_export for Device ID
# example: device id 0, pcm id 0: hw0,0; device id 1, pcm id 0: hw1,0;
SOFCARD=${SOFCARD:-}

# Decision must be made for how to load the root permission command
# 0: run cmd as root
# example: ls /sys/kernel/debug/
# 1: run cmd with sudo, but without sudo password
# example: sudo ls /sys/kernel/debug/
# 2: run cmd with sudo, but needs sudo password
# example: echo $SUDO_PASSWD | sudo -S ls /sys/kernel/debug/
SUDO_LEVEL=${SUDO_LEVEL:-}
