# DIFI 1.1 FPGA Digital IF 引擎：性能、资源及时序测试结论

> 日期：2026-10-20  
> 目标平台：Zynq-7020（XC7Z020CLG400-2），PL 时钟 100 MHz  
> 工具：Vivado / Vitis 2024.2；RTL 性能仿真采用 Icarus Verilog  
> 状态（文档同步：2026-10-22）：RTL 性能、板级 DMA IQ 回环、封装 IP 实现后时序均已完成；开发者已确认测试对应 PS CPU 时钟666.666666 MHz（显示约 666.667 MHz），两项 MB/s 为依据 PMU 原始计数换算的**板级系统级结果**。与当次 XSA 对应的 CPU 时钟配置原始截图/报告仍待单独归档。

## 1. 测试目的及口径

本次对 DIFI 1.1 协议引擎进行以下独立验证：

1. **RTL 原生性能（理想回环）**：`difi_engine_top` 的 TX Packet AXIS 直接接入 RX Packet AXIS，连续发送 100 个 Data Packet，每包 256 个 32-bit IQ 样本；无外部背压。统计有效 IQ 字节数/测试周期数与首样本延迟。
2. **Zynq 板级系统测试**：PS/DDR → AXI DMA MM2S → DIFI TX → DIFI RX → AXI DMA S2MM → PS/DDR；DMA 采用 Simple Mode，每包单独启动、等待及校验。先预热 2 包，再正式验证 100 包；使用 PS Cortex-A9 PMU 周期计数器记录测试窗口。**本项是包含 PS、DDR、DMA 配置与软件行为的系统级结果，不是纯 PL 的最高吞吐率。**
3. **Vivado 实现后资源及时序**：使用已布线的封装 IP 测试设计 `difi_ip_test_wrapper` 报告，统计 DIFI 封装 IP 与整套 PL 系统的资源，并核对 100 MHz 时序约束。

## 2. RTL 性能实测

| 测试项目 | 结果 |
|---|---:|
| Data Packet 数 | 100 |
| 每包 IQ 样本数 | 256 |
| IQ 样本总数 | 25,600 |
| IQ 有效数据总量 | 102,400 Byte |
| 测试窗口 | 52,002 cycles（520.02 μs @100 MHz） |
| **IQ 有效吞吐率** | **196.916 MB/s**（十进制） |
| 首 IQ 延迟，最小 / 平均 / 最大 | **266 / 516.470 / 519 cycles** |
| 首 IQ 延迟，最小 / 平均 / 最大 | **2.660 / 5.1647 / 5.190 μs** |
| IQ 匹配 / 接收 Metadata / 完整 Data Packet | 25,600 / 100 / 100 |
| 错误事件 | 0（此项由 RTL Testbench 检查） |
| 测试结论 | PASS |

**解释：** 32-bit AXI4-Stream @100 MHz 的物理有效数据线速上限为 400 MB/s；196.916 MB/s 对应约 49.23%。当前 Data Parser 使用整包缓存与校验，接收 263 个 Packet Word 后，再输出 256 个 IQ Word；因此该有效吞吐率接近单缓存串行处理架构的理想估计约 197.3 MB/s。这是架构层面的解释，不表示已测量到 FPGA 上的 PL 物理极限。

**延迟定义：** 某包首个源 IQ 样本被接收的时钟沿 → 该包首个解码 IQ 样本被输出接收的时钟沿。首包 266 cycles，后续满载包 519 cycles；两者分别反映无历史积压和稳定连续满载状态。

## 3. Zynq 板级实测

| 测试项目 | 结果 |
|---|---:|
| 预热 / 正式回环包数 | 2 / 100 |
| 每包 IQ 样本数 | 256 |
| 已校验 IQ 样本数 | 25,600 |
| IQ 数据失配数 | **0** |
| 总有效数据量 | 102,400 Byte |
| PS 计时器 | Cortex-A9 PMU CCNT 备用路径 |
| 完整测试窗口 | **2,729,306 PMU ticks** |
| 100 次 DMA 事务计时窗口之和 | **636,916 PMU ticks** |
| 板级系统吞吐率 | **约 25.01 MB/s**（按已确认约 666.667 MHz 换算） |
| DMA 事务窗口吞吐率 | **约 107.18 MB/s**（按同一 CPU 时钟换算） |
| 协议错误事件 | **未测量**；不能将 IQ 失配数 0 解释为协议错误 0 |
| 数据功能验证 | **PASS** |

在已确认 PMU 每 CPU 周期计数 1 次的前提下，若 CPU 频率为 `F_CPU_Hz`，则：

- `系统吞吐率 (MB/s) = 102400 × F_CPU_Hz / (2729306 × 10^6)`
- `DMA 事务窗口吞吐率 (MB/s) = 102400 × F_CPU_Hz / (636916 × 10^6)`
- `系统窗口时间 (s) = 2729306 / F_CPU_Hz`

**频率与计算来源：** 开发者已确认该板级测试对应的 PS CPU 工作频率为 **666.666666 MHz（已确认）**，由上述原始 PMU 计数换算为系统窗口 **约 25.01 MB/s**、DMA 事务窗口 **约 107.18 MB/s**，完整窗口 **约 4.094 ms**。这两项是**基于实测 ticks 和已确认时钟的换算值**，不是独立网络/PL 测速。**尚需补档：**与本次 Bitstream/XSA 配套的 Vivado PS 时钟配置截图或可核验原始配置，频率已确认，补档目的只是将该次测试与硬件配置文件相互关联，不是继续确认频率。

Global Timer 在该次自检中读到不连续的计数，程序改用 PMU；保留原始串口日志作为佐证。板级测试使用 DMA Simple Mode 逐包重启，软件缓存与样本比对、DDR 访问和 PS 轮询均可能影响结果；因此不宜直接以它和 196.916 MB/s 的差额推断 PL 核心性能退化。

## 4. Vivado 资源利用率与时序

实现环境：Vivado 2024.2；顶层设计 `difi_ip_test_wrapper`；器件 `xc7z020clg400-2`；设计状态 **Routed**。

| 项目 | DIFI 封装 IP：`difi_engine_ip_0` | 完整 PL 设计 |
|---|---:|---:|
| LUT | 1,776 | 4,562 |
| FF | 2,309 | 6,000 |
| RAMB36 | 0 | 2 |
| RAMB18 | 1 | 1 |
| DSP | 0 | 0 |

封装 IP 的资源统计包含协议核心，以及封装中的时间源、时间配置和周期触发模块。若只统计其 `u_engine` 协议核心子层级，则为 **1,389 LUT、1,773 FF、1 RAMB18、0 DSP**。完整 PL 包含 AXI DMA、SmartConnect 等外围资源。三种统计口径不能混用。

| 实现后时序指标 | 结果 |
|---|---:|
| PL 时钟 | 100.000 MHz（10 ns） |
| Setup WNS | **+0.411 ns** |
| Setup TNS | **0.000 ns** |
| Setup 违例端点 | **0** |
| Vivado 判定 | **All user specified timing constraints are met** |

说明：满足 100 MHz 时序约束不等于已经实测 Fmax；本报告不声明额外的最大工作频率。

## 5. 综合结论与局限

在 100 MHz、256 IQ Sample/Packet 条件下，DIFI 1.1 FPGA 引擎通过了连续 100 包的 RTL 回环验证，仿真有效 IQ 吞吐率为 **196.916 MB/s**，平均首 IQ 输出延迟为 **516.470 cycles**。真实 Zynq-7020 板级通过了 PS–DMA–DIFI IP–DMA–DDR 回环验证，**25,600 个 IQ 样本全部正确**。封装 IP 在 XC7Z020 的已布线设计中使用 **1,776 LUT、2,309 FF、1 RAMB18、0 DSP**，100 MHz 约束下 **WNS +0.411 ns、TNS 0 ns**，时序收敛。

需明确的限制：① RTL 结果基于无外部背压的理想回环；② 板级 PMU 吞吐率按开发者确认的 CPU 时钟换算，原始 PS 时钟配置文件/截图仍待归档；③ Simple DMA 逐包处理的系统吞吐率不代表 PL IP 的最大吞吐率；④ 板级协议错误事件未单独采集；⑤ 本轮仅是 100 包短时验证，不构成长时间稳定性测试。

## 6. 原始证据索引

以仓库 `feature/rtl-integration` 分支文件为依据：

- `report/results/perf/difi_perf_latency.csv`：100 包 RTL 延迟明细；原始 RTL 总结见性能仿真控制台日志。
- `report/results/perf/board_IP_perf.rtf`：Zynq 板级测试完整串口日志、PMU 原始计数与数据通过状态。
- `report/results/packaged_ip_impl/utilization.rpt`：已布线设计的分层资源利用率。
- `report/results/packaged_ip_impl/timing_summary.rpt`：已布线设计的 100 MHz 时序收敛结果。
- `report/results/packaged_ip_impl/critical_paths.rpt`：关键路径详情。
- `report/results/packaged_ip_impl/drc.rpt`：DRC 报告。

**待补录的证据（非新测速数值）：** 与本次 XSA/Bitstream 匹配的 Vivado `processing_system7_0` PS CPU 时钟配置截图/原始报告，以及对应版本标识。上述换算值已在表中列出；此补档无需重新运行已有 100 包数据测试。板级协议错误事件仍未单独测量，不能推断为零。
