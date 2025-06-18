# Creating a .state file

1. Gain access to a machine you'd like to create a state file for.
2. Run `alsa-info` or use the print_alsa_info from the lib.sh file.
3. Copy the `!!Alsactl output` part of the `alsa-info` file to your `.state` file.
4. Modify values you'd like to set at a specific amount and delete the rest.
5. Name the file <MODEL_NAME>.state
