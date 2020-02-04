#!/bin/bash

# Before using, please setup these options for the function
declare -gA OPT_DESC_lst OPT_OPT_lst OPT_PARM_lst OPT_VALUE_lst

# option setup && parse function
func_opt_parse_option()
{
    # OPT_OPT_lst Used to define the parameter name
    # OPT_DESC_lst Used to define a short parameter description
    # OPT_PARM_lst set to 1 (default is 0, just a switch)
    # OPT_VALUE_lst Used to store the argument value

    # for example
    # OPT_OPT_lst['r']='remote'
    # OPT_DESC_lst['r']='Run for the remote machine\nFor eample: 10.0.12.234' # please check with echo -e option for the output format
    # OPT_PARM_lst['r']=1
    # OPT_VALUE_lst['r']='' ## if PARM=1, must be set, if PARM=0, can ignore

    # h & help is default option, so don't need add into option list
    OPT_OPT_lst['h']='help'
    OPT_DESC_lst['h']='this message'
    OPT_PARM_lst['h']=0
    OPT_VALUE_lst['h']=0

    local _op_temp_script
    local -A _op_short_lst _op_long_lst

    _func_case_dump_descption()
    {
         # bash >= v4.1
         local main_script=${BASH_SOURCE[-1]}
         # bash < 4.1
         # local main_script=${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}
         cat $main_script |grep '^##'|sed 's/^##//g'
    }

    _func_create_tmpbash()
    {
        local i _short_opt _long_opt
        # loop to combine option which will be load by getopt
        for i in ${!OPT_DESC_lst[*]}
        do
            _short_opt=$_short_opt"$i"
            _op_short_lst["-$i"]="$i"
            [ "$_long_opt" ] && _long_opt="$_long_opt"','
            if [ "${OPT_OPT_lst[$i]}" ]; then
                _long_opt=$_long_opt"${OPT_OPT_lst[$i]}"
                _op_long_lst["--${OPT_OPT_lst[$i]}"]="$i"
            fi
            # option will accpect parameter
            [ ${OPT_PARM_lst[$i]} -eq 1 ] && _short_opt=$_short_opt':' && _long_opt=$_long_opt':'
        done
        _op_temp_script=`getopt -o "$_short_opt" --long "$_long_opt" -n "$ST_NAME" -- $@`
        if [ $? != 0 ] ; then echo "Error parsing option" >&2 ; _func_opt_dump_help ; fi
    }

    _func_opt_dump_help()
    {
        local i def_value
        echo -e "Usage: $0 [OPTION]\n"
        for i in ${!OPT_DESC_lst[*]}
        do
                [ "X$i" = "Xh" ] && continue
                # display short option
                [ "$i" ] && echo -ne '    -'"$i"
                # have parameter
                [ "X""${OPT_PARM_lst[$i]}" == "X1" ] && echo -ne " parameter"
                # display long option
                if [ "${OPT_OPT_lst[$i]}" ]; then
                    # whether display short option
                    [ "$i" ] && echo -ne " |  " || echo -ne "    "
                    echo -ne "--""${OPT_OPT_lst[$i]}"
                    [ "X""${OPT_PARM_lst[$i]}" == "X1" ] && echo -ne " parameter"
                fi
                echo -e "\n\t""${OPT_DESC_lst[$i]}"
                if [ "${OPT_VALUE_lst[$i]}" ]; then
                    if [ "${OPT_PARM_lst[$i]}" -eq 1 ]; then
                        echo -e "\t""Default Value: ${OPT_VALUE_lst[$i]}"
                    else
                        [ "${OPT_VALUE_lst[$i]}" -eq 0 ] && echo -e "\t""Default Value: Off" \
                            || echo -e "\t""Default Value: On"
                    fi
                fi
            done

            echo -e '    -h |  --help'
            echo -e "\tthis message"
            _func_case_dump_descption
            exit 2
        }

    # generate the command to load 'getopt'
    _func_create_tmpbash $@
    eval set -- "$_op_temp_script"

    # option function mapping
    local idx
    while true ; do
        idx="${_op_short_lst[$1]}"
        [ ! "$idx" ] && idx="${_op_long_lst[$1]}"
        if [ "$idx" ]; then
            if [ ${OPT_PARM_lst[$idx]} -eq 1 ]; then
                [ ! "$2" ] && echo "option: $1 missing parameter, parsing error" && exit 1
                OPT_VALUE_lst[$idx]="$2"
                shift 2
            else
                OPT_VALUE_lst[$idx]=$(echo '!'${OPT_VALUE_lst[$idx]}|bc)
                shift
            fi
        elif [ "X$1" == "X--" ]; then
            shift && break
        else
            echo "option: $1 unknown, internal error!" && exit 2
        fi
    done
    
    [ ${OPT_VALUE_lst['h']} -eq 1 ] && _func_opt_dump_help
    # verify & check all option value
    [[ $(declare -p |grep "[[:space:]]OPT_VALUE_lst=\"\"") ]] && echo "Missing parameter/script default value" && _func_opt_dump_help
    # record the full parameter to the cmd
    if [ ! -f $LOG_ROOT/cmd.txt ]; then
        local cmd="$0" opt
        for opt in ${!OPT_OPT_lst[@]}
        do
            [[ $opt == "h" ]] && continue
            if [ ${OPT_PARM_lst[$opt]} -eq 1 ];then
                cmd="$cmd -$opt ${OPT_VALUE_lst[$opt]}"
            else
                if [ $(echo '!'${OPT_VALUE_lst[$opt]}|bc) -eq 1 ];then
                    cmd="$cmd -$opt"
                fi
            fi
        done
        echo $cmd >> $LOG_ROOT/cmd.txt
    fi

    unset _func_create_tmpbash _func_opt_dump_help _func_case_dump_descption
}
