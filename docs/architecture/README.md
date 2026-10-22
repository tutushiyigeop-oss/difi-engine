# DIFI 1.1 竞赛架构图与源码依据

本目录保存 README 可以直接渲染的 Mermaid 源码，正式矢量图位于 `../../report/figures/`。

| 图示 | 正式矢量图 | 高清 PNG | 用途 |
| --- | --- | --- | --- |
| B5 板级端到端系统 | [SVG](../../report/figures/difi_b5_system_architecture.svg) | [PNG](../../report/figures/difi_b5_system_architecture.png) | 报告系统架构、README、演示 PPT |
| RTL 协议收发架构 | [SVG](../../report/figures/difi_engine_rtl_architecture.svg) | [PNG](../../report/figures/difi_engine_rtl_architecture.png) | 报告原理、软件硬件职责及模块划分 |

## 与真实工程的映射

**B5 原始报文导出工程**：Block Design `difi_system`，顶层 `difi_system_wrapper`，Module Reference `difi_board_raw_packet_export`（源码 `rtl/board/difi_engine_board_b5.v`）。

- PS 通过 `M_AXI_GP0` 和 AXI SmartConnect 访问 DMA 的 AXI4-Lite 寄存器、DIFI `S_AXI_CTRL` 和 `S_AXI_TIME`，另有 AXI GPIO 调试接口。地址请以 `scripts/vivado/generated/b5_raw_export/bd.tcl` 为准：DMA `0x40400000`、DIFI 控制 `0x40000000`、时间配置 `0x40001000`、GPIO `0x41200000`。
- DMA 的 `M_AXI_MM2S` 和 `M_AXI_S2MM` 经 AXI Interconnect 访问 PS `S_AXI_HP0`，由 PS DDR 控制器连接板载片外 DDR3。DMA 为 **Simple Mode（非 Scatter-Gather）**。
- `M_AXIS_MM2S` 连接包装层 `S_AXIS_IQ`；包装层 `M_AXIS_PKT` 连接 `S_AXIS_S2MM`。**S2MM 捕获完整 DIFI Packet，而非解码后的 IQ。**
- PS 端的 Standalone C 程序执行 DMA/缓存/时间寄存器操作，经 **GEM0 + lwIP** 使用 UDP 端口 4991 发送到 PC。网络接口并非 PL 内的 UDP IP 核。
- B5 包装层将 `difi_engine_top` 的 RX AXIS `s_axis_rx_pkt_tvalid` 固定为 `1'b0`。图中的 RX 路径表达通用协议引擎能力，但**未在这套 B5 BD 中连接**。
- 另一套 `difi_ip_test` / `difi_ip_test_wrapper` 封装 IP 工程使用 PL TX→RX 自回环，S2MM 取回的是解包后的 IQ；请勿与 B5 的数据路线混淆。

**完整协议引擎**：`rtl/top/difi_engine_top.v`，TX 由 Data Packetizer、Context Generator、Version Generator 和 TX Scheduler 构成；RX 由 RX Dispatch 和 Data/Context/Version Parser 构成。时间源 `difi_time_source` 与周期触发发生器是 **B5 包装层** 内的辅助模块，不是 `difi_engine_top` 内部实例。

## 图示证据与限制

1. 连接及寄存器映射已依据 GitHub `feature/rtl-integration` 分支中的 `scripts/vivado/generated/b5_raw_export/bd.tcl` 和对应顶层 RTL 核对。
2. 现有板级证据保存在 `report/results/udp/validation_notes.md`：共 22 个 UDP DIFI Packet，21,192 字节 UDP 有效载荷，5,120 个 IQ 样本比对正确；第三方参考工具检查并非正式 DIFI 认证。
3. 图示是**人工排版、源码核对的逻辑架构图**，不是 Vivado 原生 BD Screenshot。正式报告仍应另外保留原生 BD 截图和 DIFI UDP Wireshark 截图。
4. 线条省略中间 AXI Interconnect、PHY 引脚、Clock/Reset、驱动与硬件内部细节，并非可以直接照图生成网表的严格电气连线图。

## 再生成图形

在项目根目录执行：

```powershell
python scripts/figures/build_architecture_figures.py
```

需要 `svgwrite`；PNG 导出还需要 `cairosvg`。不建议把 SVG 转为低分辨率 JPG 再插入报告。可以直接插入 SVG，或使用已导出的 3600 像素宽 PNG。

## 在仓库根 README 中引用

```markdown
![DIFI B5 UDP 系统架构](report/figures/difi_b5_system_architecture.svg)

B5 数据通路：DDR IQ → AXI DMA MM2S → PL DIFI TX → AXI DMA S2MM（完整报文）→ PS DDR / lwIP → GEM0 UDP → PC。此 BD 不包含 TX→RX 解析回环。
```
