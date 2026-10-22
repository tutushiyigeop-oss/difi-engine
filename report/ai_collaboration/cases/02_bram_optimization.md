# C02 — Data Parser 整包缓存的 BRAM 推断与 OOC 资源优化

**状态：** Git/综合报告支持 E2/E3；AI 对话尚缺完整逐字 E1。

## 发现

同一 `difi_engine_top` 的 Vivado 2024.2 OOC 综合报告显示：优化前 Data Parser 消耗 `2797 LUT / 8487 FF / 0 BRAM`，其整包缓存是明显资源热点。历史讨论（非逐字原文）把注意力集中到异步读取数组导致无法有效推断 BRAM 的问题。

## 模型诊断与人工改动（讨论要点转述）

建议将整包缓存迁移为可综合推断的同步读存储体，使用 `ram_style="block"`、独立读寄存器、读地址预取，在 `TVALID && TREADY` 事件推进读位置，并在输出背压时保持 payload/last 稳定。**注意 `ram_style` 属性本身不能保证推断 BRAM，真正结果由综合报告决定。**

## 实验结果

| 指标 | 优化前 | 优化后 | 变化说明 |
|---|---:|---:|---|
| `difi_engine_top` LUT | 4023 | 1516 | 减少 62.32% |
| `difi_engine_top` FF | 10446 | 2202 | 减少 78.92% |
| `difi_engine_top` RAMB18 | 0 | 1 | 整包缓存转入 BRAM |
| `u_data_parser` LUT | 2797 | 283 | 减少 89.88% |
| `u_data_parser` FF | 8487 | 243 | 减少 97.14% |

证据：

- `report/results/ooc/utilization.rpt`（优化前），`report/results/ooc_new/utilization.rpt`（优化后）。
- `rtl/data/difi_data_parser.v` 的 `snapshot_payload`、`payload_q`、`payload_rd_en` 等。
- Git Commit [`40f3c987`](https://github.com/tutushiyigeop-oss/difi-engine/commit/40f3c987873fbfecd79ba66369bc6176d67f815d) 将 RTL 改动及前后 OOC 报告一并提交。
- 历史会话摘要记录用户在优化后表示“原仿真全部通过”；若要正式列入验收，应附本次对应原始仿真日志。

## 证据边界

本优化是**综合前后资源**对比，不可与 Routed 的 `difi_engine_ip_0` 资源数直接混淆，也不能称性能提升 62% 或延迟降低 79%。OOC 报告并不证明最终板级所有报文场景都覆盖。用户与模型逐字问答待归档。

## Skill 提炼

资源诊断的通用步骤：读取分层综合报表 → 锁定热点 Module → 检查 BRAM 可推断性 → 改同步读 / 保持 AXIS 协议语义 → 先复测功能 → 同一约束/顶层再综合对比。关联 `axis-rtl-verification`、`vivado-rebuild`。

## 待补

- [ ] 原始对话：首次贴上 OOC 报告、AI 原因判断、代码建议、复测反馈。
- [ ] 提交对应版本的 Icarus PASS 控制台日志。
- [ ] 锁定比对时完整工具配置 / Git SHA，以便第三方独立复现。
