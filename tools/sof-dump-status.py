#!/usr/bin/env python3

import subprocess
import os
from common import format_pipeline, export_pipeline

class clsSYSCardInfo():
    def __init__(self):
        self.dmi={}
        self.pci_lst=[]
        self.acpi_lst=[]
        self.proc_card={}
        # https://github.com/thesofproject/linux/tree/topic/sof-dev/sound/soc/sof/intel/
        self._pci_ids = {
            # pci-tng.c
            "0x119a":"tng",
            # pci-apl.c
            "0x5a98":"apl", "0x1a98":"apl", "0x3198":"glk",
            # pci-cnl.c
            "0x9dc8":"cnl", "0xa348":"cfl", "0x02c8":"cml", "0x06c8":"cml",
            # pci-icl.c
            "0x34c8":"icl", "0x38c8":"jsl", "0x4dc8":"jsl",
            # pci-tgl.c
            "0xa0c8":"tgl", "0x43c8":"tgl-h", "0x4b55":"ehl", "0x4b58":"ehl", "0x7ad0": "adl-s", "0x51c8":"adl",
            # Other PCI IDs
            "0x9d71":"kbl", "0x9d70":"skl", "0x33c8":"hsw", 
            "0x3438":"bdw", "0x160c":"bdw", "0x0f04":"byt", "0x2284":"cht"
        }
        # self.sys_card=[]
        # some device use acpi-dev instead of pci-dev
        # https://github.com/thesofproject/linux/blob/topic/sof-dev/sound/soc/sof/sof-acpi-dev.c
        self._acpi_ids={"byt":"80860F28", "cht": "808622A8", "bdw":"INT3438"}
        self.sys_power={}
        self.dapm={'ctrl_lst':[], 'dapm_lst':[], 'name_lst':[]}

    def _convert_dmi_type(self, line):
        name=""
        idx = 0
        if line[0] == "b":
            name += "bios_"
        elif line[0] == "s":
            name += "system_"
        elif line[0] == "p":
            name += "product_"
        elif line[0] == "r":
            name += "board_"
        elif line[0] == "c":
            name += "chassis_"
        else:
            return name, idx
        idx = 2
        if line[1:3] == "vn":
            name += "vendor"
            idx = 3
        elif line[1:3] == "vr":
            name += "version"
            idx = 3
        elif line[1] == "n":
            name += "name"
        elif line[1] == "t":
            name += "type"
        elif line[1] == "d":
            name += "date"
        return name, idx

    def loadDMI(self):
        self.dmi.clear()
        exit_code, output=subprocess.getstatusoutput("cat /sys/class/dmi/id/modalias")
        # grep exit 1 means nothing matched
        if exit_code != 0:
            return
        output = output.split(':')
        # ouput[0] = dmi; ouput[-1] = '' ignore
        output = output[1:-1]
        for line in output:
            name, idx = self._convert_dmi_type(line)
            self.dmi[name] = line[idx:]
        pass

    def loadPCI(self):
        self.pci_lst.clear()
        exit_code, output=subprocess.getstatusoutput("sudo lspci -D |grep audio -i|grep intel -i")
        # grep exit 1 means nothing matched
        if exit_code != 0:
            return
        for line in output.splitlines():
            pci_info = {}
            pci_info['pci_id'] = line.split(' ')[0]
            tmp_output = subprocess.getoutput("sudo lspci -s %s -kx" % (pci_info['pci_id'])).splitlines()
            pci_info['name'] = tmp_output[1].split(':')[-1].strip()
            for i in range(2, len(tmp_output)):
                if tmp_output[i].split()[1].strip() == 'modules:' :
                    pci_info['module'] = tmp_output[i].split(':')[-1].strip()
                elif tmp_output[i].split()[0].strip() == '00:':
                    tmp_line = tmp_output[i].split()
                    break
            pci_info['hw_id']="0x" + tmp_line[2] + tmp_line[1] + " 0x" + tmp_line[4] + tmp_line[3]
            pci_info['hw_name'] = self._pci_ids["0x" + tmp_line[4] + tmp_line[3]]
            self.pci_lst.append(pci_info)

    def loadACPI(self):
        self.acpi_lst.clear()

        for mach in self._acpi_ids.keys():
            acpi_info = {}

            # On devices such as MinnowBoard the ACPI subsystem
            # creates devices 80860F28:00 and 80860F28:01. We first
            # need to loop to find out which of the two is enabled.
            device_index = -1
            for i in range(0, 2):
                # make sure the ACPI status is 15 (indicates device presence)
                exit_code, output=subprocess.getstatusoutput(
                    "cat /sys/bus/acpi/devices/%s:0%d/status" %
                    (self._acpi_ids[mach], i))
                if exit_code == 0 and output == "15":
                    device_index = i
                    break

            if device_index != -1:
                acpi_info['hw_name'] = mach
                acpi_info['acpi_id'] = self._acpi_ids[mach]
                acpi_info['acpi_id_suffix'] = device_index
                self.acpi_lst.append(acpi_info)

    def loadProcSound(self):
        self.proc_card.clear()
        if self._loadACard() is True:
            self._loadACodec()
            self._loadAPCM()

    def _loadACard(self):
        exit_code, output=subprocess.getstatusoutput("cat /proc/asound/cards")
        if exit_code != 0:
            return False
        output = output.splitlines()
        if len(output) <= 1:
            return False
        # parse for each 2 line to fill card information
        for idx in range(0, len(output), 2):
            card_info={}
            card_info['id'] = output[idx].strip().split(' ')[0]
            card_info['short'] = output[idx].split(' - ')[-1].strip()
            card_info['type']=output[idx].strip().split()[1][1:]
            card_info['longname']=output[idx + 1].strip()
            card_info['codec']=[]
            card_info['pcm']=[]
            self.proc_card[card_info['id']] = card_info
        return True
    
    def _loadACodec(self):
        exit_code, output=subprocess.getstatusoutput("cat /proc/asound/hwdep")
        if exit_code != 0:
            return
        for line in output.splitlines():
            id = line.split(':')[0].strip()
            card_info = self.proc_card[str(int(id.split('-')[0]))]
            codec_info = {}
            codec_info['id']=str(int(id.split('-')[1]))
            codec_info['name']=line.split(':')[1].strip()
            card_info['codec'].append(codec_info)

    def _loadAPCM(self):
        exit_code, output=subprocess.getstatusoutput("cat /proc/asound/pcm")
        if exit_code != 0:
            return

        def _sort_pcm(pcm_info):
            return int(pcm_info['id'])

        for line in output.splitlines():
            line_field = line.split(':')
            # field 0 : "s-id" s is sound card id; id is pcm id
            id = line_field[0].strip()
            card_info = self.proc_card[str(int(id.split('-')[0]))]
            pcm_info = {}
            pcm_info['id']=str(int(id.split('-')[1]))
            # field 1 : "pcm name (*)"
            pcm_info['pcm']=line_field[1].strip().replace('(*)', '').strip()
            # field 2 is empty or same with field 1
            # field 3 : "playback N"
            pcm_info['type']=line_field[3].split()[0].lower()
            card_info['pcm'].append(pcm_info)
            # field 4 : "capture N"
            if len(line_field) > 4:
                # sof-tplgreader order is playback > capture
                pcm_info2 = pcm_info.copy()
                pcm_info2['type']=line_field[4].split()[0].lower()
                card_info['pcm'].append(pcm_info2)

        card_info['pcm'].sort(key=_sort_pcm)

    def loadPower(self):
        exit_code, output=subprocess.getstatusoutput("cat /sys/power/mem_sleep")
        if exit_code != 0:
            return
        self.sys_power['option']=output.split()
        for opt in self.sys_power['option']:
            if '[' in opt and ']' in opt:
                self.sys_power['current']=opt.replace('[', '').replace(']', '')
                opt = self.sys_power['current']
                break

        exit_code, output=subprocess.getstatusoutput("cat /sys/power/wakeup_count")
        if exit_code != 0:
            return
        self.sys_power['wakeup_count']=output
        self.sys_power['run_status'] = []

        # ACPI devices need to be added first since the other scripts using the dsp_status
        # assume the device we care about has the index 0 in the sys_power.['run_status']
        # list
        if len(self.acpi_lst) == 0:
            self.loadACPI()

        for acpi_info in self.acpi_lst:
            exit_code, output=subprocess.getstatusoutput(
                "cat /sys/bus/acpi/devices/%s:0%d/power/runtime_status" %
                (acpi_info['acpi_id'], acpi_info['acpi_id_suffix']))
            if exit_code != 0:
                continue
            self.sys_power['run_status'].append({'map_id': acpi_info['acpi_id'], 'status': output})

        if len(self.pci_lst) == 0:
            self.loadPCI()

        for pci_info in self.pci_lst:
            exit_code, output=subprocess.getstatusoutput("cat /sys/bus/pci/devices/%s/power/runtime_status" % (pci_info['pci_id']))
            if exit_code != 0:
                continue
            self.sys_power['run_status'].append({'map_id': pci_info['pci_id'], 'status': output})

    def loadDAPM(self, filter = "all"):
        sound_path="/sys/kernel/debug/asoc"

        if len(self.pci_lst) == 0:
            self.loadPCI()

        if len(self.acpi_lst) == 0:
            self.loadACPI()

        self.dapm['ctrl_lst'].clear()
        self.dapm['dapm_lst'].clear()
        self.dapm['name_lst'].clear()

        for pci_info in self.pci_lst:
            exit_code, output=subprocess.getstatusoutput("cat /sys/bus/pci/devices/%s/power/control" % (pci_info['pci_id']))
            if exit_code != 0:
                continue
            self.dapm['ctrl_lst'].append({'id': pci_info['pci_id'], 'status':output})

        for acpi_info in self.acpi_lst:
            exit_code, output=subprocess.getstatusoutput("cat /sys/bus/acpi/devices/%s:00/power/control" % (acpi_info['acpi_id']))
            if exit_code != 0:
                continue
            self.dapm['ctrl_lst'].append({'id': acpi_info['acpi_id'], 'status':output})

        exit_code, output = subprocess.getstatusoutput("find %s -name dapm" % (sound_path))
        if exit_code != 0:
            return

        for line in output.splitlines():
            dapm_dict = {'path':None, 'status':{}}
            # line format:
            # /sys/kernel/debug/asoc/'machine-driver'/'path_name'/dapm
            # /sys/kernel/debug/asoc/'machine-driver'/dapm
            path_name = line.replace(sound_path, '')
            path_name = path_name.split('/')[2]
            dapm_dict['path'] = path_name
            self.dapm['dapm_lst'].append(dapm_dict)
            for fname in os.scandir(line):
                exit_code, output = subprocess.getstatusoutput('cat "%s/%s"' % (line, fname.name))
                if exit_code != 0:
                    continue
                # 1st line format:
                # 'fname.name': content in x out x
                # OR
                # content
                content = output.splitlines()[0].replace("%s:" %(fname.name), '').strip().split(' ')[0]
                # content value: [ on, off, standby ]
                if filter == 'all':
                    dapm_dict['status'][fname.name]=content
                elif content.lower() == filter:
                    self.dapm['name_lst'].append("'%s/%s'" %(path_name ,fname.name))

if __name__ == "__main__":
    def dump_dmi(dmi):
        if len(dmi.keys()) == 0:
            print("Couldn't detect for DMI information from SYS modalias")
            return
        print("DMI Info:")
        for key, value in dmi.items():
            if len(key) < 15:
                flag = '\t'
            else:
                flag = ''
            print("\t%s:\t%s%s" %( key, flag, value ))
        print("")

    def dump_pci(pci_lst):
        # dump pci information
        if len(pci_lst) == 0 :
            print("Couldn't detect for PCI device for audio\n")
            return
        for pci_info in pci_lst:
            print("PCI ID:\t\t\t" +  pci_info['pci_id'])
            print("\tName:\t\t" + pci_info['name'])
            print("\tHex:\t\t" + pci_info['hw_id'])
            print("\tchipset:\t" + pci_info['hw_name'])
            if pci_info.get('module') is not None:
                print("\tmodule:\t\t" + pci_info['module'])
        print("")

    def dump_acpi(acpi_lst):
        # dump acpi information
        if len(acpi_lst) == 0 :
            print("Couldn't detect for ACPI device for audio\n")
            return
        for acpi_info in acpi_lst:
            print("ACPI ID:\t\t\t" +  acpi_info['acpi_id'])
            print("\tchipset:\t" + acpi_info['hw_name'])
        print("")

    def dump_proc_sound(proc_card):
        if len(proc_card.keys()) == 0:
            print("Couldn't detect for sound card for audio")
            return
        for card_info in proc_card.values():
            print("Card ID:\t\t" + card_info['id'])
            print("\tType:\t\t" + card_info['type'])
            print("\tShort name:\t" + card_info['short'])
            print("\tLong name:\t" + card_info['longname'])
            if len(card_info['codec']) == 0:
                print("\tCodec:\t\tNOCODEC")
            else:
                print("\tCodec:")
                for item in card_info['codec']:
                    print("\t\tID:\t" + item['id'])
                    print("\t\tName:\t" + item['name'])
            if len(card_info['pcm']) == 0:
                print("\tPCM:\t\tNOPCM")
            else:
                print("\tPCM:")
                for item in card_info['pcm']:
                    print("\t\tID:\t" + item['id'])
                    print("\t\tPCM:\t" + item['pcm'])
                    print("\t\tType:\t" + item['type'].capitalize())
            print("")

    def dump_power(sys_power):
        if len(sys_power.keys()) == 0:
            print("Couldn't detect for sound card for audio")
            return
        print("Power Info:")
        print("\tCurrent option:\t%s" %(sys_power['current']))
        print("\t\toption:\t%s" %(",".join(sys_power['option'])))
        print("\tWakeup Count:\t%s" %(sys_power['wakeup_count']))
        print("Power Status:")
        for run_status in sys_power['run_status']:
            print("\tMap ID:\t%s" %(run_status['map_id']))
            print("\t\tstatus:\t%s" %(run_status['status']))
        print("")

    def export_pci(pci_lst, platform = False):
        if len(pci_lst) == 0 :
            return
        if platform is True:
            print("PCI_PLATFORM=" + pci_lst['hw_name'])
            return

    def export_proc_sound(proc_card):
        if len(proc_card.keys()) == 0:
            return

    def dump_cardinfo_pcm(card_info):
        for pipeline in card_info.get('pcm'):
            print(format_pipeline(pipeline))

    def dump_dapm(dapm, filter = "all"):
        if filter == "all" and len(dapm['dapm_lst']) == 0:
            return
        if filter != "all" and len(dapm['name_lst']) == 0:
            return
        print("DPAM Info:")
        print("\tPower control:")
        for control in dapm['ctrl_lst']:
            print("\t\tPCI ID: %s" %(control['id']))
            print("\t\tStatus: %s" %(control['status']))
        if filter == "all":
            for em in dapm['dapm_lst']:
                print("\tPath:\t%s" %(em['path']))
                print("\tStatus:")
                for fname in em['status'].keys():
                    strtab = ""
                    if len(fname) < 24:
                        strtab += "\t"
                    if len(fname) < 16:
                        strtab += "\t"
                    if len(fname) < 8:
                        strtab += "\t"
                    print("\t\t%s%s : %s" % (fname, strtab, em['status'][fname]))
        else:
            print("\tStatus is '%s' component:" % (filter))
            for em in dapm['name_lst']:
                print("\t\t%s;" % em)

    import argparse

    parser = argparse.ArgumentParser(description='Detect system status for the Sound Card',
        add_help=True, formatter_class=argparse.RawTextHelpFormatter)

    # spec option for the automation bash
    parser.add_argument('-p', '--platform', action='store_true', help='dump pci chipset value')
    parser.add_argument('-w', '--power', action='store_true', help='dump power status value')
    parser.add_argument('-i', '--id', type=int, help='dump the pcm information of target id sound card')
    parser.add_argument('-s', '--short', type=int, help='dump the short name of target id sound card')
    parser.add_argument('-l', '--longname', type=int, help='dump the longname name of target id sound card')
    parser.add_argument('-P', '--fwpath', action='store_true', help='get firmware path according to DMI info')
    parser.add_argument('-S', '--dsp_status', type=int, help='get current dsp power status, should specify sof card number')
    parser.add_argument('-d', '--dapm', choices=['all', 'on', 'off', 'standby'], help='get current dapm status, this option need root permission to access debugfs')
    # The filter string here is compatible with the filter string for pipeline from topology,
    # and takes the form of 'type:playback & pga:any & ~asrc:any | id:5'.
    parser.add_argument('-e', '--export', type=str, help='export pipeline parameters of specified type from proc file system,\n'
    'to specify pipeline type, use "-e type:playback", complex string like\n'
    '"type:playback & pga:any" can be used, but only "type" is processed')
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')

    ret_args = vars(parser.parse_args())

    sysinfo = clsSYSCardInfo()
    if ret_args['platform'] is True:
        sysinfo.loadPCI()
        mach_name = None
        for pci_info in sysinfo.pci_lst:
            mach_name = pci_info['hw_name']
        if (mach_name is None):
            sysinfo.loadACPI()
            for acpi_info in sysinfo.acpi_lst:
                mach_name = acpi_info['hw_name']
        if (mach_name is not None):
            print(mach_name)
        exit(0)

    if ret_args['power'] is True:
        sysinfo.loadPower()
        for run_status in sysinfo.sys_power['run_status']:
            print(run_status['status'])
        exit(0)

    if ret_args['export'] is not None:
        sysinfo.loadProcSound()
        pipeline_lst = []
        for (card_id, card_info) in sysinfo.proc_card.items():
            for pcm in card_info['pcm']:
                # There are limited pipeline parameters in the proc file system,
                # add some default parameters to make use of sof-test for legacy HDA test
                pcm['fmt'] = 'S16_LE'
                pcm['fmts'] = 'S16_LE S24_LE S32_LE'
                pcm['rate'] = '48000'
                pcm['channel'] = '2'
                pcm['dev'] = 'hw:{},{}'.format(card_id, pcm['id'])
            pipeline_lst.extend(card_info['pcm'])
        # The filter string may be very complex due to the compatibility with topology pipeline
        # filter string, but we only implement a simple type filter here.
        try:
            # ret_args['export'] contains filter string, and it may looks like 'type:capture & pga:any | id:3'
            # extract filter elements, and drop logic operator
            filter_elements = [elem for elem in ret_args['export'].split(' ') if ':' in elem]
            # extract requested pipeline type from filter elements, and ignore others.
            requested_type = [f.split(':')[1] for f in filter_elements if f.strip().startswith('type')][0]
        except:
            print('Invalid filter string')
            exit(1)
        # requested_type may take one of the values: playback, capture, any
        if requested_type in ['playback', 'capture']:
            export_pipeline([p for p in pipeline_lst if p['type'] == requested_type])
        elif requested_type == 'any':
            export_pipeline(pipeline_lst)
        else:
            print('Unknown requested pipeline type: %s' % requested_type)
            print('Available requested pipeline types are: playback, capture, any')
            exit(1)
        exit(0)

    if ret_args.get('id') is not None:
        sysinfo.loadProcSound()
        card_info = sysinfo.proc_card.get(str(ret_args['id']))
        if card_info is None:
            exit(0)
        dump_cardinfo_pcm(card_info)
        exit(0)

    if ret_args.get('short') is not None:
        sysinfo.loadProcSound()
        card_info = sysinfo.proc_card.get(str(ret_args['short']))
        if card_info is None:
            exit(0)
        print(card_info['short'])
        exit(0)

    if ret_args.get('longname') is not None:
        sysinfo.loadProcSound()
        card_info = sysinfo.proc_card.get(str(ret_args['longname']))
        if card_info is None:
            exit(0)
        print(card_info['longname'])
        exit(0)

    if ret_args.get('dsp_status') is not None:
        sysinfo.loadPower()
        print(sysinfo.sys_power['run_status'][ret_args['dsp_status']]['status'])
        exit(0)

    if ret_args.get('dapm') is not None:
        if os.environ['USER'] != 'root': # this operation need root permission
            print("Need root permission to access debugfs")
            exit(1)
        sysinfo.loadDAPM(ret_args.get('dapm'))
        dump_dapm(sysinfo.dapm, ret_args.get('dapm'))
        exit(0)

    # The kernel has changed the default firmware path when community
    # key is used. Here we output firmware path according to kernel's
    # match table.
    if ret_args.get('fwpath') is True:
        def is_community_board(board, community_boards):
            for elem in community_boards:
                if match_board(elem, board):
                    return True
            return False

        # see if 'board' matches 'match', only match the key defined
        # in community boards' matches field.
        def match_board(match, board):
            for key in match["matches"].keys():
                if match["matches"][key] != board["matches"][key]:
                    return False
            return True

        # The "community_boards" structure here is in accordance
        # with "struct dmi_system_id community_key_platforms" in
        # "sound/soc/sof/sof-pci-dev.c".
        community_boards = [
            {
                "ident": "Up Squared",
                "matches": {
                    "board_name": "UP-APL01",
                    "board_vendor": "AAEON"
                }
            },
            {
                "ident": "Chromebook",
                "matches":  {
                    "board_vendor": "Google",
                }
            },
	    {
                "ident": "Up Extreme",
                "matches": {
                    "board_name": "UP-WHL01",
                    "board_vendor": "AAEON"
                }
            }
        ]
        fw_path = "/lib/firmware/intel/sof"
        sysinfo.loadDMI()
        board = {
                    "ident": sysinfo.dmi["board_name"],
                    "matches": {
                        "board_name": sysinfo.dmi["board_name"],
                        "board_vendor": sysinfo.dmi["board_vendor"]
                    }
                }
        if is_community_board(board, community_boards):
            fw_path += "/community"
        print(fw_path)
        exit(0)

    sysinfo.loadDMI()
    sysinfo.loadPCI()
    sysinfo.loadProcSound()
    sysinfo.loadPower()
    dump_dmi(sysinfo.dmi)
    dump_pci(sysinfo.pci_lst)
    dump_acpi(sysinfo.acpi_lst)
    dump_proc_sound(sysinfo.proc_card)
    dump_power(sysinfo.sys_power)

