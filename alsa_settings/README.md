# ALSA settings

SOF test case execution requires certain DSP and mixer configurations being set
on the DUT (Device Under Test). An important part of this configuration is the
signal levels adjusted to the hardware setup which runs the tests, including its
codec and loopback devices.

The `./alsa_settings/` directory contains custom ALSA configurations which
are currently applied at the SOF CI pipeline's hardware platforms.
When the SOF tests run in other environment, these confugurations can serve
as a reference.

These configurations include ALSA settings which are considered essential
for the SOF tests and expected at the appropriate DUT by default. They allow
ALSA settings tweaking in along with SOF and test developmnent, if needed.

Please note that in some cases the settings are tuned to CI DUT 'harnesses':
external codecs with their versions, audio cards at loopback connections, etc.
In the future, most of these settings should be moved to the DUT's default config
out of the test case scope, so only the test-specific settings will remain here.
For example, some platforms have their external USB audio card settings included
in the configuration files: it is needed to adjust loopback volume levels on
the appropriate DUT and harness setup.


## How it works

When a test case calls `set_alsa()` function, its task is to apply the DUT's
default ALSA configuration file as the baseline to ensure the expected ALSA
settings are active the same way as after the DUT's reboot, so to avoid
after-effects possible from the previous test's execution - either it was
success, or failure, or any other unexpected change due to the DUT's power
reset, the test case error, manual re-configuration, etc.

After `alsactl init` and `alsa restore` calls by `set_alsa()` function,
two optional custom settings are applied in the following order (assuming
the DUT belongs to a `PLATFORM` hardware configuration, and the configuration
files are in `./alsa_settings/` directory):

1. `PLATFORM.state` - an ALSA driver state file in `alsactl` format.

2. `PLATFROM.sh` - a shell script to configure the ALSA driver parameters,
   e.g. calling `amixer` tool.

The custom state should be compatible with the platform's default state.

It is important to avoid linking configuration files to 'reuse' them for
different HW configurations: the `.state` files have platform specific control
id's, whereas `amixer` command line tool refers to the sound card control by its name.


## DUT host expected configuration

The DUT host should NOT run `alsa-state.service`

The `alsa-restore.service` should work only in 'restore' mode (on start).
The 'store' mode (on shutdown) should be OFF to keep the default ALSA driver
settings not changed.

It is NOT allowed to change the DUT's default state with `alsactl store` unless
it is a special part of the test case, or a DUT recovery procedure.

For more details see [ALSA and systemd](https://wiki.archlinux.org/title/Advanced_Linux_Sound_Architecture#ALSA_and_systemd)


## How to create a custom .state file

1. Check contents of the DUT's default ALSA driver configuration `asound.state`.
   Usually, it is in `/var/lib/alsa/`, and under control of `alsa-restore.service`,
   or `alsa-state.service`. Make sure you have a backup copy of this file:
   the ALSA `.service`-s are in charge of keeping your current custom ALSA settings
   as the DUT's default, so it might unexpectedly affect your DUT's normal operations,
   unless it is your legitimate goal.

2. Copy the ALSA controls you need to change with their new values into the appropriate
   platform's `PLATFORM.state` file in `./alsa_settings/`, or create a shell script
   `PLATFORM.sh` there with the appropriate `amixer` calls.
   Both these methods can be applied simultaneously, although in the above mentioned order.

