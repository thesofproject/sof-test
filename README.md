# SOF Test Case repo
- [SOF Test Case repo](#sof-test-case-repo)
  - [Environment set up](#environment-set-up)
    - [requirements](#requirements)
      - [apt packages](#apt-packages)
      - [user group](#user-group)
    - [env-check.sh](#env-checksh)
  - [Usage](#usage)
    - [test cases](#test-cases)
    - [tools](#tools)
    - [test case result](#test-case-result)
  - [Folder description](#folder-description)
  - [Tools list description](#tools-list-description)
## Environment set up
### requirements
#### apt packages
expect alsa-utils python3 python3-graphviz
```
sudo apt install expect alsa-utils python3 python3-graphviz
```
#### user group
sudo adm audio

### env-check.sh
You can use this script to ensure the sof-test environment is set up properly

## Usage
### test cases
To run a test, call the scripts directly
 * `-h` will show the usage for the test

Example:
```
~/sof-test/test-case$ SOF_ALSA_OPTS='-q --fatal-errors' ./check-playback.sh -h
Usage: ./check-playback.sh [OPTION]

    -F |  --fmts
	    Iterate all supported formats
	    Default Value: Off
    -d parameter |  --duration parameter
	    aplay duration in second
	    Default Value: 10
    ...
```
```
~/sof-test/test-case$ ./check-playback.sh -d 4
2020-03-19 22:13:32 UTC [INFO] no source file, use /dev/zero as dummy playback source
2020-03-19 22:13:32 UTC [INFO] ./check-playback.sh using /lib/firmware/intel/sof-tplg/sof-apl-pcm512x.tplg as target TPLG to run the test case
2020-03-19 22:13:32 UTC [INFO] Catch block option from TPLG_BLOCK_LST will block 'pcm=HDA Digital,Media Playback,DMIC16k' for /lib/firmware/intel/sof-tplg/sof-apl-pcm512x.tplg
2020-03-19 22:13:32 UTC [INFO] Run command: 'sof-tplgreader.py /lib/firmware/intel/sof-tplg/sof-apl-pcm512x.tplg -f type:playback,both -b pcm:'HDA Digital,Media Playback,DMIC16k' -s 0 -e' to get BASH Array
2020-03-19 22:13:32 UTC [INFO] Testing: (Round: 1/1) (PCM: Port5 [hw:0,0]<both>) (Loop: 1/3)
2020-03-19 22:13:32 UTC [COMMAND] aplay -q --fatal-errors  -Dhw:0,0 -r 48000 -c 2 -f S16_LE -d 4 /dev/zero -v -q
    ...
```

Some tests support SOF_ALSA_OPTS, SOF_APLAY_OPTS and SOF_ARECORD_OPTS,
work in progress. Where supported, optional parameters in SOF_APLAY_OPTS
and SOF_ARECORD_OPTS are passed to all aplay and arecord
invocations. SOF_ALSA_OPTS parameters are passed to both aplay and
arecord. Warning these environments variables do NOT support parameters
with whitespace or globbing characters, in other words this does NOT
work:

   SOF_ALSA_OPTS='--foo --bar="spaces do not work"'

For the up-to-date list of tests supporting these environment variables
run:

    git grep -l 'a[[:alnum:]]*_opts'

### tools
To use tool script, call the scripts directly
 * `-h` will show the usage for the tool

Example:
```
$ ./tools/sof-dump-status.py -p
apl
```

### test case result
| exit code | display | description            |
| --------- | ------- | ---------------------- |
| 0         | PASS    | Test has passed        |
| 1         | FAIL    | Test has failed        |
| 2         | N/A     | Test is not applicable |
| *         |         | unknown exit status    |

## Folder description
* case-lib
<br> Test case helper functions library

* test-case
<br> The test cases

* tools
<br> Script helper tools for the test cases.
<br> Can also be used directly via the command line
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

* sof-combinatoric.py
<br> Used to compute permutations or combinations of the various pipelines
     avilable during tests if multiple are needed at once.

* sof-disk-usage.sh
<br> Used to ensure we have enough disk space to collect logs and avoid system
     problems.

* sof-dump-status.py
<br> Dump the sound card status

* sof-get-default-tplg.sh
<br> Load the tplg file name from system log which is recorded from system bootup

* sof-get-kernel-line.sh
<br> Print all kernel versions and their line numbers from /var/log/kern.log,
     with the most recent <first/last>

* sof-kernel-dump.sh
<br> Catch all kernel information after system boot up from /var/log/kern.log file

* sof-kernel-log-check.sh
<br> Check dmesg for errors and ensure that any found are real errors

* sof-process-kill.sh
<br> Kills aplay or arecord processes

* sof-process-state.sh
<br> Shows the current state of a given process

* sof-tplgreader.py
<br> tplgtool.py wrapper, it reads info from tplgtool.py to analyze topologies.

* tplgtool.py
<br> Dumps info from tplg binary file.
