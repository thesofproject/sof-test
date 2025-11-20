# Probes test
Simple probes functionality test.

# Preconditions
1. Linux kernel should have these config options enabled:
   CONFIG_SND_SOC_SOF_DEBUG_PROBES=y
   CONFIG_SND_SOC_SOF_HDA_PROBES=y

   These options are not user selectable but are automatically
   selected by the SOF platform options supporting probes. These
   platforms select SND_SOC_SOF_INTEL_SKL/APL/CNL/ICL/TGL/MTL. Those
   options in term select SND_SOC_SOF_HDA_COMMON, which selects
   SND_SOC_SOF_HDA_PROBES, which selects SND_SOC_SOF_DEBUG_PROBES.

2. Firmware should have these config options enabled:
   CONFIG_PROBE=y

   The following defaults are Ok:
   CONFIG_PROBE_POINTS_MAX=16
   CONFIG_PROBE_DMA_MAX=4

   In fact PROBE_DMA_MAX is ignored as inection is not currently supported

2. Enable the module, by creating file /etc/modprobe.d/sof-probes.conf, with
   following line as content:
   options snd_sof_probes enable=1

3. Add following line to /etc/modprobe.d/sof.conf:
   options snd slots=,,,snd_sof_probes

   to make the sound card for the probes to be locked at card3.

4. Have tiny compress installed:
   git clone https://github.com/alsa-project/tinycompress.git
   sudo ./gitcompile --prefix= $OUT
   sudo make install

5. Have sof-probes from sof/tools/probes installed


# Test Description
* Enable probe capture, start playback, bind the probe capture to a buffer
  in playback pipeline, convert the capture to wav, verify the wav contains
  the content played.

  The probes functionality is described in more generic way here:
  https://github.com/thesofproject/sof-docs/blob/master/developer_guides/debugability/probes/index.rst

# Simple probe capture case
## Check preconditions
1. Look for comprY under /proc/asound/cardX/, you should find for example:
   /proc/asound/card3/compr0/
2. Check that you have a working tiny compress "crecord" binary available.
3. Check that you have a working sof tools "sof-probes" binary available.

## Run Instructions
1. Start a capture on probe alsa device (3 and 0 are from
   /proc/asound/card3/compr0):
   ```
   crecord -c3 -d0 -b8192 -f4 -FS32_LE -R48000 -C4 /tmp/extract.wav
   ```
2. Start a playback
   ```
   aplay -Dplughw:0,0 test.wav -v -q
   ```

3. Bind probe capture to a buffer on playback pipeline (as super user):
   ```
   echo 36,1,0 >  /sys/kernel/debug/sof/probe_points
   ```
   The first number refers to the playback buffer being captured (it should be
   found from the topology), second tells its a capture (always 1 as insertion
   is not supported), and the last number is ignored in capture case.

4. See that the probes capture file is growing:
   ```
   ls -l /tmp/extract.wav
   ```   

5. Convert the captured file to a regular wav-file:
   ```
   sof-probes -p /tmp/extract.wav
   ```

6. Check that the resulting wav-file resembles the one that was being played
   during the capture:
   ```
   aplay -Dplughw:0,0 buffer_36.wav -v -q
   ```
