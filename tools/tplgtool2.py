#!/usr/bin/env python3

import argparse
import construct
import enum
import os
import re
import sys
import typing
from collections import defaultdict
from construct import this, Container, ListContainer, Struct, Switch, Array, Bytes, GreedyBytes, GreedyRange, FocusedSeq, Pass, Padded, Padding, Prefixed, Flag, Byte, Int16ul, Int32ul, Int64ul, Terminated
from dataclasses import dataclass
from functools import cached_property, partial

# Pylint complain about the missing names even in conditional import.
# pylint: disable=E0611
if construct.version < (2, 9, 0):
    from construct import Const, String

    def __enum_dict(enumtype):
        return dict((e.name, e.value) for e in enumtype)
    # here is a workaround to make Enum/FlagsEnum accept enum type, like construct 2.9
    def Enum(subcon, enumtype):
        return construct.Enum(subcon, default=Pass, **__enum_dict(enumtype))
    def FlagsEnum(subcon, enumtype):
        return construct.FlagsEnum(subcon, **__enum_dict(enumtype))

if construct.version >= (2, 9, 0):
    # https://github.com/construct/construct/blob/master/docs/transition29.rst
    # Pylint complain about the argument reodering
    # pylint: disable=E0102,W1114
    from construct import PaddedString as String
    from construct import Enum, FlagsEnum

    def Const(subcon, value):
        return construct.Const(value, subcon)

def CompleteRange(subcon):
    "like GreedyRange, but will report error if anything left in stream."
    return FocusedSeq("range",
            "range" / GreedyRange(subcon),
            Terminated
        )

def get_flags(flagsenum: Container) -> "list[str]":
    "Get flags for FlagsEnum container."
    return [name for (name, value) in flagsenum.items() if value is True and not name.startswith("_")]

class TplgType(enum.IntEnum):
    r"""File and Block header data types.

    `SND_SOC_TPLG_TYPE_`
    """
    MIXER = 1
    BYTES = 2
    ENUM = 3
    DAPM_GRAPH = 4
    DAPM_WIDGET = 5
    DAI_LINK = 6
    PCM = 7
    MANIFEST = 8
    CODEC_LINK = 9
    BACKEND_LINK = 10
    PDATA = 11
    DAI = 12

class VendorTupleType(enum.IntEnum):
    r"""vendor tuple types.

    `SND_SOC_TPLG_TUPLE_TYPE_`
    """
    UUID = 0
    STRING = 1
    BOOL = 2
    BYTE = 3
    WORD = 4
    SHORT = 5

class DaiFormat(enum.IntEnum):
    r"""DAI physical PCM data formats.

    `SND_SOC_DAI_FORMAT_`
    """
    I2S = 1
    RIGHT_J = 2
    LEFT_J = 3
    DSP_A = 4
    DSP_B = 5
    AC97 = 6
    PDM = 7

class DaiLnkFlag(enum.IntFlag):
    r"""DAI link flags.

    `SND_SOC_TPLG_LNK_FLGBIT_`
    """
    SYMMETRIC_RATES = 0b0001
    SYMMETRIC_CHANNELS = 0b0010
    SYMMETRIC_SAMPLEBITS = 0b0100
    VOICE_WAKEUP = 0b1000

class DaiMClk(enum.IntEnum):
    r"""DAI mclk_direction.

    `SND_SOC_TPLG_MCLK_`
    """
    CO = 0
    CI = 1

class DaiBClk(enum.IntEnum):
    r"""DAI topology BCLK parameter.

    `SND_SOC_TPLG_BCLK_`
    """
    CP = 0
    CC = 1

class DaiFSync(enum.IntEnum):
    r"""DAI topology FSYNC parameter.

    `SND_SOC_TPLG_FSYNC_`
    """
    CP = 0
    CC = 1

class DaiClockGate(enum.IntEnum):
    r"""DAI clock gating.

    `SND_SOC_TPLG_DAI_CLK_GATE_`
    """
    UNDEFINED = 0
    GATED = 1
    CONT = 2

class CtlTlvt(enum.IntEnum):
    "`SNDRV_CTL_TLVT_`"
    CONTAINER = 0
    DB_SCALE = 1
    DB_LINEAR = 2
    DB_RANGE = 3
    DB_MINMAX = 4
    DB_MINMAX_MUTE = 5

    CHMAP_FIXED = 0x101
    CHMAP_VAR = 0x102
    CHMAP_PAIRED = 0x103

class DapmType(enum.IntEnum):
    "`SND_SOC_TPLG_DAPM_`"
    INPUT = 0
    OUTPUT = 1
    MUX = 2
    MIXER = 3
    PGA = 4
    OUT_DRV = 5
    ADC = 6
    DAC = 7
    SWITCH = 8
    PRE = 9
    POST = 10
    AIF_IN = 11
    AIF_OUT = 12
    DAI_IN = 13
    DAI_OUT = 14
    DAI_LINK = 15
    BUFFER = 16
    SCHEDULER = 17
    EFFECT = 18
    SIGGEN = 19
    SRC = 20
    ASRC = 21
    ENCODER = 22
    DECODER = 23

class PcmFormatsFlag(enum.IntFlag):
    r"""PCM sample formats.

    `SND_PCM_FMTBIT_LINEAR` and `SND_PCM_FMTBIT_FLOAT`
    """
    S8 = 1 << 0
    U8 = 1 << 1
    S16_LE = 1 << 2
    S16_BE = 1 << 3
    U16_LE = 1 << 4
    U16_BE = 1 << 5
    S24_LE = 1 << 6
    S24_BE = 1 << 7
    U24_LE = 1 << 8
    U24_BE = 1 << 9
    S32_LE = 1 << 10
    S32_BE = 1 << 11
    U32_LE = 1 << 12
    U32_BE = 1 << 13

    FLOAT_LE = 1 << 14
    FLOAT_BE = 1 << 15

class SofVendorToken(enum.IntEnum):
    r"""SOF vendor tokens

    See `tools/topology1/sof/tokens.m4` in SOF.
    """
    # sof_buffer_tokens
    SOF_TKN_BUF_SIZE = 100
    SOF_TKN_BUF_CAPS = 101
    # sof_dai_tokens
    SOF_TKN_DAI_TYPE = 154
    SOF_TKN_DAI_INDEX = 155
    SOF_TKN_DAI_DIRECTION = 156
    # sof_sched_tokens
    SOF_TKN_SCHED_PERIOD = 200
    SOF_TKN_SCHED_PRIORITY = 201
    SOF_TKN_SCHED_MIPS = 202
    SOF_TKN_SCHED_CORE = 203
    SOF_TKN_SCHED_FRAMES = 204
    SOF_TKN_SCHED_TIME_DOMAIN = 205
    SOF_TKN_SCHED_DYNAMIC_PIPELINE = 206
    # sof_volume_tokens
    SOF_TKN_VOLUME_RAMP_STEP_TYPE = 250
    SOF_TKN_VOLUME_RAMP_STEP_MS = 251
    # sof_src_tokens
    SOF_TKN_SRC_RATE_IN = 300
    SOF_TKN_SRC_RATE_OUT = 301
    # sof_asrc_tokens
    SOF_TKN_ASRC_RATE_IN = 320
    SOF_TKN_ASRC_RATE_OUT = 321
    SOF_TKN_ASRC_ASYNCHRONOUS_MODE = 322
    SOF_TKN_ASRC_OPERATION_MODE = 323
    # sof_pcm_tokens
    SOF_TKN_PCM_DMAC_CONFIG = 353
    # sof_comp_tokens
    SOF_TKN_COMP_PERIOD_SINK_COUNT = 400
    SOF_TKN_COMP_PERIOD_SOURCE_COUNT = 401
    SOF_TKN_COMP_FORMAT = 402
    SOF_TKN_COMP_CORE_ID = 404
    SOF_TKN_COMP_UUID = 405
    SOF_TKN_COMP_CPC = 406
    # sof_ssp_tokens
    SOF_TKN_INTEL_SSP_CLKS_CONTROL = 500
    SOF_TKN_INTEL_SSP_MCLK_ID = 501
    SOF_TKN_INTEL_SSP_SAMPLE_BITS = 502
    SOF_TKN_INTEL_SSP_FRAME_PULSE_WIDTH = 503
    SOF_TKN_INTEL_SSP_QUIRKS = 504
    SOF_TKN_INTEL_SSP_TDM_PADDING_PER_SLOT = 505
    SOF_TKN_INTEL_SSP_BCLK_DELAY = 506
    # sof_dmic_tokens
    SOF_TKN_INTEL_DMIC_DRIVER_VERSION = 600
    SOF_TKN_INTEL_DMIC_CLK_MIN = 601
    SOF_TKN_INTEL_DMIC_CLK_MAX = 602
    SOF_TKN_INTEL_DMIC_DUTY_MIN = 603
    SOF_TKN_INTEL_DMIC_DUTY_MAX = 604
    SOF_TKN_INTEL_DMIC_NUM_PDM_ACTIVE = 605
    SOF_TKN_INTEL_DMIC_SAMPLE_RATE = 608
    SOF_TKN_INTEL_DMIC_FIFO_WORD_LENGTH = 609
    SOF_TKN_INTEL_DMIC_UNMUTE_RAMP_TIME_MS = 610
    # sof_dmic_pdm_tokens
    SOF_TKN_INTEL_DMIC_PDM_CTRL_ID = 700
    SOF_TKN_INTEL_DMIC_PDM_MIC_A_Enable = 701
    SOF_TKN_INTEL_DMIC_PDM_MIC_B_Enable = 702
    SOF_TKN_INTEL_DMIC_PDM_POLARITY_A = 703
    SOF_TKN_INTEL_DMIC_PDM_POLARITY_B = 704
    SOF_TKN_INTEL_DMIC_PDM_CLK_EDGE = 705
    SOF_TKN_INTEL_DMIC_PDM_SKEW = 706
    # sof_tone_tokens
    SOF_TKN_TONE_SAMPLE_RATE = 800
    # sof_process_tokens
    SOF_TKN_PROCESS_TYPE = 900
    # sof_sai_tokens
    SOF_TKN_IMX_SAI_MCLK_ID = 1000
    # sof_esai_tokens
    SOF_TKN_IMX_ESAI_MCLK_ID = 1100
    # sof_stream_tokens
    SOF_TKN_STREAM_PLAYBACK_COMPATIBLE_D0I3 = 1200
    SOF_TKN_STREAM_CAPTURE_COMPATIBLE_D0I3 = 1201
    # sof_led_tokens
    SOF_TKN_MUTE_LED_USE = 1300
    SOF_TKN_MUTE_LED_DIRECTION = 1301
    # sof_alh_tokens
    SOF_TKN_INTEL_ALH_RATE = 1400
    SOF_TKN_INTEL_ALH_CH = 1401
    # sof_hda_tokens
    SOF_TKN_INTEL_HDA_RATE = 1500
    SOF_TKN_INTEL_HDA_CH = 1501
    # sof_afe_tokens
    SOF_TKN_MEDIATEK_AFE_RATE = 1600
    SOF_TKN_MEDIATEK_AFE_CH = 1601
    SOF_TKN_MEDIATEK_AFE_FORMAT = 1602

# Pylint complain about too many instance attributes, but they are necessary here.
# pylint: disable=R0902
class TplgBinaryFormat:
    r"""Topology binary format description.

    To parse and build topology binary data.
    """

    _TPLG_MAGIC = b'CoSA'
    _ABI_HEADER = Struct(
        "magic" / Const(Bytes(len(_TPLG_MAGIC)), _TPLG_MAGIC),
        "abi" / Int32ul,
    )

    @staticmethod
    def parse_abi_version(filepath) -> int:
        "Recognize the ABI version for TPLG file."
        with open(os.fspath(filepath), "rb") as fs:
            return TplgBinaryFormat._ABI_HEADER.parse_stream(fs)["abi"]

    def __init__(self):
        "Initialize the topology binary format."
        self._abi = 5 # SND_SOC_TPLG_ABI_VERSION
        self._max_channel = 8 # SND_SOC_TPLG_MAX_CHAN
        self._max_formats = 16 # SND_SOC_TPLG_MAX_FORMATS
        self._stream_config_max = 8 # SND_SOC_TPLG_STREAM_CONFIG_MAX
        self._hw_config_max = 8 # SND_SOC_TPLG_HW_CONFIG_MAX
        self._tlv_size = 32 # SND_SOC_TPLG_TLV_SIZE
        self._id_name_maxlen = 44 # SNDRV_CTL_ELEM_ID_NAME_MAXLEN
        self._num_texts = 16 # SND_SOC_TPLG_NUM_TEXTS

        self._block_header = Struct( # snd_soc_tplg_hdr
            "magic" / Const(Bytes(len(self._TPLG_MAGIC)), self._TPLG_MAGIC),
            "abi" / Const(Int32ul, self._abi),
            "version" / Int32ul,
            "type" / Enum(Int32ul, TplgType),
            "size" / Const(Int32ul, 4 * 9),
            "vendor_type" / Int32ul,
            "payload_size" / Int32ul,
            "index" / Int32ul,
            "count" / Int32ul,
        )
        self._vendor_uuid_elem = Struct( # snd_soc_tplg_vendor_uuid_elem
            "token" / Enum(Int32ul, SofVendorToken),
            "uuid" / Bytes(16),
        )
        self._vendor_value_elem = Struct( # snd_soc_tplg_vendor_value_elem
            "token" / Enum(Int32ul, SofVendorToken),
            "value" / Int32ul,
        )
        self._vendor_string_elem = Struct( # snd_soc_tplg_vendor_string_elem
            "token" / Enum(Int32ul, SofVendorToken),
            "string" / String(self._id_name_maxlen, "ascii")
        )
        self._vendor_elem_cases = {
            VendorTupleType.UUID.name: self._vendor_uuid_elem,
            VendorTupleType.STRING.name: self._vendor_string_elem,
            VendorTupleType.BOOL.name: self._vendor_value_elem,
            VendorTupleType.BYTE.name: self._vendor_value_elem,
            VendorTupleType.WORD.name: self._vendor_value_elem,
            VendorTupleType.SHORT.name: self._vendor_value_elem,
        }
        self._vendor_array = Struct( # snd_soc_tplg_vendor_array
            "size" / Int32ul, # size in bytes of the array, including all elements
            "type" / Enum(Int32ul, VendorTupleType),
            "num_elems" / Int32ul, # number of elements in array
            "elems" / Array(this.num_elems, Switch(this.type, self._vendor_elem_cases, default=construct.Error)),
        )
        # expand the union of snd_soc_tplg_private for different sections:
        self._private_raw = Prefixed(
            Int32ul, # size
            GreedyBytes, # data
        )
        # currently, only dapm_widget uses vendor array
        self._private_vendor_array = Prefixed(
            Int32ul, # size
            CompleteRange(self._vendor_array), # array
        )
        self._tlv_dbscale = Struct( # snd_soc_tplg_tlv_dbscale
            "min" / Int32ul,
            "step" / Int32ul,
            "mute" / Int32ul,
        )
        self._ctl_tlv = Struct( # snd_soc_tplg_ctl_tlv
            "size" / Int32ul,
            "type" / Enum(Int32ul, CtlTlvt),
            "scale" / Padded(4 * self._tlv_size, self._tlv_dbscale)
        )
        self._channel = Struct( # snd_soc_tplg_channel
            "size" / Int32ul,
            "reg" / Int32ul,
            "shift" / Int32ul,
            "id" / Int32ul,
        )
        self._io_ops = Struct( # snd_soc_tplg_io_ops
            "get" / Int32ul,
            "put" / Int32ul,
            "info" / Int32ul,
        )
        self._kcontrol_hdr = Struct( # snd_soc_tplg_ctl_hdr
            "size" / Int32ul,
            "type" / Enum(Int32ul, TplgType),
            "name" / String(self._id_name_maxlen, "ascii"),
            "access" / Int32ul,
            "ops" / self._io_ops,
            "tlv" / self._ctl_tlv,
        )
        self._stream_caps = Struct( # snd_soc_tplg_stream_caps
            "size" / Int32ul,
            "name" / String(self._id_name_maxlen, "ascii"),
            "formats" / FlagsEnum(Int64ul, PcmFormatsFlag),
            "rates" / Int32ul, # SNDRV_PCM_RATE_ ?
            "rate_min" / Int32ul,
            "rate_max" / Int32ul,
            "channels_min" / Int32ul,
            "channels_max" / Int32ul,
            "periods_min" / Int32ul,
            "periods_max" / Int32ul,
            "period_size_min" / Int32ul,
            "period_size_max" / Int32ul,
            "buffer_size_min" / Int32ul,
            "buffer_size_max" / Int32ul,
            "sig_bits" / Int32ul,
        )
        self._stream = Struct( # snd_soc_tplg_stream
            "size" / Int32ul,
            "name" / String(self._id_name_maxlen, "ascii"),
            "format" / FlagsEnum(Int64ul, PcmFormatsFlag),
            "rate" / Int32ul,
            "period_bytes" / Int32ul,
            "buffer_bytes" / Int32ul,
            "channels" / Int32ul,
        )
        self._hw_config = Struct( # snd_soc_tplg_hw_config
            "size" / Int32ul,
            "id" / Int32ul,
            "fmt" / Enum(Int32ul, DaiFormat),
            "clock_gated" / Enum(Byte, DaiClockGate),
            "invert_bclk" / Flag,
            "invert_fsync" / Flag,
            "bclk_provider" / Enum(Byte, DaiBClk),
            "fsync_provider" / Enum(Byte, DaiFSync),
            "mclk_direction" / Enum(Byte, DaiMClk),
            Padding(2), # reserved
            "mclk_rate" / Int32ul,
            "bclk_rate" / Int32ul,
            "fsync_rate" / Int32ul,
            "tdm_slots" / Int32ul,
            "tdm_slot_width" / Int32ul,
            "tx_slots" / Int32ul,
            "rx_slots" / Int32ul,
            "tx_channels" / Int32ul,
            "tx_chanmap" / Array(self._max_channel, Int32ul),
            "rx_channels" / Int32ul,
            "rx_chanmap" / Array(self._max_channel, Int32ul),
        )
        self._manifest = Struct( # snd_soc_tplg_manifest
            "size" / Int32ul,
            "control_elems" / Int32ul,
            "widget_elems" / Int32ul,
            "graph_elems" / Int32ul,
            "pcm_elems" / Int32ul,
            "dai_link_elems" / Int32ul,
            "dai_elems" / Int32ul,
            Padding(4 * 20), # reserved
            "priv" / self._private_raw,
        )
        self._mixer_control_body = Struct( # `snd_soc_tplg_mixer_control` without `hdr`
            "size" / Int32ul,
            "min" / Int32ul,
            "max" / Int32ul,
            "platform_max" / Int32ul,
            "invert" / Int32ul,
            "num_channels" / Int32ul,
            "channel" / Array(self._max_channel, self._channel),
            "priv" / self._private_raw,
        )
        self._enum_control_body = Struct( # `snd_soc_tplg_enum_control` without `hdr`
            "size" / Int32ul,
            "num_channels" / Int32ul,
            "channel" / Array(self._max_channel, self._channel),
            "items" / Int32ul,
            "mask" / Int32ul,
            "count" / Int32ul,
            "texts" / Array(self._num_texts, String(self._id_name_maxlen, "ascii")),
            "values" / Array(self._num_texts * self._id_name_maxlen / 4, Int32ul),
            "priv" / self._private_raw,
        )
        self._bytes_control_body = Struct( # `snd_soc_tplg_bytes_control` without `hdr`
            "size" / Int32ul,
            "max" / Int32ul,
            "mask" / Int32ul,
            "base" / Int32ul,
            "num_regs" / Int32ul,
            "ext_ops" / self._io_ops,
            "priv" / self._private_raw,
        )
        self._kcontrol_cases = {
            TplgType.MIXER.name: self._mixer_control_body,
            TplgType.ENUM.name: self._enum_control_body,
            TplgType.BYTES.name: self._bytes_control_body,
        }
        self._kcontrol_wrapper = Struct( # wrapper for kcontrol types, divide header and body
            "hdr" / self._kcontrol_hdr,
            "body" / Switch(
                this.hdr.type,
                self._kcontrol_cases,
            ),
        )
        self._dapm_graph_elem = Struct( # snd_soc_tplg_dapm_graph_elem
            "sink" / String(self._id_name_maxlen, "ascii"),
            "control" / String(self._id_name_maxlen, "ascii"),
            "source" / String(self._id_name_maxlen, "ascii"),
        )
        self._dapm_widget = Struct( # snd_soc_tplg_dapm_widget
            "size" / Int32ul,
            "id" / Enum(Int32ul, DapmType),
            "name" / String(self._id_name_maxlen, "ascii"),
            "sname" / String(self._id_name_maxlen, "ascii"),
            "reg" / Int32ul,
            "shift" / Int32ul,
            "mask" / Int32ul,
            "subseq" / Int32ul,
            "invert" / Int32ul,
            "ignore_suspend" / Int32ul,
            "event_flags" / Int16ul,
            "event_type" / Int16ul,
            "num_kcontrols" / Int32ul,
            "priv" / self._private_vendor_array,
        )
        self._dapm_widget_with_kcontrols = Struct(
            "widget" / self._dapm_widget,
            "kcontrols" / Array(this.widget.num_kcontrols, self._kcontrol_wrapper),
        )
        self._pcm = Struct( # snd_soc_tplg_pcm
            "size" / Int32ul,
            "pcm_name" / String(self._id_name_maxlen, "ascii"),
            "dai_name" / String(self._id_name_maxlen, "ascii"),
            "pcm_id" / Int32ul,
            "dai_id" / Int32ul,
            "playback" / Int32ul,
            "capture" / Int32ul,
            "compress" / Int32ul,
            "stream" / Array(self._stream_config_max, self._stream),
            "num_streams" / Int32ul,
            "caps" / Array(2, self._stream_caps),
            "flag_mask" / Int32ul,
            "flags" / FlagsEnum(Int32ul, DaiLnkFlag),
            "priv" / self._private_raw,
        )
        self._link_config = Struct( # snd_soc_tplg_link_config
            "size" / Int32ul,
            "id" / Int32ul,
            "name" / String(self._id_name_maxlen, "ascii"),
            "stream_name" / String(self._id_name_maxlen, "ascii"),
            "stream" / Array(self._stream_config_max, self._stream),
            "num_streams" / Int32ul,
            "hw_config" / Array(self._hw_config_max, self._hw_config),
            "num_hw_configs" / Int32ul,
            "default_hw_config_id" / Int32ul,
            "flag_mask" / Int32ul,
            "flags" / FlagsEnum(Int32ul, DaiLnkFlag),
            "priv" / self._private_raw,
        )
        self._section_blocks_cases = {
            TplgType.MANIFEST.name: self._manifest,
            TplgType.MIXER.name: self._kcontrol_wrapper,
            TplgType.ENUM.name: self._kcontrol_wrapper,
            TplgType.BYTES.name: self._kcontrol_wrapper,
            TplgType.DAPM_GRAPH.name: self._dapm_graph_elem,
            TplgType.DAPM_WIDGET.name: self._dapm_widget_with_kcontrols,
            TplgType.PCM.name: self._pcm,
            TplgType.CODEC_LINK.name: self._link_config,
            TplgType.BACKEND_LINK.name: self._link_config,
        }
        _section_blocks_cases = dict((k, Array(this.header.count, v)) for (k, v) in self._section_blocks_cases.items())
        self._section = Struct(
            "header" / self._block_header,
            "blocks" / Switch(
                this.header.type,
                _section_blocks_cases,
                default = Padding(this.header.payload_size)  # skip unknown blocks,
            ),
        )
        self.sections = CompleteRange(self._section)

    def parse_file(self, filepath) -> ListContainer:
        "Parse the TPLG binary file to raw structure."
        with open(os.fspath(filepath), "rb") as fs:
            return self.sections.parse_stream(fs)

    def build(self, data: ListContainer) -> bytes:
        "Build the topology data to byte array."
        return self.sections.build(data)

@dataclass(init=False)
class GroupedTplg:
    "Grouped topology data."

    manifest: Container
    "Manifest info."
    pcm_list: "list[Container]"
    "PCM data list."
    widget_list: "list[Container]"
    "DAPM widgets list."
    graph_list: "list[Container]"
    "DAPM graph elements list."
    link_list: "list[Container]"
    "DAI/backend links list."
    pipeline_widgets: "list[Container]"
    "Pipeline widgets list."

    def __init__(self, raw_parsed_tplg: ListContainer):
        "Group topology blocks by their types."
        self.pcm_list = []
        self.widget_list = []
        self.graph_list = []
        self.link_list = []
        self.pipeline_widgets = []
        for item in raw_parsed_tplg:
            tplgtype = item["header"]["type"]
            blocks: ListContainer = item["blocks"]
            if tplgtype == TplgType.PCM.name:
                self.pcm_list.extend(sorted(blocks, key=lambda pcm: pcm["pcm_id"]))
            elif tplgtype == TplgType.DAPM_WIDGET.name:
                self.widget_list.extend(blocks)
                self.pipeline_widgets.extend(block for block in blocks if block["widget"]["name"].startswith("PIPELINE."))
            elif tplgtype == TplgType.DAPM_GRAPH.name:
                self.graph_list.extend(blocks)
            elif tplgtype == TplgType.MANIFEST.name:
                assert item["header"]["count"] == 1, "Manifest should only contains one block."
                self.manifest = blocks[0]
            elif tplgtype in [TplgType.DAI_LINK.name, TplgType.BACKEND_LINK.name]:
                self.link_list.extend(sorted(blocks, key=lambda link: link["id"]))

    __pipeline_widget_name_re = re.compile("PIPELINE.(\\d+)", re.RegexFlag.ASCII)
    @staticmethod
    def __get_pipeline_id_for_pipeline_widget(name: str):
        "Get pipeline id for pipeline widget, like 2 of `PIPELINE.2.SSP0.OUT`."
        return GroupedTplg.__pipeline_widget_name_re.match(name).group(1)

    __widget_name_re = re.compile("([A-Za-z_ ]+)(\\d+)\\.(\\d+)", re.RegexFlag.ASCII)
    @staticmethod
    def get_pipeline_id_by_name(name: str):
        r"""Get pipeline id by widget name.

        NOTE
        ----
        The widget name should match pattern like: "<prefix><pipeline>.<index>", otherwise it return None. e.g.

        - BUF1.0 -> 1
        - PGA2.1 -> 2
        - EQIIR10.2 -> 10
        - PCM0P -> None
        - SSP0.OUT -> None
        - Dmic0 -> None
        - ECHO REF 7 -> None
        - PIPELINE.1.SSP1.OUT -> None
        """
        match = GroupedTplg.__widget_name_re.match(name)
        if match is None:
            return None
        return match.group(2)

    @staticmethod
    def get_pcm_fmt(pcm: Container) -> "list[list[str]]":
        r"""Get PCM format.

        Returns
        -------
        a list of formats lists:
        - [0]: playback stream formats
        - [1]: capture stream formats
        """
        return [get_flags(cap["formats"]) for cap in pcm["caps"]]

    @staticmethod
    def get_pcm_type(pcm: Container):
        if pcm["playback"] == 1 and pcm["capture"] == 1:
            return "duplex"
        if pcm["playback"] == 1:
            return "playback"
        if pcm["capture"] == 1:
            return "capture"
        return "None"

    @staticmethod
    def is_virtual_widget(widget: Container):
        "Whether it is a virtual widget depends on its DAPM type."
        return widget["widget"]["id"] in [DapmType.INPUT.name, DapmType.OUTPUT.name, DapmType.OUT_DRV.name]

    @staticmethod
    def get_priv_element(comp: Container, token: SofVendorToken, default = None):
        "Get private element with specific token."
        try:
            return next(
                elem["value"]
                for vendor_array in comp["priv"]
                for elem in vendor_array["elems"]
                if elem["token"] == token.name
            )
        except (KeyError, AttributeError, StopIteration):
            return default

    @staticmethod
    def get_widget_token_value(widget: Container, token: SofVendorToken, default = None):
        "Get the value for specified token"
        return GroupedTplg.get_priv_element(widget["widget"], token, default)

    @staticmethod
    def get_widget_uuid(widget: Container, default = None):
        "Get widget UUID."
        try:
            return next(
                elem["uuid"]
                for vendor_array in widget["widget"]["priv"]
                for elem in vendor_array["elems"]
                if elem["token"] == SofVendorToken.SOF_TKN_COMP_UUID.name
            )
        except (KeyError, AttributeError, StopIteration):
            return default

    def is_dynamic_pipeline(self, pipeline_id: str):
        "Check if the pipeline is a dynamic pipeline."
        widget = next(
            widget["widget"]
            for widget in self.pipeline_widgets
            if self.__get_pipeline_id_for_pipeline_widget(widget["widget"]["name"]) == pipeline_id
        )
        return bool(GroupedTplg.get_priv_element(widget, SofVendorToken.SOF_TKN_SCHED_DYNAMIC_PIPELINE, default=0))

    def print_pcm_info(self):
        r"""Print pcm info, like::

        pcm=Speaker;id=2;type=playback;rate_min=48000;rate_max=48000;ch_min=2;ch_max=2;fmts=S16_LE S32_LE
        """
        for pcm in self.pcm_list:
            name = pcm["pcm_name"]
            pcm_id = pcm["pcm_id"]
            pcm_type = self.get_pcm_type(pcm)
            fmt_list = self.get_pcm_fmt(pcm)
            cap_index = int(pcm_type == "capture") # 1 for capture, 0 for playback
            cap = pcm["caps"][cap_index]
            fmts = ' '.join(fmt_list[cap_index])
            rate_min = cap["rate_min"]
            rate_max = cap["rate_max"]
            ch_min = cap["channels_min"]
            ch_max = cap["channels_max"]
            print(f"pcm={name};id={pcm_id};type={pcm_type};"
            f"rate_min={rate_min};rate_max={rate_max};ch_min={ch_min};ch_max={ch_max};"
            f"fmts={fmts}")

    @cached_property
    def coreids(self):
        "All available core IDs."
        cores = set()
        for widget in self.widget_list:
            core = self.get_widget_token_value(widget, SofVendorToken.SOF_TKN_COMP_CORE_ID)
            if core is None:
                cores.add(-1) # placeholder for the lack of core ID
            else:
                cores.add(core)
        return cores

    @cached_property
    def has_core_differences(self):
        "Check whether this topology uses more than one coreID"
        return len(self.coreids) > 1

class TplgGraph:
    "Topology components graph for drawing and searching components through pipelines."
    # In graph, every node is corresponding to its identifier name,
    # this name is same as the sink/source in dapm_graph_elem.
    # The edges of graph is a dictionary like:
    # {sourceA: [sinkA1, sinkA2, ...], sourceB: [sinkB1, ...], ...}
    # Here we both build forward and backward edges for convenience.

    @staticmethod
    def _build_nodes_dict(widget_list: "list[Container]") -> "dict[str, Container]":
        r"Create a dictionary of all the widgets in widget_list, keyed by their name/sname."
        nodes = {}
        for widget in widget_list:
            nodes[widget["widget"]["name"]] = widget
            sname = widget["widget"]["sname"]
            if sname: # skip empty sname
                nodes.setdefault(sname, widget) # stream name has lower priority than identical name
        return nodes

    @staticmethod
    def _build_nodes_names_in_graph(graph_list: "list[Container]", nodes_dict: "dict[str, Container]") -> "dict[str, str]":
        r"""Create a dictionary from node name/sname to identifier graph name.

        Only contains the name/sname key which is different from its identifier name.
        """
        names = {}
        for edge in graph_list:
            for ename in [edge["source"], edge["sink"]]:
                node = nodes_dict[ename]
                for name in [node["widget"]["name"], node["widget"]["sname"]]:
                    if name != ename:
                        names[name] = ename
        return names

    @staticmethod
    def _build_edges(graph_list: "list[Container]") -> "tuple[dict[str, list[str]], dict[str, list[str]]]":
        r"""Build forward and backward edges.

        Return
        ------
        forward_edges : `dict[str, list[str]`
            like `{sourceA: [sinkA1, sinkA2, ...], sourceB: [sinkB1, ...], ...}`
        backward_edges : `dict[str, list[str]`
            like `{sinkA: [sourceA1, sourceA2, ...], sinkB: [sourceB1, ...], ...}`
        """
        forward_edge = defaultdict(list)
        backward_edge = defaultdict(list)
        for edge in graph_list:
            forward_edge[edge["source"]].append(edge["sink"])
            backward_edge[edge["sink"]].append(edge["source"])
        return forward_edge, backward_edge

    @staticmethod
    def _build_leaves(node_names: "list[str]", forward_edges: "dict[str, list[str]]", backward_edges: "dict[str, list[str]]") -> "tuple[set[str], set[str], set[str]]":
        r"""Build leaves.

        Returns
        -------
        isolated : `set[str]`
            All isolated nodes (neither incoming edge nor outgoing edge).
        heads : `set[str]`
            All head nodes (incoming edges only).
        tails : `set[str]`
            All tail nodes (outgoing edges only).
        """
        isolated = set()
        heads = set()
        tails = set()
        for node in node_names:
            if forward_edges[node] == [] == backward_edges[node]:
                isolated.add(node)
            elif forward_edges[node] == []:
                heads.add(node)
            elif backward_edges[node] == []:
                tails.add(node)
        return isolated, heads, tails

    def __init__(self, grouped_tplg: GroupedTplg):
        "Build graph from grouped topology data."
        self.errors = 0 # non fatal errors
        self.show_core = 'auto'
        self.without_nodeinfo = False
        self._tplg = grouped_tplg
        self._nodes_dict = TplgGraph._build_nodes_dict(grouped_tplg.widget_list)
        self._nodes_names_in_graph = TplgGraph._build_nodes_names_in_graph(grouped_tplg.graph_list, self._nodes_dict)
        self._forward_edges, self._backward_edges = TplgGraph._build_edges(grouped_tplg.graph_list)
        self._isolated, self._heads, self._tails = TplgGraph._build_leaves(map(self.node_name_in_graph, grouped_tplg.widget_list), self._forward_edges, self._backward_edges)

    def _node_name_in_graph_from_name(self, name: str) -> str:
        r"""Return the node name in graph.

        NOTE: if the node is not in graph, return the origin name.
        """
        if name in self._nodes_names_in_graph:
            return self._nodes_names_in_graph[name]
        return name

    def node_name_in_graph(self, node: Container) -> str:
        r"""Return the node name in graph.

        NOTE: if the node is not in graph, return the its "name".
        """
        return self._node_name_in_graph_from_name(node["widget"]["name"])

    # pylint: disable=R0201
    def node_sublabel(self, widget: Container) -> str:
        if widget["widget"]["id"] == 'PGA':
            sublabel = f'<BR ALIGN="CENTER"/><SUB>PGA: {widget["kcontrols"][0]["hdr"]["name"]}</SUB>'
        elif widget["widget"]["id"] in ['AIF_IN' , 'AIF_OUT' , 'DAI_IN' , 'DAI_OUT']:
            sublabel = f'<BR ALIGN="CENTER"/><SUB>{widget["widget"]["id"]}: {widget["widget"]["sname"]}</SUB>'
        else:
            sublabel = ""
        return sublabel

    PCM_NUM_REGEX = re.compile(r"PCM(?P<num>\d+)", re.IGNORECASE)
    HOST_COPIER_NUM_REGEX = re.compile(r"host-copier\.(?P<num>\d+)", re.IGNORECASE)
    def pcm_name(self, widget: Container):
        """The widget argument is expected to be a `PCMnnnX` or `host-copier.nnn.X` where nnn is
        a pcm_id.  Find in self._tplg.pcm_list the corresponding PCM and return its pcm_name.
        The kernel performs some similar PCM ID match but in a more complicated way, see
        spcm_bind() as a starting point
        https://github.com/thesofproject/linux/blob/2776754a4cd984a3/sound/soc/sof/topology.c#L1148

        """
        wname = widget.name

        match = self.HOST_COPIER_NUM_REGEX.match(wname)
        if match is None:
            match = self.PCM_NUM_REGEX.match(wname)

        # This function is not supposed to be passed random arguments
        missing_number_errmsg = f'No PCM or host-copier number found in widget name="{wname}"'
        assert not match is None, missing_number_errmsg

        pcm_id = int(match["num"])
        pcm_names = [ pcm.pcm_name for pcm in self._tplg.pcm_list if pcm.pcm_id == pcm_id ]

        # Some topologies are broken, see ID fix
        # https://github.com/thesofproject/sof/commit/75e8f4b63c168fb
        # and others in
        # https://github.com/thesofproject/sof-test/pull/1054
        n_l = len(pcm_names)

        multiple_id_errmsg = f"Multiple pcm id={pcm_id}: {n_l} ({pcm_names})"
        missing_id_errmsg = f"No pcm id={pcm_id} for widget={wname}"

        if 1 < n_l:
            self.errors += 1
            print("ERROR: " + multiple_id_errmsg)
            return multiple_id_errmsg

        if n_l < 1:
            self.errors += 1
            print("ERROR: " + missing_id_errmsg)
            return missing_id_errmsg

        return pcm_names[0]

    def _display_node_attrs(self, name: str, widget: Container):
        sublabel = ""
        sublabel2 = ""
        attr = {}
        if not self.without_nodeinfo:
            sublabel = self.node_sublabel(widget)
        core = GroupedTplg.get_widget_token_value(widget, SofVendorToken.SOF_TKN_COMP_CORE_ID)
        if core is not None:
            if self.show_core == 'always' or (
                self.show_core == 'auto' and self._tplg.has_core_differences
            ):
                sublabel2 += f'<BR ALIGN="CENTER"/><SUB>core:{core}</SUB>'
        comp_cpc = GroupedTplg.get_widget_token_value(widget, SofVendorToken.SOF_TKN_COMP_CPC)
        if comp_cpc is not None:
            sublabel2 += f'<BR ALIGN="CENTER"/><SUB>cpc:{comp_cpc}</SUB>'
        display_name = name
        wname = widget.widget.name
        # See the *_NUM_REGEX above
        if wname.startswith("PCM") or wname.startswith("host-copier."):
            display_name += f" ({self.pcm_name(widget.widget)})"
        attr['label'] = f'<{display_name}{sublabel}{sublabel2}>'
        pipelines = self.get_pipelines_id(name)
        if any(map(self._tplg.is_dynamic_pipeline, pipelines)):
            attr['style'] = "dashed"
            attr['color'] = 'orange'
        if GroupedTplg.is_virtual_widget(widget):
            attr['style'] = "dotted"
            attr['color'] = 'blue'
        return attr

    def _display_edge_attr(self, edge: Container):
        attr = {}
        if GroupedTplg.is_virtual_widget(self._nodes_dict[edge["source"]])\
            or GroupedTplg.is_virtual_widget(self._nodes_dict[edge["sink"]]):
            attr['style'] = "dotted"
            attr['color'] = 'blue'
        return attr

    def draw(self, outfile: str, outdir: str = '.', file_format: str = "png", live_view: bool = False):
        r"""Draw graph and write it to file.

        Parameters
        ----------
        outfile : `str`
            output file name without extension.
        outdir : `str`, optional
            output directory.
        file_format : `str`, optional
            output file format (extension).
        live_view : `bool`, optional
            generate and view topology graph.
            If true, the output directory will be a temporary directory.

        Returns
        -------
        the path of rendered file or `None` if no output file generated.
        """
        from graphviz import Digraph
        from tempfile import gettempdir

        graph = Digraph("Topology Graph", format=file_format)
        for node in self._tplg.widget_list:
            name = self.node_name_in_graph(node)
            if name not in self._isolated: # skip isolated nodes.
                graph.node(name, **self._display_node_attrs(name, node))
        for edge in self._tplg.graph_list:
            graph.edge(edge["source"], edge["sink"], **self._display_edge_attr(edge))
        if live_view:
            # if run the tool over ssh, live view feature will be disabled
            if 'DISPLAY' not in os.environ.keys():
                print("No available GUI over ssh, unable to view the graph", file=sys.stderr)
            else:
                return graph.view(filename=outfile, directory=gettempdir(), cleanup=True)
        else:
            return graph.render(filename=outfile, directory=outdir, cleanup=True)
        return None

    __prefix_re = re.compile('[A-Za-z_]+')
    @staticmethod
    def get_comp_prefix(name: str) -> str:
        r"""Get component prefix. e.g.

        - PCM0C -> PCM
        - SSP0.IN -> SSP
        - ALH0x102 -> ALH
        - SMART_AMP1.0 -> SMART_AMP
        - ECHO REF 5 -> ECHO
        """
        return TplgGraph.__prefix_re.match(name).group()

    @staticmethod
    def _prefix_eq(name1: str, name2: str) -> bool:
        "Return true if the components have same prefix."
        return TplgGraph.get_comp_prefix(name1) == TplgGraph.get_comp_prefix(name2)

    def get_pipelines_id(self, node_name: str):
        r"""Get pipelines id by name and connection.

        NOTE
        ----
        This is different from `GroupedTplg.get_pipeline_id_by_name`.
        Because `TplgGraph` involves connection informations,
        We can find connected widgets if the current widget name doesn't contain pipeline id.
        Some of components like dai may involve multiple pipelines.
        """
        pipelines = set()
        pipeline = GroupedTplg.get_pipeline_id_by_name(node_name)
        if pipeline is not None:
            # 1. prefer current node.
            pipelines.add(pipeline)
        else:
            TplgGraph._get_pipelines_id_recursively(self._forward_edges, node_name, pipelines)
            TplgGraph._get_pipelines_id_recursively(self._backward_edges, node_name, pipelines)
        return pipelines

    @staticmethod
    def _get_pipelines_id_recursively(edges: "dict[str, list[str]]", node_name: str, pipelines: set):
        "Used by `get_pipeline_id`."
        next_candidates = edges[node_name]
         # 2. prefer the direction where there is exactly one connected node.
        if len(pipelines) == 1:
            return
        if len(pipelines) > 1 and len(next_candidates) == 1:
            pipelines.clear()
        # 3. prefer neighbor.
        for next_node_name in next_candidates:
            pipeline = GroupedTplg.get_pipeline_id_by_name(next_node_name)
            if pipeline is not None:
                pipelines.add(pipeline)
        if not pipelines:
            # 4. try recursive (deeper).
            for next_node_name in next_candidates:
                TplgGraph._get_pipelines_id_recursively(edges, next_node_name, pipelines)

    @staticmethod
    def _find_connected_node_recursively(edges: "dict[str, list[str]]", node_name: str, name_predicate, acc: "set[str]"):
        r"""Used by `_find_connected_comp`.

        Parameters
        ----------
        edges : `dict[str, list[str]]`
            graph edges.
        node_name : `str`
            start point for searching.
        name_predicate : `(str)->bool`
            predicate function which will apply to node names.
        acc : `set[str]`
            accumulator to collect found node_name(s).
        """
        if name_predicate(node_name) is True:
            acc.add(node_name)
        for next_node_name in edges[node_name]:
            TplgGraph._find_connected_node_recursively(edges, next_node_name, name_predicate, acc)

    def _find_connected_comp(self, node_name: str, name_predicate) -> "list[Container]":
        r"""Find specified components connected to `node_name`.

        Parameters
        ----------
        node_name : `str`
            reference node name.
        name_predicate : `(str)->bool`
            predicate function which will apply to node names.

        Returns
        -------
        list of found components.
        """
        acc = set()
        self._find_connected_node_recursively(self._forward_edges, node_name, name_predicate, acc)
        self._find_connected_node_recursively(self._backward_edges, node_name, name_predicate, acc)
        return [self._nodes_dict[name] for name in acc]

    def find_connected_comp(self, ref_node: Container, predicate) -> "list[Container]":
        r"""Find specified components connected to `ref_node`.

        Parameters
        ----------
        ref_node : `contruct.Container`
            reference node
        predicate : `(contruct.Container)->bool`
            predicate function which will apply to nodes

        Returns
        -------
        list of found components.

        NOTE
        ----
        Since this method is usually used to search components through a pipeline,
        it start searching forward and backward from `ref_node`,
        but keep the direction for any other nodes.
        Therefore the indirect branch can't be found, for example::

            +---+    +---+    +---+
            | A +--->| B +--->| C |
            +---+    +-+-+    +---+
                       |
                       v
            +---+    +---+    +---+
            | D +--->| E +--->| F |
            +---+    +---+    +---+

        As shown above,
        if `ref_node` is B and `predicate` always true, [A, B, C, E, F] will be found;
        if `ref_node` is E and `predicate` always true, [A, B, D, E, F] will be found;
        if `ref_node` is C and `predicate` always true, only [A, B, C] will be found.
        """
        return self._find_connected_comp(
            self.node_name_in_graph(ref_node),
            lambda name: predicate(self._nodes_dict[name]))

    def find_comp_for_pcm(self, pcm: Container, prefix: str) -> "list[list[Container]]":
        r"""Find specified components for PCM.

        Parameters
        ----------
        pcm : `contruct.Container`
            PCM data.
        prefix : `str`
            the name prefix for specified components.

        Returns
        -------
        a list with two elements:
        - [0]: specified components connected to playback
        - [1]: specified components connected to capture
        """
        prefix = prefix.upper()
        return [
            self._find_connected_comp(
                self._node_name_in_graph_from_name(cap["name"]),
                lambda name: name.startswith(prefix))
            for cap in pcm["caps"]
            ]

    def find_interweaved_pipelines(self) -> "list[tuple[Container, list[Container]]]":
        r"""Find all interweaved pipelines.

        Returns
        -------
        a list of intereaved pipelines. Each element is a tuple related to the pipeline:
        component : `contruct.Container`
            interweaved component, like SMART_AMP or ECHO REF
        pcms : `list[contruct.Container]`
            the PCM components for the intereaved pipeline

        NOTE
        ----
        If there is one/more link between two pipelines, these two pipeline are interweaved, for example::

            +-------+                                                                   +---------+
            | PCM0P |                                                                   | SSP2.IN |
            +---+---+                                                                   +----+----+
                |                                                                            |
                v                                                                            v
            +--------+                                                                   +--------+
            | BUF1.0 |                                                                   | BUF6.1 |
            +---+----+                                                                   +---+----+
                |                                                                            |
                v                                                                            v
            +--------+                                          +-------+         +---------------+
            | PGA1.1 |                                          | PCM2P |         |  MUXDEMUX6.0  |
            +---+----+                                          +---+---+         +-+--------+----+
                |                                                   |               |        |
                v                                                   v               v        v
            +--------+                        +---------+       +--------+   +--------+  +--------+
            | BUF1.1 |                    +---+ SSP0.IN +--+    | BUF5.0 |   | BUF5.2 |  | BUF6.0 |
            +---+----+                    |   +---------+  |    +----+---+   +---+----+  +---+----+
                |                         |                |         |           |           |
                v                         v                v         v           v           v
            +---------------+    +--------------+     +--------+   +----------------+     +-------+
            |  MUXDEMUX1.0  |    |  ECHO REF 7  |     | BUF2.1 |   |  SMART_AMP5.0  |     | PCM2C |
            +---+-------+---+    +--------+-----+     +----+---+   +--------+-------+     +-------+
                |       |                 |                |                |
                v       |                 |                v                v
            +--------+  |    +--------+   |           +--------+        +--------+
            | BUF1.2 |  +--->| BUF7.0 |<--+           | PGA2.0 |        | BUF5.1 |
            +---+----+       +---+----+               +----+---+        +---+----+
                |                |                         |                |
                v                v                         v                v
            +----------+     +-------+                +--------+       +----------+
            | SSP0.OUT |     | PCM3C |                | BUF2.0 |       | SSP2.OUT |
            +----------+     +-------+                +----+---+       +----------+
                                                           |
                                                           v
                                                       +-------+
                                                       | PCM0C |
                                                       +-------+

        As shown above,
        PCM0P and PCM3C in echo reference topology are interweaved;
        PCM2P and PCM2C in DSM topology are interweaved.
        So for this topology, the return value looks like:
        [(ECHO REF 7, [PCM0P, PCM3C]), (SMART_AMP5.0, [PCM2P, PCM2C])]
        """
        interweaved_prefix = ['ECHO', 'SMART_AMP']
        pipelines = []
        for head in self._heads:
            endpoints: "set[str]" = set()
            self._find_connected_node_recursively(self._backward_edges, head, partial(TplgGraph._prefix_eq, head), endpoints)
            # endpoints should contain 2 elements, e.g. PCM0P, PCM3C
            if len(endpoints) != 2:
                continue
            for endpoint in list(endpoints): # make a copy to avoid conflict
                self._find_connected_node_recursively(
                    self._forward_edges,
                    endpoint,
                    lambda name: name in self._heads,
                    endpoints)
                self._find_connected_node_recursively(
                    self._backward_edges,
                    endpoint,
                    lambda name: name in self._tails,
                    endpoints)
            # endpoints should contain 4 elements, e.g. PCM0P, PCM3C, SSP0.OUT, SSP0.IN
            assert len(endpoints) == 4
            for endpoint in endpoints:
                comps = self._find_connected_comp(endpoint, lambda name: TplgGraph.get_comp_prefix(name) in interweaved_prefix)
                if any(comps):
                    break
            assert len(comps) == 1
            # we are only interested in PCM and intereaved component
            pipelines.append((comps[0], [self._nodes_dict[name] for name in endpoints if name.startswith('PCM')]))
        return pipelines

if __name__ == "__main__":
    from pathlib import Path

    def parse_cmdline():
        parser = argparse.ArgumentParser(add_help=True, formatter_class=argparse.RawTextHelpFormatter,
            description='A Topology Reader totally Written in Python.')

        parser.add_argument('--version', action='version', version='%(prog)s 1.0')
        parser.add_argument('-t', '--tplgroot', type=str, help="""Load topology files matching \
a patterns argument from the tplg_root folder.
Enables internal globbing mode: the single positional argument is not a file but a comma-separated list of patterns.""")
        parser.add_argument('-d', '--dump', type=str, help='dump specified topology information, '
            'if multiple information types are wanted, use "," to separate them, eg, `-d pcm,graph`')
        parser.add_argument('filenames', nargs='+', type=str, help="""topology filenames or single pattern argument depending on
--tplgroot, see below. To pass multiple patterns use "," to separate them.""")
        # The below options are used to control generated graph
        parser.add_argument('-D', '--directory', type=str, default=".", help="output directory for generated graph")
        parser.add_argument('-F', '--format', type=str, default="png", help="output format for generated graph, defaults to 'png'."
            "check https://graphviz.gitlab.io/_pages/doc/info/output.html for all supported formats")
        parser.add_argument('-V', '--live_view', action="store_true", help="generate and view topology graph")
        parser.add_argument('-w', '--without_nodeinfo', action="store_true", help="show only widget names, no additional node info ")
        parser.add_argument('-c', '--show_core', choices=['never', 'auto', 'always'], default='auto',
            help="""control the display of component core ID in topology graph, there are 3 modes:
* never: never show core IDs.
* auto: show core IDs only when components don't all have the same core ID.
* always: always show core IDs

For this display option, components that don't specify any core ID are
considered different from components that specific core ID 0.
""")

        return parser.parse_args()

    def arg_split(value: str) -> "list[str]":
        "Split comma-delimited arguements value."
        return [v.strip() for v in value.split(',')]

    def do_glob(rootpath: Path, pattern: str):
        # Path.glob() didn't implement for absolute path.
        # This workaround just use the global root as the root path to transform the absolute path to relative path.
        pattern_path = Path(pattern)
        if pattern_path.is_absolute():
            rootpath = Path(pattern_path.root)
            pattern_path = pattern_path.relative_to(rootpath)
        return rootpath.glob(os.fspath(pattern_path))

    def get_tplg_paths(tplgroot: typing.Union[str, None], patterns: str) -> "list[Path]":
        """Get topology file paths based on the directory and file patterns.

        Parameters
        ----------
        tplgroot : `str | None`
            Root directory for topology files, or `None` if unspecified.
        patterns : `str`
            Comma-delimited file name patterns.

        NOTE
        ----
        1. Split patterns by comma.
        2. If tplgroot is unspecified, use current working directory.
        3. If pattern is absolute, ignore tplgroot and search matched files. Otherwise, search in tplgroot.
        """
        rootpath = Path.cwd() if tplgroot is None else Path(tplgroot.strip())
        if not rootpath.is_dir():
            raise NotADirectoryError(rootpath)
        return [tplgpath
            for pattern in arg_split(patterns) 
            for tplgpath in do_glob(rootpath, pattern) 
        ]

    def main():
        supported_dump = ['pcm', 'graph']
        tplgFormat = TplgBinaryFormat()

        cmd_args = parse_cmdline()
        dump_types = supported_dump if cmd_args.dump is None else arg_split(cmd_args.dump)

        if cmd_args.tplgroot:
            assert len(cmd_args.filenames) == 1, \
                f"Too many arguments when using --tplgroot, try quoting? {cmd_args.filenames}"
            patterns = cmd_args.filenames[0]
            files = get_tplg_paths(cmd_args.tplgroot, patterns)
            assert len(files) > 0, f"{patterns} did not match anything in '{cmd_args.tplgroot}'"
        else:
            files = [ Path(f) for f in cmd_args.filenames ]

        errors = 0
        for f in files:
            tplg = GroupedTplg(tplgFormat.parse_file(f))
            if 'pcm' in dump_types:
                tplg.print_pcm_info()
            if 'graph' in dump_types:
                graph = TplgGraph(tplg)
                graph.show_core = cmd_args.show_core
                graph.without_nodeinfo = cmd_args.without_nodeinfo
                graph.draw(f.stem, outdir=cmd_args.directory, file_format=cmd_args.format, live_view=cmd_args.live_view)
                errors += graph.errors

        return errors

    sys.exit(main())
