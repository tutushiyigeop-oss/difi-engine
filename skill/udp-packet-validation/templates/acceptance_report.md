# UDP Packet Validation Skill 验收报告（模板）

> 本文件为模板，请用**实际执行结果**填充。禁止把合成样例自检结果写成 FPGA 板级实测。

| 字段 | 待填写 |
|---|---|
| Skill SHA / Git Commit | `<SHA>` |
| 测试日期 / 测试人 | `<DATE> / <NAME>` |
| FPGA / IP / Vivado / Vitis / BSP | `<HW_SOFTWARE>` |
| 网络拓扑 / 源、目标 IP/端口 | `<NETWORK>` |
| PCAP 格式 / 原文件 SHA-256 | `<FORMAT> / <HASH>` |
| 生成器与接收器路径 | `<SENDER> / <RECEIVER>` |
| Profile 与期望包数 | `<CONFIG>` |
| 期望数据字节数 / 样本数 | `<EXPECTED>` |
| 离线 Python 工具自检 | `<PASS/FAIL/SKIP> + 日志路径` |
| 真实 PC 上抓包及校验 | `<PASS/FAIL/NOT_TESTED> + 证据` |
| 原版本第三方参考工具 | `<PASS/FAIL/NOT_APPLICABLE> + 版本/参数/日志` |
| 长时/线速测试 | `<PASS/FAIL/NOT_TESTED>` |
| 关键错误与人工修复 | `<具体错误、日志、前后 diff>` |
| 残余限制 | `<哪些情况无法得出结论>` |

## 统一分级

- **L1**：Python 语法、单元测试、正反合成样例通过。
- **L2**：新 Skill 工具在真实捕获 PCAP 上检查通过。
- **L3**：新脚本在重建的 FPGA/Vitis 环境完成一次真实收发与内容校验。
- **L4**：合法的第三方独立协议验证另行通过；不等同于官方认证。

## 指令与输出摘要

```text
<Command>
<Exact output>
```

## 结论

`<PASS / FAIL / PARTIALLY VERIFIED>`，证据限于上述已实际执行的测试。
