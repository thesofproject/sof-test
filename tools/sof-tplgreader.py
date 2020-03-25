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
        self._filter_dict = {"filter":[], "op":[]}
        self._ignore_lst = []

    def __comp_pipeline(self, pipeline):
        return pipeline['id']

    def _key2str(self, cap, key):
        return cap["%s_min" % (key)], cap["%s_max" % (key)]

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
                pipeline_dict = {}
                pipeline_dict['pcm'] = pcm["pcm_name"]
                pipeline_dict['id'] = str(pcm["pcm_id"])
                pipeline_dict['type'] = TplgFormatter.get_pcm_type(pcm)
                cap = pcm["caps"][pcm['capture']]
                pga = pgas[pcm['capture']]
                if pga != []:
                    pga_names = [i['name'] for i in pga]
                    pipeline_dict['pga'] = " ".join(pga_names)
                eq = eqs[pcm['capture']]
                if eq != []:
                    eq_names = [i['name'] for i in eq]
                    pipeline_dict['eq'] = " ".join(eq_names)
                # supported formats of playback pipeline in formats[0]
                # supported formats of capture pipeline in formats[1]
                formats = TplgFormatter.get_pcm_fmt(pcm)
                pipeline_dict['fmts'] = " ".join(formats[pcm['capture']])
                # use the first supported format for test
                pipeline_dict['fmt'] = pipeline_dict['fmts'].split(' ')[0]
                pipeline_dict['rate_min'], pipeline_dict['rate_max'] = self._key2str(cap, 'rate')
                pipeline_dict['ch_min'], pipeline_dict['ch_max'] = self._key2str(cap, 'channels')
                if pcm_type == "both":
                    pipeline_dict["type"] = "capture"
                    # copy pipeline and change values
                    pb_pipeline_dict = pipeline_dict.copy()
                    pb_pipeline_dict["type"] = "playback"
                    cap = pcm["caps"][pcm['playback']]
                    pga = pgas[0] # idx 0 is playback PGA
                    if pga != []:
                        pga_names = [i['name'] for i in pga]
                        pb_pipeline_dict['pga'] = " ".join(pga_names)
                    eq = eqs[0]
                    if eq != []:
                        eq_names = [i['name'] for i in eq]
                        pb_pipeline_dict['eq'] = " ".join(eq_names)
                    pb_pipeline_dict["fmts"] = " ".join(formats[pcm['playback']])
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
        self._filter_dict['filter'] = self._setlist(filter_dict['filter'])[:]
        self._filter_dict['op'] = self._setlist(filter_dict['op'])

    def setField(self, field_lst):
        self._field_lst = self._setlist(field_lst)[:]

    def setIgnore(self, ignore_lst=None):
        self._ignore_lst = self._setlist(ignore_lst)[:]

    def _filterOutput(self, target_lst, filter_dict, bIn):
        self._output_lst.clear()
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
                self._output_lst.append(line)

        return self._output_lst.copy()

    def _filterKeyword(self):
        if len(self._filter_dict['filter']) == 0:
            return

        full_list = self._output_lst[:]
        filtered = None
        # pipelines filtered by the first filter item
        for key, value in self._filter_dict['filter'][0].items():
            if key.startswith('~'):
                filtered = self._filterOutput(full_list, {key[1:]:value}, True)
            else:
                filtered = self._filterOutput(full_list, {key:value}, False)
        # do filtering by the rest filter items and logic operations
        for idx in range(1, len(self._filter_dict['filter'])):
            new_filtered = None
            for key, value in self._filter_dict['filter'][idx].items():
                if key.startswith("~"):
                    new_filtered = self._filterOutput(full_list, {key[1:]:value} , True)
                else:
                    new_filtered = self._filterOutput(full_list, {key:value}, False)
            if self._filter_dict['op'][idx-1] == '&':
                filtered = self.list_and(filtered, new_filtered)
            if self._filter_dict['op'][idx-1] == '|':
                filtered = self.list_or(filtered, new_filtered)
        self._output_lst = filtered # the final filtered pipeline list

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

    def _ignoreKeyword(self):
        if len(self._ignore_lst) == 0:
            return
        for ignore_dict in self._ignore_lst:
            tmp_lst = self._output_lst[:]
            self._filterOutput(tmp_lst, ignore_dict, True)

    def sortPipeline(self):
        if len(self._pipeline_lst) != 0:
            self._pipeline_lst.sort(key=self.__comp_pipeline)
        if len(self._output_lst) != 0:
            self._output_lst.sort(key=self.__comp_pipeline)

    def getPipeline(self, sort=False):
        self._output_lst = self._pipeline_lst[:]
        self._filterKeyword()
        self._ignoreKeyword()
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
    parser.add_argument('-b', '--ignore', type=str, nargs='+',
        help='''setup ignore list, this value is format value,
string format is 'key':'value','value'
for example: ignore "pcm" is "HDA Digital"
pcm:HDA Digital
''')
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
    filter_dict = {"filter":[], "op":[]}
    dump_lst = []
    ignore_lst = []
    pipeline_lst = []
    tplg_root = ""

    if ret_args['filter'] is not None and len(ret_args['filter']) > 0:
        # parse filter string into two structures, one is dict list for each filter item,
        # and another is logic operation list.
        filter_lst = []
        op_lst = []
        for filter_elem in ret_args['filter'].split('|'):
            for item in filter_elem.split('&'):
                key, _, value = item.partition(':')
                filter_lst.append({key.strip():value.strip().split(',')})
        for char in ret_args['filter']:
            if char == '|' or char == "&":
                op_lst.append(char)
        filter_dict['filter'] = filter_lst
        filter_dict['op'] = op_lst

    if ret_args['ignore'] is not None and len(ret_args['ignore']) > 0:
        for emStr in ret_args['ignore']:
            key, flag, value=emStr.partition(':')
            ignore_lst.append({key.strip():value.strip().replace('[','').replace(']','').split(',')})

    if ret_args['dump'] is not None and len(ret_args['dump']) > 0:
        dump_lst = ret_args['dump']

    if len(filter_dict['filter']) > 0:
        tplgreader.setFilter(filter_dict)

    if len(ignore_lst) > 0:
        tplgreader.setIgnore(ignore_lst)
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
