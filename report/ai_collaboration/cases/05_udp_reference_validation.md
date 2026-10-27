# C05 — B5 UDP 报文检查与 DIFI Consortium 参考工具的 Stream ID 适配

**材料性质：** 基于历史交流回顾、B5 UDP 捕获记录、原版参考工具输出和 Git 提交的技术复盘；不是重现的逐字问答。

## 1. 真实链路及测试向量

B5 路径为 `DDR IQ → DMA MM2S → PL DIFI TX → DMA S2MM → DDR → PS lwIP/GEM0 → PC UDP`。它导出**完整 DIFI Packet**，区别于封装 IP 内部 TX→RX 后只取回 IQ 的回环测试。

| Packet | 数量 | 每包 UDP Payload | 本轮 Stream ID |
| --- | ---: | ---: | ---: |
| Version Flow Context | 1 | 44 B | 2 |
| Standard Flow Signal Context | 1 | 108 B | 1 |
| Signal Data | 20 | 1,052 B | 1 |

实收共 **22 包、21,192 字节 UDP Payload、5,120 IQ**，PC 黄金参考比对失配 0。Data Packet 采用 4-bit Sequence，并覆盖回绕。

## 2. AI 讨论与方案纠正

验证中遇到的重点并非只看 UDP 能否接收，而是如何正确解释参考工具面对不同 Stream ID 的行为：Version SID=2，Context/Data SID=1，混合抓包可能不符合该版参考工具单流状态检查的输入假设。

历史技术交流中出现过调整检查器行为的方案，最终选择**不修改 DIFI Consortium 原版参考程序**，而是按 Stream ID 将原始抓包拆分为 Version 与 Context/Data 两个输入，在 DIFI 1.1 模式分别测试。这保留了第三方工具的独立性，也避免把混流产生的 SID 变化提示当成单个 Packet 字段错误。

## 3. 测试结果与证据

| 验证输入 | 参考检查统计（合规/不合规） |
| --- | --- |
| Version 流 | 1/0 |
| Context/Data 流中的 Context | 1/0 |
| Context/Data 流中的 Data | 20/0 |

对应原版验证器命令采用 `certify_source.py --difi-version 1.1`，两份实际运行结果位于：

- `report/results/udp/tx/consortium/version/result.txt`
- `report/results/udp/tx/consortium/data_context/result.txt`
- `report/results/udp/tx/consortium/{version,data_context}/console.txt`
- 原始 22 包 PCAPNG：`report/results/udp/tx/difi_b5_udp_22.pcapng`
- PC 接收工具：`scripts/verify/tools/difi_udp_receiver.py`
- 提交：[`a25ded8a`](https://github.com/tutushiyigeop-oss/difi-engine/commit/a25ded8aa8817b55bd69b6dc2651a53ac16c9506)。

归档结果文件中仍保留了当时验证工具输入文件的本机绝对路径；这些是历史工具执行记录，而不是当前仓库要求存在的路径。

## 4. 结论与工程边界

本案例说明如何通过外部参考程序交叉检查**指定 DIFI 1.1 Profile 报文**。两组 PASS 属于开源验证器结果，**不是 DIFI Consortium 官方认证**，亦不覆盖所有 VITA 49.2 Packet 类型、持续网络吞吐与跨流丢包行为。原 UDP 演示设置了约 2 ms 发送间隔，不能将接收统计直接宣称为网络峰值速率。

## 5. Skill 与 B6 的关系

`skill/udp-packet-validation/SKILL.md` 对应 PCAP 提取、UDP Payload、Sequence、Golden 对比和外部参考工具独立校验。B6 v0.2 则是另一方向的板级验证：Version/Context 经 PL Metadata 事件核验，Data 经 PL RX 还原 5,120 IQ 并由 PS 比对，见 `report/results/udp/rx/three_types_udp_rx.rtf`。B6 的结论不与 B5 的第三方参考检查混为一谈。
