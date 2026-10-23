# DIFI FPGA 协议引擎：Dashboard 主导的比赛演示方案

> 修订日期：2026-10-23 · 版本：v0.2 · **执行方案，不是赛事时长/格式要求**。正式剪辑时长必须以当期赛事官方通知为准。
>
> 前置事实：开发者已确认 B5 UDP TX、B6 UDP RX 两种 Dashboard **Live / Hardware** 模式在实体板上成功运行。尚未提供这次 UI 录屏素材，本文件不得用 Replay 截图代替实机视频。

## 一、核心故事线

**自研 FPGA DIFI 1.1 协议 TX/RX → Zynq PS/PL + DMA → 真实 UDP 网络 → PC Dashboard 逐包解析、可视化及校验 → Vivado 可复现构建。**

B5、B6 分别使用**不同 Vivado BD/XSA、Bitstream 和 Vitis ELF**，只能先后切换，**不是同时全双工**。UDP/IP/Ethernet 由 PS lwIP 实现，PL 内是 DIFI 协议引擎。当前 Dashboard **不是任意 IQ/Packet 编辑器**，而是对接两个经过测试的固定验证脚本。

## 二、建议的最终视频：约 6–8 分钟

| 段落 | 参考时段 | 必须拍到的真实内容 | 目的 |
|---|---|---|---|
| 1. 实体平台与系统介绍 | 00:00–00:40 | Zynq-7020、PC、有线以太网、串口；Dashboard 首页；简要 TX/RX 架构图 | 证明这是实际 FPGA/SoC 系统而不是单纯网页动画 |
| 2. FPGA 引擎与设计贡献 | 00:40–01:30 | `rtl/top/difi_engine_ip.v` 中四个 AXIS 接口、TX Scheduler/RX Parser 架构图；BRAM 优化对比 | 让评委认识独立 RTL 协议 IP |
| 3. B5 真实 TX 演示 | 01:30–03:10 | 先展示 B5 板卡 UART UTC 初始化 / WAIT START；Dashboard 选 `B5 UDP TX + Live / Hardware`，点击 Run；动态拓扑、22 包 Timeline、5120 IQ 波形与 PASS | FPGA TX 生成 Packet → PS UDP → PC 真实接收 |
| 4. B5 抓包第三方检查 | 03:10–03:55 | Wireshark 中 Version/Context/Data 三类 Packet；已存证据中的 DIFI Consortium 开源参考工具 `--difi-version 1.1` PASS | 独立验证已实现 Profile 内的字段 |
| 5. B6 真实 RX 演示 | 03:55–05:30 | 明确镜头切换 B6 Bitstream 和 `difi_b6_udp_rx_pro` ELF；Dashboard 选择 `B6 UDP RX + Live / Hardware`，Run；STATUS/ACK、Version/Context/Data Timeline 和 IQ 验证 5120 | PC → PS UDP → FPGA RX Parser → PS Golden 对比 |
| 6. 工程可复现性与成果总结 | 05:30–06:30 | 三套 BD Tcl、三套 SUCCESS 实现报告、三套 WNS；四个 Skill 目录和适用范围；总结支持边界 | 展示工程化能力，不只展示 UI |
| 7. 结尾可裁剪 | 06:30–07:00 | B5/B6 Live 完成截图并排展示，显示 Version/Context/Data、IQ 样本和结果 | 强化双方向分别验证、交付完整 |

建议先拍**未经剪辑的完整 B5/B6 Live 素材**，再剪辑短视频。屏幕录制中 `LIVE / HARDWARE` 字样应清楚可见，并至少短暂展示板卡与运行环境；不要仅使用 Replay 演示镜头。

## 三、录制前准备与操作顺序

1. 固定当前已通过测试的 `feature/rtl-integration` 工作副本（先确认 `git status` 干净），不在录制当天临时改 RTL/Vitis 或重装依赖。
2. Windows 有线网卡、Zynq 板端地址与 UDP 端口按现场实测参数设置；默认常见配置为 PC `192.168.1.20`、板卡 `192.168.1.10`、UDP `4991`，必须以实际网络为准。
3. 用 `python dashboard/main.py` 启动应用；确认不会误用 `Replay / Offline`；准备屏幕录制和同步拍摄实体板卡的方式。
4. **先录 B5**：下载 B5 硬件、启动其 Vitis ELF，串口配置 UTC，并确认进入 WAIT START；在 Dashboard 切换 `B5 UDP TX` 与 `Live / Hardware` 后点击 Run。B5 原程序是一次性流程，重复拍摄通常需重新启动板端应用并再次配置 UTC。
5. B5 完成后可以补拍 Wireshark。抓包与第三方检查如使用历史归档结果，在画面中明确“此前真实测试归档”，不要伪装成与此刻 Dashboard 同一次抓包。
6. **然后录 B6**：明确重新加载 B6 v0.2 Bitstream / XSA 对应 Vitis 程序 `difi_b6_udp_rx_pro`。在 Dashboard 切换 B6 Live 并 Run，显示真实 STATUS/ACK 及三类 Packet PASS。B6 计数可能延续前一次测试，Sequence 不必从 0 开始。
7. 依次截取 B5/B6 两张 Live 界面完成图；如需演示离线 Replay，必须明确展示其显著的模拟标签，不能用于证明上板通过。
8. 最后收录 RTL 架构图、OOC 优化图、Vivado WNS 与工具归档；这些属于已有工程报告，不需要重新跑实现。

## 四、必须保留或核对的镜头/素材

- 两段来自**真实开发板**的 Dashboard B5 Live 和 B6 Live 完整运行视频；如可能，在开始或结尾展示对应 UART/程序标识。
- Dashboard 界面的 Packet Summary、Timeline、IQ Verification、日志和运行来源标签特写。
- B5：真实收到的 Packet 与 I/Q 波形；B6：实际 ACK 验证结果，以及图上 **Golden Reference / NOT FPGA returned IQ** 标注。
- 至少一张真实 Vivado BD 全图（B5/B6 系统不同），支持展示两种硬件连接差异。
- 既有 `report/results/udp/tx/screenshots/` Wireshark 截图和开源 DIFI 检查结果。
- `report/figures/` 中 RTL、优化及性能证据图；`report/results/vivado_rebuild/` 中各工程 SUCCESS 报告。
- 四个 Skill 的 README/示例/测试结果，避免把尚未验收的通用部分说成全部跨项目完成。
- 录制完毕后将可发布的视频/截图放进后续确定的交付位置；大文件可以保留独立素材盘，不强制推入 Git 历史。

## 五、准确性与剪辑原则

- B5 UDP TX、B6 UDP RX 是**分别切换硬件镜像**的两次成功测试，不称“同一 XSA 实时全双工”。
- B6 的 IQ 曲线是 Golden Reference，不称 FPGA 实时返回的原始 IQ 波形；板卡 ACK 确认内部 256 样本/包 Golden 比对。
- `196.916 MB/s` 是 **100 MHz 理想 RTL 回环 IQ 吞吐**，不称真实 UDP 速率；B6 的逐包 ACK 也不是带宽压力测试。
- DIFI Consortium 开源脚本对所选 B5 抓包通过，不意味着正式 DIFI 认证或支持全部可选 Profile。
- GUI 的 Replay 是模拟样例；B5/B6 Live 才是这次已通过的硬件可视化路径。
- 视频不允许通过剪辑重排时间顺序来冒充连续实时全双工；剪辑应使用“切换 B6 工程”字样明确解释镜像更换。
- 打码用户名、学号、密钥、账号、PC 网络隐私信息；不要为掩盖错误而删除技术结论所依赖的上下文。

## 六、录制状态

- [x] Dashboard B5 Live 实机可用——开发者于 2026-10-23 确认。
- [x] Dashboard B6 Live 实机可用——开发者于 2026-10-23 确认。
- [ ] B5 Live 完整实机演示视频录制。
- [ ] B6 Live 完整实机演示视频录制。
- [ ] 两套硬件对应的 BD 画面与 UI 完成截图整理。
- [ ] 技术图、第三方参考检查、Skill 介绍素材合成。
- [ ] 按实际赛事时长和提交要求剪辑、审核、导出成片。
