# 来源案例：DIFI 1.1 FPGA 数字中频协议引擎

> **出处**：仓库 `feature/rtl-integration` 中已存在的 RTL 与 Testbench。本文只整理这些文件中可定位的设计约定和历史测试结果，**不宣称新 Skill 的通用 RTL 示例已经实跑**。

## 1. 实际协议背景

- `rtl/data/difi_data_packetizer.v`：将 IQ 数据封装为 Data Packet；Data 头部固定 7 个 32-bit Word，最后一个 Payload Word 拉 `TLAST`，`TKEEP=4'b1111`。
- `rtl/data/difi_data_parser.v`：接收 Data Packet，校验整包后先输出 Metadata，再输出 IQ；最多支持 256 个 IQ Word。对非法包报告错误并抑制未经检验的数据输出。
- `rtl/rx/difi_rx_dispatch.v`：根据首字类型将 Data、Context 和 Version 分流，并将后续 Word 绑定同一目的通道至包末。
- 全部流控的基本计数条件是 `TVALID && TREADY`；接收停止或输出端背压不应导致丢失/重排。

## 2. 直接可引用的真实 Testbench

| 文件 | 已有验证内容与用途 |
|---|---|
| `sim/data/tb_difi_data_packetizer.v` | 4 样本参考包、N=1/256、17 包序号回绕、指定 Header/Payload/TLAST 字背压、快照与 `time_valid` 门控 |
| `sim/data/tb_difi_data_parser.v` | 全包 Metadata/IQ Scoreboard、输入气泡、输出及 Metadata 背压、SID 过滤、TKEEP、早 TLAST、缺 TLAST、错误码与错误优先级、序号不连续 |
| `sim/rx/tb_difi_rx_dispatch.v` | Data/Context/Version 路由、无效类型丢弃以及不同路由背压 |
| `sim/top/tb_difi_engine_top.v` | 核心 TX-RX 集成、配置、元数据与异常接口验证 |
| `sim/perf/tb_difi_engine_perf.v` | 理想 TX→RX 回环，100 MHz 下 100×256 IQ 实测有效吞吐率 196.916 MB/s，错误事件计数 0（此 TB 检查范围内） |

已归档的性能证据：`report/results/perf/performance_summary.md`、`report/results/perf/difi_perf_latency.csv`。后续报告写作应检查文档所注明的频率、缓存和无外部背压条件。

## 3. 为什么提炼这个 Skill

真实设计中需要同时避免以下两类错误：

1. **DUT 错**：背压时输出变化、Packet Size/TLAST 不一致、错误包仍输出 IQ、Metadata 时机错误、错误恢复失效。
2. **测试工具错**：仅按仿真周期而不是握手计数、只比较正常情况下的数据、未覆盖末字被 stall、把打印 PASS 当成退出码 PASS、只复用 DUT 内部算法而非独立 Golden Model。

通用 Skill 从这些要求提炼：单通道 AXIS 保持检查器、Golden accepted-beat 校验、确定性随机/周期背压、小型错误 RTL 反向检验与记录模板。

## 4. DIFI 特有、不能泛化的规则

- DIFI Data Packet 各 32-bit Word 要求 `TKEEP=4'b1111`，但普通 AXI4-Stream 未必如此。
- Data Packet 的结构 `7 + IQ Words`、固定 OUI、Stream ID、序号回绕与错误码属于 DIFI 1.1 项目，非任意 AXIS IP 通用要求。
- Data Parser 的序号异常策略与其他格式异常不同，不能无条件“序号错误就丢包”。
- Metadata 的优先输出与 parser 的整包缓存延迟属于当前设计架构，而非 AXIS 规范的强制要求。

## 5. 当前实证边界

该工程已经完成自己的 RTL 仿真、板级 DMA/UDP 等测试；可查看 `report/results/` 和 Vitis 源文件。

但是这次新 Skill 的 `axis_register_slice.v`、`tb_axis_register_slice.v` 与 `axis_trace_check.py` 不是原 DIFI 工程上板时使用的工具。当前已完成**Python 离线正反例单元测试**，Icarus RTL 示例与异构项目复用计划等待统一验证。
