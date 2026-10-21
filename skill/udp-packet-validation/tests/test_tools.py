"""Run: python -m unittest discover -s skill/udp-packet-validation/tests -v"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from udp_pcap import PacketFormatError, PcapFrame, extract_udp, read_udp_pcap, read_pcap, read_length_prefixed,write_pcap,write_length_prefixed
from udp_validate import check_packets, ProfileError, normalize_profile
from difi_b5_validate import inspect,iq
from split_difi_pcap import split_frames
from make_fixtures import make_b5_packets, frames_for_packets, ether_udp, create_all

BASE=Path(__file__).resolve().parents[1]
class UDPTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory()
        cls.d=Path(cls.tmp.name)
        create_all(cls.d)
        cls.profile=json.loads((BASE/'templates/generic_profile.json').read_text(encoding='utf8'))
    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()
    def p(self,name):return self.d/name
    def call(self,script,*args):
        return subprocess.run([sys.executable,str(BASE/'scripts'/script),*map(str,args)],
                              capture_output=True,text=True)
    def test_pcap_count(self):self.assertEqual(len(list(read_pcap(self.p('b5_synthetic_valid.pcap')))),22)
    def test_udp_decode(self):self.assertEqual(len(list(read_udp_pcap(self.p('b5_synthetic_valid.pcap')))),22)
    def test_udp_vlan(self):self.assertEqual(len(list(read_udp_pcap(self.p('b5_synthetic_vlan.pcap')))),22)
    def test_udp_bin(self):self.assertEqual(len(list(read_length_prefixed(self.p('b5_synthetic_valid.bin')))),22)
    def test_b5_valid(self):self.assertEqual(inspect(list(read_udp_pcap(self.p('b5_synthetic_valid.pcap'))))['result'],'PASS')
    def test_b5_iq_count(self):self.assertEqual(inspect(list(read_length_prefixed(self.p('b5_synthetic_valid.bin'))))['validated_iq_samples'],5120)
    def test_b5_total_bytes(self):self.assertEqual(inspect(list(read_udp_pcap(self.p('b5_synthetic_valid.pcap'))))['payload_bytes'],21192)
    def test_b5_corrupt_iq(self):self.assertEqual(inspect(list(read_udp_pcap(self.p('b5_synthetic_bad_iq.pcap'))))['result'],'FAIL')
    def test_b5_missing(self):self.assertEqual(inspect(list(read_udp_pcap(self.p('b5_synthetic_missing.pcap'))))['result'],'FAIL')
    def test_b5_sequence(self):
        packets=make_b5_packets();bad=list(packets)
        head=int.from_bytes(bad[4][:4],'big')^0x00010000
        bad[4]=head.to_bytes(4,'big')+bad[4][4:]
        self.assertEqual(inspect([__import__('udp_pcap').UdpPacket(x) for x in bad])['result'],'FAIL')
    def test_b5_header(self):
        packets=make_b5_packets();bad=list(packets)
        bad[0]=bytes([bad[0][0]^0x10])+bad[0][1:]
        self.assertEqual(inspect([__import__('udp_pcap').UdpPacket(x) for x in bad])['result'],'FAIL')
    def test_b5_short(self):
        packets=make_b5_packets();packets[1]=packets[1][:-4]
        self.assertEqual(inspect([__import__('udp_pcap').UdpPacket(x) for x in packets])['result'],'FAIL')
    def test_b5_zero_packets(self):self.assertEqual(inspect([])['result'],'FAIL')
    def test_generic_valid(self):self.assertEqual(check_packets(list(read_udp_pcap(self.p('generic_valid.pcap'))),self.profile,True)['result'],'PASS')
    def test_generic_bad_seq(self):self.assertEqual(check_packets(list(read_udp_pcap(self.p('generic_bad_seq.pcap'))),self.profile,True)['result'],'FAIL')
    def test_generic_no_ip_metadata(self):
        with self.assertRaises(ProfileError):check_packets(list(read_length_prefixed(self.p('generic_valid.bin'))),self.profile,False)
    def test_generic_no_matching(self):
        p=dict(self.profile);p['filter']={'dst_port':60001}
        self.assertEqual(check_packets(list(read_udp_pcap(self.p('generic_valid.pcap'))),p,True)['result'],'FAIL')
    def test_generic_bad_profile(self):
        with self.assertRaises(ProfileError):normalize_profile({'expected_count':-1})
    def test_generic_golden(self):
        p=dict(self.profile);p['golden_payloads_hex']=[(bytes([i])+b'PAYLOAD').hex() for i in range(3)]
        self.assertEqual(check_packets(list(read_udp_pcap(self.p('generic_valid.pcap'))),p,True)['result'],'PASS')
    def test_generic_golden_invalid(self):
        p=dict(self.profile);p['golden_payloads_hex']=['00','01','02']
        self.assertEqual(check_packets(list(read_udp_pcap(self.p('generic_valid.pcap'))),p,True)['result'],'FAIL')
    def test_split(self):
        a,b=split_frames(list(read_pcap(self.p('b5_synthetic_valid.pcap'))),'192.168.1.10','192.168.1.20',4991,2,1)
        self.assertEqual((len(a),len(b)),(1,21))
    def test_split_bad_sid(self):
        with self.assertRaises(PacketFormatError):split_frames(list(read_pcap(self.p('b5_synthetic_valid.pcap'))),'192.168.1.10','192.168.1.20',4991,3,1)
    def test_pcapng_reject(self):
        p=self.p('fake.pcapng');p.write_bytes(b'\x0a\x0d\x0d\x0a'+b'\x00'*20)
        with self.assertRaisesRegex(PacketFormatError,'pcapng'):list(read_pcap(p))
    def test_truncated_bin_reject(self):
        p=self.p('truncated.bin');p.write_bytes(b'\x00\x00\x00\x20abc')
        with self.assertRaises(PacketFormatError):list(read_length_prefixed(p))
    def test_truncated_pcap_reject(self):
        p=self.p('truncated.pcap');p.write_bytes(self.p('b5_synthetic_valid.pcap').read_bytes()[:-1])
        with self.assertRaises(PacketFormatError):list(read_pcap(p))
    def test_non_udp_ignored(self):
        f=PcapFrame(1,0,b'\x00'*12+b'\x08\x06'+b'\x00'*28,42)
        self.assertIsNone(extract_udp(f,1))
    def test_fragment_reject(self):
        data=bytearray(ether_udp(b'payload'));data[14+6:14+8]=b'\x20\x00'
        with self.assertRaises(PacketFormatError):extract_udp(PcapFrame(1,0,bytes(data),len(data)),1)
    def test_cli_b5_pass(self):
        r=self.call('difi_b5_validate.py','--pcap',self.p('b5_synthetic_valid.pcap'),'--src-ip','192.168.1.10','--dst-port','4991')
        self.assertEqual(r.returncode,0,r.stderr)
    def test_cli_b5_fail(self):
        r=self.call('difi_b5_validate.py','--pcap',self.p('b5_synthetic_bad_iq.pcap'))
        self.assertEqual(r.returncode,1,r.stderr)
    def test_cli_generic_pass(self):
        r=self.call('udp_validate.py','--pcap',self.p('generic_valid.pcap'),'--profile',BASE/'templates/generic_profile.json')
        self.assertEqual(r.returncode,0,r.stderr)
    def test_cli_generic_fail(self):
        r=self.call('udp_validate.py','--pcap',self.p('generic_bad_seq.pcap'),'--profile',BASE/'templates/generic_profile.json')
        self.assertEqual(r.returncode,1,r.stderr)
    def test_cli_generic_bin_pass(self):
        p=dict(self.profile);p['filter']={}
        temp=self.p('profile-bin.json');temp.write_text(json.dumps(p))
        r=self.call('udp_validate.py','--capture-bin',self.p('generic_valid.bin'),'--profile',temp)
        self.assertEqual(r.returncode,0,r.stderr)
    def test_cli_split(self):
        out=self.p('split')
        r=self.call('split_difi_pcap.py','--pcap',self.p('b5_synthetic_valid.pcap'),
                    '--board-ip','192.168.1.10','--pc-ip','192.168.1.20','--outdir',out)
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(len(list(read_pcap(out/'version_flow.pcap'))),1)
        self.assertEqual(len(list(read_pcap(out/'data_context_flow.pcap'))),21)
    def test_ipv4_payload_padding(self):
        data=ether_udp(b'abc')+b'\x00'*10
        self.assertEqual(extract_udp(PcapFrame(1,0,data,len(data)),1).payload,b'abc')

if __name__=='__main__':unittest.main()
