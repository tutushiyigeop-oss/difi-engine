#!/usr/bin/env python3
"""Deterministically generate editable architecture SVGs and high-resolution PNGs.
Requires svgwrite and cairosvg (PNG generation only). Diagram depicts B5 BD verified in
scripts/vivado/generated/b5_raw_export/bd.tcl and RTL under rtl/.
"""
from pathlib import Path
import svgwrite
import cairosvg

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'report'/'figures'; OUT.mkdir(parents=True,exist_ok=True)
C={'bg':'#F7F9FC','white':'#FFFFFF','navy':'#13243D','slate':'#52647B','muted':'#8191A7','border':'#CFD8E5','data':'#2075BA','difi':'#008E87','ctrl':'#CA8B23','udp':'#765BC0','lightblue':'#EDF5FC','lightteal':'#E8F7F5','lightamber':'#FFF6E7','lightpurple':'#F2EEFC','darkgray':'#344966','ltgray':'#EFF2F7','warn':'#AF5A26'}
FONT='Noto Sans CJK SC, Microsoft YaHei, sans-serif'

def base(name,w=1800,h=1000):
    d=svgwrite.Drawing(str(OUT/name),size=(f'{w}px',f'{h}px'),viewBox=f'0 0 {w} {h}')
    d.add(d.rect(insert=(0,0),size=(w,h),fill=C['bg']))
    defs=d.defs
    for key,col in [('data',C['data']),('difi',C['difi']),('ctrl',C['ctrl']),('udp',C['udp']),('muted',C['muted'])]:
        marker=d.marker(id='arrow_'+key,insert=(11,6),size=(12,12),orient='auto',markerUnits='userSpaceOnUse')
        marker.add(d.path(d='M 1 1 L 11 6 L 1 11 z',fill=col))
        defs.add(marker)
    return d

def box(d,x,y,w,h,fill=C['white'],stroke=C['border'],r=18,sw=1.7,dashed=False):
    kw={'insert':(x,y),'size':(w,h),'rx':r,'ry':r,'fill':fill,'stroke':stroke,'stroke_width':sw}
    if dashed:kw['stroke_dasharray']='7 7'
    d.add(d.rect(**kw))

def txt(d,x,y,label,size=22,color=C['navy'],weight=400,anchor='start',ls=None):
    attrs={'insert':(x,y),'font_size':size,'font_family':FONT,'fill':color,'font_weight': int(round(weight / 100) * 100),'text_anchor':anchor}
    if ls:attrs['letter_spacing']=ls
    d.add(d.text(label,**attrs))

def line(d,pts,col,sw=4,arrow=True,dash=False):
    kw={'fill':'none','stroke':col,'stroke_width':sw,'stroke_linecap':'round','stroke_linejoin':'round'}
    if dash:kw['stroke_dasharray']='10 8'
    if arrow:
        key=next((i for i in ['data','difi','ctrl','udp','muted'] if C[i]==col),'muted')
        kw['marker_end']=f'url(#arrow_{key})'
    d.add(d.polyline(points=pts,**kw))

def center_title(d,x,y,w,title,subtitle=None,fs=25):
    txt(d,x+w/2,y,title,fs,C['navy'],650,'middle')
    if subtitle:txt(d,x+w/2,y+34,subtitle,17,C['slate'],420,'middle')

def pill(d,x,y,w,text,fill,color):
    box(d,x,y,w,36,fill,fill,18,0)
    txt(d,x+w/2,y+25,text,17,color,600,'middle')

def step(d,x,y,n,col):
    d.add(d.circle(center=(x,y),r=17,fill=col,stroke='#fff',stroke_width=3))
    txt(d,x,y+6,str(n),16,'#fff',700,'middle')

def heading(d,title,subtitle,tag):
    txt(d,74,94,title,48,C['navy'],750)
    txt(d,77,136,subtitle,20,C['slate'])
    pill(d,1530,69,205,tag,C['lightteal'],C['difi'])
    d.add(d.line(start=(75,164),end=(1725,164),stroke='#DEE5EF',stroke_width=2))

def zone(d,x,y,w,h,bg,title,subtitle):
    box(d,x,y,w,h,bg,'#D5DEEA',20,2)
    txt(d,x+28,y+51,title,27,C['navy'],740)
    txt(d,x+28,y+81,subtitle,17,C['slate'])
    d.add(d.line(start=(x+25,y+102),end=(x+w-25,y+102),stroke='#D8E1EC',stroke_width=1.5))

def legend(d,x,y,labels):
    xx=x
    for label,col in labels:
        d.add(d.line(start=(xx,y),end=(xx+40,y),stroke=col,stroke_width=6,stroke_linecap='round'))
        txt(d,xx+53,y+7,label,18,C['slate'])
        xx+=53+len(label)*18+58


def make_b5():
    d=base('difi_b5_system_architecture.svg',1800,1020)
    heading(d,'DIFI 1.1 — Zynq PS / PL 端到端系统架构','B5 原始报文导出：IQ → DIFI 1.1 Packet → PS UDP → PC 验证','已完成板级验证')
    legend(d,90,202,[('IQ / DDR 数据',C['data']),('完整 DIFI 报文',C['difi']),('AXI4-Lite 控制',C['ctrl']),('UDP 网络',C['udp'])])
    zone(d,65,253,310,642,'#F2F4FA','PC 端','Windows 主机 / 192.168.1.20')
    zone(d,410,253,485,642,'#F2F7FD','PS + 板载 DDR','Zynq-7020 / Cortex-A9')
    zone(d,930,253,810,642,'#F2F9F8','PL 可编程逻辑','AXI DMA + DIFI RTL / 100 MHz')
    # PC app
    box(d,102,393,234,240,C['white'],'#C8D1E7',16)
    txt(d,219,430,'UDP 接收与验证',22,C['navy'],700,'middle')
    txt(d,219,479,'Python 接收器',21,C['darkgray'],550,'middle')
    d.add(d.line(start=(131,498),end=(308,498),stroke='#E2E7F0',stroke_width=1))
    txt(d,219,535,'DIFI / IQ 校验',20,C['darkgray'],540,'middle')
    d.add(d.line(start=(131,552),end=(308,552),stroke='#E2E7F0',stroke_width=1))
    txt(d,219,589,'Wireshark + 参考工具',18,C['darkgray'],520,'middle')
    pill(d,119,668,203,'UDP 端口 4991',C['lightpurple'],C['udp'])
    txt(d,222,843,'22 个 Packet · 5,120 IQ',17,C['slate'],500,'middle')
    # PS blocks
    box(d,455,376,395,118,C['white'],'#CAD9E9',18)
    txt(d,652,413,'ARM Cortex-A9 + Vitis',24,C['navy'],700,'middle')
    txt(d,652,449,'Standalone C / lwIP RAW API',18,C['slate'],500,'middle')
    txt(d,652,476,'DMA 配置、Cache、报文转 UDP',16,C['slate'],450,'middle')
    box(d,455,542,395,116,C['white'],'#CAD9E9',18)
    txt(d,652,584,'板载 DDR3 数据缓冲',25,C['navy'],680,'middle')
    txt(d,652,623,'通过 PS DDR 控制器访问（片外存储）',16,C['slate'],440,'middle')
    box(d,455,725,395,111,C['white'],'#CABFE6',18)
    txt(d,652,768,'PS GEM0 + PHY',24,C['navy'],700,'middle')
    txt(d,652,805,'以太网 / UDP 发送',18,C['slate'],460,'middle')
    # PL blocks
    box(d,987,357,315,63,C['lightamber'],'#E7C48E',15)
    txt(d,1144,382,'AXI SmartConnect',22,C['navy'],660,'middle')
    txt(d,1144,405,'GP0 → DMA / CTRL / TIME / GPIO',15,C['slate'],420,'middle')
    box(d,986,467,280,104,C['white'],'#B7D7ED',18)
    txt(d,1126,505,'AXI DMA · MM2S',23,C['navy'],680,'middle')
    txt(d,1126,540,'DDR → AXI4-Stream IQ',17,C['slate'],450,'middle')
    box(d,986,641,280,104,C['white'],'#A9D9D5',18)
    txt(d,1126,679,'AXI DMA · S2MM',23,C['navy'],680,'middle')
    txt(d,1126,713,'DIFI Packet → DDR',17,C['slate'],460,'middle')
    box(d,1352,448,335,300,C['white'],'#7FC9C3',20,2.6)
    pill(d,1380,464,278,'PL Protocol Engine',C['lightteal'],C['difi'])
    txt(d,1519,538,'DIFI 1.1 TX',31,C['navy'],760,'middle')
    txt(d,1519,583,'Signal Data Packetizer',18,C['darkgray'],510,'middle')
    txt(d,1519,613,'Context / Version Generator',18,C['darkgray'],510,'middle')
    txt(d,1519,643,'TX Scheduler + AXIS Mux',18,C['darkgray'],510,'middle')
    d.add(d.line(start=(1387,668),end=(1656,668),stroke='#E6ECEF',stroke_width=1.5))
    txt(d,1519,694,'B5：RX 输入关闭',17,C['warn'],600,'middle')
    txt(d,1519,719,'配置和时间源经 AXI4-Lite',16,C['slate'],460,'middle')
    # Data connections - drawn atop boxes so endpoints precise
    line(d,[(850,573),(917,573),(917,519),(985,519)],C['data'],5)
    line(d,[(1267,519),(1350,519)],C['data'],5)
    line(d,[(1351,692),(1268,692)],C['difi'],5)
    line(d,[(985,696),(915,696),(915,624),(852,624)],C['difi'],5)
    # PS CPU -> DDR/PS GEM paths
    line(d,[(650,495),(650,540)],C['muted'],3,False)
    line(d,[(467,493),(432,493),(432,781),(453,781)],C['muted'],3,True)
    # config dotted paths
    line(d,[(851,407),(917,407),(917,383),(985,383)],C['ctrl'],3.4,True,True)
    line(d,[(1093,422),(1093,465)],C['ctrl'],2.7,True,True)
    line(d,[(1298,382),(1333,382),(1333,462),(1350,462)],C['ctrl'],2.7,True,True)
    # network link PC and GEM0
    line(d,[(453,774),(375,774),(338,774)],C['udp'],5)
    # abstract START opposite directional via offset y799
    line(d,[(338,807),(375,807),(453,807)],C['udp'],2.5,True,True)
    txt(d,389,753,'DIFI UDP',15,C['udp'],650,'middle')
    txt(d,388,840,'START',15,C['udp'],500,'middle')
    # Step markers
    step(d,926,520,1,C['data']); step(d,1310,518,2,C['data']); step(d,919,695,3,C['difi']); step(d,404,775,4,C['udp'])
    # Footer
    txt(d,78,945,'实际 BD 连接：PS M_AXI_GP0 → SmartConnect（寄存器）；DMA M_AXI_MM2S / M_AXI_S2MM → PS S_AXI_HP0（DDR 数据）',18,C['slate'])
    txt(d,78,981,'注意：B5 输出的是完整 DIFI 报文，TX→RX 解析回环属于另一套「封装 IP」板级测试工程。',18,C['warn'],570)
    d.save(); export_png(d.filename)

def make_rtl():
    d=base('difi_engine_rtl_architecture.svg',1800,1030)
    heading(d,'DIFI 1.1 — RTL 协议收发引擎内部结构','引擎 TX/RX 通路 + B5 包装层配置/时间模块；B5 UDP 板级工程只连接 TX','模块层级 / RTL')
    legend(d,90,202,[('发送 TX',C['data']),('接收 RX',C['difi']),('配置 / 时间',C['ctrl'])])
    # outer engine
    box(d,65,245,1669,700,C['white'],'#D2DAE7',22,2)
    # TX band
    box(d,96,289,1600,304,'#F3F8FD','#BED8EB',18,1.5)
    pill(d,119,307,155,'TX / 发送',C['lightblue'],C['data'])
    pill(d,1510,307,163,'B5 实际启用',C['lightteal'],C['difi'])
    # TX input IQ
    box(d,117,416,215,109,'#FFFFFF','#AACFE6',15)
    center_title(d,117,450,215,'IQ AXI4-Stream','32-bit 样本输入',21)
    box(d,396,396,236,132,C['white'],'#AACFE6',16)
    center_title(d,396,438,236,'Data Packetizer','IQ → Signal Data',22)
    box(d,690,329,236,74,C['white'],'#AACFE6',15)
    center_title(d,690,374,236,'Context Generator',None,19)
    box(d,690,500,236,74,C['white'],'#AACFE6',15)
    center_title(d,690,545,236,'Version Generator',None,19)
    box(d,1003,397,240,132,'#FFFFFF','#AACFE6',16)
    center_title(d,1003,437,240,'TX Scheduler','选择、复用、背压',22)
    box(d,1360,416,278,109,C['white'],'#AACFE6',15)
    center_title(d,1360,452,278,'M_AXIS_TX_PKT','32-bit DIFI Packet',19)
    line(d,[(334,470),(394,470)],C['data'],5)
    line(d,[(632,465),(1001,465)],C['data'],5)
    line(d,[(926,366),(969,366),(969,435),(1001,435)],C['data'],3.7)
    line(d,[(926,536),(964,536),(964,499),(1001,499)],C['data'],3.7)
    line(d,[(1244,463),(1357,463)],C['data'],5)
    # top control band mid
    box(d,103,612,1590,101,C['lightamber'],'#F0D5A6',15)
    box(d,123,632,346,60,C['white'],'#EAC48B',11)
    center_title(d,123,668,346,'AXI4-Lite CFG (Shadow / Commit)',None,17)
    box(d,538,632,350,60,C['white'],'#EAC48B',11)
    center_title(d,538,668,350,'B5 Wrapper: Time Source (sec/ps)',None,17)
    box(d,959,632,350,60,C['white'],'#EAC48B',11)
    center_title(d,959,668,350,'B5 Wrapper: Periodic Trigger',None,17)
    box(d,1360,632,305,60,C['white'],'#EAC48B',11)
    center_title(d,1360,668,305,'Status & Error Outputs',None,16)
    line(d,[(335,632),(335,573),(515,573),(515,529)],C['ctrl'],2.8,True,True)
    line(d,[(714,632),(714,591),(810,591),(810,574)],C['ctrl'],2.8,True,True)
    line(d,[(1130,632),(1130,532)],C['ctrl'],2.8,True,True)
    # RX path within band
    box(d,95,734,1598,176,'#F1FAF8','#B1DDD8',17,1.5)
    pill(d,116,749,155,'RX / 接收',C['lightteal'],C['difi'])
    pill(d,1497,749,171,'B5 未连接',C['ltgray'],C['muted'])
    box(d,114,799,222,79,C['white'],'#ADD6D2',13)
    center_title(d,114,831,222,'S_AXIS_RX_PKT','DIFI Packet 输入',18)
    box(d,388,799,225,79,C['white'],'#ADD6D2',13)
    center_title(d,388,831,225,'RX Dispatch','按 Packet Type 分流',18)
    box(d,682,765,260,40,C['white'],'#ADD6D2',10)
    center_title(d,682,791,260,'Data Parser',None,18)
    box(d,682,816,260,40,C['white'],'#ADD6D2',10)
    center_title(d,682,842,260,'Context Parser',None,18)
    box(d,682,866,260,40,C['white'],'#ADD6D2',10)
    center_title(d,682,892,260,'Version Parser',None,18)
    box(d,1043,802,270,92,C['white'],'#ADD6D2',13)
    center_title(d,1043,839,270,'IQ / Metadata / Error','AXIS & Sideband',18)
    line(d,[(337,838),(387,838)],C['difi'],4.5)
    line(d,[(614,838),(653,838)],C['difi'],3.5,False)
    line(d,[(653,787),(653,886)],C['difi'],3.3,False)
    line(d,[(653,786),(680,786)],C['difi'],3.4)
    line(d,[(653,837),(680,837)],C['difi'],3.4)
    line(d,[(653,886),(680,886)],C['difi'],3.4)
    line(d,[(943,786),(997,786),(997,821),(1041,821)],C['difi'],3.3)
    line(d,[(943,837),(1041,837)],C['difi'],3.3)
    line(d,[(943,885),(1002,885),(1002,867),(1041,867)],C['difi'],3.3)
    txt(d,1360,836,'另一路工程连接 TX→RX',17,C['slate'],520)
    txt(d,1360,862,'用于封装 IP IQ 回环',17,C['slate'],500)
    # Footer
    txt(d,86,987,'参考：rtl/top/difi_engine_top.v、rtl/data/、rtl/context/、rtl/version/、rtl/tx/、rtl/rx/。模块级示意，非 Vivado 生成的 BD 截图。',17,C['slate'])
    d.save(); export_png(d.filename)

def export_png(svgfile):
    p=Path(svgfile)
    cairosvg.svg2png(url=str(p),write_to=str(p.with_suffix('.png')),output_width=3600,output_height=round(3600*int(p.read_text().split('viewBox="0 0 ')[1].split('"')[0].split()[1])/1800))

if __name__=='__main__':
    make_b5();make_rtl();print('created:',*[str(x) for x in sorted(OUT.iterdir())],sep='\n- ')
