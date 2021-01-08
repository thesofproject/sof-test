#!/bin/bash

# Before using this, you must define these option arrays in your test
# script. They must all be indexed by some unique, one-character
# codename for each of your option.
declare -A OPT_DESC_lst OPT_NAME OPT_PARM_lst OPT_VALUE_lst

# option setup && parse function
func_opt_parse_option()
{
    # OPT_NAME     (long) option name
    # OPT_DESC_lst    short sentence describing the option
    # OPT_PARM_lst    0 or 1: number of argument required
    # OPT_VALUE_lst   default value overwritten by command line
    #                 input if any. Set to 0 or 1 when PARM=0

    # for example
    # OPT_NAME['r']='remote'
    # OPT_DESC_lst['r']='Run for the remote machine'
    # OPT_PARM_lst['r']=1
    # OPT_VALUE_lst['r']='' ## if PARM=1, must be set, if PARM=0, can ignore

    # h & help is default option, so don't need to add into option list
    OPT_NAME['h']='help'
    OPT_DESC_lst['h']='this message'
    OPT_PARM_lst['h']=0
    OPT_VALUE_lst['h']=0

    local _op_temp_script
    local -A _op_short_lst _op_long_lst

    _func_case_dump_descption()
    {
         grep '^##' "$SCRIPT_NAME"|sed 's/^##//g'
    }

    # Asks getopt to validate command line input and generate $_op_temp_script
    #
    # Also initialize the global _op_short_list and _op_long_list
    # "reversed maps" (reversed compared to the user's OPT_ maps) that
    # map valid command line input to the corresponding
    # one-character option code name. Example:
    #   _op_short_lst=
    #        ( [-t]="t" [-d]="d" [-l]="l" [-h]="h" )
    #   _op_long_lst=
    #        ( [--help]="h" [--duration]="d" [--tplg]="t" [--loop]="l" )
    _func_create_tmpbash()
    {
         # options in getopt format
        local i _short_opt _long_opt
        for i in ${!OPT_DESC_lst[*]}
        do
            _short_opt=$_short_opt"$i"
            _op_short_lst["-$i"]="$i"
            [ "$_long_opt" ] && _long_opt="$_long_opt"','
            if [ "${OPT_NAME[$i]}" ]; then
                _long_opt=$_long_opt"${OPT_NAME[$i]}"
                _op_long_lst["--${OPT_NAME[$i]}"]="$i"
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
                if [ "${OPT_NAME[$i]}" ]; then
                    # whether display short option
                    [ "$i" ] && printf ' |  ' || printf '    '
                    printf '%s' "--${OPT_NAME[$i]}"
                    [ "X${OPT_PARM_lst[$i]}" == "X1" ] && printf ' parameter'
                fi
                printf '\n\t%s\n' "${OPT_DESC_lst[$i]}"
                if [ "${OPT_VALUE_lst[$i]}" ]; then
                    if [ "${OPT_PARM_lst[$i]}" -eq 1 ]; then
                        printf '\tDefault Value: %s\n' "${OPT_VALUE_lst[$i]}"
                    elif [ "${OPT_VALUE_lst[$i]}" -eq 0 ]; then
                        printf '\tDefault Value: Off\n'
                    else
                        printf '\tDefault Value: On\n'
                    fi
                fi
            done

            printf '    -h |  --help\n'
            printf '\tthis message\n'
            _func_case_dump_descption
            trap - EXIT
            exit 2
        }

    # Asks getopt to validate input and generate _op_temp_script.
    # Initialize reverse maps _op_short_lst and _opt_long_lst used next.
    _func_create_tmpbash "$@"

    # FIXME: what is this supposed to do!?
    eval set -- "$_op_temp_script"

    # Iterate over command line input and overwrite OPT_VALUE_lst
    # default values.
    # declare -p OPT_NAME OPT_VALUE_lst
    local idx
    while true ; do
        # idx is our internal one-character code name unique for each option
        idx="${_op_short_lst[$1]}"
        [ ! "$idx" ] && idx="${_op_long_lst[$1]}"
        if [ "$idx" ]; then
            if [ ${OPT_PARM_lst[$idx]} -eq 1 ]; then
                [ ! "$2" ] && printf 'option: %s missing parameter, parsing error' "$1" && exit 2
                OPT_VALUE_lst[$idx]="$2"
                shift 2
            else # boolean flag: reverse the default value
                OPT_VALUE_lst[$idx]=$((!${OPT_VALUE_lst[$idx]}))
                shift
            fi
        elif [ "X$1" == "X--" ]; then
            shift && break
        else # this should never happen if getopt does a good validation job
            printf 'option: %s unknown, error!' "$1" && exit 2
        fi
    done
    # declare -p OPT_VALUE_lst

    [ "${OPT_VALUE_lst['h']}" -eq 1 ] && _func_opt_dump_help
    # record the full parameter to the cmd
    if [[ ! -f "$LOG_ROOT/version.txt" ]] && [[ -f "$SCRIPT_HOME/.git/config" ]]; then
        {
            printf "Command:\n"
            [[ "$TPLG" ]] && printf "TPLG=%s" "$TPLG "
            printf "%s %s\n" "$SCRIPT_NAME" "$SCRIPT_PRAM"
            printf 'Commit:\n'
            git -C "$SCRIPT_HOME" log --oneline --decorate -n 5
        } >> "$LOG_ROOT/version.txt"
    fi

    unset _func_create_tmpbash _func_opt_dump_help _func_case_dump_descption
}
