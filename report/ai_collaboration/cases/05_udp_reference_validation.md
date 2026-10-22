# C05 — B5 原始 DIFI UDP 报文与参考验证器的 Stream ID 处理

**状态：** PCAP、PC 端程序、第三方报告 E2/E3 可查；真实逐轮 E1 待导出。

## 架构事实

B5 不是板级 TX→RX 的 DIFI 解析回环：PL 从 `AXI DMA MM2S` 读取 DDR IQ 样本，生成完整 DIFI 报文到 `DMA S2MM`，PS 从 DDR 获取报文并经 lwIP/GEM0 发送 UDP 到 PC。

## 完成的验证

| Packet | 数量 | 每包 UDP Payload | Stream ID（本次测试） |
|---|---:|---:|---:|
| Version Flow Context | 1 | 44 B | 2 |
| Standard Flow Signal Context | 1 | 108 B | 1 |
| Signal Data | 20 | 1052 B | 1 |

合计 22 个 UDP Payload、21,192 Byte，Data IQ 20×256=5,120 个，PC 黄金比对失配 0；Data Sequence 按 4 bit 0～15 回绕。

在第三方 DIFI Consortium 参考工具中，混合不同 Stream ID 的抓包可能触发单流假设检查；本项目将 Version 与 Context+Data 分成两个验证流，**保持原版验证器不修改**，使用 `--difi-version 1.1` 检查，结果为：Version 1/0、Context 1/0、Data 20/0（合规/不合规）。

证据：`report/results/udp/validation_notes.md`、`difi_b5_udp_22.pcapng`、`report/results/udp/consortium/{version,data_context}/console.txt`、`scripts/verify/tools/difi_udp_receiver.py`。提交：[`a25ded8a`](https://github.com/tutushiyigeop-oss/difi-engine/commit/a25ded8aa8817b55bd69b6dc2651a53ac16c9506)。

## AI 迭代的可恢复要点

历史讨论曾出现修改参考验证器的备选想法，后来明确转向“不修改官方参考工具、按 Stream ID 分流测试”。该描述目前属于**历史交互摘要**，不是逐字 AI 聊天。提交时应以原始聊天截图证实具体建议先后，不应从最终 PASS 反推 AI 一开始就选择了正确方案。

## 限制

第三方开源程序对本轮三类报文判为 PASS 不等于取得 DIFI 正式认证；本轮包含人为 2 ms 发包间隔，不构成最大网络吞吐率测试。分流结果只验证各自流内协议合规性，不能代表混合链路的跨流排序/丢包已被参考工具检查。

## 对应 Skill

`skill/udp-packet-validation` 将 PCAP、UDP Payload、Golden 和 Stream ID 适配工作封装成通用工具；新版本工具的真实板级复测仍待统一验收。

## 待补

- [ ] 原始修改验证器/分流方案相关的用户提问与模型回答。
- [ ] 初次混流失败完整原始控制台日志。
- [ ] 分流操作具体命令、原始结果截图和关联 SHA。
