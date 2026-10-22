#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DIFI competition evidence figures.

Use ONLY the source reports/CSV in the target repository. No simulated or random
measurements enter the published charts. Requires Python 3 + matplotlib.

Examples:
 python scripts/figures/build_performance_figures.py
 python scripts/figures/build_performance_figures.py --repo-root D:/Study/project/DIFI --cpu-hz 666666667
"""
import argparse
import csv
import re
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.ticker import FuncFormatter

INK = '#1E2B37'
MUTED = '#62717E'
CYAN = '#007F89'
BLUE = '#2765AE'
GRAY = '#A6B2BD'
LIGHT = '#E8EEF2'
ORANGE = '#BC6A2E'


def setup_font():
    all_fonts = {f.name for f in font_manager.fontManager.ttflist}
    for fam in ('Noto Sans CJK SC', 'Noto Sans CJK JP', 'Microsoft YaHei', 'WenQuanYi Micro Hei', 'SimHei', 'DejaVu Sans'):
        if fam in all_fonts:
            plt.rcParams['font.sans-serif'] = [fam, 'DejaVu Sans']
            break
    plt.rcParams['axes.unicode_minus'] = False
    plt.rcParams['svg.fonttype'] = 'none'  # SVG retains editable text
    plt.rcParams['font.size'] = 11
    plt.rcParams['axes.edgecolor'] = LIGHT
    plt.rcParams['text.color'] = INK
    plt.rcParams['axes.labelcolor'] = INK
    plt.rcParams['xtick.color'] = MUTED
    plt.rcParams['ytick.color'] = MUTED
    plt.rcParams['figure.facecolor'] = 'white'
    plt.rcParams['axes.facecolor'] = 'white'
    plt.rcParams['savefig.facecolor'] = 'white'


def parse_ooc(path):
    rows = path.read_text(encoding='utf-8', errors='replace').splitlines()
    for row in rows:
        if not row.lstrip().startswith('|'):
            continue
        cells = [c.strip() for c in row.strip().strip('|').split('|')]
        if len(cells) >= 10 and cells[0] == 'difi_engine_top' and cells[1] == '(top)':
            return dict(lut=int(cells[2]), ff=int(cells[6]), ramb36=int(cells[7]), ramb18=int(cells[8]), dsp=int(cells[9]))
    raise ValueError(f'Cannot find top-level OOC row: {path}')


def parse_latency(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        records = list(csv.DictReader(f))
    assert len(records) == 100, f'Expected exactly 100 test packets, got {len(records)}'
    idx = [int(x['packet_index']) for x in records]
    lat = [int(x['first_iq_latency_cycles']) for x in records]
    assert idx == list(range(100)), 'Packet index gaps or reordering'
    assert min(lat) == 266 and max(lat) == 519 and sum(lat) / len(lat) == 516.47, 'Latency dataset differs from archived test summary'
    return idx, lat, records


def parse_board(path):
    text = path.read_text(encoding='utf-8', errors='replace')
    def get(s):
        match = re.search(re.escape(s) + r'=(\d+)', text)
        if not match:
            raise ValueError(f'Missing {s} in board log {path}')
        return int(match.group(1))
    def ticks(s):
        match = re.search(re.escape(s) + r'_hi=(\d+)\s+lo=(\d+)', text)
        if not match:
            raise ValueError(f'Missing tick pair {s} in board log {path}')
        return (int(match.group(1)) << 32) + int(match.group(2))
    all_ticks = ticks('total_wall_ticks')
    dma_ticks = ticks('summed_dma_ticks')
    bytes_ = get('iq_payload_bytes')
    assert (all_ticks, dma_ticks, bytes_) == (2729306, 636916, 102400), 'Board logfile differs from reference experiment'
    return all_ticks, dma_ticks, bytes_


def verify_udp(path):
    t = path.read_text(encoding='utf-8', errors='replace')
    assert re.search(r'22\s*个\s*DIFI Packet', t), 'UDP result packet count not found'
    assert re.search(r'5,?120\s*个\s*IQ', t), 'UDP result IQ count not found'
    assert '21,192' in t and '失配数为 0' in t, 'UDP payload or mismatch count not found'


def finish(fig, root, name):
    fig.savefig(root / (name + '.svg'), bbox_inches='tight', pad_inches=0.23)
    fig.savefig(root / (name + '.png'), bbox_inches='tight', pad_inches=0.23, dpi=240)
    plt.close(fig)


def header(fig, title, subtitle):
    fig.text(0.055, 0.945, title, ha='left', va='top', fontsize=19, fontweight='bold', color=INK)
    fig.text(0.055, 0.872, subtitle, ha='left', va='top', fontsize=10.3, color=MUTED)


def resource_chart(root, before, after):
    fig, axs = plt.subplots(1, 2, figsize=(13.2, 5.25))
    fig.subplots_adjust(left=0.095, right=0.95, top=0.72, bottom=0.20, wspace=0.24)
    header(fig, '综合资源优化｜寄存器缓存改为 BRAM 同步读', '同一统计口径：difi_engine_top · Vivado 2024.2 · XC7Z020 · OOC Synthesis')
    for ax, (name, field, unit) in zip(axs, [('逻辑查找表', 'lut', 'LUT'), ('触发器', 'ff', 'FF')]):
        x, y = before[field], after[field]
        ax.barh([1, 0], [x, y], color=[GRAY, CYAN], height=0.48)
        ax.set_yticks([1, 0], ['优化前', '优化后'])
        ax.set_title(f'{name}（{unit}）', loc='left', fontsize=12, pad=15, fontweight='bold')
        ax.set_xlim(0, x * 1.22)
        ax.grid(axis='x', alpha=.4, color=LIGHT)
        ax.set_axisbelow(True)
        ax.spines[['top', 'right', 'left']].set_visible(False)
        ax.tick_params(axis='y', length=0)
        ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f'{v:,.0f}'))
        for ypos,val in [(1,x),(0,y)]:
            ax.text(val + x * .022, ypos, f'{val:,}', va='center', fontsize=11, fontweight='bold', color=INK)
        reduced = (1-y/x)*100
        ax.text(.52, 1.06, f'减少 {reduced:.2f}%', transform=ax.transAxes, color=CYAN, ha='left', fontsize=11.6, fontweight='bold')
    fig.text(.055, .105, f'RAMB18：{before["ramb18"]} → {after["ramb18"]}    |    DSP：{before["dsp"]} → {after["dsp"]}', fontsize=11, weight='bold', color=INK)
    fig.text(.055, .050, '来源：report/results/ooc/utilization.rpt；report/results/ooc_new/utilization.rpt。综合数据，非实现后完整 PL 资源。', fontsize=9.2, color=MUTED)
    finish(fig, root, 'difi_ooc_resource_optimization')


def latency_chart(root, idx, lat):
    fig, ax = plt.subplots(figsize=(13.2, 5.35))
    fig.subplots_adjust(left=.095, right=.95, top=.74, bottom=.22)
    header(fig, 'RTL 回环｜首个 IQ 样本的端到端延迟', '100 包 × 256 IQ/包 · AXI4-Stream 32-bit · 100 MHz · TX Packet 直接回接 RX Packet · 无外部背压')
    ax.plot(idx,lat,lw=2.5,color=BLUE,zorder=2)
    ax.scatter(idx,lat,s=14,color=BLUE,zorder=3)
    ax.scatter([0],[lat[0]],s=75,color=ORANGE,zorder=4)
    avg=sum(lat)/len(lat)
    ax.axhline(avg,color=CYAN,ls='--',lw=1.7,alpha=.8,label=f'平均 {avg:.3f} cycles')
    ax.annotate('首包 266 cycles',xy=(0,266),xytext=(8,330),arrowprops=dict(arrowstyle='->',color=ORANGE,lw=1.4),color=ORANGE,fontweight='bold',fontsize=11)
    ax.annotate('后续 99 包：519 cycles',xy=(80,519),xytext=(46,465),arrowprops=dict(arrowstyle='->',color=BLUE,lw=1.3),color=BLUE,fontweight='bold',fontsize=11)
    ax.set_xlim(-2, 103); ax.set_ylim(220,560)
    ax.set_xlabel('Packet index（从 0 开始）'); ax.set_ylabel('首 IQ 延迟（cycles）')
    ax.grid(alpha=.5,color=LIGHT)
    ax.spines[['top','right']].set_visible(False)
    ax.legend(loc='lower right',frameon=False)
    fig.text(.055,.095,'最小 266 cycles（2.660 μs）  ·  平均 516.470 cycles（5.165 μs）  ·  最大 519 cycles（5.190 μs）',fontsize=11,weight='bold')
    fig.text(.055,.047,'来源：report/results/perf/difi_perf_latency.csv；延迟定义：首个输入 IQ 握手 → 首个输出 IQ 握手。',fontsize=9.4,color=MUTED)
    finish(fig,root,'difi_rtl_first_iq_latency')


def throughput_chart(root, rtl_mbps, dma_mbps, board_mbps, cpu_hz):
    fig, ax = plt.subplots(figsize=(13.2, 5.5))
    fig.subplots_adjust(left=.095, right=.95, top=.72, bottom=.245)
    header(fig, 'IQ 有效吞吐率｜三个不同测量窗口', '数值仅用于说明不同测试口径：不能将其差值解释为单纯的 PL 核心性能损失')
    vals=[rtl_mbps,dma_mbps,board_mbps]
    names=['RTL 理想直接回环', '板级 DMA 事务窗口', '板级完整软件窗口']
    bars=ax.barh([2,1,0],vals,color=[BLUE,CYAN,GRAY],height=.53)
    ax.set_yticks([2,1,0],names);ax.set_xlim(0,max(vals)*1.30)
    ax.set_xlabel('IQ payload MB/s（十进制；1 MB = 10^6 B）')
    ax.grid(axis='x',color=LIGHT);ax.set_axisbelow(True)
    ax.spines[['top','right','left']].set_visible(False);ax.tick_params(axis='y',length=0)
    for b,v in zip(bars,vals):
        ax.text(v+max(vals)*.028,b.get_y()+b.get_height()/2,f'{v:.2f} MB/s',va='center',weight='bold',fontsize=12)
    fig.text(.055,.126,'RTL：52,002 PL cycles @100 MHz  |  DMA：636,916 PMU ticks  |  系统：2,729,306 PMU ticks',fontsize=10.1,weight='bold')
    fig.text(.055,.071,f'板级换算以 PS CPU ≈ {cpu_hz/1e6:.3f} MHz 且 PMU 每 CPU 周期递增 1 为前提；需归档对应 PS 时钟设置证据。',fontsize=9.7,color=ORANGE)
    fig.text(.055,.027,'UDP 测试存在人为约 2 ms/包的节流，不纳入吞吐率横向比较。',fontsize=9.5,color=MUTED)
    finish(fig,root,'difi_throughput_measurement_scopes')


def validation_chart(root):
    fig, ax=plt.subplots(figsize=(13.2,5.5))
    fig.subplots_adjust(left=.20,right=.93,top=.73,bottom=.33)
    header(fig,'多层验证证据｜三条独立测试链路','图示为已校验 IQ 样本数量，不代表吞吐率或持续稳定性；不同链路的测试输入规模不完全相同')
    samples=[25600,25600,5120]
    names=['RTL 理想收发回环','Zynq DMA 封装 IP 回环','B5 UDP 到 PC']
    bar=ax.barh([2,1,0],samples,color=[BLUE,CYAN,GRAY],height=.50)
    ax.set_xlim(0,33000);ax.set_yticks([2,1,0],names)
    ax.set_xlabel('经黄金数据比对的 IQ 样本数量')
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v,_:f'{v:,.0f}'))
    ax.spines[['top','right','left']].set_visible(False);ax.tick_params(axis='y',length=0)
    ax.grid(axis='x',color=LIGHT);ax.set_axisbelow(True)
    for y,val in zip([2,1,0],samples):
        ax.text(val+450,y,f'{val:,} IQ · 0 失配',va='center',weight='bold',fontsize=10.8,color=INK)
    fig.text(.055,.165,'第三方参考工具：DIFI 1.1 模式下 1 Version / 1 Context / 20 Data 均 PASS（非正式认证）',fontsize=10.4,color=INK,weight='bold')
    fig.text(.055,.107,'B5 UDP：22 包 / 21,192 B UDP payload / 5,120 IQ；人为设置约 2 ms 发包间隔，不主张 UDP 最大速率。',fontsize=9.5,color=MUTED)
    fig.text(.055,.044,'来源：RTL latency CSV、板级 PMU/回环日志、report/results/udp/validation_notes.md 及 Consortium 检查记录。',fontsize=9.1,color=MUTED)
    finish(fig,root,'difi_multilayer_validation_evidence')


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo-root',type=Path,default=Path(__file__).resolve().parents[2],help='DIFI repository root')
    ap.add_argument('--output',type=Path,default=None,help='figure output directory (default <repo>/report/figures)')
    ap.add_argument('--cpu-hz',type=int,default=666666667,help='PS CPU Hz reported by project owner; used with PMU ticks')
    args=ap.parse_args()
    root=args.repo_root.resolve()
    out=(args.output or root/'report'/'figures').resolve()
    assert args.cpu_hz>0, 'cpu-hz must be positive'
    before=parse_ooc(root/'report/results/ooc/utilization.rpt')
    after=parse_ooc(root/'report/results/ooc_new/utilization.rpt')
    assert (before['lut'],before['ff'],before['ramb18'])==(4023,10446,0), 'OOC pre-optimization baseline differs'
    assert (after['lut'],after['ff'],after['ramb18'])==(1516,2202,1), 'OOC post-optimization baseline differs'
    idx,lat,records=parse_latency(root/'report/results/perf/difi_perf_latency.csv')
    assert (int(records[0]['first_input_cycle']),int(records[-1]['last_output_cycle']))==(85,52086), 'RTL measurement boundary changed'
    rtl_ticks=int(records[-1]['last_output_cycle'])-int(records[0]['first_input_cycle'])+1
    assert rtl_ticks == 52002
    payload_bytes=100*256*4
    rtl_mbps=payload_bytes*1e8/rtl_ticks/1e6
    wall,dma,board_bytes=parse_board(root/'report/results/perf/board_IP_perf.rtf')
    verify_udp(root/'report/results/udp/validation_notes.md')
    dma_mbps=board_bytes*args.cpu_hz/dma/1e6
    board_mbps=board_bytes*args.cpu_hz/wall/1e6
    out.mkdir(parents=True,exist_ok=True)
    setup_font()
    resource_chart(out,before,after)
    latency_chart(out,idx,lat)
    throughput_chart(out,rtl_mbps,dma_mbps,board_mbps,args.cpu_hz)
    validation_chart(out)
    for name in ['difi_ooc_resource_optimization','difi_rtl_first_iq_latency','difi_throughput_measurement_scopes','difi_multilayer_validation_evidence']:
        print('[PASS]', name, 'svg/png')
    print(f'[VALUES] LUT {before["lut"]}->{after["lut"]}; FF {before["ff"]}->{after["ff"]}; RAMB18 {before["ramb18"]}->{after["ramb18"]}')
    print(f'[VALUES] RTL throughput={rtl_mbps:.3f} MB/s, latency={sum(lat)/len(lat):.3f} cycles')
    print(f'[VALUES] DMA_window={dma_mbps:.3f} MB/s, board_system={board_mbps:.3f} MB/s (conditional PS clock)')
    return 0

if __name__=='__main__':
    try:
        sys.exit(main())
    except (AssertionError,ValueError,FileNotFoundError,KeyError) as exc:
        print('[FAIL]',exc,file=sys.stderr)
        sys.exit(1)
