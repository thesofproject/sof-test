# SOF Test Case repo
- [SOF Test Case repo](#sof-test-case-repo)
  - [Status](#status)
  - [Enviroment set up](#enviroment-set-up)
    - [requirments](#requirments)
      - [apt packages](#apt-packages)
      - [user group](#user-group)
    - [env-check.sh](#env-checksh)
  - [Usage](#usage)
    - [test cases](#test-cases)
    - [tools](#tools)
  - [Folder description](#folder-description)
  - [Tools list description](#tools-list-description)

## Status
[![Build Status](https://travis-ci.org/thesofproject/sof-test.svg?branch=master)](https://travis-ci.org/thesofproject/sof-test)

## Enviroment set up
### requirments
#### apt packages
expect alsa-utils python3
```
sudo apt install expect alsa-utils python3
```
#### user group
sudo adm audio

### env-check.sh
You can use this scripts to check what you missed and follow the guide to set the enviroment

## Usage
### test cases
call the scripts directly.
-h will show the usage for the test

Example:
```
$ ./test-case/verify-sof-firmware-load.sh
2019-12-12 07:29:46 UTC [INFO] Checking SOF Firmware load info in kernel log
kernel: [    3.296245] sof-audio-pci 0000:00:0e.0: Firmware info: version 1:1:0-65de2
kernel: [    3.296247] sof-audio-pci 0000:00:0e.0: Firmware: ABI 3:12:0 Kernel ABI 3:12:0
kernel: [    3.296249] sof-audio-pci 0000:00:0e.0: Firmware debug build 1 on Dec  4 2019-21:17:51 - options:
kernel: [    3.296249]  GDB: disabled
kernel: [    3.296249]  lock debug: disabled
kernel: [    3.296249]  lock vdebug: disabled
2019-12-12 07:29:47 UTC [INFO] Test PASS!
```

### tools
call the scripts directly.
-h will show the usage for the tool

Example:
```
$ ./tools/sof-dump-status.py -p
apl
```

## Folder description
* case-lib
<br> Test case helper functions libary

* test-case
<br> Test case folder holds the test cases

* tools
<br> Script helper tools for setting up system.
<br> Can be used via the command line
<br> Filenames should have the "sof-" prefix

* logs
<br> Records in the test-case log folder.
<br> It will be auto created and follow the test name
<br> Ordered by time tag, the last link will link to the last run result

## Tools list description

* sof-boot-once.sh
<br> This script writes to rc.local, which is loaded and read after reboot.
<br> After rc.local command is run, the command will be removed.
<br> example: sof-boot-once.sh reboot
<br> Effect: when system boots up it will auto reboot again

* sof-dmesg-check.sh
<br> Check dmesg for errors
<br> Contains keyword lists to ensure we're stopping due to a real error.

* tplgtool.py
<br> tplgtool dump info from tplg binary file.

* sof-tplgreader.py
<br> tplgtool.py wrapper, it read info from tplgtool.py to analyze tplgs.

* sof-dump-status.py
<br> Dump the sound card status

* sof-process-clear.sh
<br> force confirm kill process

* sof-get-default-tplg.sh
<br> Load the tplg file name from system log which is recorded from system bootup

* sof-kernel-dump.sh
<br> catch all kernel information after system boot up from /var/log/kern.log file

* sof-get-kernel-line.sh
<br> print all kernel versions and their line numbers from /var/log/kern.log, with the most recent <first/last>

* sof-disk-usage.sh
<br> check current disk size for avoid system problem without enough space
