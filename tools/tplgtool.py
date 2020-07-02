#! /usr/bin/python3

import os
import sys
import argparse
import struct
from enum import IntEnum

# Constants used from ASoC
class AsocConsts(IntEnum):
    # topology header types
    TPLG_TYPE_MIXER        = 1
    TPLG_TYPE_BYTES        = 2
    TPLG_TYPE_ENUM         = 3
    TPLG_TYPE_DAPM_GRAPH   = 4
    TPLG_TYPE_DAPM_WIDGET  = 5
    TPLG_TYPE_DAI_LINK     = 6
    TPLG_TYPE_PCM          = 7
    TPLG_TYPE_MANIFEST     = 8
    TPLG_TYPE_CODEC_LINK   = 9
    TPLG_TYPE_BACKEND_LINK = 10
    TPLG_TYPE_PDATA        = 11
    TPLG_TYPE_DAI          = 12

    # mixer kcontrol types
    TPLG_CTL_VOLSW        = 1
    TPLG_CTL_VOLSW_SX     = 2
    TPLG_CTL_VOLSW_XR_SX  = 3
    TPLG_CTL_RANGE        = 7
    TPLG_CTL_STROBE       = 8
    TPLG_DAPM_CTL_VOLSW   = 64
    # enum kcontrol types
    TPLG_CTL_ENUM         = 4
    TPLG_CTL_ENUM_VALUE   = 6
    TPLG_DAPM_CTL_ENUM_DOUBLE = 65
    TPLG_DAPM_CTL_ENUM_VIRT   = 66
    TPLG_DAPM_CTL_ENUM_VALUE  = 67
    # bytes kcontrol types
    TPLG_CTL_BYTES        = 5

    TPLG_DAPM_CTL_PIN     = 68

# the TplgParser class will transform binary tplg into python lists and dicts
class TplgParser():
    # no such header type in the binary tplg, leave this unimplemented
    def _tplg_kcontrol_parse(self, block):
        return None

    # parse snd_soc_tplg_dapm_graph_elem struct
    # the order is rearranged, [sink, ctrl, source] -> [source, ctrl, sink]
    def _tplg_dapm_graph_parse(self, block):
        graph_list = []
        bytes_data = block["data"]
        # we have 3 string to parse for each graph
        for cnt in range(block["header"]["count"]):
            # 44 here is the max string length in C
            idx_start = cnt * 44 * 3
            sink = self._parse_char_array(bytes_data[idx_start: idx_start+44])
            ctrl = self._parse_char_array(bytes_data[idx_start+44:idx_start+88])
            source = self._parse_char_array(bytes_data[idx_start+88:idx_start+132])
            graph = [source, ctrl, sink]
            graph_list.append(graph)
        return graph_list

    # parse snd_soc_tplg_ctl_hdr struct
    def _kcontrol_header_parse(self, bytes_data):
        tplg_kctrl_fields = ["size", "type", "name", "access", "ops", "tlv"]
        values = []
        values.append(struct.unpack("I", bytes_data[:4])[0])
        values.append(struct.unpack("I", bytes_data[4:8])[0])
        values.append(self._parse_char_array(bytes_data[8:52]))
        values.append(struct.unpack("I", bytes_data[52:56])[0])
        # three u32 type to parse for struct snd_soc_tplg_io_ops
        io_ops_val = []
        io_ops_val.append(struct.unpack("I", bytes_data[56:60])[0])
        io_ops_val.append(struct.unpack("I", bytes_data[60:64])[0])
        io_ops_val.append(struct.unpack("I", bytes_data[64:68])[0])
        values.append(dict(zip(["get", "put", "info"], io_ops_val)))
        # parse snd_soc_tplg_ctl_tlv struct
        ctrl_tlv_val = []
        ctrl_tlv_val.append(struct.unpack("I", bytes_data[68:72])[0])
        ctrl_tlv_val.append(struct.unpack("I", bytes_data[72:76])[0])
        tlv_union = []
        for i in range(32):
            idx_start = 76 + 4*i
            idx_end = 76 + 4*i + 4
            tlv_union.append(struct.unpack("I", bytes_data[idx_start: idx_end])[0])
        ctrl_tlv_val.append(tlv_union)
        values.append(dict(zip(["size", "type", "data_or_scale"], ctrl_tlv_val)))

        ctrl_hdr = dict(zip(tplg_kctrl_fields, values))

        return ctrl_hdr, bytes_data[204:]

    # parse snd_soc_tplg_mixer_control struct
    def _mixer_ctrl_parse(self, bytes_data):
        mixer_ctrl_fields = ["size", "min", "max", "platform_max", "invert", "num_channels", \
            "channel", "priv"]
        values = []
        # 6 u32 to parse (size ... num_channels)
        for i in range(6):
            idx_start = 4 * i
            idx_end = 4*i + 4
            values.append(struct.unpack("I",bytes_data[idx_start:idx_end])[0])
        # parse channel_list, up to 8 elems in the list, each with 4 u32
        channel_list = []
        for i in range(8):
            tplg_channel_val = []
            idx_start = 24 + i*16
            tplg_channel_val.append(struct.unpack("I",bytes_data[idx_start:idx_start+4])[0])
            tplg_channel_val.append(struct.unpack("I",bytes_data[idx_start+4:idx_start+8])[0])
            tplg_channel_val.append(struct.unpack("I",bytes_data[idx_start+8:idx_start+12])[0])
            tplg_channel_val.append(struct.unpack("I",bytes_data[idx_start+12:idx_start+16])[0])
            channel_list.append(dict(zip(["size","reg","shift","id"], tplg_channel_val)))
        values.append(channel_list)

        priv_size = struct.unpack("I", bytes_data[152:156])[0]
        priv = {"size":priv_size}
        if priv_size == 0:
            priv["data"] = None
        else :
            priv["data"] = bytes_data[156:156+priv_size]
        values.append(priv)

        mixer = dict(zip(mixer_ctrl_fields, values))
        # test if we are at the end of the byte data
        if len(bytes_data[156 + priv_size - 1:]) < 4:
            return mixer, None

        bytes_data = bytes_data[156 + priv_size:]
        return mixer, bytes_data

    # no such kcontrol in the binary tplg till now, leave this unimplemented
    def _enum_ctrl_parse(self, bytes_data):
        pass

    def _bytes_ctrl_parse(self, bytes_data):
        bytes_ctrl_fields = ["size", "max", "mask", "base", "num_regs", "ext_ops", "priv"]
        values = []
        # parse 5 u32 (size ... num_regs)
        for i in range(5):
            idx_start = 4 * i
            idx_end = 4*i + 4
            values.append(struct.unpack("I",bytes_data[idx_start:idx_end])[0])
        # parse snd_soc_tplg_io_ops struct
        io_ops_val = []
        io_ops_val.append(struct.unpack("I", bytes_data[20:24])[0])
        io_ops_val.append(struct.unpack("I", bytes_data[24:28])[0])
        io_ops_val.append(struct.unpack("I", bytes_data[28:32])[0])
        values.append(dict(zip(["get", "put", "info"], io_ops_val)))

        priv_size = struct.unpack("I", bytes_data[32:36])[0]
        priv = {"size": priv_size}
        if priv_size == 0:
            priv["data"] = None
        else :
            priv["data"] = bytes_data[36:36+priv_size]
        values.append(priv)

        bytes_ctrl = dict(zip(bytes_ctrl_fields, values))

        if len(bytes_data[36 + priv_size - 1:]) < 4:
            return bytes_ctrl, None

        rest_data = bytes_data[36 + priv_size:]
        return bytes_ctrl, rest_data

    # find the corresponding function to call for each kcontrol type
    def _find_kctrl_parse_func(self, ctrl_hdr):
        kctrl_type = ctrl_hdr["ops"]["info"]
        if kctrl_type in [AsocConsts.TPLG_CTL_VOLSW, AsocConsts.TPLG_CTL_STROBE, \
                AsocConsts.TPLG_CTL_VOLSW_SX, AsocConsts.TPLG_CTL_VOLSW_XR_SX, \
                AsocConsts.TPLG_CTL_RANGE, AsocConsts.TPLG_DAPM_CTL_VOLSW]:
            return self._mixer_ctrl_parse

        if kctrl_type in [AsocConsts.TPLG_CTL_ENUM, AsocConsts.TPLG_CTL_ENUM_VALUE, \
                AsocConsts.TPLG_DAPM_CTL_ENUM_DOUBLE, AsocConsts.TPLG_DAPM_CTL_ENUM_VIRT, \
                AsocConsts.TPLG_DAPM_CTL_ENUM_VALUE]:
            return self._enum_ctrl_parse

        if kctrl_type in [AsocConsts.TPLG_CTL_BYTES]:
            return self._bytes_ctrl_parse
        return None

    def _dapm_kcontrol_parse(self, bytes_data, kctrl_count):
        bytes_array = bytes_data
        kctrl_list = []
        parse_func = None

        for _ in range(kctrl_count):
            ctrl_hdr, bytes_array = self._kcontrol_header_parse(bytes_array)
            parse_func = self._find_kctrl_parse_func(ctrl_hdr)
            if parse_func is not None:
                ctrl, bytes_array = parse_func(bytes_array)
                ctrl["hdr"] = ctrl_hdr
                kctrl_list.append(ctrl)

        return kctrl_list, bytes_array

    # parse snd_soc_tplg_dapm_widget struct
    def _parse_dapm_widget_struct(self, bytes_data):
        widget_fields = ["size", "id", "name", "sname", "reg", "shift", "mask", "subseq", "invert", \
            "ignore_suspend", "event_flags", "event_type", "num_kcontrols", "priv"]

        values = []

        values.append(struct.unpack("I",bytes_data[:4])[0])
        values.append(struct.unpack("I",bytes_data[4:8])[0])
        values.append(self._parse_char_array(bytes_data[8:52]))
        values.append(self._parse_char_array(bytes_data[52:96]))
        #the next six fields(reg ... ignore_suspend) have the same u32 type
        six_le32 = [i[0] for i in struct.iter_unpack("I", bytes_data[96:120])]
        for i in six_le32: values.append(i)

        values.append(struct.unpack("H", bytes_data[120:122])[0])
        values.append(struct.unpack("H", bytes_data[122:124])[0])
        values.append(struct.unpack("I",bytes_data[124:128])[0])

        priv_size = struct.unpack("I", bytes_data[128:132])[0]
        priv = {"size":priv_size}
        if priv_size == 0:
            priv_data = None
        else :
            priv_data = bytes_data[132:132+priv_size]
        priv["data"] = priv_data
        values.append(priv)

        bytes_data_idx = 132 + priv_size

        dapm_widget = dict(zip(widget_fields, values))

        kctrl_count = dapm_widget["num_kcontrols"]
        if kctrl_count == 0:
            dapm_widget["kcontrol"] = None
            if len(bytes_data[bytes_data_idx-1:]) < 4:
                return dapm_widget, None

            return dapm_widget, bytes_data[bytes_data_idx:]

        kctrl_list, bytes_data = self._dapm_kcontrol_parse(bytes_data[bytes_data_idx:], kctrl_count)

        dapm_widget["kcontrol"] = kctrl_list

        if bytes_data == None:
            return dapm_widget, None

        return dapm_widget, bytes_data

    def _tplg_dapm_widget_parse(self, block):
        bytes_data = block["data"]
        dapm_widget_list = []
        while bytes_data != None:
            widget, bytes_data = self._parse_dapm_widget_struct(bytes_data)
            dapm_widget_list.append(widget)
        return dapm_widget_list

    def _parse_char_array(self, bytes_data):
        string = str(bytes_data).split('\'')[1]
        idx = string.find('\\')
        return string[0:idx]

    def _parse_stream_struct(self, bytes_data):
        tplg_stream_fields = ["size", "name", "format", "rate", "period_bytes", "buffer_bytes", "channels"]
        stream_value = []
        stream_value.append(struct.unpack("I", bytes_data[0:4])[0])
        stream_value.append(self._parse_char_array(bytes_data[4:48]))
        stream_value.append(struct.unpack("Q", bytes_data[48: 56])[0])
        for i in list(struct.iter_unpack("I", bytes_data[56:])):
            stream_value.append(i[0])
        stream_struct = dict(zip(tplg_stream_fields, stream_value))
        return stream_struct

    def _parse_stream_cap_struct(self, bytes_data):
        tplg_stream_caps_fields = ["size", "name", "formats", "rates", "rate_min", "rate_max", "channels_min",
            "channels_max", "periods_min", "periods_max", "period_size_min", "period_size_max",
            "buffer_size_min", "buffer_size_max", "sig_bits"]
        stream_cap_value = []
        stream_cap_value.append(struct.unpack("I", bytes_data[:4])[0])
        stream_cap_value.append(self._parse_char_array(bytes_data[4:48]))
        stream_cap_value.append(struct.unpack("Q", bytes_data[48:56])[0])
        # rates ... sig_bits are all u32 type
        for i in list(struct.iter_unpack("I", bytes_data[56:])):
            stream_cap_value.append(i[0])
        stream_cap_struct = dict(zip(tplg_stream_caps_fields, stream_cap_value))
        return stream_cap_struct


    def _parse_pcm_struct(self, bytes_data):
        pcm_fields = ["size", "pcm_name", "dai_name", "pcm_id", "dai_id", "playback", "capture",
            "compress", "stream", "num_streams", "caps", "flag_mask", "flags", "priv"]
        values = []
        values.append(struct.unpack("I",bytes_data[:4])[0])
        values.append(self._parse_char_array(bytes_data[4:48]))
        values.append(self._parse_char_array(bytes_data[48:92]))
        for i in list(struct.iter_unpack("I", bytes_data[92:112])):
            values.append(i[0])

        # parse snd_soc_tplg_stream array
        stream_list = []
        tplg_stream_size = 72 # tplg_stream size is 72
        stream_data = bytes_data[112:688]
        for idx in range(8):
            stream_start = tplg_stream_size * idx
            stream_list.append(self._parse_stream_struct(stream_data[stream_start: stream_start + 72]))
        values.append(stream_list)

        values.append(struct.unpack("I", bytes_data[688:692])[0])

        # parse snc_soc_tplg_stream_caps
        stream_cap_list = []
        tplg_stream_caps_size = 104
        stream_cap_data = bytes_data[692:900]
        for idx in range(2):
            start = tplg_stream_caps_size * idx
            stream_cap_list.append(self._parse_stream_cap_struct(stream_cap_data[start:start+tplg_stream_caps_size]))

        values.append(stream_cap_list)
        values.append(struct.unpack("I", bytes_data[900:904])[0])
        values.append(struct.unpack("I", bytes_data[904:908])[0])

        priv_size = struct.unpack("I", bytes_data[908:912])[0]
        priv = {"size":priv_size}
        if priv_size == 0:
            priv["data"] = None
        else :
            priv["data"] = bytes_data[908:908+priv_size]
        values.append(priv)

        pcm = dict(zip(pcm_fields, values))
        if len(bytes_data[912 + priv_size -1:]) < 4:
            return pcm, None
        return pcm, bytes_data[912+priv_size:]

    def _tplg_pcm_parse(self, block):
        bytes_data = block["data"]
        pcm_list = []
        for _ in range(block["header"]["count"]):
            parsed_pcm, bytes_data = self._parse_pcm_struct(bytes_data)
            pcm_list.append(parsed_pcm)

        return pcm_list

    # no such header type in the binary tplg now, leave this unimplemented
    def _tplg_dai_parse(self, bytes_data):
        return None

    def _tplg_link_parse(self, block):
        link_config_fields = ["size", "id", "name", "stream_name", "stream", "num_streams", "hw_config", \
            "num_hw_configs", "default_hw_config_id", "flag_mask", "flags", "priv"]
        bytes_data = block["data"]
        link_list = []

        for _ in range(block["header"]["count"]):
            values = []
            values.append(struct.unpack("I", bytes_data[:4])[0])
            values.append(struct.unpack("I", bytes_data[4:8])[0])
            values.append(self._parse_char_array(bytes_data[8:52]))
            values.append(self._parse_char_array(bytes_data[52:96]))

            # parse snd_soc_tplg_stream
            stream_list = []
            tplg_stream_size = 72 # tplg_stream size is 72
            stream_data = bytes_data[96:672]
            for idx in range(8):
                stream_start = tplg_stream_size * idx
                stream_val = self._parse_stream_struct(stream_data[stream_start: stream_start+tplg_stream_size])
                stream_list.append(stream_val)
            values.append(stream_list)

            values.append(struct.unpack("I", bytes_data[672:676])[0])

            # parse snd_soc_tplg_hw_config
            hw_config_list = []
            hw_config_size = 120 # sizeof snd_soc_tplg_hw_config is 120
            hw_config_data = bytes_data[676:1636]
            for idx in range(8):
                idx_start = hw_config_size * idx
                hw_config_list.append(self._parse_hw_config(hw_config_data[idx_start:idx_start+hw_config_size]))
            values.append(hw_config_list)

            for i in range(4):
                values.append(struct.unpack("I", bytes_data[1636+4*i: 1640+4*i])[0])

            priv_size = struct.unpack("I", bytes_data[1652:1656])[0]
            priv = {"size": priv_size}
            if priv_size == 0:
                priv["data"] = None
                bytes_data = bytes_data[1656:]
            else :
                priv["data"] = bytes_data[1656:1656+priv_size]
                bytes_data = bytes_data[1656+priv_size:]

            values.append(priv)
            link_config = dict(zip(link_config_fields, values))
            link_list.append(link_config)

        return link_list

    # parse snd_soc_tplg_hw_config struct
    def _parse_hw_config(self, bytes_data):
        hw_config_fields = ["size", "id", "fmt", "clock_gated", "invert_bclk", "invert_fsync", "bclk_master", \
             "fsync_master", "mclk_direction", "reserved", "mclk_rate", "bclk_rate", "fsync_rate", "tdm_slots", \
             "tdm_slot_width", "tx_slots", "rx_slots", "tx_channels", "tx_chanmap", "rx_channels", "rx_chanmap"]

        values = []
        # size ... fmt
        values.append(struct.unpack("I", bytes_data[:4])[0])
        values.append(struct.unpack("I", bytes_data[4:8])[0])
        values.append(struct.unpack("I", bytes_data[8:12])[0])
        # clock_gated ... mclk_direction
        for i in range(6):
            values.append(bytes_data[12+i])
        # reserved
        values.append(struct.unpack("H", bytes_data[18:20])[0])
        # mclk_rate ... tx_channels
        for i in range(8):
            values.append(struct.unpack("I", bytes_data[20+4*i: 24+4*i])[0])
        # tx_chanmap
        tx_chanmap_val = []
        for i in range(8):
            tx_chanmap_val.append(struct.unpack("I", bytes_data[52+4*i: 56+4*i])[0])
        values.append(tx_chanmap_val)
        # rx_channels
        values.append(struct.unpack("I", bytes_data[84:88]))
        # rx_chanmap
        rx_chanmap_val = []
        for i in range(8):
            rx_chanmap_val.append(struct.unpack("I", bytes_data[88+4*i: 92+4*i])[0])
        values.append(rx_chanmap_val)

        hw_config = dict(zip(hw_config_fields, values))
        return hw_config

    def _tplg_manifest_parse(self, block):
        bytes_data = block["data"]
        manifest_fields = ["size", "ctrl_elems", "widget_elems", "graph_elems", "pcm_elems", \
            "dai_link_elems", "dai_elems","reserved", "priv"]
        values = [i[0] for i in list(struct.iter_unpack("I", bytes_data[:28]))]
        # reserved
        values.append(bytes_data[28:108])

        priv_size = struct.unpack("I", bytes_data[28:32])[0]
        priv = {"size": priv_size}
        if priv_size == 0:
            priv["data"] = None
        else :
            priv["data"] = bytes_data[32:32+priv_size]
        values.append(priv)
        return dict(zip(manifest_fields, values))


    def _parse_block_header(self, block):
        header_fields = ["abi","version", "type", "size", \
            "vender_type","payload_size", "index", "count"]
        header_values = [i[0] for i in list(struct.iter_unpack("I",block[:32]))]
        # we lost magic info when we use it to split tplg binary, add it back here
        header_values.append({"magic":"CoSA"})
        parse_header = dict(zip(header_fields, header_values))
        # retain raw data in the dict
        block = {"header": parse_header, "data": block[32:], "raw_hdr":b'CoSA' + block[:32]}
        return block

    def _parse_block_data(self, block):
        hdr_type = block["header"]["type"]

        if hdr_type in [AsocConsts.TPLG_TYPE_MANIFEST]:
            block["manifest"] = self._tplg_manifest_parse(block)

        if hdr_type in [AsocConsts.TPLG_TYPE_PCM]:
            block["pcm"] = self._tplg_pcm_parse(block)

        if hdr_type in [AsocConsts.TPLG_TYPE_MIXER, AsocConsts.TPLG_TYPE_ENUM, \
                AsocConsts.TPLG_TYPE_BYTES]:
            block["kcontrol"] = self._tplg_kcontrol_parse(block)

        if hdr_type in [AsocConsts.TPLG_TYPE_DAI]:
            block["dai"] = self._tplg_dai_parse(block)

        if hdr_type in [AsocConsts.TPLG_TYPE_DAPM_GRAPH]:
            block["graph"] = self._tplg_dapm_graph_parse(block)

        if hdr_type in [AsocConsts.TPLG_TYPE_DAPM_WIDGET]:
            block["widget"] = self._tplg_dapm_widget_parse(block)

        if hdr_type in [AsocConsts.TPLG_TYPE_DAI_LINK, AsocConsts.TPLG_TYPE_BACKEND_LINK]:
            block["link"] = self._tplg_link_parse(block)
        return block

    def _parse_block(self, block):
        block = self._parse_block_header(block)
        block = self._parse_block_data(block)
        return block

    def parse(self,tplg_file):
        try:
            with open(tplg_file,"rb") as fd:
                self._tplg_binary = fd.read()
        except:
            print("File %s open error" %tplg_file)
            sys.exit(1)

        # here we call a header with its data a block
        parsed_tplg = []
        # split binary with header's "magic" field
        splited_blocks = self._tplg_binary.split(b'CoSA')

        # skip the first element for it is introduced by the 'split' and is actually nothing
        for block in splited_blocks[1:]:
            parsed_tplg.append(self._parse_block(block))
        # the last element in the parsed tplg is the tplg file name
        parsed_tplg.append(tplg_file)
        return parsed_tplg

# the TplgFormater class will format the output
class TplgFormatter:
    def __init__(self, parsed_tplg):
        self._tplg = self._group_block(parsed_tplg)

    def _group_block(self, parsed_tplg):
        tplg = dict()
        widget_list = []
        graph_list = []
        pcm_list = []
        # the last item is tplg name, ignore it
        for item in parsed_tplg[:-1]:
            if "pcm" in item.keys():
                pcm_list.append(sorted(item["pcm"],key=self._sort_by_id))
            if "widget" in item.keys():
                widget_list.append(item["widget"])
            if "graph" in item.keys():
                graph_list.append(item["graph"])
            if "link" in item.keys():
                tplg["link"] = sorted(item["link"],key=self._sort_by_id)
            if "manifest" in item.keys():
                tplg["manifest"] = item["manifest"]
        tplg["pcm_list"] = pcm_list
        tplg["graph_list"] = graph_list
        tplg["widget_list"] = widget_list
        tplg["name"] = parsed_tplg[-1]
        return tplg

    @staticmethod
    def _sort_by_id(item):
        # for link sort
        if "id" in item.keys():
            return item["id"]
        # for pcm sort
        if "pcm_id" in item.keys():
            return item["pcm_id"]
        return 0

    # transform number denoted pipeline format to string
    @staticmethod
    def _to_fmt_string(fmt):
        fmts = []
        if fmt & (1 << 2) != 0:
            fmts.append("S16_LE")
        if fmt & (1 << 6) != 0:
            fmts.append("S24_LE")
        if fmt & (1 << 10) != 0:
            fmts.append("S32_LE")
        if fmt & (1 << 14) != 0:
            fmts.append("FLOAT")
        return fmts

    # always return a list, playback stream fmt in fmt_list[0]
    # capture stream fmt in fmt_list[1], the format of absense
    # stream is UNKNOWN
    @staticmethod
    def get_pcm_fmt(pcm):
        fmt_list = []
        caps = pcm["caps"]
        for cap in caps:
            fmt_list.append(TplgFormatter._to_fmt_string(cap["formats"]))
        return fmt_list

    @staticmethod
    def get_pcm_type(item):
        if item["playback"] == 1 and item["capture"] == 1:
            return "both"
        if item["playback"] == 1:
            return "playback"
        if item["capture"] == 1:
            return "capture"
        return "None"

    # return a list of six elements, rate_min, rate_max and rates of playback
    # pipeline and rate_min, rate_max and rates of capture pipeline
    @staticmethod
    def get_pcm_rates(pcm):
        return [pcm["caps"][0]["rate_min"], pcm["caps"][0]["rate_max"], \
        pcm["caps"][0]["rates"], pcm["caps"][1]["rate_min"], \
        pcm["caps"][1]["rate_max"], pcm["caps"][1]["rates"]]

    # return a list of four elements, channels_min/channel_max
    # for playback and channels_min/channel_max for capture
    @staticmethod
    def get_pcm_channels(pcm):
        return [pcm["caps"][0]["channels_min"], pcm["caps"][0]["channels_max"],
            pcm["caps"][1]["channels_min"], pcm["caps"][1]["channels_max"]]

    # merge pcm blocks into one list for output
    def _merge_pcm_list(self, pcm_block_list):
        merged_pcm_list = []
        for pcms in pcm_block_list:
            for pcm in pcms:
                merged_pcm_list.append(pcm)
        return merged_pcm_list

    # graph node form: {"name":name, "widget":widget, "ctrl":ctrl, "source":source, "sink":sink}
    # return values:
    #   link_head_list: head node list of every graph
    #   node_list: list of all nodes
    def link_graph(self):
        node_list = self._init_node_list()
        # const variables for graph
        SOURCE = 0
        CONTROL = 1
        SINK = 2
        for graphs in self._tplg["graph_list"]:
            for graph in graphs:
                source_node = self.find_node_by_name(graph[SOURCE], node_list)
                sink_node = self.find_node_by_name(graph[SINK], node_list)

                # some of the names in graph are from widget["name"] (eg: PCM0P), and others are
                # from widget["sname"] (eg: SSP1.OUT), use the name in graph as standard name of a node
                source_node["name"] = graph[SOURCE]
                sink_node["name"] = graph[SINK]

                source_node["ctrl"] = graph[CONTROL]
                # a node may link to multiple nodes
                if source_node["sink"] != None: # this node has a link already
                    # if already link to a node
                    if type(source_node["sink"]) != list:
                        next_list = [source_node["sink"], sink_node]
                        source_node["sink"] = next_list
                    # if already link to a node list
                    else:
                        source_node["sink"].append(sink_node)
                # not link to any node
                else:
                    source_node["sink"] = sink_node

                if sink_node["source"] != None:
                    if type(sink_node["source"]) != list:
                        prev_list = [sink_node["source"], source_node]
                        sink_node["source"] = prev_list
                    else:
                        sink_node["source"].append(source_node)
                else:
                    sink_node["source"] = source_node

        link_head_list = []
        # find head node of a graph
        for elem in node_list:
            if elem["source"] == None and elem["sink"] != None:
                link_head_list.append(elem)
        return link_head_list, node_list

    # initialize node list from widget list, all the node should have its name
    # and widget field initialized, and other fields are left None
    def _init_node_list(self):
        node_list = []

        for widgets in self._tplg["widget_list"]:
            for widget in widgets:
                node = {"name":widget["name"], "widget":widget, "ctrl":None, "source":None, "sink":None}
                node_list.append(node)
        if node_list == []: # should never goes here
            print("No widget in topology!")
            sys.exit(1)
        return node_list

    # find node by its name from node_list, as the name of a node is not unified to
    # widget["name"] or widget["sname"], we should check both
    @staticmethod
    def find_node_by_name(name, node_list):
        if name == '': return None
        for node in node_list:
                if name == node["widget"]["name"] or name == node["widget"]["sname"]:
                    return node
        # if excution goes here, it means we didn't find the widget in the list,
        # obviously, there is error in topology
        print("Widget %s not exist, error in topology" %name)
        sys.exit(1)
        return None

    @staticmethod
    def recursive_search_comp(node, comp_type, comp_list, direction):
        def comp_in_list(comp, comp_list):
            for elem in comp_list:
                if elem == comp["widget"]:
                    return True
            return False

        if node is None:
            return

        if type(node) == list:
            for elem in node:
                TplgFormatter.recursive_search_comp(elem, comp_type, comp_list, direction)

        if type(node) != list and direction == "forward":
            if node["widget"]["name"].startswith(comp_type):
                if not comp_in_list(node, comp_list): comp_list.append(node["widget"])
            TplgFormatter.recursive_search_comp(node["sink"], comp_type, comp_list, direction)

        if type(node) != list and direction == "backward":
            if node["widget"]["name"].startswith(comp_type):
                if not comp_in_list(node, comp_list): comp_list.append(node["widget"])
            TplgFormatter.recursive_search_comp(node["source"], comp_type, comp_list, direction)

    # find specified type of components connected to ref_node
    @staticmethod
    def find_connected_comp(ref_node, comp_type):
        if ref_node is None:
            return None
        comp_type = comp_type.upper() # to upper case
        comp_list = []
        node = ref_node
        TplgFormatter.recursive_search_comp(node, comp_type, comp_list, "forward")
        TplgFormatter.recursive_search_comp(node, comp_type, comp_list, "backward")
        return comp_list

    # find specified components for PCM
    # return a list:
    #   [0]: specified components connected to playback
    #   [1]: specified components connected to capture
    def find_comp_for_pcm(self, pcm, comp_type):
        _, node_list = self.link_graph()
        pcm_name = [pcm["caps"][0]["name"], pcm["caps"][1]["name"]]
        playback_node = self.find_node_by_name(pcm_name[0], node_list) # playback node
        capture_node = self.find_node_by_name(pcm_name[1], node_list) # capture node
        playback_comp = self.find_connected_comp(playback_node, comp_type)
        capture_comp = self.find_connected_comp(capture_node, comp_type)
        return [playback_comp, capture_comp]

    def format_pcm(self):
        pcms = self._merge_pcm_list(self._tplg["pcm_list"])
        for pcm in pcms:
            fmt_list = TplgFormatter.get_pcm_fmt(pcm)
            pcm_type = TplgFormatter.get_pcm_type(pcm)
            pcm_rates = TplgFormatter.get_pcm_rates(pcm)
            pcm_channels = TplgFormatter.get_pcm_channels(pcm)

            fmt = fmt_list[0]
            rates = pcm_rates[:3]
            channel = pcm_channels[0:2]
            if pcm_type == "capture":
                fmt = fmt_list[1]
                rates = pcm_rates[3:]
                channel = pcm_channels[2:]

            print("pcm=%s;id=%d;type=%s;fmt=%s;rate_min=%d;rate_max=%d;ch_min=%d;ch_max=%d;"
                %(pcm["pcm_name"], pcm["pcm_id"], pcm_type, fmt[0], rates[0], rates[1], \
                channel[0], channel[1]))


if __name__ == "__main__":

    def parse_cmdline():
        parser = argparse.ArgumentParser(add_help=True, formatter_class=argparse.RawTextHelpFormatter,
            description='A Topology Reader totally Written in Python.')

        parser.add_argument('--version', action='version', version='%(prog)s 1.0')
        parser.add_argument('-t', '--tplgroot', type=str, help="load tplg file from tplg_root folder")
        parser.add_argument('-d', '--dump', type=str, help='dump specified topology information, '
            'if multiple information types are wanted, use "," to separate them, eg, `-d pcm,graph`')
        parser.add_argument('filename', type=str, help='topology file name(s), ' \
            'if multiple topology file names are specified, please use "," to separate them')
        # The below options are used to control generated graph
        parser.add_argument('-D', '--directory', type=str, default=".", help="output directory for generated graph")
        parser.add_argument('-F', '--format', type=str, default="png", help="output format for generated graph, check "
            "https://graphviz.gitlab.io/_pages/doc/info/output.html for all supported formats")
        parser.add_argument('-V', '--live_view', action="store_true", help="generate and view topology graph")


        return vars(parser.parse_args())

    def get_tplg_paths(cmd_args):
        if cmd_args["tplgroot"] is None:
            return [tplg.strip() for tplg in cmd_args['filename'].split(',')]
        tplg_paths = []
        tplg_root = cmd_args["tplgroot"].strip()
        if not os.path.exists(tplg_root):
            print("path %s not exist!" %tplg_root)
            sys.exit(1)
        if cmd_args["filename"] == "all":
            files = os.walk(tplg_root)
            for _, _, files in os.walk(tplg_root, topdown=False):
                for name in files:
                    if name.endswith(".tplg"): tplg_paths.append(tplg_root + '/' + name)
            return tplg_paths

        for f in cmd_args["filename"].split(','):
            if len(tplg_root) > 0:
                f = tplg_root.strip() + '/' + f.strip()
            tplg_paths.append(f)
        return tplg_paths

    # connect nodes
    def connect(graph, head):
        assert(head is not None) # make sure head is not None
        if head["sink"] != None and type(head["sink"]) != list:
            graph.edge(head["name"], head["sink"]["name"])
            connect(graph, head["sink"])
        elif head["sink"] != None:
            for node in head["sink"]:
                graph.edge(head["name"], node["name"])
                connect(graph, node)

    # traverse all nodes, and add them to graph
    def init_node(graph, head):
        # this function is used to deal with multiple connections.
        def inner_init(graph, head):
            if head["sink"] != None and type(head) != list:
                graph.node(name=head["name"])
                init_node(graph, head["sink"])
            elif head["sink"] != None:
                for node in head["sink"]:
                    init_node(graph, node)
            else :
                graph.node(name=head["name"])

        assert(head is not None) # make sure head is not None
        if type(head) != list:
            inner_init(graph, head)
        else :
            for subhead in head:
                inner_init(graph, subhead)

    def dump_pcm_info(parsed_tplgs):
        for tplg in parsed_tplgs:
            formatter = TplgFormatter(tplg)
            formatter.format_pcm()
            print()

    def dump_graph(parsed_tplgs, cmd_args):
        try:
            from graphviz import Digraph
        except:
            print("graphviz package not installed, please install with `sudo apt install python3-graphviz`")
            sys.exit(1)

        format = cmd_args['format'].strip()
        dir = cmd_args['directory'].strip()

        for tplg in parsed_tplgs:
            # the last element in tplg is topology path
            outfile = tplg[-1].split(sep='/')[-1].split('.')[0]
            formatter = TplgFormatter(tplg)
            head_list, _ = formatter.link_graph()

            graph = Digraph("Topology Graph", format=format)
            # Here we make every pipeline as a subgraph, this gives us more precise control
            for head in head_list:
                subgraph = Digraph('Pipeline' + head['name'])
                init_node(subgraph, head)
                connect(subgraph,head)
                # add subgraph to the graph
                graph.subgraph(graph=subgraph)
            # Developers may want to view graph without saving it.
            if cmd_args['live_view']:
                # if run the tool over ssh, live view feature will be disabled
                if 'DISPLAY' not in os.environ.keys():
                    print("No available GUI over ssh, unable to view the graph")
                else:
                    graph.view(filename=outfile, directory='/tmp', cleanup=True)
            else:
                graph.render(filename=outfile, directory=dir, cleanup=True)

    parsed_tplg_list = []

    cmd_args = parse_cmdline()

    tplg_paths = get_tplg_paths(cmd_args)

    tplg_parser = TplgParser()

    for tplg in tplg_paths:
        parsed_tplg_list.append(tplg_parser.parse(tplg))

    supported_dump = ['pcm', 'graph']
    dump_types = supported_dump if cmd_args['dump'] is None else cmd_args['dump'].split(',')
    dump_types = list(map(lambda elem: elem.strip(), dump_types))
    if 'pcm' in dump_types:
        dump_pcm_info(parsed_tplg_list)
    if 'graph' in dump_types:
        dump_graph(parsed_tplg_list, cmd_args)
