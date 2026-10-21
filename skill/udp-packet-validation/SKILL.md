---
name: udp-packet-validation
description: >-
  对 FPGA/Zynq 经 PS lwIP UDP 输出到 PC 的报文进行可复现的接收、抓包、
  逐包顺序/长度/黄金数据校验、PCAP 过滤与第三方协议工具交叉验证。
  提供不依赖 DIFI 的通用工具，并以 DIFI 1.1 B5 工程为实测案例。
---

# UDP 数据链路端到端验证 Skill

## 何时调用

- PL 产生报文，经 DMA/DDR、Zynq PS lwIP 发送 UDP 到 PC，需要证明 PC 实际收到**正确的应用负载**。
- 发送端报告 `udp_sendto` 成功，但接收端丢包、长度不对、字节序不对、数据错位或 Sequence 不连续。
- 需要保存可审计的 PCAP、原始 UDP 负载、黄金参考和第三方协议检查证据。
- 大模型要帮助诊断链路故障，必须能给出**可操作的最小验证**而非仅猜测网络设置。

**不适用于**：需要保证 UDP 可靠送达/重传的系统、RTT 精确测试、长期压力测试、真实线速测试、IP Fragment 重组、IPv6/SCTP/TCP，或证明第三方正式协议认证。

## 输入与环境

1. 确认网络拓扑、板卡/PC IP、监听端口、BSP/lwIP 模式、期望报文数及长度，尤其说明报文是**原始二进制还是本机小端 u32**。
2. 发送程序和接收程序需来自可信仓库；不要无授权向未知网络设备发送 START/控制命令。
3. 可选 Wireshark/TShark 抓包；本包自身离线分析采用 Python 3 **标准库**，不需要 Scapy。
4. 已有 `.pcapng` 时，通过 Wireshark 导出经典 `.pcap` 或使用 TShark 转换。工具读取的是 Ethernet/IPv4/UDP 的经典 PCAP（支持至多两层 VLAN），**不直接读取 pcapng**。
5. 配置两类验证器：`udp_validate.py` 面向一般 UDP 二进制协议；`difi_b5_validate.py` 只适用于本项目特定 DIFI B5 测试向量。

## AI 逐层验证工作流

1. **确定发送端合同**：从 RTL、PS 软件确认字节序、报文头长度、Payload、SID/序列号、包长与 START 行为；绝不假定发送端 `udp_sendto()` 成功就说明 PC 已接收。
2. **先确认 IP/端口**：板卡 IP、PC NIC IP、掩码、端口、防火墙、板卡 UART、PC socket 实际绑定地址；有需要检查 ARP，禁止从“Wireshark 没有显示”立即推断 RTL 错误。
3. **PC 捕获且保留原件**：建议同时保存 `.pcapng` 原始抓包和 PC 端应用负载 `.bin`。PCAP 应包含源/目的地址，二进制录制文件只包含四字节长度前缀与 UDP payload。
4. **离线检查与对照**：用黄金参考检查包数、长度、顺序、字节序及 Payload 内容。任何零匹配/短包/丢包必须 FAIL，不能把部分正确自动算 PASS。
5. **第三方交叉验证**：有正式公开参考工具时，使用原版并明确版本；DIFI 案例用 Consortium `certify_source.py --difi-version 1.1`，须按流分开并记录局限。
6. **故障注入回归**：改动测试文件的顺序、某一字节、长度或 SID，要求离线校验失败；保持原始抓包只读，禁止改写真实证据来制造“通过”。
7. **量化报告**：记录每包大小、接收数、IQ 数、失配数、IP/软件/时钟参数。人为 2 ms 包间隔时不得把字节数除以录制窗口宣称为网络最大吞吐率。
8. **分级验收**：L1 离线工具自检；L2 通用工具在真实抓包上检查通过；L3 真实 FPGA→PC 全链路复测；L4 第三方工具另行通过。每一层独立陈述。

## 直接命令

从仓库根目录运行：

```powershell
# 离线测试（本 Skill）
python -m unittest discover -s skill/udp-packet-validation/tests -v

# PC 端已捕获的 22 包二进制（只检查 DIFI B5 特定向量）
python skill/udp-packet-validation/scripts/difi_b5_validate.py `
  --capture-bin report/results/udp/difi_udp_capture.bin

# 真实 Ethernet PCAP（仅当已经转换成 classic PCAP）
python skill/udp-packet-validation/scripts/difi_b5_validate.py `
  --pcap report/results/udp/difi_b5_udp_22.pcap `
  --src-ip 192.168.1.10 --dst-ip 192.168.1.20 --dst-port 4991
```

若仓库中只有 `.pcapng`，先转换；请勿凭空假定上面示例文件存在。通用配置示例见 [README](README.md)。

## 四种核心交付能力

- `scripts/udp_capture.py`：仅在显式指定 `--trigger-host` 时发送一次控制报文；其余时间监听并保存到长度前缀二进制。用于任何简单 UDP 应用数据流。
- `scripts/udp_pcap.py` + `scripts/udp_validate.py`：从 Ethernet IPv4 UDP 经典 PCAP/长度前缀 `.bin` 解析与匹配，根据 JSON Profile 检查数量、长度、起始序列字段、可选黄金负载。
- `scripts/difi_b5_validate.py` + `scripts/split_difi_pcap.py`：固定 DIFI 1.1 B5 测试向量完整检查及按 Version/Context+Data Stream ID 分流；**不是通用 DIFI 标准验证器**。
- `tests/`：生成**合成** Ethernet PCAP/二进制正反例，完成离线回归。产生的样例文件不是 FPGA 实测输出。

## 错误与排查边界

| 观察到的情况 | 首先核实什么 | 不得直接推断什么 |
|---|---|---|
| UART 显示发送成功，PC 收不到 | `START`、GEM0/PHY、PC 网卡绑定、防火墙、ARP、端口、接收脚本启动顺序 | PL 报文一定正确送达 |
| 字节序与 Word0 不符 | `u32` 从 DDR 拷贝到 `pbuf` 前是否按网络大端序拆字节 | 改写协议标准的字段定义 |
| 22 包少一包 | PCAP 是否含启动 Version/Context、接收是否先监听、丢包和过滤器 | 强行 PASS 或填补缺失的数据 |
| Packet 长度错 | UDP 长度是否包含 8B 首部、DIFI 包长是否以 32-bit Word 计数 | Wireshark GUI 的帧长度等于 UDP Payload |
| `difi.packet_type` 显示过滤器无效 | DIFI Lua dissector 是否加载；可先用 `udp.length`/IP/端口过滤 | 该报文本身不符合 DIFI |
| 官方验证混合流出现 SID 变化 | Version SID 与 Data/Context SID 是否不同；先分离，再用工具检查 | 误报意味着 FPGA 协议实现一定错误 |
| `.pcapng` 格式错误 | 使用 Wireshark/TShark 重新导出 classic `.pcap` | 文件损坏或 UDP 包错误 |
| 解析器报 fragmented UDP | 此包的检查器不支持 IPv4 Fragment 重组 | 分片本身必然非法 |

## 来源与证据等级

来自本仓库 `feature/rtl-integration` 已完成的真实链路：`rtl/board/difi_engine_board_b5.v`、`vitis/vitis_ws/difi_b5_udp_tx/src/difi_b5_udp_tx.c`、`scripts/verify/tools/difi_udp_receiver.py`、`report/results/udp/validation_notes.md`、`scripts/verify/tools/certify_difi_pcap.ps1`。

**真实既有证据**：Zynq-7020 → PS GEM0 → PC，22 包（1 Version + 1 Context + 20 Data）、5,120 IQ、0 mismatch；参考工具 v1.1 检查 Version 1/1、Context 1/1、Data 20/20，分流均 PASS。这个结果属于原 DIFI 工程和原测试程序。

**当前新 Skill 的验证范围**：Python 离线合成正反例自测通过；新通用接收器、解析器及通用配置在真实其他 FPGA 项目上的验证**待四个 Skill 统一测试**。不可将旧工程的实测证据当作本 Skill 工具的独立板级测试证据。

请参见 [案例记录](examples/difi-case-study.md)、[AI 协作工作流](templates/ai_workflow.md)、[验收模板](templates/acceptance_report.md) 及 [离线自测说明](tests/VALIDATION.md)。
