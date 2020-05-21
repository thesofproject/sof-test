# Jack detection for headset/HDMI/DP in system suspended state test
Jack detection for headset/HDMI/DP in system suspend state is part of a series of manual
tests.

# Preconditions
1. System is syspended via `sudo su` then `echo freeze > /sys/power/state`

# Test Description
* Plug headset into jack, and determine if status is updated as expected.
* Repeat for both HDMI and DisplayPort if available.

## Headset
1. Plug headset into applicable jack during system suspended
   - Can be 3.5 mm, 2.5 mm, or USB type-c if available.
2. Tap keyboard to wake up system
3. Check amixer contents via:
    ```
    watch -d -n 1 "amixer contents | grep -i jack -A 2"
    ```
    - Jack information for headset should indicate **ON**.
4. Put system to suspend again via `echo freeze > /sys/power/state`
5. Unplug headset during system suspended then wake up system
6. Watch amixer contents for update:
   - Jack information for headset should indicate **OFF**.
7. Check system sound settings for any updates to output options.
8. Check dmesg for any unexpected errors.
9. Repeat as necessary.

## HDMI / DP
1. Same as headset instructions, but test HDMI, DP, and USB Type-C output as
available.

## Expect result
* Data value for jack plug event should flip between off and on.
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
