#!/usr/bin/env python3

import argparse
import re
import sys

from tplgtool import TplgParser, TplgFormatter
from common import format_pipeline, export_pipeline


class clsTPLGReader:
    def __init__(self):
        self._pipeline_lst = []
        self._output_lst = []
        self._field_lst = []
        self._filter_dict = {}
        self._block_lst = []

    def __comp_pipeline(self, item):
        return int(item['id'])

    def _key2str(self, cap, key):
        return cap["%s_min" % (key)], cap["%s_max" % (key)]

    @staticmethod
    def attach_comp_to_pipeline(comps, comp_index, comp_name, pipeline_dict):
        comp = comps[comp_index]
        if comp != []:
            comp_names = [i['name'] for i in comp]
            pipeline_dict[comp_name.lower()] = " ".join(comp_names)

    def _build_pcm_entry(self, formatter, pcm):
        pcm_type = TplgFormatter.get_pcm_type(pcm)
        # if we find None type pcm, there must be errors in topology
        if pcm_type == "None":
            print("type of %s is neither playback nor capture, please check your"
                  "topology source file" % pcm["pcm_name"])
            sys.exit(1)

        comp_map = {
            'PGA': formatter.find_comp_for_pcm(pcm, 'PGA'),
            'EQ': formatter.find_comp_for_pcm(pcm, 'EQ'),
            'KPBM': formatter.find_comp_for_pcm(pcm, 'KPBM'),
            'kpb': formatter.find_comp_for_pcm(pcm, 'kpb'),
            'ASRC': formatter.find_comp_for_pcm(pcm, 'ASRC'),
            'CODEC_ADAPTER': formatter.find_comp_for_pcm(pcm, 'CODEC_ADAPTER'),
        }
        formats = TplgFormatter.get_pcm_fmt(pcm)
        rates = TplgFormatter.get_pcm_rate_list(pcm)

        def make_entry(dir_idx, entry_type):
            entry = {
                'pcm': pcm["pcm_name"],
                'id': str(pcm["pcm_id"]),
                'type': entry_type,
                'compress': str(pcm.get("compress", 0)),
            }
            cap = pcm["caps"][dir_idx]
            entry['cap_name'] = cap['name']
            for comp_name, comps in comp_map.items():
                if dir_idx == 0 and comp_name in ('KPBM', 'kpb'):
                    continue
                clsTPLGReader.attach_comp_to_pipeline(comps, dir_idx, comp_name, entry)
            entry['fmts'] = " ".join(formats[dir_idx])
            entry['fmt'] = entry['fmts'].split(' ')[0]
            entry['rates'] = " ".join(rates[dir_idx])
            entry['rate_min'], entry['rate_max'] = self._key2str(cap, 'rate')
            entry['ch_min'], entry['ch_max'] = self._key2str(cap, 'channels')
            return entry

        if pcm_type == "both":
            self._pipeline_lst.append(make_entry(0, "playback"))
            self._pipeline_lst.append(make_entry(pcm['capture'], "capture"))
        else:
            self._pipeline_lst.append(make_entry(pcm['capture'], pcm_type))

    @staticmethod
    def _finalize_pipeline_entry(entry, sofcard):
        # If rates is available get first sampling rate from the list.
        # If rates list doesn't have any, then get it from rate_min or rate_max.
        # If none of them is available, then set rate to 0
        if entry['rates']:
            entry['rate'] = entry['rates'].split(' ')[0]
        elif int(entry['rate_min']) != 0:
            entry['rate'] = entry['rate_min']
        elif int(entry['rate_max']) != 0:
            entry['rate'] = entry['rate_max']
        else:
            entry['rate'] = 0
        entry['channel'] = entry['ch_min']
        entry['dev'] = "hw:" + str(sofcard) + ',' + entry['id']
        if entry.get('compress') == '1':
            entry['snd'] = "/dev/snd/comprC" + str(sofcard) + "D" + entry['id']
        else:
            # the character devices for PCM under /dev/snd take the form of
            # "pcmC + card_number + D + device_number + capability", eg, pcmC0D0p.
            entry['snd'] = "/dev/snd/pcmC" + str(sofcard) + "D" + entry['id']
            entry['snd'] += 'p' if entry['type'] == "playback" else 'c'

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
                self._build_pcm_entry(formatter, pcm)

        # format pipeline, this change for script direct access 'rate' 'channel' 'dev' 'snd'
        for entry in self._pipeline_lst:
            self._finalize_pipeline_entry(entry, sofcard)
        return 0

    # The following functions re-implement built-in Python sets
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

    def _filterOutput(self, pipelines, filter_dict, bIn):
        """Returns the subset of pipelines matching a single filter expression.

        pipelines: list of pipelines. Each pipeline is a dict, example:
           {'cap_name': 'Low Latency Playback 0', 'dev': 'hw:0,6',...

        filter_dict: filter like for instance { 'id' : ['3'] }. It's not
           clear what happens if the dict has several elements; avoid?

        bIn: True: exclude filter, False: include filter.
        """
        filtered = []
        for line in pipelines[:]:
            check = False # "check" means "match"
            # This inner for loop is deceiving: the filter_dict usually has a
            # single key:value and then the break/else is pure confusion.
            for key, value in filter_dict.items():
                if 'any' in value or value == ['']:
                    check = key in line
                else:
                    # Use full match for numerical values, and use substring
                    # match for string values
                    if str(line[key]).isdigit():
                        check = str(line[key]) in value
                    else:
                        check = any(em in str(line[key]) for em in value)
                if check is bIn:
                    break
            else:
                # No 'break': include this pipeline
                filtered.append(line)
        return filtered

    def _filter_by_dict(self, filter_dict):
        "filter_dict comes from parse_filter(), see filter_dict example there."
        if filter_dict == {}:
            return self._pipeline_lst
        full_list = self._pipeline_lst
        filtered = None
        # Apply the first expression in the filter
        for key, value in filter_dict['filter'][0].items():
            if key.startswith('~'):
                filtered = self._filterOutput(full_list, {key[1:]:value}, True)
            else:
                filtered = self._filterOutput(full_list, {key:value}, False)
        # Combine with the remaining expressions and boolean
        # operators. Apply the filters from left to right, no usual
        # boolean precedence. See --help below.
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

def func_getPipeline(tplgObj, tplgName, sdcard_id, sort):
    if tplgObj.loadFile(tplgName, sdcard_id) != 0:
        print("tplgreader load file %s failed" % (tplgName))
        sys.exit(1)
    return tplgObj.getPipeline(sort)


def parse_filter(filter_str):
    """Parse filter input into two structures, one is dict list for each
    filter item, and another is logic operation list.  For example
    "id:2 | pga & id:1" is parsed as:

    { 'filter':  [ {'id': ['2']}, {'pga': ['']}, {'id': ['1']} ],
           'op': [              '|',           '&'             ]
    }
    """
    filter_lst = []
    op_lst = []
    for filter_elem in filter_str.split('|'):
        for item in filter_elem.split('&'):
            key, _, value = item.partition(':')
            filter_lst.append({key.strip(): value.strip().split(',')})
    for char in filter_str:
        if char in ('|', '&'):
            op_lst.append(char)
    return dict(zip(['filter', 'op'], [filter_lst, op_lst]))


def parse_and_set_block_keyword(block_str, tplgreader):
    block_list = []
    block_strs = block_str.split(';')
    block_items = [item.strip() for item in block_strs if item != ""]
    for item in block_items:
        block_list.append(parse_filter(item))
    tplgreader.setBlock(block_list)


def _build_arg_parser():
    parser = argparse.ArgumentParser(
        description='Filters and prints PCMs found in a .tplg file',
        add_help=True, formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('filename', type=str, help='tplg file name, multi-tplg file name use "," to split it')
    parser.add_argument('-s', '--sofcard', type=int, help='sofcard id', default=0)
    parser.add_argument('-f', '--filter', type=str,
        help='''setup filter, command line parameter
string format is 'key':'value','value', the filter
string support & | and ~ logic operation.
if only care about key, you can use 'key':'any'.

NOTE: pipelines (actually: _PCMs_) are filtered according to their key-value attributes pairs,
the value in a key-value pair is either numerical or non-numerical. Strings
contain only digits are considered numerical, and others are considered
non-numerical. Exact value match will be carried out for numerical values,
and partial(substring) value match will be carried for non-numerical values.

Example Usage:
`-f "type:any` -> all pipelines (special value match, 'any' matches everything)
`-f "type:playback"` -> playback pipelines (partial match)
`-f "type:capture & pga"` -> capture pipelines with PGA
`-f "pga & eq"` -> pipelines with both EQ and PGA (key match)
`-f "id:3"` -> pipeline whose id is 3 (exact value match)
`-f "pcm:HDMI"` -> pipelines with pcm name contains HDMI (partial value match)

WARNING: usual boolean precedence does NOT apply! Filters are naively
applied from left to right. For instance you could expect "id:2 | pga & id:1"
to be interpreted as "id:2 | (pga & id:1)" and to return some pipelines
with id:1 plus others with id:2. But no: this gets computed from left to
right like this: "(id:2 | pga) & id:1", so this filter is actually
equivalent to the shorter "pga & id:1"

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
    return parser


def _print_pipeline_output(ret_args, pipeline_lst):
    if ret_args['export'] is True:
        sys.exit(export_pipeline(pipeline_lst))
    if ret_args['count'] is True:
        msg = len(pipeline_lst) if ret_args['value'] else "Pipeline Count: %d" % len(pipeline_lst)
        print(msg)
        return
    if ret_args['index'] is not None and ret_args['index'] < len(pipeline_lst):
        print(format_pipeline(pipeline_lst[ret_args['index']], ret_args['value']))
        return
    for entry in pipeline_lst:
        print(format_pipeline(entry, ret_args['value']))


def main():
    ret_args = vars(_build_arg_parser().parse_args())
    tplgreader = clsTPLGReader()

    if ret_args['filter']:
        tplgreader.setFilter(parse_filter(ret_args['filter']))

    default_block_keyword = 'kpbm:any;kpb:any;type:capture & echo;compress:1;'
    cmd_block_str = ret_args['block'].strip() if ret_args['block'] is not None else ''
    if ret_args["filter"] is not None and not re.search('echo|kpb|compress', ret_args["filter"]):
        block_str = default_block_keyword + cmd_block_str
    else:
        block_str = cmd_block_str or "block_none"
    parse_and_set_block_keyword(block_str, tplgreader)

    if ret_args['dump']:
        tplgreader.setField(ret_args['dump'])

    tplg_root = ret_args['tplgroot'] or ""
    pipeline_lst = []
    for fname in ret_args['filename'].split(','):
        path = f"{tplg_root}/{fname}" if tplg_root else fname
        pipeline_lst += func_getPipeline(tplgreader, path, ret_args['sofcard'], ret_args['sort'])[:]

    _print_pipeline_output(ret_args, pipeline_lst)


if __name__ == "__main__":
    main()
