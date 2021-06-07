#!/bin/bash

set -e

sof_test_dir=$(cd "$(dirname "$0")"; cd ..; pwd)

function get_os_distro()
{
    grep -w ID /etc/os-release | awk -F= '{print $2}'
}

function die()
{
    printf "\e[31m%s\n\e[0m" "$*"
    exit 1
}

function common_env_setup()
{
    printf "Add user %s to audio group\n" "$SUDO_USER"
    if grep -q audio /etc/group | grep -q "$SUDO_USER"; then
        printf "User \e[32m%s\e[0m is already in audio group\n" "$SUDO_USER"
    else
        usermod --append --groups audio "$SUDO_USER"
    fi

    printf "Enable NOPASSWD mode for user %s\n" "$SUDO_USER"
    if grep -q "$SUDO_USER" /etc/sudoers; then
        printf "NOPASSWD mode is already enabled for %s\n" "$SUDO_USER"
    else
        echo "$SUDO_USER ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers
    fi

    printf "Copy dynamic debug file 'sof-dyndbg.conf' to /etc/modprobe.d\n"
    # Always use the latest file
    cp sof-dyndbg.conf /etc/modprobe.d
}

function env_setup_ubuntu()
{
    printf "TODO"
}

function env_setup_fedora()
{
    local PKGS="jq expect alsa-utils-alsabat python3-graphviz python3-numpy \
python3-scipy"

    printf "Install dependencies: %s\n" "$PKGS"
    # word splitting for $PKGS is wanted here
    # shellcheck disable=SC2086
    dnf install -y $PKGS
}

function env_setup_chrome()
{
    printf "TODO"
}

function manual_steps()
{
    if type sof-logger &> /dev/null; then
        printf "sof-logger is properly installed\n"
    else
        printf "\e[31mPlease manually download sof-logger to /usr/local/bin\e[0m\n"
    fi

    if type sof-ctl &> /dev/null; then
        printf "sof-ctl is properly installed\n"
    else
        printf "\e[31mPlease manually download sof-ctl to /usr/local/bin\e[0m\n"
    fi

    local platform
    platform=$("$sof_test_dir"/tools/sof-dump-status.py -p)
    if test -e "/etc/sof/sof-$platform.ldc"; then
        printf "%s is properly installed\n" "sof-$platform.ldc"
    else
        printf "\e[31mPlease manually download %s file to /etc/sof\e[0m\n" "sof-$platform.ldc"
    fi
}

function main()
{
    # check if we have root privilege
    CUR_UID=$(id -u)
    [ "$CUR_UID" == "0" ] || die "Need root privilege to run this script"

    OS_DISTRO=$(get_os_distro)
    printf "Your OS distribution is: \e[32m%s\e[0m\n" "$OS_DISTRO"

    common_env_setup

    case "$OS_DISTRO" in
    "ubuntu")
        env_setup_ubuntu
        ;;
    "fedora")
        env_setup_fedora
        ;;
    "chromeos")
        env_setup_chrome
        ;;
    *)
        ;;
    esac

    manual_steps
}

main
