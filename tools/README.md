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

* tplgtool2.py
<br> Dumps info from tplg binary file.
     SOF CI uses this to generate a topology graph.

* tplgtool.py
<br> Dumps info from tplg binary file. sof-tplgreader.py still use this but new features
     will go to tplgtool2.py. When all functions are migrated to tplgtool2.py
     it will be deprecated.
