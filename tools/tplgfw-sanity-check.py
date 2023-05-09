#!/usr/bin/env python3

import argparse
import uuid
from construct import this, ListContainer, Struct, Bytes, PaddedString
from construct import Int16ul, Int32ul
import tplgtool2

class Fw_Parser:

    def __init__(self):
        self.fw_header_offset = 0x2000

        self.Ext_header = Struct (
            "id" / PaddedString(4, "ascii"),
            "len" / Int32ul,
            "version_major" / Int16ul,
            "version_minor" / Int16ul,
            "module_entries" / Int32ul,
        )

        self.Fw_binary_header = Struct (
            "id" / PaddedString(4, "ascii"),
            "len" / Int32ul,
            "name" / PaddedString(8, "ascii"),
            "preload_page_count" / Int32ul,
            "flags" /Int32ul,
            "feature_mask" / Int32ul,
            "major" / Int16ul,
            "minor" / Int16ul,
            "hotfix" / Int16ul,
            "build" / Int16ul,
            "module_entries" / Int32ul,
            "hw_buffer_add" / Int32ul,
            "hw_buffer_len" / Int32ul,
            "load_offset" / Int32ul,
        )

        self.Module_segment = Struct (
            "flags" / Int32ul,
            "v_base_addr" / Int32ul,
            "file_offset" / Int32ul,
        )

        self.Module_entry = Struct (
            "id" / Int32ul,
            "name" / PaddedString(8, "ascii"),
            "uuid" / Bytes(16),
            "type" / Int32ul,
            "hash" / Bytes(32),
            "entry_point" / Int32ul,
            "cfg_offset" / Int16ul,
            "cfg_count" / Int16ul,
            "affinity_mask" / Int32ul,
            "instance_max_count" / Int16ul,
            "stack_size" / Int16ul,
            "segment" / self.Module_segment[3],
        )

        self.Ext_manifest = Struct (
            "ext_header" / self.Ext_header,
            "padding1" / Bytes(this.ext_header.len + self.fw_header_offset - self.Ext_header.sizeof()),
            "fw_binary_header" / self.Fw_binary_header,
            "modules" / self.Module_entry[this.fw_binary_header.module_entries],
        )

    def parse_file(self, filepath) -> ListContainer:
        with open(filepath, "rb") as fw :
            return self.Ext_manifest.parse_stream(fw)

    def parse_fw_header(self, filepath) -> ListContainer:
        with open(filepath, "rb") as fw :
            return self.Ext_header.parse_stream(fw)

if __name__ == "__main__":

    def parse_cmdline():
        parser = argparse.ArgumentParser(add_help=True, formatter_class=argparse.RawTextHelpFormatter, description="""
        A Python tool to match UUID in topology and FW, then find out whether all module in topoloy
        can be supported by this FW. Currently it only supports IPC4 FW and IPC3 & IPC4 topology.
        The output includes FW version and with an error message if they are not matched. And all the
        unsupported modules will be printed out.

        example: tplgfw-sanity-check.py -t sof-tgl-nocodec.tplg -f basefw.bin"""
        )

        parser.add_argument('--version', action='version', version='%(prog)s 1.0')
        parser.add_argument('-t', type=str, nargs='+', required=True, help="""Load topology files for check """)
        parser.add_argument('-f', type=str, nargs='+', required=True, help="""Load firmware files for check """)
        parser.add_argument('-v', '--verbose', action="store_true", help="Show check state")

        return parser.parse_args()

if __name__=="__main__":
    def main():
        tplgFormat = tplgtool2.TplgBinaryFormat()
        cmd_args = parse_cmdline()
        tplg = tplgtool2.GroupedTplg(tplgFormat.parse_file(cmd_args.t[0]))

        fw_parser = Fw_Parser()
        fw_content = fw_parser.parse_file(cmd_args.f[0])
        print("FW release version: {0}.{1}".format(fw_content.ext_header.version_major, fw_content.ext_header.version_minor))

        if fw_content.ext_header.id == '$AE1':
            print("IPC4 supported FW\n")
        elif fw_content.ext_header.id == 'XMan':
            print("IPC3 supported FW\n")
        else:
            print("Invalid FW")
            return -1

        fw_uuid_set = {m.uuid for m in fw_content.modules}
        tplg_uuid_dict = {tplg.get_widget_uuid(w): w["widget"]["name"] for w in tplg.widget_list if tplg.get_widget_uuid(w) is not None}

        uuid_diff_set = set(tplg_uuid_dict.keys()) - fw_uuid_set
        for uuid_item in uuid_diff_set:
            failed_uuid = uuid.UUID(bytes=uuid_item)
            print("wdiget {0} uuid: {1} is not found ".format(tplg_uuid_dict[uuid_item], failed_uuid))

        if len(uuid_diff_set):
            print("This FW can't support with this topology")
            return -1

        print("This FW can support with this topology")
        return 0

if __name__=="__main__":
    main()
