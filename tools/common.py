def func_dump_pipeline(pipeline, noKey=False):
    output = ""
    for key, value in pipeline.items():
        if noKey is True:
            output += str(value) + " "
        else:
            output += key + "=" + str(value) + ";"
    return output.strip()

# This function will generate shell code according to pipeline parameters,
# then pipeline parameters can be accessed from test case by sourcing or
# executing the generated code.
def func_export_pipeline(pipeline_lst):
    length = len(pipeline_lst)
    keyword = 'PIPELINE'
    # clear up the older define
    print('unset %s_COUNT' % (keyword))
    print('unset %s_LST' % (keyword))
    print('declare -g %s_COUNT' % (keyword))
    print('declare -ag %s_LST' % (keyword))
    print('%s_COUNT=%d' % (keyword, length))
    for idx in range(0, length):
        # store pipeline
        print('%s_LST[%d]="%s"' % (keyword, idx, func_dump_pipeline(pipeline_lst[idx])))
        # store pipeline to each list
        print('unset %s_%d' % (keyword, idx))
        print('declare -Ag %s_%d' % (keyword, idx))
        for key, value in pipeline_lst[idx].items():
            print('%s_%d["%s"]="%s"' % (keyword, idx, key, value))
    return 0
