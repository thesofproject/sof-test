#!/bin/bash

rm -rf blob
preamble_time=0
history_depth=0
format=s16_le
buffer_size=68000
max_loop=100
preamble_time_init=2100
history_depth_init=1800
str=$(amixer contents | grep "Detector")
control=${str#*=}
control_id=${control%%,*}


usage(){
        echo "Wrong parameters, please specify the test item"
        echo "Eg: '-p' preamble_time, '-h' history_depth, '-f' format and '-s' period-size\
        ./$0 -p 2500 -h 3000 -f s16_le -s 500"
}

# DEC to HEX
dec2hex(){
        printf "%x" "$1"
}

_save_def(){
	echo "Save WoV as default configure blob:"
	if [ ! -f detector-default-config ]; then
		sudo sof-ctl -Dhw:0 -n "$control_id" -br -o detector-default-config
	fi
}

_set_default(){
	echo "Set WoV as default configure blob:"
	sudo sof-ctl -Dhw:0 -n "$control_id" -br -s detector-default-config
}

# get the preamble time and history depth
_get_pt_hd(){
	_set_default
        # save current WoV configure blob
	sof-ctl -Dhw:0 -n "$control_id" -br -o blob
	def_1st=x08
	def_snd=x34

}

# set the preamble time & history depth
_set_pt_hd(){
        preamble_time_aft=$(dec2hex $preamble_time)
	length_pt=$(echo "$preamble_time_aft" |wc -L)
	if [ "$length_pt" -eq 3 ]; then
		preamble_time_aft=0$preamble_time_aft
	fi
	pt_aft_1st=$(echo "$preamble_time_aft" |cut -c 1-2)
	pt_aft_1st=x$pt_aft_1st
	pt_aft_snd=$(echo "$preamble_time_aft" |cut -c 3-4)
	pt_aft_snd=x$pt_aft_snd
        history_depth_aft=$(dec2hex $history_depth)
	length_hd=$(echo "$history_depth_aft" |wc -L)
	if [ "$length_hd" -eq 3 ]; then
		history_depth_aft=0$history_depth_aft
	fi
	hd_aft_1st=$(echo "$history_depth_aft" |cut -c 1-2)
	hd_aft_1st=x$hd_aft_1st
	hd_aft_snd=$(echo "$history_depth_aft" |cut -c 3-4)
	hd_aft_snd=x$hd_aft_snd
}

# update the blob
_update_blob(){
	sed -i 's/\'"$def_snd"'\'"$def_1st"'/\'"$hd_aft_snd"'\'"$hd_aft_1st"'/g' blob 
	sed -i '1s/\'"$hd_aft_snd"'\'"$hd_aft_1st"'/\'"$pt_aft_snd"'\'"$pt_aft_1st"'/1' blob 
	sof-ctl -Dhw:0 -n "$control_id" -br -s blob # write back the new blob
}	

while getopts :p:h:f:s: OPTION;do
	case $OPTION in
		p)preamble_time=$OPTARG
		;;
                h)history_depth=$OPTARG
		;;
		f)format=$OPTARG
		;;
		s)period_size=$OPTARG
		;;
		?)usage
		exit;;
	esac
done
if [ "$preamble_time" == 0 ]; then
	preamble_time="$preamble_time_init"
fi
if [ "$history_depth" == 0 ]; then
	history_depth="$history_depth_init"		
fi
if [ "$preamble_time" -lt "$history_depth" ]; then
        echo "Warning: invalid arguments, preamble_time must be greater than or equal to history_depth"
        exit 1
fi

_save_def
_get_pt_hd
_set_pt_hd
_update_blob
	
# test with arecord
for (( i=1; i <= "$max_loop"; i++ ));
do
	file_name='wov_pt'-"$preamble_time"'_hd'-"$history_depth"'_f-'"$format"'_ps'-"$period_size"'.wav'
	if arecord -Dhw:0,8 -M -N -c 2 -f "$format" --buffer-size="$buffer_size" -r 16000 -vvv -d 5 "$file_name";then
		echo "WoV test passed, please check the recorded wav file: wov_pt-""$file_name"
	else
		echo "WoV test failed, please have a check"
		exit 1
	fi
done
