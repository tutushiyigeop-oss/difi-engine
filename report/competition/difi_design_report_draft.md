# DIFI 1.1 FPGA Digital IF Protocol Engine：设计与验证报告（初稿 v0.2）

> 全国大学生嵌入式芯片与系统设计竞赛（AMD 自主选题赛道）  
> 队伍、成员、学校：[提交前填写]  
> 项目仓库：`https://github.com/tutushiyigeop-oss/difi-engine`  
> 参考分支：`feature/rtl-integration`（最终提交前固定 Commit SHA / Tag）  
> 报告状态：**工程内容初稿；AI 协作原始记录、Skill 最终验收及参考工作比较尚待补齐**  
> 文档基准日期：2026-10-22

## 摘要

本项目针对数字中频（Digital IF）场景中的 IQ 数据封装与跨系统互操作需求，设计实现了基于 **VITA 49.2 / DIFI Profile 1.1** 的 FPGA 协议收发引擎。引擎采用 Verilog RTL 实现，提供 AXI4-Stream IQ 输入/输出及协议报文输入/输出，使用 AXI4-Lite 完成配置与状态访问，支持 Signal Data、Standard Flow Signal Context 与 Version Flow Context 三类报文的生成和解析，并提供 Stream ID 过滤、Sequence 检查、时间戳与协议错误事件等功能。

在 XC7Z020CLG400-2 上，项目完成了 RTL 系统级仿真、BRAM 存储结构优化、封装 IP 的真实布局布线、Zynq PS/PL AXI DMA 板级数据回环与完整 DIFI 报文的 UDP 网络发送。100 MHz 理想 RTL 回环测试中，100 个数据包 / 25,600 个 IQ 样本均正确，IQ 有效吞吐率为 **196.916 MB/s**。封装 IP 的已布线资源占用为 **1,776 LUT、2,309 FF、1 RAMB18、0 DSP**，Setup WNS **+0.411 ns**。B5 网络验证中，PC 端收到 **1 Version + 1 Context + 20 Data** 共 22 个 DIFI Packet，5,120 个 IQ 样本全部正确；DIFI Consortium 开源参考工具以 DIFI 1.1 模式检查上述三类报文，结果均为 PASS。

为检验可复现性，项目使用从原始 Vivado 工程导出的 Tcl 快照独立重建两套硬件工程，再次完成综合、实现、Bitstream/XSA 导出及板级回归。相关 Tcl、软件、日志和证据按照仓库路径保存。本文明确区分 RTL 理想吞吐率、Simple DMA 系统吞吐率与真实 UDP 功能验证结果；不将参考工具 PASS 表述为 DIFI Consortium 正式认证。

**关键词：** FPGA；Zynq-7000；DIFI 1.1；VITA 49.2；AXI4-Stream；AXI DMA；UDP；可复现构建

---

## 1. 选题背景、目标与价值

### 1.1 选题背景

数字中频系统需要在信号采集、数字处理及通信传输节点之间传递 IQ 样本及配套元数据。直接发送原始 IQ 字节流难以统一表达样本属性、时间戳、流标识等信息。DIFI Profile 在 VITA 49.2 的基础上规定了特定互操作约束，适合作为可验证的数字中频报文接口。

本项目聚焦**可独立集成的 FPGA 端协议收发组件**及其在 Zynq PS/PL 协同架构下的工程化验证，而非在 FPGA 内实现完整以太网协议栈。协议部分位于 PL；UDP 网络发送示例由 Zynq PS 侧 lwIP 完成。

### 1.2 设计目标与边界

- 实现三类 DIFI 1.1 报文的发送与接收解析，并完成系统级功能测试。
- 对 IQ、元数据和协议报文提供明确定义的 AXI4-Stream 接口，支持 TVALID/TREADY 背压。
- 提供 AXI4-Lite 配置与状态接口，支持 Shadow→Active Commit、时间源和流标识配置。
- 通过资源优化将接收端整包缓存映射到 FPGA Block RAM。
- 在 Zynq-7020 上完成封装 IP 回环测试，以及完整 DIFI Packet 经 PS UDP 发送到 PC 的端到端测试。
- 保存第三方协议参考工具验证证据、综合/实现报告和可重建的 Vivado Tcl 脚本。

**边界声明：** 当前报告覆盖上述已经实现和测试的功能范围；不宣称支持 DIFI 1.1 全部可选功能，不声称取得正式认证，不把简单 DMA 轮询性能等同于纯 PL 吞吐上限。

### 1.3 工程特点与拟突出的创新点

1. **模块化协议收发架构：** 三类报文生成器、TX Scheduler、RX Dispatch 与对应 Parser 解耦，便于独立验证及 IP 复用。
2. **面向 FPGA 存储结构的优化：** 接收端完整报文缓存由寄存器式实现转为可推断 Block RAM 的结构，显著改善综合资源占用。
3. **多层验证闭环：** RTL 黄金模型、综合/时序、PS/PL DMA、UDP/PC 和独立 DIFI 参考工具相互补充，避免仅凭单一仿真结论推断系统正确。
4. **可复现的软硬件工程：** 原始 Vivado 工程的 BD Tcl 导出、全新目录恢复、重新生成 XSA 与上板回归形成闭环。

**待补：** 相关研究、开源 DIFI/VITA FPGA 实现或类似产品的客观对比。上述为本项目的**工程贡献和设计特点**，在完成文献/开源对比前不使用“首创”“唯一”“最先进”等缺乏证据的表述。

## 2. 设计需求与支持范围

| 功能 | 已实现内容 | 验证方式 |
|---|---|---|
| Signal Data Packet | IQ 样本打包、解包、元数据提取 | 模块级及系统级 Testbench；板级 IQ 数据对比；UDP PC 解析 |
| Standard Flow Signal Context | Context 生成及解析 | RTL 测试、UDP 抓包、参考工具校验 |
| Version Flow Context | Version 生成及解析 | RTL 测试、UDP 抓包、参考工具校验 |
| TX 调度与 Packet Mux | 三类报文调度、包边界切换 | System Testbench |
| RX 类型分发 | 分类路由、错误类型丢弃 | RX Dispatch Testbench |
| AXI4-Lite 配置 | Shadow/Active Commit、状态读取和流配置 | 仿真及 Vitis 控制配置 |
| 时间戳 | UTC 时间加载与协议字段编码 | RTL、B5 板级测试与参考工具（仅限已覆盖字段） |
| 异常输入 | Stream ID、Size、TKEEP、TLAST 等检查 | 相关 RTL 异常包测试；不等于覆盖全部协议异常 |

实际模块端口及寄存器偏移以 `rtl/top/`、`rtl/include/difi_cfg_regmap.vh`、`rtl/include/difi_time_cfg_regmap.vh` 与 `docs/interface/` 文件为准。

## 3. 总体架构及软硬件划分

### 3.1 协议引擎数据通路

![图 3-1：DIFI 1.1 RTL 协议收发引擎与 B5 包装层结构](../figures/difi_engine_rtl_architecture.svg)

*图 3-1　DIFI 1.1 协议引擎内部结构：TX 路径包含 Data/Context/Version 生成与调度；RX 路径包含类型分发与三类解析器。图中时间源与周期触发为 B5 包装层的辅助模块，不属于 `difi_engine_top` 内部实例。*

```mermaid
flowchart LR
    IQIN[AXI4-Stream IQ Input] --> TXD[Data Packetizer]
    CFG[AXI4-Lite Configuration] --> SCHED[TX Scheduler / Packet Mux]
    TM[UTC Time Source] --> TXD
    TXC[Context Generator] --> SCHED
    TXV[Version Generator] --> SCHED
    TXD --> SCHED
    SCHED --> DOUT[AXI4-Stream DIFI Packet Output]
    PIN[AXI4-Stream DIFI Packet Input] --> DISP[RX Dispatch]
    DISP --> RXD[Data Parser]
    DISP --> RXC[Context Parser]
    DISP --> RXV[Version Parser]
    RXD --> IQOUT[AXI4-Stream IQ Output]
    RXD --> META[Data Metadata]
    RXC --> CTXMETA[Context Metadata]
    RXV --> VERMETA[Version Metadata]
```

> 此图为功能结构概括图，正式报告中的细节连线以源码及 Vivado BD 为准。

### 3.2 Zynq 硬件测试：两套不能混淆的 BD

**A. 封装 IP 回环工程**：`difi_ip_test` / `difi_ip_test_wrapper`

```text
PS DDR → AXI DMA MM2S → DIFI Engine TX → DIFI Engine RX → AXI DMA S2MM → PS DDR
```

该路径验证 IQ→DIFI Packet→IQ 的逻辑闭环；DMA S2MM 获得的是**解析后的 IQ 数据**。

**B. B5 原始报文导出工程**：`difi_system` / `difi_system_wrapper`

```text
PS DDR → AXI DMA MM2S → DIFI TX → AXI DMA S2MM → PS DDR
                                              ↓
                                    PS lwIP / GEM0 UDP → PC
```

该路径 S2MM 接收的是**完整的 DIFI Packet**，PS 负责将 32 位报文 Word 按网络字节序序列化，并经 UDP 发送到 PC。此工程不是 TX/RX 自回环工程。B4 历史工程与 B5 使用同名 `difi_system`，重建时需根据 BD 内原始 Packet 导出模块识别。

![图 3-2：DIFI B5 FPGA—Zynq PS—UDP—PC 端到端系统架构](../figures/difi_b5_system_architecture.svg)

*图 3-2　B5 板级系统数据通路。PS 通过 AXI4-Lite 控制 PL 寄存器；DMA 经 HP0 访问片外 DDR。MM2S 提供原始 IQ；S2MM 收回完整 DIFI 报文；PS GEM0/lwIP 再将报文作为 UDP Payload 发往 PC。图示不表示 PL 内存在 UDP 协议栈或 B5 配置了 TX→RX 回环。*

### 3.3 软硬件划分依据

PL 使用状态机及流式接口处理周期敏感的协议字段封装与解析；PS 用于配置寄存器、初始化时间源、控制 AXI DMA、进行缓冲区缓存维护及 UDP 网络通信。这一划分避免将每个数据 Word 的封装过程交给 PS 软件，同时充分利用 Zynq 的外设与应用程序开发能力。

## 4. RTL 设计中的关键机制

### 4.1 AXI4-Stream 传输语义

仅在 `TVALID && TREADY` 时计为一次成功传输；背压期间应维持待发送数据和侧带字段稳定。`TLAST` 表示当前 Packet 的末字；在本项目采用的 32-bit DIFI Word 路径中，完整 Word 使用 `TKEEP=4'b1111`。

### 4.2 配置一致性

TX 配置由 AXI4-Lite Shadow 寄存器写入，经 Commit 完成 Active 配置更新。报文生成模块在报文开始时使用必要的配置和时间快照，避免 Packet 中途出现配置混杂。

### 4.3 RX 缓存、错误控制与 Metadata

Data Parser 对完整接收报文进行检查，在接受正确的完整 Packet 之后提交 Metadata，再输出缓存 IQ 数据。解析器提供长度、字段、Stream ID、TLAST/TKEEP 及序列等检查。针对多个错误同周期出现的情形，项目 Testbench 验证其预设优先级；精确的错误编码、优先级与恢复行为以 `rtl/include/difi_v1_1_defs.vh` 和 RTL/Testbench 为准。

### 4.4 BRAM 推断优化

将 Data Parser 的整包 IQ 存储结构调整为具备同步读特征的存储体，避免大量寄存器实现缓存。这提高资源效率，但也引入整包接收/验证后再输出的延迟与串行处理吞吐约束。

## 5. 优化前后性能与资源比较

### 5.1 OOC 综合对比

条件：`difi_engine_top`，XC7Z020CLG400-2，Vivado 2024.2，OOC Synthesis；**同一统计口径比较**。

| 指标 | 优化前 | 优化后 | 变化 |
|---|---:|---:|---:|
| LUT | 4,023 | 1,516 | −62.32% |
| FF | 10,446 | 2,202 | −78.92% |
| RAMB18 | 0 | 1 | +1（用于缓存推断） |
| DSP | 0 | 0 | 无变化 |

证据：`report/results/ooc/utilization.rpt`、`report/results/ooc_new/utilization.rpt`。上述为综合阶段比较；不要与下节的封装 IP 实现后资源表混用。

![图 5-1：DIFI OOC 综合前后 LUT、FF 优化对比](../figures/difi_ooc_resource_optimization.svg)

*图 5-1　原始综合报告提取的资源对比。LUT 减少约 62.32%、FF 减少约 78.92%；引入 1 块 RAMB18。只比较同一 RTL 顶层的 OOC 综合结果，不能将它与封装 IP 的实现后资源混作一组。*

### 5.2 封装 IP 实现后资源与时序

条件：`difi_ip_test_wrapper`，XC7Z020CLG400-2，100 MHz，Routed。

| 资源 | DIFI 封装 IP | 完整 PL 系统 |
|---|---:|---:|
| LUT | 1,776 | 4,562 |
| FF | 2,309 | 6,000 |
| RAMB36 | 0 | 2 |
| RAMB18 | 1 | 1 |
| DSP | 0 | 0 |

Setup WNS = **+0.411 ns**；TNS = **0 ns**；规定约束满足。此处的封装 IP 包含协议核心、时间源、时间配置与周期触发模块；完整 PL 系统还包含 AXI DMA、互连等外围。

证据：`report/results/packaged_ip_impl/utilization.rpt`、`timing_summary.rpt`、`critical_paths.rpt`、`drc.rpt`。

### 5.3 RTL IQ 有效吞吐率与延迟

在 100 MHz、理想直接 TX→RX 回环、每包 256 个 32-bit IQ、外部无背压条件下：

| 指标 | 测试结果 |
|---|---:|
| 数据包数 | 100 |
| IQ 样本总数 | 25,600 |
| IQ Payload 字节数 | 102,400 B |
| 测量时钟周期数 | 52,002 cycles |
| IQ 有效吞吐率 | **196.916 MB/s** |
| 首 IQ 延迟（min/avg/max） | **266 / 516.470 / 519 cycles** |
| IQ 数据错误事件 | 0（测试覆盖范围内） |

计算方式：`102400 B / (52002 / 100 MHz) = 196.916 MB/s`。理论 32-bit × 100 MHz 物理通路带宽 400 MB/s，这与 DIFI Header、接收整包缓存、输出阶段分离下的有效 IQ 速率不同。该结果不等同于 DMA、UDP 或 PHY 的线速吞吐。

证据：`report/results/perf/difi_perf_latency.csv`、`sim/perf/tb_difi_engine_perf.v`。

![图 5-2：100 个 RTL 数据包的首 IQ 输出延迟](../figures/difi_rtl_first_iq_latency.svg)

*图 5-2　逐包延迟来自原始 `difi_perf_latency.csv`：首包为 266 cycles，其余 99 包均为 519 cycles；100 包平均 516.470 cycles。数值是理想 RTL 回环条件下的首 IQ 延迟，不是网络传输时延。*

### 5.4 板级 DMA 回环

在 Zynq-7020 上，封装 IP 回环使用 100 包 × 256 IQ 的数据集，共 **25,600 IQ 全部正确、失配为 0**。计时数据来自 Cortex-A9 PMU 周期计数器，PS CPU 配置频率在后续核对中确认为约 **666.667 MHz**。据已归档的 `2,729,306` 完整窗口 ticks 和 `636,916` 次 DMA 事务窗口总 ticks 换算，分别约 **25.01 MB/s** 与 **107.18 MB/s**。报告应继续保留原始 ticks 和换算公式：

- `system_MBps = 102400 × 666666667 / (2729306 × 10^6)`
- `dma_window_MBps = 102400 × 666666667 / (636916 × 10^6)`

**口径说明：** 该系统级结果包含 Simple DMA 逐包重新启动、PS 轮询及 DDR/软件开销，不能用于宣称 PL 协议引擎最大处理性能。`report/results/perf/performance_summary.md` 仍有“频率待确认”的旧表述，最终版须同步修订，并附 PS 时钟配置证据。

![图 5-3：三种不同测量窗口的有效 IQ 吞吐率](../figures/difi_throughput_measurement_scopes.svg)

*图 5-3　RTL 理想回环 196.916 MB/s；板级 DMA 事务窗口约 107.18 MB/s；完整 PS 软件测试窗口约 25.01 MB/s。板级换算以开发者确认的 PS CPU 666.667 MHz 配置及 PMU 每周期递增 1 为前提，仍须在最终验收时归档时钟配置证据。三组数据并非同一环境下的端到端性能比较，不能根据横条差额推出协议引擎的 PL 吞吐退化。*

## 6. Zynq UDP 端到端验证与第三方检查

### 6.1 B5 测试条件

- 硬件：Zynq-7020，PS GEM0 网络接口；B5 原始报文导出工程。
- 发送端 IP：`192.168.1.10`；PC 测试网卡 IP：`192.168.1.20`；UDP 端口：`4991`。
- START 控制：PC 发送启动请求，Zynq 接收后按已配置测试序列发包。
- 数据：1 个 Version（44 B）、1 个 Context（108 B）、20 个 Data（每个 1052 B）。

### 6.2 应用层校验

PC 接收脚本 `scripts/verify/tools/difi_udp_receiver.py` 对类型、长度、Stream ID、序列字段及 IQ 样本进行检查，得到：

- **22/22 Packet 正确接收**；总 UDP Payload **21,192 B**。
- **20 × 256 = 5,120 IQ** 全部匹配；Sequence 计数按 4 bit 回绕。
- 程序人为设置 2 ms 的报文间隔，**本轮不是 UDP 最高吞吐测试**。

证据：`report/results/udp/validation_notes.md`、完整 `.pcapng`、PC 侧日志和截图。

### 6.3 DIFI Consortium 开源参考工具校验

使用 DIFI Consortium 的 `certify_source.py --difi-version 1.1`。由于测试中 Version 与 Context/Data 使用不同 Stream ID，为避免参考工具的跨流统计产生歧义，保存原始完整 PCAP 并分别导出两组流进行离线检查。

| 流 | 符合项 | 不符合项 | 结果 |
|---|---:|---:|---|
| Version | 1 | 0 | PASS |
| Context | 1 | 0 | PASS |
| Data | 20 | 0 | PASS |

**边界：** 此结果表示第三方开源参考程序在本轮检查范围内 PASS，**不等于 DIFI Consortium 的正式认证**。证据保存在 `report/results/udp/consortium/`。

![图 6-1：RTL、DMA、UDP 多层 IQ 正确性验证规模](../figures/difi_multilayer_validation_evidence.svg)

*图 6-1　三条测试链路的黄金数据比对规模：RTL 回环 25,600 IQ、板级 DMA 回环 25,600 IQ、B5 UDP 到 PC 5,120 IQ，已记录样本均无失配。图中没有展示未测试场景的通过率；第三方参考工具检查的 PASS 也不是正式认证。*

## 7. Tcl 构建可复现性验证

使用 `scripts/vivado/export_bd.tcl`、`rebuild_bd.tcl` 和 `verify_rebuilt_impl.tcl`，分别对封装 IP (`packaged_ip`) 与 B5 原始 Packet (`b5_raw_export`) 执行：原始工程导出 BD Tcl → 独立目录重建 → Vivado 综合实现 → Bitstream/XSA → Vitis 使用新平台再上板。

| 验证项 | 封装 IP 工程 | B5 UDP 工程 |
|---|---:|---:|
| 目标 Part | xc7z020clg400-2 | xc7z020clg400-2 |
| 顶层 | `difi_ip_test_wrapper` | `difi_system_wrapper` |
| 综合/实现/Bitstream | PASS | PASS |
| Setup WNS | +0.411 ns | +2.206 ns |
| Hold WHS | +0.046 ns | +0.021 ns |
| 重建 XSA | 已生成 | 已生成 |
| 新重建工程上板回归 | 开发者确认通过 | 开发者确认通过 |

证据：`report/results/vivado_rebuild/{packaged_ip,b5_raw_export}/SUCCESS.txt` 及实现报告。**待归档：** 新 XSA 对应的 Vitis 构建日志、板级 UART 日志、PC 接收日志以及关联的 Git Commit SHA。

## 8. 大模型协作过程与纠错记录（待补原始材料）

AMD 指南要求真实的提示词、模型回答、自我纠错轨迹，不能用事后编造的对话替代。计划至少整理以下真实过程，每个案例都要有**错误/原始请求 → 模型建议 → 人工验证 → 反馈纠错 → 最终结果**：

1. Data Parser 的 TKEEP、TLAST、Sequence、Drop 状态与 BRAM 同步读问题。
2. Icarus Verilog 跨目录 `include` / 源文件依赖与 VS Code 一键仿真配置。
3. Zynq AXI DMA 的 Cache Flush/Invalidate、先 S2MM 后 MM2S 和真实板级波形/日志。
4. Vivado Tcl 导出中 `open_bd_design unavailable` 的误判、修复与重新执行结果。
5. UDP 应用层字节序、Wireshark 显示过滤器、DIFI Consortium 参考工具分流验证。

**重要：** 上述仅是候选案例。正式报告应引用已保存的真实会话或原始日志，以及对应的 Git Diff/Commit；若找不到原始证据，应注明，不得重构为虚假的逐轮对话。

## 9. Skill 技能包提炼（统一验收待补）

已制作四个模块，目录位于 `skill/`：

| Skill | 可复用范围 | 当前证据与限制 |
|---|---|---|
| `vivado-rebuild` | BD Tcl 导出、依赖审计、独立重建、时序/实现报告 | DIFI 专用流程已板级通过；通用化脚本待跨项目测试 |
| `zynq-dma-debug` | Simple DMA、Cache、TLAST、日志/寄存器检查 | 离线工具测试已完成；新通用 C 模板待 Vitis 实测 |
| `axis-rtl-verification` | AXI4-Stream 握手、背压、Golden、错误注入 | 离线测试已完成；真实 Icarus 及跨项目适配待验收 |
| `udp-packet-validation` | UDP 抓包、长度序列黄金数据、DIFI 专用适配 | 离线测试已完成；新工具真实链路适配待验收 |

正式报告须在统一验收后增补每项 Skill 的失效条件、代表性正反例、命令输出和跨项目复用结论。**当前仅称“已制作，待统一验收”。**

## 10. 复现说明与交付物

### 10.1 环境

- AMD/Xilinx Zynq-7020（`xc7z020clg400-2`）；Vivado / Vitis **2024.2**。
- Python、Icarus Verilog、Wireshark（按具体测试准备）；DIFI Consortium 参考工具为独立第三方组件。
- 软件与 IP 依赖以根目录 `README.md`、`scripts/vivado/`、`ip_repo/`、`vitis/` 为准。

**版本差异说明：** AMD 指南推荐 2025.2 或 2026.1；本工程实际采用 2024.2，因此需保留版本信息和 Tcl 可复现证据。

### 10.2 推荐复现顺序

1. 检出最终提交时冻结的 Git SHA / Tag，确认 RTL、IP Repo、构建脚本和 XDC 完整。
2. 运行 RTL 模块与系统级仿真；执行性能 Testbench 并检查 100 包黄金 IQ。
3. 使用 `scripts/vivado/` 导入两套真实 BD 快照，在新的工程目录中重建并重新综合/实现。
4. 根据对应的 XSA 重新创建 Vitis Platform/BSP 和应用（需要在根 README/附录给出逐项设置）；下载匹配的新 Bitstream。
5. 在封装 IP 工程复现板级 100 包 DMA IQ 回环。
6. 在 B5 工程复现 UDP 22 包发送、PC IQ 比对及 Wireshark 抓包。
7. 按 DIFI 1.1 模式分别验证 Version 与 Context/Data 流，并归档脚本版本、PCAP Hash、输出日志。

### 10.3 交付核查清单

- [x] RTL、Testbench、Vitis C、封装 IP 仓库及 Tcl 重建/实现脚本。
- [x] 原始 RTL 性能、综合/实现、UDP/第三方工具的既有证据。
- [x] 两套 Vivado Tcl 重建的实现输出与用户确认的板级通过结果。
- [x] 四个 Skill 的初始内容。
- [ ] Skill 的统一验收及交叉项目复用测试。
- [ ] 大模型真实协作记录和失败→修复→验证的逐例证据。
- [ ] 新重建 XSA 对应的 Vitis/板级回归原始日志补档。
- [ ] 文献/开源方案对比与参考文献、图片标注及最终校对。
- [ ] 最终 Git Commit SHA/Tag、开源许可证及目录命名检查。

---

## 附录 A：主要证据路径索引

| 证据类型 | 仓库路径 |
|---|---|
| OOC 优化前 | `report/results/ooc/utilization.rpt` |
| OOC 优化后 | `report/results/ooc_new/utilization.rpt` |
| 封装 IP 已布线资源及时序 | `report/results/packaged_ip_impl/` |
| 性能 CSV / 板级 PMU 原始值 | `report/results/perf/` |
| B5 实现结果 | `report/results/b5_impl/` |
| 原始 PCAP、截图、第三方日志 | `report/results/udp/` |
| Tcl 独立重建验收 | `report/results/vivado_rebuild/` |
| 可复现 BD Tcl 脚本 | `scripts/vivado/` |
| Vivado 封装 IP | `ip_repo/difi_engine_ip/` |
| Vitis C 源码 | `vitis/vitis_ws/` |
| Skill | `skill/` |

## 附录 B：定稿前必须审阅的风险点

1. DIFI 标准符合性声明不可超出已测试内容，不可将开源工具 PASS 说成“官方认证”。
2. 196.916 MB/s 只能称为无外部背压 RTL 理想回环的 **IQ 有效吞吐率**。
3. 25.01/107.18 MB/s 必须保留 CPU 时钟配置与 PMU ticks 的计算口径；不同条件不能横比。
4. OOC 资源对比、封装 IP 资源与完整 PL 资源是三种不同统计口径。
5. “新 XSA 上板通过”目前是开发者确认事实，正式材料应附对应原始 UART / PC 输出日志。
6. Skill 初版离线测试结果不等于其已完成跨项目复现；统一验收暂缓。
7. 仓库中的文件名/目录名应遵循 AMD 指南“英文小写、数字、下划线或连字符”的要求，检查并修改不合规名称或在必要情况下解释仓库结构。
