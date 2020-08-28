# Jack detection for headset/HDMI/DP during boot test
Jack detection for headset/HDMI/DP during boot is part of a series of manual
tests.

# Preconditions
1. System is powered off.

# Test Description
* Plug events that occur during device power down are reflected when checked
  after device is powered on.
* Repeat for both HDMI and DisplayPort if available.

## Headset
1. Plug headset into applicable jack.
   - Can be 3.5 mm, 2.5 mm, or USB type-c if availble.
2. Power on system.
3. Check amixer contents via:
    ```
    amixer contents | grep -i jack -A 2
    ```
    - Jack information for headset should indicate **ON**.
4. Check system sound settings for any updates to output options.
5. Check journalctl -k for any unexpected errors.
6. Power off system.
7. Unplug headset.
8. Power on system.
9. Again check amixer contents.
   - Jack information for headset should indicate **OFF**.
10. Again check system sound settings for any updates to output options.
11. Check journalctl -k for any unexpected errors.
12. Repeat as necessary.

## HDMI / DP
1. Same as headset instructions, but test HDMI, DP, and USB Type-C output as
available

## Expect result
* Plug events that occur during device power down are reflected when checked
  after device is powered on:
    * Status is **ON** if inserted during power down cycle
    * Status is **OFF** if removed during power down cycle
* No unexpected errors should be present in journalctl -k during or after test
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
