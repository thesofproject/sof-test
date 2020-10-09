#!/bin/bash

# Before using, please setup these options for the function
declare -A OPT_DESC_lst OPT_OPT_lst OPT_PARM_lst OPT_VALUE_lst

# option setup && parse function
func_opt_parse_option()
{
    # OPT_OPT_lst Used to define the parameter name
    # OPT_DESC_lst Used to define a short parameter description
    # OPT_PARM_lst set to 1 (default is 0, just a switch)
    # OPT_VALUE_lst Used to store the argument value

    # for example
    # OPT_OPT_lst['r']='remote'
    # OPT_DESC_lst['r']='Run for the remote machine'
    # OPT_PARM_lst['r']=1
    # OPT_VALUE_lst['r']='' ## if PARM=1, must be set, if PARM=0, can ignore

    # h & help is default option, so don't need to add into option list
    OPT_OPT_lst['h']='help'
    OPT_DESC_lst['h']='this message'
    OPT_PARM_lst['h']=0
    OPT_VALUE_lst['h']=0

    local _op_temp_script
    local -A _op_short_lst _op_long_lst

    _func_case_dump_descption()
    {
         grep '^##' "$SCRIPT_NAME"|sed 's/^##//g'
    }

    _func_create_tmpbash()
    {
        local i _short_opt _long_opt
        # loop to combine option which will be loaded by getopt
        for i in ${!OPT_DESC_lst[*]}
        do
            _short_opt=$_short_opt"$i"
            _op_short_lst["-$i"]="$i"
            [ "$_long_opt" ] && _long_opt="$_long_opt"','
            if [ "${OPT_OPT_lst[$i]}" ]; then
                _long_opt=$_long_opt"${OPT_OPT_lst[$i]}"
                _op_long_lst["--${OPT_OPT_lst[$i]}"]="$i"
            fi
            # append ':' if the option accepts an argument
            [ ${OPT_PARM_lst[$i]} -eq 1 ] && _short_opt=$_short_opt':' && _long_opt=$_long_opt':'
        done

        if  ! _op_temp_script=$(
                getopt -o "$_short_opt" --long "$_long_opt" -- "$@"); then
            # here output for the End-User who don't care about this function/option couldn't to run
            printf 'Error parsing options: %s\n' "$*"
            # To debug uncomment these lines:
            # printf 'DEBUG parsing options: short_opt: %s / long_opt: %s / args: %s\n' "$_short_opt" "$_long_opt" "$*" >&2
            # declare -p |grep -E 'OPT_[A-Z]*_lst|_op_'
            _func_opt_dump_help
        fi
    }

    _func_opt_dump_help()
    {
        local i
        printf 'Usage: %s [OPTION]\n' "$0"
        for i in ${!OPT_DESC_lst[*]}
        do
                [ "X$i" = "Xh" ] && continue
                # display short option
                [ "$i" ] && printf '    -%s' "$i"
                # have parameter
                [ "X${OPT_PARM_lst[$i]}" == "X1" ] && printf ' parameter'
                # display long option
                if [ "${OPT_OPT_lst[$i]}" ]; then
                    # whether display short option
                    [ "$i" ] && printf ' |  ' || printf '    '
                    printf '%s' "--${OPT_OPT_lst[$i]}"
                    [ "X${OPT_PARM_lst[$i]}" == "X1" ] && printf ' parameter'
                fi
                printf '\n\t%s\n' "${OPT_DESC_lst[$i]}"
                if [ "${OPT_VALUE_lst[$i]}" ]; then
                    if [ "${OPT_PARM_lst[$i]}" -eq 1 ]; then
                        printf '\tDefault Value: %s' "${OPT_VALUE_lst[$i]}"
                    elif [ "${OPT_VALUE_lst[$i]}" -eq 0 ]; then
                        printf '\tDefault Value: Off'
                    else
                        printf '\tDefault Value: On'
                    fi
                fi
            done

            printf '    -h |  --help\n'
            printf '\tthis message\n'
            _func_case_dump_descption
            trap - EXIT
            exit 2
        }

    # generate the command to load 'getopt'
    _func_create_tmpbash "$@"
    eval set -- "$_op_temp_script"

    # option function mapping
    local idx
    while true ; do
        idx="${_op_short_lst[$1]}"
        [ ! "$idx" ] && idx="${_op_long_lst[$1]}"
        if [ "$idx" ]; then
            if [ ${OPT_PARM_lst[$idx]} -eq 1 ]; then
                [ ! "$2" ] && printf 'option: %s missing parameter, parsing error' "$1" && exit 2
                OPT_VALUE_lst[$idx]="$2"
                shift 2
            else
                OPT_VALUE_lst[$idx]=$(echo '!'"${OPT_VALUE_lst[$idx]}"|bc)
                shift
            fi
        elif [ "X$1" == "X--" ]; then
            shift && break
        else
            printf 'option: %s unknown, error!' "$1" && exit 2
        fi
    done
    
    [ "${OPT_VALUE_lst['h']}" -eq 1 ] && _func_opt_dump_help
    # record the full parameter to the cmd
    if [[ ! -f "$LOG_ROOT/version.txt" ]] && [[ -f "$SCRIPT_HOME/.git/config" ]]; then
        {
            printf "Command:\n"
            [[ "$TPLG" ]] && printf "TPLG=%s" "$TPLG "
            printf '%s %s' "$SCRIPT_NAME" "$SCRIPT_PRAM"
            printf 'Branch:\n'
            git -C "$SCRIPT_HOME" branch
            printf 'Commit:\n'
            git -C "$SCRIPT_HOME" log --branches --oneline -n 5
        } >> "$LOG_ROOT/version.txt"
    fi

    unset _func_create_tmpbash _func_opt_dump_help _func_case_dump_descption
}
