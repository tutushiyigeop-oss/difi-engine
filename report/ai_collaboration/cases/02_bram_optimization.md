# C02 — Data Parser 整包缓存的 BRAM 推断与 OOC 资源优化

**材料性质：** 从历史技术讨论、RTL 改动及同口径 Vivado 2024.2 OOC 报告整理的追溯性复盘，不是逐字聊天记录。

## 1. 问题识别

Signal Data Parser 为“完整 Packet 先检查、成功后再输出 IQ”保留最多 256 个 32-bit IQ Word。最初的存储体读取形式导致 LUT/FF 使用显著升高。对 `difi_engine_top` 做 OOC 综合后，Data Parser 是主要资源热点：`2797 LUT / 8487 FF`，BRAM 使用为 0。

## 2. AI 分析与人工改造路径

历史讨论的技术诊断集中在：大数组如果采用组合式/异步读、多路选择或不适合 BRAM 的复位结构，工具可能以 LUT/FF 实现。建议遵循目标器件的 BRAM 可推断模板，不是仅增加属性后宣布优化成功。

实际改造采用：

1. 维持 IQ Buffer 的 256×32-bit 逻辑容量和 Parser 对外时序协议。
2. 使用同步时钟写、同步读存储体，配合 `(* ram_style="block" *)`，避免逐字节清零整个存储体。
3. 增加 `payload_q` 读出寄存器；Metadata 被接收时预取第一点 IQ。
4. `ST_OUTPUT` 中仅在 `TVALID && TREADY` 后推进读地址；输出停顿时保证数据与 `TLAST` 稳定。
5. 修改后先检查功能，再以相同顶层和综合口径比较资源，避免用 Routed IP 与 OOC 顶层互相对比。

## 3. 实测结果

| 指标 | 优化前 | 优化后 | 差异 |
| --- | ---: | ---: | ---: |
| `difi_engine_top` LUT | 4,023 | 1,516 | -62.32% |
| `difi_engine_top` FF | 10,446 | 2,202 | -78.92% |
| `difi_engine_top` RAMB18 | 0 | 1 | +1 |
| `u_data_parser` LUT | 2,797 | 283 | -89.88% |
| `u_data_parser` FF | 8,487 | 243 | -97.14% |

用户在 2026-10-12 的历史讨论中提交新 OOC 报告，并反馈原有仿真全部通过。上述资源数字取自 Git 中实际的**优化前/后 OOC 报告**，不是根据 AI 对话估算。

## 4. 工程证据及解释

- 优化前：`report/results/ooc/utilization.rpt`
- 优化后：`report/results/ooc_new/utilization.rpt`
- 代码：`rtl/data/difi_data_parser.v`，含 `snapshot_payload`、`payload_q`、`payload_rd_en` 及其预取地址。
- 历史提交：[`40f3c987`](https://github.com/tutushiyigeop-oss/difi-engine/commit/40f3c987873fbfecd79ba66369bc6176d67f815d)。

本结果只能得出**资源实现方式与 OOC 资源开销改善**，不能直接推导板级 UDP 吞吐率或同幅度时延提升；最终封装 IP 的 Routed 资源统计属于另一口径。

## 5. 技能沉淀

“分层综合报告定位热点 → 确认 RAM 推断方式 → 同步读与握手预取改造 → 重新检查协议行为 → 同条件综合对比”形成可复用流程，关联 `axis-rtl-verification` 与 `vivado-rebuild`。
