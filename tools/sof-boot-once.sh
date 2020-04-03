#!/bin/bash

if [ $UID -ne 0 ]; then
    echo "ERROR: user is not root. This script needs to access /etc/rc.local."
    echo "User must be root in order to run script. Exiting."
    exit 0
fi

cd $(dirname $0)
boot_full_name="$PWD/$(basename $0)"
cd $OLDPWD

boot_exec_file="/etc/rc.local"
# because Ubuntu 18.04 doesn't have an /etc/rc.local file, create it
if [ ! -f "$boot_exec_file"  ]; then
    echo "Missing $boot_exec_file Now creating it."
cat > /etc/rc.local << END

exit 0
END
    chmod +x $boot_exec_file
fi

boot_once_flag=$(grep $(basename $0) $boot_exec_file -n)
boot_once_flag=${boot_once_flag/:*/}

if [ "$#" -ne 0 ]; then
    # convert cmd to the cmd full path, because in the rc.local it just support PATH=/bin:/sbin:/usr/bin:/usr/sbin
    cmd_path=$(dirname $(which $1) 2>/dev/null)
    if [ "X${cmd_path/\/*/}" == "X." -o -d "$cmd_path" ]; then #relative path
        cd $cmd_path
        cmd=$PWD/$(basename $1)
        cd $OLDPWD
        shift
    elif [ "X${cmd_path:0:1}" == "X/" ]; then #absolute path
        cmd=$cmd_path/$(basename $1)
        shift
    elif [ "$(type -t $(basename $1))" == "builtin" ]; then #shell builtin command
        cmd=$(basename $1)
        shift
    else # Missing cmd_path means it couldn't find this cmd in the path, so no change
        exit
    fi
    [[ ! "$boot_once_flag" ]] && echo $boot_full_name >> $boot_exec_file
    echo "$cmd $*" >> $boot_exec_file
else
    # clean up the boot once flag to force it to the end
    [[ "$boot_once_flag" ]] && \
        sed -i "$boot_once_flag,\$d" $boot_exec_file
fi

# now add rc.local exit status
sed -i '/^exit/d' $boot_exec_file
echo "exit 0" >> $boot_exec_file
