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
expect alsa-utils python3 python3-construct python3-graphviz
```
sudo apt install expect alsa-utils python3 python3-construct python3-graphviz
```
If you would like to use tinyALSA for testing, install tinyALSA and SoX.
- How to install tinyALSA: https://github.com/tinyalsa/tinyalsa
- To install SoX run below command:
```
sudo apt-install sox
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
Some tests support these environment variables (work in progress):
  - SOF_ALSA_TOOL is used to select the audio tool for testing.
  Set this variable to 'alsa' (default value) or 'tinyalsa' to choose between the ALSA and TinyALSA toolsets.
  - SOF_ALSA_OPTS contains optional parameters passed on both play and record.
  - SOF_APLAY_OPTS and SOF_ARECORD_OPTS contain optional parameters passed additionally on play and record respectively.
These options are applied to the selected tool (alsa or tinyalsa) based on the value of SOF_ALSA_TOOL 

Warning, these environment variables do NOT support parameters
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

See tools/README.md

## System configuration tips

### sudo noise

sof-test uses sudo a lot which creates a lot of noise in `journalctl`
output which is especially a problem when testing. To turn off that
noise first run `sudo visudo` and add the following line:

```
Defaults:USER_LOGIN,root !log_allowed
```
For more see `man sudoers`.

Then add the following line at the _top_ of `/etc/pam.d/sudo`

```
# Be "done" when the pam_succeed_if.so arguments are matched; don't
# process other lines. If not matched then "ignore" this line.
# Also support "double sudo" :-(
session [success=done default=ignore] pam_succeed_if.so quiet         uid = 0 ruser = root
session [success=done default=ignore] pam_succeed_if.so quiet_success uid = 0 ruser = USER_LOGIN
```

Note PAM security configuration is complex and
distribution-specific. This was tested only on Ubuntu 20.04. See `man
pam.d` or one of the PAM guides available on the Internet. Be careful
not to make your system vulnerable.

On systems using auditd, sof-test will also generate a huge amount of
log. If you need to keep `audit`, check `man auditctl` to find how to
filter out sudo noise.
