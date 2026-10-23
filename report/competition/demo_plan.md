# DIFI 1.1 FPGA 协议引擎：演示规划与镜头清单

> v0.1；这是**建议的演示流程**，不是赛事正式要求的视频时长。比赛若另行规定时长/格式，应以最新通知为准。建议分别保留“真实硬件现场版”与“已归档证据版”。

## 演示的唯一主线

**让评委看到 IQ 数据确实由 PL 生成 DIFI 报文，PS 通过 AXI DMA 接回完整报文并发 UDP，PC 能解析/比对；同时展示 FPGA 实现、资源优化和工程可复现性。**

必须坚持的事实边界：B5 演示 **TX 原始 Packet 导出**，不连接 RTL RX；封装 IP 的 TX→RX 回环是另一套 BD。**PL 不负责 UDP/IP 协议栈，网络发送运行于 Zynq PS 的 lwIP/GEM0。**

## 建议镜头表（建议录制 7～9 分钟素材，再视赛事要求剪辑）

| 段落 | 建议时段 | 画面/动作 | 评委需要确认的结果 | 已有证据/需要补录 |
|---|---|---|---|---|
| 1. 场景和硬件 | 0:00–0:45 | 板卡、PS 网线、UART、PC 一镜交代；显示两张架构图 | 作品为真实 Zynq-7020 实现，不是纯软件协议演示 | `report/figures/difi_b5_system_architecture.png`；板卡镜头待录 |
| 2. RTL 结构 | 0:45–1:40 | 介绍 TX Data/Context/Version、RX Dispatch/Parser；展示 TB 概览 | FPGA 上的协议逻辑是自己设计的 RTL | `rtl/top/difi_engine_top.v`、`sim/data/`、`sim/top/`、RTL 架构图 |
| 3. 资源优化 | 1:40–2:35 | OOC 优化前后柱状图，解释同步 BRAM 读 | LUT 4,023→1,516，FF 10,446→2,202，RAMB18 增加 1 | `report/figures/difi_ooc_resource_optimization.png`、`report/results/ooc*/utilization.rpt` |
| 4. 时序/RTL 性能 | 2:35–3:20 | 放 Vivado 时序结果 + RTL 100 包延迟图 | 已布线 WNS +0.411 ns；RTL 25,600 IQ 正确；196.916 MB/s 是理想仿真值 | `report/results/packaged_ip_impl/`、`report/figures/difi_rtl_first_iq_latency.png` |
| 5. 封装 IP 板级回环 | 3:20–4:20 | 显示封装 IP BD、Vitis UART 回环测试 PASS | DMA 100 包、25,600 IQ 零失配 | `report/results/perf/board_IP_perf.rtf`；真实 BD 截图及新 XSA UART 需补档 |
| 6. B5 UDP 真机闭环 | 4:20–6:20 | 切换到 B5 Bitstream/Vitis ELF；串口输入 UTC；PC 发 START；Wireshark 捕获；Python PASS | Version×1 / Context×1 / Data×20，共 22 包；5,120 IQ 无失配；PS 发 UDP | `vitis/vitis_ws/difi_b5_udp_tx/src/`、`scripts/verify/tools/difi_udp_receiver.py`、`report/results/udp/tx/screenshots/`；现场录屏待录 |
| 7. 第三方检查 | 6:20–7:10 | 出示 Version 与 Context/Data 的 DIFI 1.1 参考工具 PASS | 独立参考程序所覆盖项目符合预期 | `report/results/udp/tx/consortium/`；强调非官方认证 |
| 8. 可复现与 Skill | 7:10–8:00 | 浏览仓库、BD Tcl、两套 SUCCESS 报告、四个 Skill | 他人可以取走代码/脚本；四 Skill 已制作、统一实测待完成 | `scripts/vivado/`、`report/results/vivado_rebuild/`、`skill/` |

## 录制前物料与环境

- 桌面清理无关文件、账号和聊天；Wireshark 只抓目标有线网卡，关闭包含隐私的流量视图。
- 硬件板卡型号、USB-UART 端口、网线、PC 网卡 IP、开发板 IP、UDP 端口提前确认；必要时关闭影响通信的 VPN/代理。
- **不要互换两个工程的 XSA**：`difi_ip_test_wrapper`（解析 IQ 回环）和 `difi_system_wrapper`（B5 raw Packet）对应不同 Vitis 应用。
- 准备 `START` 触发过程：B5 中串口等待时间加载/发送触发，PC 程序启动前先复位对应 PL 状态。
- 准备“失败时的替代证据”：保留原 UART、PCAP、完整截图，但要标注是“已有实测归档”而非本次录制的实时结果。
- **不要临时展示尚未通过统一验收的 Skill 的“现场成功”**；它们可展示目录结构、工具、用法及当前验证边界。

## 画面素材清单（优先补录）

1. `difi_ip_test` 原生 Vivado BD 的全图与关键连线。
2. B5 `difi_system` 原生 Vivado BD 的全图与 AXI GPIO/PS GEM0 配置。
3. 新 XSA 对应 Vitis 平台和板级 UART 成功日志的同屏镜头。
4. Wireshark 22 包列表，以及 1 Version/1 Context/1 Data 的字段展开镜头（已有四张截图可以再利用）。
5. 第三方参考工具完整命令、版本参数 `--difi-version 1.1`、PASS 结果与文件来源。
6. Github 公开后仓库主页、发行版本 Tag、LICENSE、README “最短复现路径”。

## 录制中的表述禁区

- 不说“DIFI 官方认证”，应说“DIFI Consortium 开源参考程序对本次数据检查通过”。
- 不说“UDP 速度 196.916 MB/s”，那是 RTL 理想回环 IQ 吞吐率。
- 不说“所有 DIFI 标准全部支持”；当前是受限 DIFI 1.1 Profile。
- 不说“4 个 Skill 已完成跨项目测试”；目前制作完成，统一验收尚未进行。
- 不把 B5 原始 Packet 导出当成了封装 IP 的 TX→RX 上板回环。


## B6 v0.2 三类 UDP RX 演示新增镜头（2026-10-23）

切换到 **B6 v0.2** 对应的 bitstream 和 `difi_b6_udp_rx_pro` ELF，PC 运行 `python scripts/verify/tools/difi_b6_three_types.py --board 192.168.1.10 --local-ip 192.168.1.20 --types version,context,data --rounds 20`。展示 PL Metadata Monitor 的 Version/Context 握手各 +1、20 个 Data 的 5,120 IQ Golden 匹配，以及序列号 15→0 回绕。证据：`report/results/udp/rx/three_types_udp_rx.rtf`。B5 与 B6 是不同硬件配置下分别进行的测试，不声称同时全双工。仍待录制同版 Bitstream/ELF 的实机镜头。
