#!/bin/bash

# These four arrays are used to define script options, and they should be
# indexed by a character [a-zA-Z], which is the option short name.
# OPT_NAME: option long name
# OPT_HAS_ARG:
#    1: this option requires an extra argument
#    0: this option behaves like boolean, and requires no argument
# OPT_VAL: the extra argument required, or 0 if option requires no argument
# OPT_DESC: description for this option
declare -A OPT_NAME OPT_HAS_ARG OPT_VAL OPT_DESC

# option setup && parse function
func_opt_parse_option()
{
    # The help option
    OPT_NAME['h']='help'
    OPT_HAS_ARG['h']=0
    OPT_VAL['h']=0
    OPT_DESC['h']='show help information'

    local _op_temp_script
    local -A _op_short_lst _op_long_lst

    _func_case_dump_description()
    {
         grep '^##' "$SCRIPT_NAME" | sed 's/^## //g'
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
        for i in ${!OPT_DESC[*]}
        do
            _short_opt=$_short_opt"$i"
            _op_short_lst["-$i"]="$i"
            [ "$_long_opt" ] && _long_opt="$_long_opt"','
            if [ "${OPT_NAME[$i]}" ]; then
                _long_opt=$_long_opt"${OPT_NAME[$i]}"
                _op_long_lst["--${OPT_NAME[$i]}"]="$i"
            fi
            # append ':' if the option accepts an argument
            [ ${OPT_HAS_ARG[$i]} -eq 1 ] && _short_opt=$_short_opt':' && _long_opt=$_long_opt':'
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
        for i in ${!OPT_DESC[*]}
        do
                [ "X$i" = "Xh" ] && continue
                # display short option
                [ "$i" ] && printf '    -%s' "$i"
                # if option requires extra argument
                [ "X${OPT_HAS_ARG[$i]}" == "X1" ] && printf ' parameter'
                # display long option
                if [ "${OPT_NAME[$i]}" ]; then
                    # whether display short option
                    [ "$i" ] && printf ' |  ' || printf '    '
                    printf '%s' "--${OPT_NAME[$i]}"
                    [ "X${OPT_HAS_ARG[$i]}" == "X1" ] && printf ' parameter'
                fi
                printf '\n\t%s\n' "${OPT_DESC[$i]}"
                if [ "${OPT_VAL[$i]}" ]; then
                    if [ "${OPT_HAS_ARG[$i]}" -eq 1 ]; then
                        printf '\tDefault Value: %s\n' "${OPT_VAL[$i]}"
                    elif [ "${OPT_VAL[$i]}" -eq 0 ]; then
                        printf '\tDefault Value: Off\n'
                    else
                        printf '\tDefault Value: On\n'
                    fi
                fi
            done

            printf '    -h |  --help\n'
            printf '\tthis message\n'
            _func_case_dump_description
            trap - EXIT
            exit 2
        }

    # Asks getopt to validate input and generate _op_temp_script.
    # Initialize reverse maps _op_short_lst and _opt_long_lst used next.
    _func_create_tmpbash "$@"

    # FIXME: what is this supposed to do!?
    eval set -- "$_op_temp_script"

    # Iterate over command line input and overwrite OPT_VAL
    # default values.
    # declare -p OPT_NAME OPT_VAL
    local idx
    while true ; do
        # idx is our internal one-character code name unique for each option
        idx="${_op_short_lst[$1]}"
        [ ! "$idx" ] && idx="${_op_long_lst[$1]}"
        if [ "$idx" ]; then
            if [ ${OPT_HAS_ARG[$idx]} -eq 1 ]; then
                [ ! "$2" ] && printf 'option: %s missing parameter, parsing error' "$1" && exit 2
                OPT_VAL[$idx]="$2"
                shift 2
            else # boolean flag: reverse the default value
                OPT_VAL[$idx]=$((!${OPT_VAL[$idx]}))
                shift
            fi
        elif [ "X$1" == "X--" ]; then
            shift && break
        else # this should never happen if getopt does a good validation job
            printf 'option: %s unknown, error!' "$1" && exit 2
        fi
    done
    # declare -p OPT_VAL

    [ "${OPT_VAL['h']}" -eq 1 ] && _func_opt_dump_help
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

    unset _func_create_tmpbash _func_opt_dump_help _func_case_dump_description
}
