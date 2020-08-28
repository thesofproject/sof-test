# DPMST test
DisplayPort Multi-Stream Transport is a manual test.

# Preconditions
1. Hardware requirements met for each DPMST case

# Test Description
* Test output from one test unit to (minimum of) two separate monitors with audio
  output via DP (as well as with USB-C and HDMI adapters if monitors have those
  inputs available).

# 1) Single DP -> Multi DP hub Test Case:
## Hardware Requirements
1. One DP-MST hub with single DP input -> multi-DP output
2. Two monitors with DP input and audio output
3. Two DP-USB-C adapters (if monitors also have USB-C input)
4. Two DP-HDMI adapters (if monitors also have HDMI input)
* If DP-MST hub has additional outputs, test can be extended to include
  additional monitors as availble

## Run Instructions
1. Two monitors are connected via one DP hub using DP-DP cables.
2. Run:
   ```
   amixer contents | grep -i jack -A 2
   ```
   to ensure DP jacks on DP hub are detected.
3. Run aplay, using the 2 DP jacks found with `amixer contents` command.
   ```
   aplay -D $dev(jack1) -r $rate -c 2 -f $fmt -d 3 resource/raw/test<specified>.raw
   aplay -D $dev(jack2) -r $rate -c 2 -f $fmt -d 3 resource/raw/test<specified>.raw
   ```
4. Connected monitors should both show display and play audio.
5. Check journalctl -k for any unexpected errors.
* If monitors have USB-C / HDMI input as well, test can also be run with:
  * DP hub -> DP cable + DP-USB-C adapters -> monitors
  * DP hub -> DP cable + DP-HDMI adapters -> monitors

# 2) Daisy Chain Test Case:
## Hardware Requirements
1. One monitor with DP input **AND** ouput, as well as audio output (monitor1)
2. An additional monitor with DP input and audio output (monitor2)
3. Two DP-USB-C adapters (if monitors also have USB-C input)
4. Two DP-HDMI adapters (if monitors also have HDMI input)
* Test can be extended to include additional monitors if hardware is available.

## Run Instructions
1. Monitors are connected via:
   test unit -> DP cable -> monitor1 -> DP cable -> monitor2
* Make sure DP 1.2 is enabled in the monitor on screen display menu as well
2. Run:
   ```
   amixer contents | grep -i jack -A 2
   ```
   to ensure DP jacks on monitors are detected.
3. Run 2 aplay processes, using the 2 DP jacks found with `amixer contents` command.
   ```
   aplay -D $dev(jack1) -r $rate -c 2 -f $fmt -d 3 resource/raw/test<specified>.raw
   aplay -D $dev(jack2) -r $rate -c 2 -f $fmt -d 3 resource/raw/test<specified>.raw
   ```
4. Connected monitors should both show display and play audio.
5. Check journalctl -k for any unexpected errors.
* If monitors have USB-C / HDMI input as well, test can also be run with:
  * test unit -> DP cable + DP-USB-C adapter -> monitor1 -> DP cable + DP-USB-C
  adapter -> monitor2
  * test unit -> DP cable + DP-HDMI adapter -> monitor1 -> DP cable + DP-HDMI
  adapter -> monitor2

# Expect result (both cases)
* Display and audio to monitors is as expected.
* No unexpected journalctl -k errors on testing unit.
