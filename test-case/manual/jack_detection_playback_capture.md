# Jack detection for headset/HDMI/DP in during playback and capture test
Jack detection for headset/HDMI/DP during playback / capture is part of a series of manual
tests.

# Preconditions
1. Runtime PM status is on.
2. aplay (playback) or arecord (capture) is running.

# Test Description
* While aplay/arecord is running, plug headset into unit, and determine if
status is updated as expected.
* Repeat for both HDMI and DisplayPort if available.

## Headset
1. In terminal 1: run aplay/arecord via:
    ```
    aplay -Dhw:0,0 -r 48000 -c 2 -f s16_le -d 60 /dev/zero
    arecord -Dhw:0,0 -r 48000 -c 2 -f s16_le -d 60 /dev/null
    ```
2. Plug headset into applicable jack.
   - Can be 3.5 mm, 2.5 mm, or USB type-C if available.
3. In terminal 2: check amixer contents via:
    ```
    watch -d -n 1 "amixer contents | grep -i jack -A 2"
    ```
    Jack information for headset should indicate **ON**.
4. Check system sound settings for any updates to output options.
5. Close system sound settings.
6. While aplay/arecord is still running, unplug headset.
7. Watch amixer contents for update:
   - Jack information for headset should indicate **OFF**.
8. Again check system sound settings for any updates to output options.
9. Check dmesg for any unexpected errors.
10. Repeat as necessary.

## HDMI / DP
1. Same as headset instructions, but test HDMI, DP, and USB Type-C output as
available

## Expect result
* While aplay/arecord is running, data value for inserted / removed jack
should flip between off and on.
* No unexpected errors should be present in dmesg during or after test
completion.

### Notes
* The various jacks (headset/HDMI/DP) are all named differently on each platform,
    so there is no universal "data value to look for when testing headset". The
    best way to determine where you need to look is to run:
    ```
    watch -d -n 1 "amixer contents | grep -i jack -A 2"
    ```
    then insert & remove jack while watching to see what value flips off/on.
    * For example -- data change on two different platforms:
    ```
      Platform 1:
      numid=17,iface=CARD,name='Front Headphone Jack'
        ; type=BOOLEAN,access=r-------,values=1
        : values=off/on
    ```
    ```
      Platform 2:
      numid=20,iface=CARD,name='Headphone Surround Jack'
        ; type=BOOLEAN,access=r-------,values=1
        : values=off/on
    ```
