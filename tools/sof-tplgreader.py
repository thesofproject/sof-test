#!/usr/bin/python3

import subprocess
import os
import re
from tplgtool import TplgParser, TplgFormatter

class clsTPLGReader:
    def __init__(self):
        self._pipeline_lst = []
        self._output_lst = []
        self._filed_lst = []
        self._filter_lst = []
        self._block_lst = []
    
    def __comp_pipeline(self, pipeline):
        return pipeline['id']

    def _key2str(self, cap, key):
        return cap["%s_min" % (key)], cap["%s_max" % (key)]

    # fork & split from TplgFormatter
    def loadFile(self, filename, sofcard=0):
        tplg_parser = TplgParser()
        parsed_tplg = tplg_parser.parse(filename)
        tplg_formatter = TplgFormatter(parsed_tplg)
        # ignore the last element, for it is tplg name
        for item in parsed_tplg[:-1]:
            if "pcm" not in item:
                continue
            for pcm in item['pcm']:
                pipeline_dict = {}
                pipeline_dict['pcm'] = pcm["pcm_name"]
                pipeline_dict['id'] = str(pcm["pcm_id"])
                pipeline_dict['type'] = tplg_formatter._get_pcm_type(pcm)
                # if we find None type pcm, there must be errors in topology
                if pipeline_dict['type'] == "None":
                    print("type of %s is neither playback nor capture, please check your"
                        "topology source file", pcm["pcm_name"])
                    exit(1)
                cap = pcm["caps"][pcm['capture']]
                # supported formats of playback pipeline in formats[0]
                # supported formats of capture pipeline in formats[1]
                formats = tplg_formatter._get_pcm_fmt(pcm)
                pipeline_dict['fmts'] = " ".join(formats[pcm['capture']])
                # use the first supported format for test
                pipeline_dict['fmt'] = pipeline_dict['fmts'].split(' ')[0]
                pipeline_dict['rate_min'], pipeline_dict['rate_max'] = self._key2str(cap, 'rate')
                pipeline_dict['ch_min'], pipeline_dict['ch_max'] = self._key2str(cap, 'channels')
                self._pipeline_lst.append(pipeline_dict)

        # format pipeline, this change for script direct access 'rate' 'channel' 'dev'
        for pipeline in self._pipeline_lst:
            #pipeline['fmt']=pipeline['fmt'].upper().replace('LE', '_LE')
            pipeline['rate'] = pipeline['rate_min']
            pipeline['channel'] = pipeline['ch_min']
            pipeline['dev'] = "hw:" + str(sofcard) + ',' + pipeline['id']
        return 0

    def _setlist(self, orig_lst):
        tmp_lst = []
        if orig_lst is None:
            return tmp_lst

        if type(orig_lst) is list:
            tmp_lst = orig_lst[:]
        else:
            tmp_lst.append(orig_lst)
        return tmp_lst

    def setFilter(self, filter_lst=None):
        self._filter_lst = self._setlist(filter_lst)[:]

    def setFiled(self, filed_lst):
        self._filed_lst = self._setlist(filed_lst)[:]

    def setBlock(self, block_lst=None):
        self._block_lst = self._setlist(block_lst)[:]

    def _filterOutput(self, target_lst, filter_dict, bIn):
        self._output_lst.clear()
        for line in target_lst[:]:
            for key, value in filter_dict.items():
                # match for 'keyword'/'keyword [0-9]' target line
                check = len ([em for em in value if re.match(em + '$|' + em + '[^a-zA-Z]', line[key], re.I)]) > 0
                if check is bIn:
                    break
            else:
                self._output_lst.append(line)

    def _filterKeyword(self):
        if len(self._filter_lst) == 0:
            return
        for filter_dict in self._filter_lst:
            tmp_lst = self._output_lst[:]
            self._filterOutput(tmp_lst, filter_dict, False)

    def _filterFiled(self):
        if len(self._filed_lst) == 0:
            return
        tmp_lst = self._output_lst[:]
        self._output_lst.clear()
        for pipeline in tmp_lst:
            tmp_dict ={}
            for filed in self._filed_lst:
                if filed in pipeline.keys():
                    tmp_dict[filed]=pipeline[filed]
            self._output_lst.append(tmp_dict)

    def _blockKeyword(self):
        if len(self._block_lst) == 0:
            return
        for block_dict in self._block_lst:
            tmp_lst = self._output_lst[:]
            self._filterOutput(tmp_lst, block_dict, True)

    def sortPipeline(self):
        if len(self._pipeline_lst) != 0:
            self._pipeline_lst.sort(key=self.__comp_pipeline)
        if len(self._output_lst) != 0:
            self._output_lst.sort(key=self.__comp_pipeline)

    def getPipeline(self):
        self._output_lst = self._pipeline_lst[:]
        self._filterKeyword()
        self._blockKeyword()
        self._filterFiled()
        return self._output_lst
    
if __name__ == "__main__":
    def func_dump_pipeline(pipeline, noKey=False):
        output = ""
        for key, value in pipeline.items():
            if noKey is True:
                output += str(value) + " "
            else:
                output += key + "=" + str(value) + ";"
        return output

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

    def func_getPipeline(tplgObj, tplgName, sdcard_id, sort):
        if tplgObj.loadFile(tplgName, sdcard_id) != 0:
            print("tplgreader load file %s failed" %(tplgName))
            exit(1)
        if sort:
            tplgreader.sortPipeline()
        return tplgObj.getPipeline()

    import argparse

    parser = argparse.ArgumentParser(description='Warp Tools to mapping tplgreader convert TPLG file.',
        add_help=True, formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('filename', type=str, help='tplg file name, multi-tplg file name use "," to split it')
    parser.add_argument('-s', '--sofcard', type=int, help='sofcard id', default=0)
    parser.add_argument('-f', '--filter', type=str, nargs='+',  
        help='''setup filter, this value is format value,
string format is 'key':'value','value'
for example: Get "type" is "capture"
type: capture
for example: Get "type" is "capture, both" and "fmt" is S16_LE
type:capture,both fmt:S16_LE
''')
    parser.add_argument('-b', '--block', type=str, nargs='+',
        help='''setup block list, this value is format value,
string format is 'key':'value','value'
for example: block "pcm" is "HDA Digital"
pcm:HDA Digital
''')
    parser.add_argument('-d', '--dump', type=str, nargs='+', help='Dump target field')
    parser.add_argument('-e', '--export', action='store_true',
        help='''export the pipeline to Bash declare -Ax Array
this option conflict with other output format option: -c -i -v
export format: 
PIPELINE_$ID['key']='value' ''')
    parser.add_argument('-c', '--count', action='store_true', help='Get pipeline count')
    parser.add_argument('-i', '--index', type=int, help='Get index of pipeline, start with 0')
    parser.add_argument('-v', '--value', action='store_true', help="Just display the vaule")
    parser.add_argument('-t', '--tplgroot', type=str, help="load file from tplg-root folder")
    parser.add_argument('-o', '--sort', action='store_true', help="sort pipeline by id for the same tplg")
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')

    ret_args = vars(parser.parse_args())

    tplgreader = clsTPLGReader()
    filter_lst = []
    dump_lst = []
    block_lst = []
    pipeline_lst = []
    tplg_root = ""

    if ret_args['filter'] is not None and len(ret_args['filter']) > 0:
        for emStr in ret_args['filter']:
            key, flag, value=emStr.partition(':')
            filter_lst.append({key.strip():value.strip().replace('[','').replace(']','').split(',')})

    if ret_args['block'] is not None and len(ret_args['block']) > 0:
        for emStr in ret_args['block']:
            key, flag, value=emStr.partition(':')
            block_lst.append({key.strip():value.strip().replace('[','').replace(']','').split(',')})

    if ret_args['dump'] is not None and len(ret_args['dump']) > 0:
        dump_lst = ret_args['dump']

    if len(filter_lst) > 0:
        tplgreader.setFilter(filter_lst)
    if len(block_lst) > 0:
        tplgreader.setBlock(block_lst)
    if len(dump_lst) > 0:
        tplgreader.setFiled(dump_lst)

    if ret_args['tplgroot'] is not None and len(ret_args['tplgroot']) >0:
        tplg_root = ret_args['tplgroot']

    for f in ret_args['filename'].split(','):
        if len(tplg_root) > 0:
            f = tplg_root + "/" + f
        pipeline_lst += func_getPipeline(tplgreader, f, ret_args['sofcard'], ret_args['sort'])[:]

    if ret_args['export'] is True:
        exit(func_export_pipeline(pipeline_lst))

    if ret_args['count'] is True:
        if ret_args['value'] is True:
            print(len(pipeline_lst))
        else:
            print("Pipeline Count: %d" % (len(pipeline_lst)))
    elif ret_args['index'] is not None and ret_args['index'] < len(pipeline_lst):
        print(func_dump_pipeline(pipeline_lst[ret_args['index']], ret_args['value']))
    else:
        for pipeline in pipeline_lst:
            print(func_dump_pipeline(pipeline, ret_args['value']))


