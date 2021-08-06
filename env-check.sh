#!/bin/bash

set -e

mydir=$(cd "$(dirname "$0")"; pwd)

# enable dynamic debug logs for SOF modules
DYNDBG="/etc/modprobe.d/sof-dyndbg.conf"

# check for the system package
func_check_pkg(){
    if command -v "$1" >/dev/null; then
        return
    else
        out_str="$out_str""\tPlease install the \e[31m $1 \e[0m package\n"
        check_res=1
    fi
}

func_check_python_pkg(){
    if command -v python3 >/dev/null; then
        if python3 -c "import $1" &> /dev/null; then
            return
        else
            out_str="$out_str""\tPlease install the \e[31m python3-$1 \e[0m package\n"
            check_res=1
        fi
    else
        return
    fi
}

func_check_file(){
    if [ -e "$1" ]; then
        return
    fi
    out_str="$out_str""Optional: Enable dynamic debug logs in \e[31m $1 \e[0m file\n\tFor example,\n\toptions snd_sof dyndbg=+p\n\toptions snd_sof_pci dyndbg=+p\n"
    check_res=1
}

func_check_exec_binary() {
    if ! type "$1" &> /dev/null; then
        out_str="$out_str""\tExecutable \e[31m $1 \e[0m not found, please put $1 in PATH\n"
        check_res=1
    fi
}

out_str="" check_res=0
printf "Checking for some OS packages:\t\t"
func_check_pkg expect
func_check_pkg aplay
func_check_pkg python3
# jq is command-line json parser
func_check_pkg jq
func_check_python_pkg graphviz
func_check_python_pkg numpy
func_check_python_pkg scipy
func_check_file "$DYNDBG"
func_check_exec_binary sof-logger
func_check_exec_binary sof-ctl
if [ $check_res -eq 0 ]; then
    printf "pass\n"
else
    printf '\e[31mWarning\e[0m\n'
# Need ANSI color characters to be the format string. This is not
# unsanitized input.
# shellcheck disable=SC2059
    printf "$out_str"
fi

# octave packages are required only for check-volume-levels.sh
# Good to check upfront but this can be optional requirement
out_str="" check_res=0
func_check_pkg octave
func_check_pkg octave-signal
func_check_pkg octave-io
if [ $check_res -eq 0 ]; then
    printf "pass for Octave packages\n"
else
    printf 'Optional: Octave packages are required for check-volume-levels.sh\n'
# Need ANSI color characters to be the format string. This is not
# unsanitized input.
# shellcheck disable=SC2059
    printf "$out_str"
fi

# check for the tools folder
out_str="" check_res=0
echo -ne "Checking exec permissions in tools/ directory:\t\t"

cd "$mydir"

if stat -c "%n %A" ./tools/* | grep -v 'x$'; then
    check_res=1; out_str=$out_str"\n
\tMissing execution permission for some script/binary in tools/ directory\n
\tWarning: you need to make sure the current user has execution permssion\n
\tPlease use the following command to give execution permission:\n
\tchmod a+x ${mydir}/tools/*\e[0m"
fi
[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:$out_str"

out_str="" check_res=0
echo -ne "Checking exec permissions in test-case/ directory:\t\t"
if stat -c "%n %A" ./test-case/* |grep -v 'x$';then
   check_res=1; out_str="\n
\tMissing execution permission for some script/binary in test-case/ directory\n
\tWarning: you need to make sure the current user has execution permssion\n
\tPlease use the following command to give execution permission:\n
\tchmod a+x ${mydir}/test-case/*\e[0m"
fi
[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:$out_str"

out_str="" check_res=0
echo -ne "Checking group memberships:\t\t"

if [[ "$SUDO_USER" ]]; then
    user="$SUDO_USER"
elif [[ "$UID" -ne 0 ]]; then
    user="$USER"
else
    user=""
fi

check_group()
{
    local grp="$1" errmsg="$2"
    if getent group "$grp" | grep -q "$user"; then return 0; fi

    check_res=1
    out_str=$out_str"\n
${errmsg}
\t\tPlease use the following command to add current user to the group $grp:\n
\t\e[31m sudo usermod --append --groups $grp $user\e[0m
"
}

check_group adm '\tMissing permission to access /var/log/kern.log\n'
check_group sudo '\tMissing permission to run command as sudo\n'
check_group audio '\tMissing audio group membership to access /dev/snd/* devices\n'

[[ ! -e "/var/log/kern.log" ]] && \
check_res=1 && out_str=$out_str"\n
\tMissing /var/log/kern.log file, which is where we'll catch the kernel log\n
\t\tPlease create the \e[31mlink\e[0m of your distribution kernel log file at \e[31m/var/log/kern.log\e[0m"

[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:$out_str"

out_str="" check_res=0
echo -ne "Checking the config setup:\t\t"
# shellcheck source=case-lib/config.sh
source  "${mydir}/case-lib/config.sh"
# effect check
case "$SUDO_LEVEL" in
    '0'|'1'|'2')
        if [[ "$SUDO_LEVEL" -eq 2 ]]; then
            [[ ! "$SUDO_PASSWD" ]] &&  check_res=1 && out_str=$out_str"\n
\tPlease setup \e[31mSUDO_PASSWD\e[0min ${mydir}/case-lib/config.sh file\n
\t\tIf you don't want modify to this value, you will need to export SUDO_PASSWD\n
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
\t\tPossible permission error occurred during script execution. Please ensure\n
\t\tthe permissions are properly set up according to instructions."

[[ $check_res -eq 0 ]] && echo "pass" || \
    echo -e "\e[31mWarning\e[0m\nSolution:$out_str"
