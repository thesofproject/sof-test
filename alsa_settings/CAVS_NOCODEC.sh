set -e

# to set the volume as 0dB we have to use the scontrol interface
amixer -Dhw:0 scontrols | sed -e "s/^.*'\(.*\)'.*/\1/" | while read -r mixer_name; do
     amixer -Dhw:0 -- sset "$mixer_name" 0dB;
done

# to turn the switches on we have to use the control interface
amixer -Dhw:0 controls | grep Switch | sed -e 's/.*numid=\([^,]*\),.*/\1/' | while read -r i; do
    amixer -Dhw:0 cset numid=$i on;
done
