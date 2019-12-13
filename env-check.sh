#!/bin/bash

# check for the system package
out_str=""
func_check_pkg(){
    which $1 >/dev/null
    [[ $? -ne 0 ]] && \
    out_str=$out_str"\nPlease install \e[31m $1 \e[0m package" && \
    check_res=1
}
check_res=0
echo -ne "Check for the package:\t\t"
func_check_pkg expect
func_check_pkg gcc
func_check_pkg aplay
func_check_pkg python3
[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:"$out_str

# check for the tools folder
old_path=$PWD
cd $(dirname $0)/tools/
out_str="" check_res=0
echo -ne "Check for tools folder:\t\t"

[[ "$(stat -c "%A" * |grep -v 'x')" ]] && check_res=1 && out_str=$out_str"\n
\tMissing execution permission of script/binary in tools folder\n
\tWarning: you need to make sure the current user has execution permssion\n
\tPlease use the following command to give execution permission:\n
\t\e[31mcd $(dirname $0)\n
\tchmod a+x tools/*\e[0m"
[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:"$out_str

out_str="" check_res=0
cd $old_path
cd $(dirname $0)/test-case/
echo -ne "Checking for case folder:\t\t"
[[ "$(stat -c "%A" * |grep -v 'x')" ]] && check_res=1 && out_str="\n
\tMissing execution permission of script/binary in test-case folder\n
\tWarning: you need to make sure the current user has execution permssion\n
\tPlease use the following command to give execution permission:\n
\t\e[31mcd $(dirname $0)\n
\tchmod a+x test-case/*\e[0m"
[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:"$out_str
cd $old_path

out_str="" check_res=0
echo -ne "Checking the permission:\t\t"
if [[ "$SUDO_USER" ]]; then
    user="$SUDO_USER"
elif [[ "$UID" -ne 0 ]]; then
    user="$USER"
else
    user=""
fi
[[ "$user" ]] && [[ ! $(awk -F ':' '/^adm:/ {print $NF;}' /etc/group|grep "$user") ]] && \
check_res=1 && out_str=$out_str"\n
\tMissing permission to access /var/log/kern.log\n
\t\tPlease use the following command to add current user to the adm group:\n
\t\e[31msed -i '/^adm:/s:$:,$user:g' /etc/group\e[0m"

[[ "$user" ]] && [[ ! $(awk -F ':' '/^sudo:/ {print $NF;}' /etc/group|grep "$user") ]] && \
check_res=1 && out_str=$out_str"\n
\tMissing permission to run command as sudo\n
\t\tPlease use the following command to add current user to the sudo group:\n
\t\e[31msed -i '/^sudo:/s:$:,$user':g' /etc/group\e[0m"

[[ "$user" ]] && [[ ! $(awk -F ':' '/^audio:/ {print $NF;}' /etc/group|grep "$user") ]] && \
check_res=1 && out_str=$out_str"\n
\tMissing permission to access sound card\n
\t\tPlease use the following command to add current user to the audio group:\n
\t\e[31msed -i '/^audio:/s:$:,$user':g' /etc/group\e[0m"

[[ ! -e "/var/log/kern.log" ]] && \
check_res=1 && out_str=$out_str"\n
\tMissing /var/log/kern.log file, which is where we'll catch the kernel log\n
\t\tPlease create the \e[31mlink\e[0m of your distribution kernel log file at \e[31m/var/log/kern.log\e[0m"

[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:"$out_str

out_str="" check_res=0
echo -ne "Checking the config setup:\t\t"
source  $(dirname $0)/case-lib/config.sh
# effect check
case "$SUDO_LEVEL" in
    '0'|'1'|'2')
        if [[ "$SUDO_LEVEL" -eq 2 ]]; then
            [[ ! "$SUDO_PASSWD" ]] &&  check_res=1 && out_str=$out_str"\n
\tPlease setup \e[31mSUDO_PASSWD\e[0min $(dirname $0)/case-lib/config.sh file\n
\t\tIf you don't want modify this value, you will need to export SUDO_PASSWD\n
\t\tso our scripts can access debugfs, as some test cases need it.\n
\t\tYou also can modify the SUDO_LEVEL to 1, using visudo to modify the permission"
        fi
        ;;
    *)
        if [[ "$SUDO_LEVEL" ]]; then
            check_res=1 && out_str=$out_str"\n
\tSUDO_LEVEL only accepts 0-2\n
\t\t\e[31m0\e[0m: means: run as root, don't need to preface with sudo \n
\t\t\e[31m1\e[0m: means: run sudo command without password\n
\t\t\e[31m2\e[0m: means: run sudo command, but need password\n
\t\t\t\e[31mSUDO_PASSWD\e[0m: Is the sudo password sent to the sudo command?"
        fi
        ;;
esac
[[ "$LOG_ROOT" ]] && [[ ! -d $LOG_ROOT ]] && check_res=1 && out_str=$out_str"\n
\tAlready setup LOG_ROOT, but missing the folder: $LOG_ROOT\n
\t\tMaybe in the script process will meet the permission issue, please check it."

[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:"$out_str
