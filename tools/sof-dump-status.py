#!/usr/bin/python3

import subprocess

class clsSYSCardInfo():
    def __init__(self):
        self.dmi={}
        self.pci_lst=[]
        self.proc_card={}
        # https://github.com/thesofproject/linux/blob/topic/sof-dev/sound/soc/sof/sof-pci-dev.c
        self._pci_ids={"0x119a":"tng","0x5a98":"apl", "0x1a98":"apl", "0x3198":"glk",
            "0x9dc8":"cnl", "0xa348":"cfl", "0x9d71":"kbl", "0x9d70":"skl", "0x34c8":"icl", "0x38c8":"jsl",
            "0x02c8":"cml", "0x06c8":"cml", "0xa0c8":"tgl", "0x4b55":"ehl",
            # https://github.com/thesofproject/linux/blob/topic/sof-dev/sound/soc/sof/sof-acpi-dev.c
            "0x3438":"bdw", "0x33c8":"hsw", "0x0f04":"byt", "0x2284":"cht"}
        # self.sys_card=[]
        self.sys_power={}

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
        # grep exit 1 means nothing match
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
        exit_code, output=subprocess.getstatusoutput("lspci |grep audio -i")
        # grep exit 1 means nothing match
        if exit_code != 0:
            return
        for line in output.splitlines():
            pci_info = {}
            pci_info['pci_id'] = line.split(' ')[0]
            tmp_output = subprocess.getoutput("lspci -s %s -kx" % (pci_info['pci_id'])).splitlines()
            pci_info['name'] = tmp_output[1].split(':')[-1].strip()
            for i in range(2, len(tmp_output)):
                if tmp_output[i].split()[1].strip() == 'modules:' :
                    pci_info['module'] = tmp_output[i].split(':')[-1].strip()
                elif tmp_output[i].split()[0].strip() == '00:':
                    tmp_line = tmp_output[i].split()
                    break
            pci_info['hw_id']="0x" + tmp_line[2] + tmp_line[1] + " 0x" + tmp_line[4] + tmp_line[3]
            pci_info['hw_name']=self._pci_ids["0x" + tmp_line[4] + tmp_line[3]]
            self.pci_lst.append(pci_info)

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
            card_info['short'] = output[idx].split(' ')[-1].strip()
            card_info['type']=output[idx].strip().split()[1][1:]
            card_info['desc']=output[idx + 1].strip()
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
            line_filed = line.split(':')
            id = line_filed[0].strip()
            card_info = self.proc_card[str(int(id.split('-')[0]))]
            pcm_info = {}
            pcm_info['id']=str(int(id.split('-')[1]))
            pcm_info['pcm']=line_filed[1].strip()
            # filed 2 is same with filed 1 ??
            pcm_info['type']=[str(el).strip() for el in line_filed[3:]]
            card_info['pcm'].append(pcm_info)

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
        if len(self.pci_lst) > 0:
            self.sys_power['run_status'] = [ {'pci_id': pci_info['pci_id'] for pci_info in self.pci_lst} ]
        else:
            exit_code, output=subprocess.getstatusoutput("lspci |grep audio -i")
            # grep exit 1 means nothing match
            if exit_code != 0:
                return
            self.sys_power['run_status'] = [ {'pci_id': line.split(' ')[0] for line in output.splitlines()} ]
        for run_status in self.sys_power['run_status']:
            exit_code, output=subprocess.getstatusoutput("cat /sys/bus/pci/devices/0000:%s/power/runtime_status" % (run_status['pci_id']))
            if exit_code != 0:
                continue
            run_status['status'] = output

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
            print("Couldn't detect for PCI device for audio")
            return
        for pci_info in pci_lst:
            print("PCI ID:\t\t\t" +  pci_info['pci_id'])
            print("\tName:\t\t" + pci_info['name'])
            print("\tHex:\t\t" + pci_info['hw_id'])
            print("\tchipset:\t" + pci_info['hw_name'])
            print("\tmodule:\t\t" + pci_info['module'])
        print("")

    def dump_proc_sound(proc_card):
        if len(proc_card.keys()) == 0:
            print("Couldn't detect for sound card for audio")
            return
        for card_info in proc_card.values():
            print("Card ID:\t\t" + card_info['id'])
            print("\tType:\t\t" + card_info['type'])
            print("\tShort name:\t" + card_info['short'])
            print("\tDesc:\t\t" + card_info['desc'])
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
                    print("\t\tType:\t" + ', '.join(item['type']))
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
            print("\tPCI ID:\t%s" %(run_status['pci_id']))
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

    def export_cardinfo_pcm(card_info):
        pcm_lst = card_info.get('pcm')
        length = len(pcm_lst)
        if length == 0:
            return

        keyword = 'ASOUND_PCM'
        # clear up the older define
        print('unset %s_COUNT' % (keyword))
        print('unset %s_LST' % (keyword))
        print('declare -g %s_COUNT' % (keyword))
        print('declare -ag %s_LST' % (keyword))
        print('%s_COUNT=%d' % (keyword, length))

        def _getStr(tmp_dict, key):
            return '%s=%s'%(key, tmp_dict.get(key))

        def _covertType(type_lst):
            ret=0
            for type_str in type_lst:
                if type_str.split()[0].lower() == 'playback':   ret += 1
                elif type_str.split()[0].lower() == 'capture':  ret += 2
                # here maybe have some problem, so don't need to check it
                else:   return ""
            if ret == 1:    return 'playback'
            elif ret == 2:  return 'capture'
            else:           return 'both'

        for idx in range(0, length):
            pcm = pcm_lst[idx]
            print('%s_LST[%d]="%s;%s;%s=%s"' % (keyword, idx, _getStr(pcm, 'id'), _getStr(pcm, 'pcm'), 'type', ', '.join(pcm.get('type'))))
            # date format for match tplg format
            pcm['pcm'] = pcm['pcm'].replace('(*)', '').strip()
            pcm['type'] = _covertType(pcm['type'])
            # store pcm to each list
            print('unset %s_%s' % (keyword, pcm['id']))
            print('declare -Ag %s_%s' % (keyword, pcm['id']))
            for key, value in pcm_lst[idx].items():
                print('%s_%s["%s"]="%s"' % (keyword, pcm['id'], key, value))
        return 0

    import argparse

    parser = argparse.ArgumentParser(description='Detect system status for the Sound Card',
        add_help=True, formatter_class=argparse.RawTextHelpFormatter)

    # spec option for the automation bash
    parser.add_argument('-p', '--platform', action='store_true', help='just dump pci chipset value')
    parser.add_argument('-w', '--power', action='store_true', help='just dump power status value')
    parser.add_argument('-i', '--id', type=int, help='just dump the pcm infomation of target id sound card')
    parser.add_argument('-s', '--short', type=int, help='just dump the short name of target id sound card')
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')

    ret_args = vars(parser.parse_args())

    sysinfo = clsSYSCardInfo()
    if ret_args['platform'] is True:
        sysinfo.loadPCI()
        for pci_info in sysinfo.pci_lst:
            print(pci_info['hw_name'])
        exit(0)

    if ret_args['power'] is True:
        sysinfo.loadPower()
        for run_status in sysinfo.sys_power['run_status']:
            print(run_status['status'])
        exit(0)

    if ret_args.get('id') is not None:
        sysinfo.loadProcSound()
        card_info = sysinfo.proc_card.get(str(ret_args['id']))
        if card_info is None:
            exit(0)
        export_cardinfo_pcm(card_info)
        exit(0)

    if ret_args.get('short') is not None:
        sysinfo.loadProcSound()
        card_info = sysinfo.proc_card.get(str(ret_args['short']))
        if card_info is None:
            exit(0)
        print(card_info['short'])
        exit(0)

    sysinfo.loadDMI()
    sysinfo.loadPCI()
    sysinfo.loadProcSound()
    sysinfo.loadPower()
    dump_dmi(sysinfo.dmi)
    dump_pci(sysinfo.pci_lst)
    dump_proc_sound(sysinfo.proc_card)
    dump_power(sysinfo.sys_power)

