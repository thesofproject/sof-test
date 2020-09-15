#!/usr/bin/python3

import subprocess
import os
import re
from tplgtool import TplgParser, TplgFormatter

class clsTPLGReader:
    def __init__(self):
        self._pipeline_lst = []
        self._output_lst = []
        self._field_lst = []
        self._filter_dict = {}
        self._block_lst = []

    def __comp_pipeline(self, pipeline):
        return int(pipeline['id'])

    def _key2str(self, cap, key):
        return cap["%s_min" % (key)], cap["%s_max" % (key)]

    @staticmethod
    def attach_comp_to_pipeline(comps, comp_index, comp_name, pipeline_dict):
        comp = comps[comp_index]
        if comp != []:
            comp_names = [i['name'] for i in comp]
            pipeline_dict[comp_name.lower()] = " ".join(comp_names)

    # fork & split from TplgFormatter
    def loadFile(self, filename, sofcard=0):
        tplg_parser = TplgParser()
        parsed_tplg = tplg_parser.parse(filename)
        formatter = TplgFormatter(parsed_tplg)
        # ignore the last element, it is tplg name
        for item in parsed_tplg[:-1]:
            if "pcm" not in item:
                continue
            for pcm in item['pcm']:
                pcm_type = TplgFormatter.get_pcm_type(pcm)
                # if we find None type pcm, there must be errors in topology
                if pcm_type == "None":
                    print("type of %s is neither playback nor capture, please check your"
                        "topology source file" % pcm["pcm_name"])
                    exit(1)
                pgas = formatter.find_comp_for_pcm(pcm, 'PGA')
                eqs = formatter.find_comp_for_pcm(pcm, 'EQ')
                kwds = formatter.find_comp_for_pcm(pcm, 'KPBM')
                asrcs = formatter.find_comp_for_pcm(pcm, 'ASRC')
                codec_adapters = formatter.find_comp_for_pcm(pcm, 'CODEC_ADAPTER')
                pipeline_dict = {}
                pipeline_dict['pcm'] = pcm["pcm_name"]
                pipeline_dict['id'] = str(pcm["pcm_id"])
                pipeline_dict['type'] = TplgFormatter.get_pcm_type(pcm)
                cap = pcm["caps"][pcm['capture']]
                pipeline_dict['cap_name'] = cap['name']
                # acquire component from pipeline graph, and add to pipeline dict
                clsTPLGReader.attach_comp_to_pipeline(pgas, pcm['capture'], "PGA", pipeline_dict)
                clsTPLGReader.attach_comp_to_pipeline(eqs, pcm['capture'], "EQ", pipeline_dict)
                clsTPLGReader.attach_comp_to_pipeline(kwds, pcm['capture'], "KPBM", pipeline_dict)
                clsTPLGReader.attach_comp_to_pipeline(asrcs, pcm['capture'], "ASRC", pipeline_dict)
                clsTPLGReader.attach_comp_to_pipeline(codec_adapters, pcm['capture'], "CODEC_ADAPTER", pipeline_dict)
                # supported formats of playback pipeline in formats[0]
                # supported formats of capture pipeline in formats[1]
                formats = TplgFormatter.get_pcm_fmt(pcm)
                # if capture is present, pcm['capture'] = 1, otherwise, pcm['capture'] = 0,
                # same thing for pcm['playback']
                pipeline_dict['fmts'] = " ".join(formats[pcm['capture']])
                # use the first supported format for test
                pipeline_dict['fmt'] = pipeline_dict['fmts'].split(' ')[0]
                pipeline_dict['rate_min'], pipeline_dict['rate_max'] = self._key2str(cap, 'rate')
                pipeline_dict['ch_min'], pipeline_dict['ch_max'] = self._key2str(cap, 'channels')
                # for pcm with both playback and capture capabilities, we can extract two pipelines.
                # the paramters for capture pipeline is filled above, and the parameters for playback
                # pipeline is filled below.
                if pcm_type == "both":
                    pipeline_dict["type"] = "capture"
                    # copy pipeline and change values
                    pb_pipeline_dict = pipeline_dict.copy()
                    pb_pipeline_dict["type"] = "playback"
                    cap = pcm["caps"][0]
                    pb_pipeline_dict['cap_name'] = cap['name']
                    # with index = 0, we get parameters from playback pipeline
                    clsTPLGReader.attach_comp_to_pipeline(pgas, 0, "PGA", pb_pipeline_dict)
                    clsTPLGReader.attach_comp_to_pipeline(eqs, 0, "EQ", pb_pipeline_dict)
                    clsTPLGReader.attach_comp_to_pipeline(asrcs, 0, "ASRC", pb_pipeline_dict)
                    clsTPLGReader.attach_comp_to_pipeline(codec_adapters, 0, "CODEC_ADAPTER", pb_pipeline_dict)
                    pb_pipeline_dict["fmts"] = " ".join(formats[0])
                    pb_pipeline_dict['fmt'] = pb_pipeline_dict['fmts'].split(' ')[0]
                    pb_pipeline_dict['rate_min'], pb_pipeline_dict['rate_max'] = self._key2str(cap, 'rate')
                    pb_pipeline_dict['ch_min'], pb_pipeline_dict['ch_max'] = self._key2str(cap, 'channels')
                    self._pipeline_lst.append(pb_pipeline_dict)
                self._pipeline_lst.append(pipeline_dict)

        # format pipeline, this change for script direct access 'rate' 'channel' 'dev' 'snd'
        for pipeline in self._pipeline_lst:
            #pipeline['fmt']=pipeline['fmt'].upper().replace('LE', '_LE')
            pipeline['rate'] = pipeline['rate_min'] if int(pipeline['rate_min']) != 0 else pipeline['rate_max']
            pipeline['channel'] = pipeline['ch_min']
            pipeline['dev'] = "hw:" + str(sofcard) + ',' + pipeline['id']
            # the character devices for PCM under /dev/snd take the form of
            # "pcmC + card_number + D + device_number + capability", eg, pcmC0D0p.
            pipeline['snd'] = "/dev/snd/pcmC" + str(sofcard) + "D" + pipeline['id']
            if pipeline['type'] == "playback":
                pipeline['snd'] += 'p'
            else:
                pipeline['snd'] += 'c'
        # find interweaved pipelines
        # echo: echo reference pipelines
        # smart_amp: dsm pipelines
        interweaved_comps = ['echo', 'smart_amp']
        for comp in interweaved_comps:
            interweaved_dict = formatter.find_interweaved_pipeline(comp)
            if interweaved_dict:
                for pipeline in self._pipeline_lst:
                    if pipeline['cap_name'] in interweaved_dict['sname']:
                        pipeline[comp] = interweaved_dict[comp]
        return 0

    @staticmethod
    def list_and(lst1, lst2):
        assert(lst1 is not None and lst2 is not None)
        output_lst = []
        for elem in lst1:
            if elem in lst2:
                output_lst.append(elem)
        return output_lst

    @staticmethod
    def list_or(lst1, lst2):
        assert(lst1 is not None and lst2 is not None)
        output_lst = lst1.copy()
        for elem in lst2:
            if elem not in output_lst:
                output_lst.append(elem)
        return output_lst

    @staticmethod
    def list_diff(lst1, lst2):
        assert(lst1 is not None and lst2 is not None)
        output_lst = []
        for elem in lst1:
            if elem not in lst2:
                output_lst.append(elem)
        return output_lst

    def _setlist(self, orig_lst):
        tmp_lst = []
        if orig_lst is None:
            return tmp_lst

        if type(orig_lst) is list:
            tmp_lst = orig_lst[:]
        else:
            tmp_lst.append(orig_lst)
        return tmp_lst

    def setFilter(self, filter_dict=None):
        self._filter_dict = filter_dict

    def setField(self, field_lst):
        self._field_lst = self._setlist(field_lst)[:]

    def setBlock(self, block_lst=None):
        self._block_lst = block_lst

    def _filterOutput(self, target_lst, filter_dict, bIn):
        filtered = []
        for line in target_lst[:]:
            check = False
            for key, value in filter_dict.items():
                if 'any' in value or value == ['']:
                    check = True if key in line.keys() else False
                else:
                    # match for 'keyword'/'keyword [0-9]' target line
                    check = len ([em for em in value if re.match(em + '$|' + em + '[^a-zA-Z]', str(line[key]), re.I)]) > 0
                if check is bIn:
                    break
            else:
                filtered.append(line)
        return filtered

    def _filter_by_dict(self, filter_dict):
        if filter_dict == {}:
            return self._pipeline_lst
        full_list = self._pipeline_lst
        filtered = None
        # pipelines filtered by the first filter item
        for key, value in filter_dict['filter'][0].items():
            if key.startswith('~'):
                filtered = self._filterOutput(full_list, {key[1:]:value}, True)
            else:
                filtered = self._filterOutput(full_list, {key:value}, False)
        # do filtering by the rest filter items and logic operations
        for idx in range(1, len(filter_dict['filter'])):
            new_filtered = None
            for key, value in filter_dict['filter'][idx].items():
                if key.startswith("~"):
                    new_filtered = self._filterOutput(full_list, {key[1:]:value} , True)
                else:
                    new_filtered = self._filterOutput(full_list, {key:value}, False)
            if filter_dict['op'][idx-1] == '&':
                filtered = self.list_and(filtered, new_filtered)
            if filter_dict['op'][idx-1] == '|':
                filtered = self.list_or(filtered, new_filtered)
        return filtered

    def _filterKeyword(self):
        self._output_lst = self._filter_by_dict(self._filter_dict)

    def _filterField(self):
        if len(self._field_lst) == 0:
            return
        tmp_lst = self._output_lst[:]
        self._output_lst.clear()
        for pipeline in tmp_lst:
            tmp_dict ={}
            for field in self._field_lst:
                if field in pipeline.keys():
                    tmp_dict[field]=pipeline[field]
            self._output_lst.append(tmp_dict)

    def _blockKeyword(self):
        if len(self._block_lst) == 0:
            return
        filtered = []
        for block_dict in self._block_lst:
            filtered.extend(self._filter_by_dict(block_dict))
        self._output_lst = clsTPLGReader.list_diff(self._output_lst, filtered)

    def sortPipeline(self):
        if len(self._pipeline_lst) != 0:
            self._pipeline_lst.sort(key=self.__comp_pipeline)
        if len(self._output_lst) != 0:
            self._output_lst.sort(key=self.__comp_pipeline)

    def getPipeline(self, sort=False):
        self._output_lst = self._pipeline_lst[:]
        self._filterKeyword()
        self._blockKeyword()
        self._filterField()
        if sort:
            self.sortPipeline()
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
        return tplgObj.getPipeline(sort)

    # parse filter string into two structures, one is dict list for each filter item,
    # and another is logic operation list.
    def parse_filter(filter_str):
        filter_lst = []
        op_lst = []
        for filter_elem in filter_str.split('|'):
            for item in filter_elem.split('&'):
                key, _, value = item.partition(':')
                filter_lst.append({key.strip():value.strip().split(',')})
        for char in filter_str:
            if char == '|' or char == "&":
                op_lst.append(char)
        return dict(zip(['filter', 'op'], [filter_lst, op_lst]))

    def parse_and_set_block_keyword(block_str, tplgreader):
        block_list = []
        block_strs = block_str.split(';')
        block_items = [item.strip() for item in block_strs if item != ""]
        for item in block_items:
            block_list.append(parse_filter(item))
        tplgreader.setBlock(block_list)

    import argparse

    parser = argparse.ArgumentParser(description='Warp Tools to mapping tplgreader convert TPLG file.',
        add_help=True, formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('filename', type=str, help='tplg file name, multi-tplg file name use "," to split it')
    parser.add_argument('-s', '--sofcard', type=int, help='sofcard id', default=0)
    parser.add_argument('-f', '--filter', type=str,
        help='''setup filter, command line parameter
string format is 'key':'value','value', the filter
string support & | and ~ logic operation.
if only care about key, you can use 'key':'any'.
Example Usage:
`-f "type:any` -> all pipelines
`-f "type:playback"` -> playback pipelines
`-f "type:capture & pga"` -> capture pipelines with PGA
`-f "pga & eq"` -> pipelines with both EQ and PGA
`-f "id:3"` -> pipeline whose id is 3
''')
    parser.add_argument('-b', '--block', type=str,
        help='setup block filter, command line parameter format is the same as -f argument')
    parser.add_argument('-d', '--dump', type=str, nargs='+', help='Dump target field')
    parser.add_argument('-e', '--export', action='store_true',
        help='''export the pipeline to Bash declare -Ax Array
this option conflicts with other output format option: -c -i -v
export format:
PIPELINE_$ID['key']='value' ''')
    parser.add_argument('-c', '--count', action='store_true', help='Get pipeline count')
    parser.add_argument('-i', '--index', type=int, help='Get index of pipeline, start with 0')
    parser.add_argument('-v', '--value', action='store_true', help="Just display the value")
    parser.add_argument('-t', '--tplgroot', type=str, help="load file from tplg-root folder")
    parser.add_argument('-o', '--sort', action='store_true', help="sort pipeline by id for the same tplg")
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')

    ret_args = vars(parser.parse_args())

    tplgreader = clsTPLGReader()
    dump_lst = []
    pipeline_lst = []
    tplg_root = ""

    # parse and set filter keyword
    if ret_args['filter'] is not None and len(ret_args['filter']) > 0:
        filter_dict = parse_filter(ret_args['filter'])
        tplgreader.setFilter(filter_dict)

    # If run general test case on WOV pipeline or ECHO REFERENCE capture pipeline, there will be error
    # due to no feed data, and they should be blocked in general test case.
    default_block_keyword = 'kpbm:any;type:capture & echo;'
    # if no filter or block item is specified, the "block_none" here will help to
    # block nothing
    block_str = "block_none"
    # user specified block items from command line
    cmd_block_str = ret_args['block'].strip() if ret_args['block'] is not None else ''

    if ret_args['filter'] is not None and 'kpbm' not in ret_args['filter'] and 'echo' not in ret_args['filter']:
        block_str = default_block_keyword + cmd_block_str
    else:
        block_str = cmd_block_str if cmd_block_str != '' else block_str

    parse_and_set_block_keyword(block_str, tplgreader)

    if ret_args['dump'] is not None and len(ret_args['dump']) > 0:
        dump_lst = ret_args['dump']

    if len(dump_lst) > 0:
        tplgreader.setField(dump_lst)

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
