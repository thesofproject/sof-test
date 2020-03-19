# Linux#1762 Regression test
The missing SOF firmware and tplg tests are regression tests based on a sof_probe function failure documented in [linux#1762](https://github.com/thesofproject/linux/issues/1762)

# Preconditions
PulseAudio should be enabled

# Test Description
* Check that system does not hang when expected SOF fw and tplg are missing and letting sof_probe functions fail. Once they are restored, check to make sure all is working properly

## Test Case:
1. Test check-fail-no-fw.md
2. Test check-fail-no-tplg.md
3. `sudo rmmod snd_sof_pci` -> System should not hang
4. `sudo rtcwake -m mem -s 10` -> System should not hang

## Expected results
* System should not hang when expected SOF fw and tplg are missing 

