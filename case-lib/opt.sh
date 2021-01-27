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

# Define common options among test scripts.
add_common_options()
{
    # The help option
    OPT_NAME['h']='help'
    OPT_HAS_ARG['h']=0
    OPT_VAL['h']=0
    OPT_DESC['h']='show help information'
}

# option setup && parse function
func_opt_parse_option()
{
    _func_case_dump_description()
    {
        grep '^##' "$SCRIPT_NAME" | sed 's/^## //g'
    }

    # This function helps to fill below four variables
    # - short_opt_str/long_opt_str: short/long option in getopt format, used
    #   for command line validation
    # - short_opt_lst/long_opt_lst: list of short/long option map which maps
    #   command line option to its corresponding short/long name, used for
    #   overriding default OPT_VAL, eg, short_opt_lst=([-h]="h" [-t]="t")
    #   long_opt_lst=([--help]="h" [--tplg]="t")
    _fill_opt_vars()
    {
        local opt
        for opt in ${!OPT_DESC[*]}
        do
            short_opt_str="$short_opt_str""$opt"
            short_opt_lst["-$opt"]="$opt"
            [ "$long_opt_str" ] && long_opt_str="$long_opt_str"','
            if [ "${OPT_NAME[$opt]}" ]; then
                long_opt_str="$long_opt_str""${OPT_NAME[$opt]}"
                long_opt_lst["--${OPT_NAME[$opt]}"]="$opt"
            fi
            # append ':' if this option requires an argument
            [ ${OPT_HAS_ARG[$opt]} -ne 1 ] || {
                short_opt_str=$short_opt_str':'
                long_opt_str=$long_opt_str':'
            }
        done
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

    add_common_options

    # short option and long option in getopt format
    local short_opt_str long_opt_str
    # the option map used for OPT_VAL overriding
    local -A short_opt_lst long_opt_lst
    # Fill above four variables
    _fill_opt_vars

    local formatted_cmd_opts
    # Call getopt to help us to validate and format command line options,
    # the formatted command line options will end with '--', which denotes
    # the end of the command line options. eg, run "check-playback.sh -l1 -r1 -d1",
    # we get formatted_cmd_opts="-l '1' -r '1' -d '1' --".
    formatted_cmd_opts=$(getopt -o "$short_opt_str" --long "$long_opt_str" -- "$@") || {
        # Wrong option(s) are specified
        printf 'Unrecognized option(s) found: %s\n' "$*"
        # Uncomment below lines for debug purpose
        # printf '[DEBUG] short option: %s\n' "$short_opt_str" >&2
        # printf '[DEBUG] long option: %s\n' "$long_opt_str" >&2
        # printf '[DEBUG] command line: %s\n' "$*" >&2
        _func_opt_dump_help
    }

    # set the contents in formatted_cmd_opts to position arguments $1, $2, ...
    eval set -- "$formatted_cmd_opts"

    # Iterate over command line input and overwrite OPT_VAL
    # default values.
    # declare -p OPT_NAME OPT_VAL
    local idx
    while true ; do
        # idx is our internal one-character code name unique for each option
        idx="${short_opt_lst[$1]}"
        [ ! "$idx" ] && idx="${long_opt_lst[$1]}"
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

    unset _fill_opt_vars _func_opt_dump_help _func_case_dump_description
}
