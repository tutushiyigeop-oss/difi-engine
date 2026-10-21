# DIFI 1.1 / Zynq-7020 的实际案例与证据边界

## 项目环境

- Zynq-7020 (`xc7z020clg400-2`)，Vivado/Vitis 2024.2，PL 100 MHz；Bare-metal/Standalone 使用 AXI DMA Simple Mode。
- 可追溯源码：
  - `vitis/vitis_ws/difi_ip_loopback_test/src/difi_ip_loopback_test.c`
  - `vitis/vitis_ws/difi_ip_perf_test/src/difi_ip_perf_test.c`
  - `vitis/vitis_ws/difi_stage_b5-b_test/src/difi_stage_b5-b_test.c`
  - `vitis/vitis_ws/difi_b5_udp_tx/src/difi_b5_udp_tx.c`

## 两种不能混淆的系统

| 系统 | S2MM 实际收到的内容 | 验证证据 |
|---|---|---|
| 封装 IP 回环 | 经 DIFI RX 解析后的 32-bit IQ | `report/results/perf/board_IP_perf.rtf`；正式 100×256 IQ，失配 0 |
| B5 原始报文导出 | 11/27/263 words 的 DIFI Version/Context/Data 整包 | `report/results/udp/validation_notes.md`、相应 PCAP、第三方验证日志 |

B5 由 PS 接收原始 Packet 后再通过 lwIP UDP 发给 PC。它不是 AXI DMA 直接连接到 GEM；UDP 是 PS 软件负责的另一段数据路径。

## 已在工程中采用的可复用实践

1. `XAxiDma_LookupConfig` 根据 Vitis 2024.2 SDT 及 legacy BSP 的差异使用 base address 或 device ID；需要查看当前 `xparameters.h`。
2. 初始化后通过 `XAxiDma_HasSg()` 检查驱动模式；Simple Mode 轮询时关闭相关 DMA 中断。
3. 接收通道先启动 S2MM；随后才发起 MM2S / 使能数据源。**特别注意 Version 和 Context 可能在启动后立即到达。**
4. TX CPU 已写入 Buffer，调用 `Xil_DCacheFlushRange`；对于 CPU 写入过的 RX Buffer，DMA 前清理脏缓存行，DMA 完成后 `Xil_DCacheInvalidateRange`，再进行 IQ 或报文字节级比对。
5. 轮询两个通道的 `DMASR` 错误位与完成状态，并设置超时限制；失败时保存通道方向与寄存器值，不只打印 “timeout”。
6. B5 `RxWords` 分配了 272 words 的接收存储空间，每种报文按实际 11/27/263 words 发起对应 S2MM SimpleTransfer；说明**分配容量**与**本次 DMA 长度**是两个不同参数。

## 测量数据，严格区分归因

原始 UART 证据：`report/results/perf/board_IP_perf.rtf`。

- 100 个 Data Packet × 256 IQ = 25,600 个样本；IQ 比对为 0 mismatch。
- `total_wall_ticks=2,729,306`、`summed_dma_ticks=636,916`，测量时因 Global Timer 结果异常采用 Cortex-A9 PMU 计数。
- 已另行确认 PS CPU 频率约 666.667 MHz，按 PMU 每 CPU cycle 一个 tick 换算：系统窗口约 **25.01 MB/s**、DMA 事务窗口约 **107.18 MB/s**。这是包含 PS、DDR、Simple DMA 软件启动/轮询的测量口径，**不是 PL IP 峰值吞吐率**。
- 原始 UART 仍标注 `NOT_CALIBRATED`，因为记录时未完成 CPU 时钟频率确认。引用数据应说明后续的校准前提，不得伪造新的 UART 输出。
- B5 网络验证：1 Version + 1 Context + 20 Data，20×256=5120 IQ 全部正确；UDP 发送加入人工 2 ms 间隔，**不是 UDP 最高吞吐率测试**。

## 问题来源、AI 贡献与证据诚实性

本 Skill 从真实工程中多轮讨论的这些问题提炼：为什么要区分完整 DIFI Packet 与解码 IQ 的接收通路，为什么 S2MM 先启动、如何跨 SDT/legacy 找到 DMA 标识、如何维持 Cache 一致性、如何避免把系统吞吐率当作 PL 吞吐率。

**不声称**项目真实发生过 Cache 损坏、TLAST 永久挂起或 DMAIntErr。它们属于从接口规范和源码设计出的可测试故障假设，计划用故障注入演示工具的诊断能力。

## 与新 Skill 的关系

仓库上述 DIFI 程序是已通过上板验证的**项目专用实现**；`templates/axi_dma_simple_loopback_template.c` 是为其他项目制作的**新通用教学模板**，目前尚未使用实际 Vivado/Vitis 构建与上板测试。离线 `scripts/` 仅检验静态信息与 UART 文本，不替代软硬件测量。
