# DIFI 自主选题竞赛演示讲解稿（Dashboard 实机版）

> 2026-10-23 更新。以下为**拟录制口播稿**，不是已经录制的画面。按 `demo_plan.md` 先录 B5/B6 的 Live 实机画面再剪辑；时间仅为建议，不代表官方提交要求。

## 1. 开场及系统介绍（约 40 秒）

“我们的作品是面向数字中频数据互操作场景的 DIFI 1.1 FPGA 协议收发引擎，运行在 AMD Zynq-7020 平台上。DIFI 三类报文的生成和解析主要由 PL 侧 Verilog RTL 实现，PS 侧负责配置、AXI DMA 数据搬运和 lwIP UDP 通信。PC 端的 DIFI Engine Control Center 将实际网络验证结果可视化，展示协议报文、序列号、IQ 校验和硬件数据路径。”

“我们当前实现的是受限 DIFI 1.1 Profile，不声称支持全部 VITA 49.2 扩展功能。”

## 2. RTL 结构、资源与定量结果（约 50 秒）

“RTL 核心分别提供 AXI4-Stream IQ 输入、DIFI TX Packet 输出、DIFI RX Packet 输入和 IQ 输出，外加 AXI4-Lite 控制接口，收发模块可独立复用。我们对接收报文缓存的存储结构进行了优化，使其适合推断 Block RAM。在同一 OOC 综合口径下，LUT 从 4,023 降到 1,516，FF 从 10,446 降到 2,202。”

“100 MHz 的理想 RTL 测试覆盖 100 个 Packet 和 25,600 个 IQ 样本，计算的有效 IQ 吞吐率为 196.916 MB/s。这个数字属于仿真条件，不是实际以太网 UDP 吞吐率。”

## 3. B5：FPGA 生成并通过 UDP 发送 DIFI Packet（约 100 秒）

（镜头拍板卡、B5 启动串口 UTC、Dashboard B5 Live，然后切入 GUI 运行。）

“首先演示 B5 UDP TX。这里的 FPGA TX 引擎接收 IQ，输出包含 DIFI 协议头与 Payload 的 Packet。Zynq PS 通过 AXI DMA 获取完整报文，使用 lwIP 将其发送到 PC。现在界面选择的是 **B5 UDP TX / Live Hardware**，不是模拟回放。”

“标准测试发送 1 个 Version、1 个 Context、20 个 Data Packet，共 22 包、5,120 个 IQ 样本。界面上的逐包 Timeline、统计和波形来自 PC 真正收到并校验的报文。我们同时可以通过 Wireshark 检查报文结构；DIFI Consortium 的开源参考检查工具针对已归档的 B5 测试流在 1.1 模式下返回 PASS，但这不代表官方认证。”

（等待真实测试完成，拍清楚界面 PASS、Packet Summary、IQ Waveform。）

## 4. B6：PC 发送报文由 FPGA 接收解析（约 100 秒）

（切到板卡实景，明确展示更换 B6 硬件配置及 `difi_b6_udp_rx_pro` 程序，再展示 Dashboard B6 Live。）

“接下来切换到**独立的 B6 硬件设计**，方向与刚才相反：PC 通过 UDP 发送三类 DIFI Packet，PS 将 UDP Payload 通过 DMA 送入 FPGA RX Parser。”

“Version、Context 依靠 PL Metadata 握手和板端状态检查验证；Data 在 FPGA 内解包得到 IQ，再通过 DMA 回到 PS，由板端软件做 Golden 对比。Dashboard 根据真正的板卡 STATUS 和 ACK 更新验证结果。”

“这里的 B6 IQ 曲线明确标记为 **Golden Reference**，因为当前 ACK 返回的是 FPGA 内部校验结论，并不会把完整 IQ 波形原样通过 UDP 返回 PC。两种方向都已完成实体板上的 GUI 现场运行验证，但它们属于两套分别测试的 XSA，并不是持续同时全双工。”

（拍清楚真实 ACK、类型统计、Sequence Timeline 和完成状态。）

## 5. 独立重建、Skill 与结尾（约 70 秒）

“为了支持工程复现，我们把封装 IP 回环、B5 UDP TX 和 B6 UDP RX 三套真实 Vivado Block Design 都导出为 Tcl 快照，再在新工程中完成综合、实现、时序和 Bitstream/XSA 生成，并进行了对应板级回归。”

“项目还沉淀了 Vivado 重建、Zynq DMA 调试、AXI4-Stream 验证与 UDP Packet 校验四套 Skill。我们将原 FPGA 项目中已经验证的流程，与通用 Skill 后续验收范围分别记录，避免把离线测试当成完整板级认证。”

“通过这套系统，我们实现了从 FPGA 协议逻辑、SoC 数据通路、真实网络验证到 PC 可视化和工程再构建的一条完整开发验证链。”

## 录制检查

- 画面中的完成状态必须与现场真实执行结果相符，禁止在报错时照读 PASS 台词。
- 如果从已归档 Wireshark / DIFI 参考工具视频或截图中取材，应说明是已归档的历史实测证据。
- 口播不宣称 Dashboard 允许任意编辑 IQ/Packet、全双工同时工作或已经实现高吞吐持续流。
- 具体时长与成片形式最后根据大赛最新正式公告调整。
