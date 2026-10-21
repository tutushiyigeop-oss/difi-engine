---
name: zynq-dma-debug
description: >-
  面向 Zynq-7000 / Vitis Standalone AXI DMA Simple Mode 的数据通路审计与故障排查。
  结合 MM2S/S2MM、AXI4-Stream TLAST/握手、内存与缓存一致性、SDT/legacy BSP，
  使用离线日志分析、配置检查、最小代码模板和真实板级案例组织证据驱动的调试流程。
---

# Zynq AXI DMA 数据通路与 Cache 一致性调试

## 适用场景

- 新集成 PS DDR ↔ AXI DMA ↔ PL IP，DMA MM2S/S2MM 初始化失败、Busy 卡住、状态寄存器报错或结果比对失败。
- 已有 Zynq-7000 Standalone 工程，需核对 AXI4-Stream TLAST、传输字节数、TKEEP、TVALID/TREADY、RX 初始化顺序与 CPU DCache 操作。
- Vivado/Vitis 2024.2 SDT 或 legacy BSP 切换后，`XAxiDma_LookupConfig` 使用设备 ID/基地址方式发生不兼容。
- 大模型参与排查，需要从“猜测可能原因”改为“收集寄存器、提出可证伪假设、每步实测”。

**不适用或需改写**：AXI DMA Scatter-Gather、Linux DMA 驱动/设备树与内核 DMA API、VDMA、PCIe DMA、非 AXI DMA IP、cache-coherent ACP/HPC 特殊路径。本 Skill 不是硬件调试器，也不自动编辑 BD/下载 Bitstream。

## 输入前提

1. 可确认的板卡和 PS/PL 硬件架构：DMA 模式、通道使能、DRE、Memory Mapped/Stream 接口宽度、时钟复位与连接。
2. 当前 XSA、Vivado Address Editor、DMA IP 配置、Vitis BSP 生成的 `xparameters.h`；对当前工具版本核对驱动签名。
3. DMA 发送和接收的**物理可访问内存区**、BUFFER 容量、事务长度（字节）、缓存行对齐情况。
4. DMA MM2S_DMASR / S2MM_DMASR 原始 32 位值、两个通道的 Busy 状态、UART 原始日志、必要时 ILA 波形。
5. 明确应用期望：纯 32-bit Stream loopback？DIFI 解析后 IQ？还是完整 DIFI Packet？三者的 S2MM 字节数不同。

## 操作工作流

### 1. 先区分“软件启动失败”和“数据流未终止”

- 先记录 `XAxiDma_LookupConfig`、`CfgInitialize`、`HasSg`、两次 `SimpleTransfer` 的返回值，确认 DMA 不在 SG 模式。
- 区分 `XAXIDMA_DMA_TO_DEVICE`（MM2S）和 `XAXIDMA_DEVICE_TO_DMA`（S2MM），分别记录 `MM2S_DMASR` 与 `S2MM_DMASR`，并解析错误标志。
- 如果 DMA Busy，观察 PL 是否存在实际的 TVALID/TREADY 握手和最后一个握手 beat 上的 TLAST；不要仅凭 AXI-Lite 状态推断 TLAST 已出现。
- S2MM 通常需要先于可立即输出数据的源启动。尤其带启动 Version/Context 的系统，在 TX 使能前先武装 RX。

### 2. 检查字节数、地址与缓存

- `SimpleTransfer(..., Length, ...)` 的 `Length` 为**字节**，不是 32-bit Word 数；它不能超过硬件配置的 BTT 上限或实际缓冲容量。
- 对无 DRE 的 DMA 按实际通道的 Memory Mapped 数据宽度和 IP 配置检查地址对齐；对缓存区域进一步检查 cache-line 隔离，防止误伤同一行的其他数据。
- TX：CPU 写数据后、MM2S 启动前 `Xil_DCacheFlushRange`；RX：若 CPU 曾写过目标缓存行，DMA 前清理脏行并禁止 CPU 并发访问，DMA 完成后 `Xil_DCacheInvalidateRange` 后再读数据。
- 若 CPU/DMA 缓存一致性属性与上述非一致性路径不同，应改用对应平台/驱动的正确同步方法，不能照搬。

### 3. 离线工具辅助检查

- 根据真实硬件填好 [`templates/example_transfer_plan.json`](templates/example_transfer_plan.json)，运行 `scripts/dma_config_check.py`，审计地址、容量、长度、BTT、DRE 对齐和缓存行提示。**示例地址纯属占位，不能下载到开发板。**
- 对**纯文本 UART 日志**运行 `scripts/dma_log_analyzer.py`，从 `SR=...` / `status=...` 提取常见 DMASR 标志和显式 `[FAIL]` 信息。它不能读取寄存器、不能检测 RTL 中没有观测到的 TLAST，也不能替代真实数据比对。
- 两种脚本只给出 `PASS_STATIC_ONLY` / `PASS_EVIDENCE_ONLY` 等**有限证据判定**，绝不表述为“板级 PASS”。

### 4. 创建最小复测案例

- 纯 AXI4-Stream loopback 项目可参考 `templates/axi_dma_simple_loopback_template.c`。**需要在用户真实 Vivado BD 中存在支持 TLAST 的 MM2S→S2MM 路径**，同时核对 Vitis BSP 宏定义后才能编译和运行。
- DIFI 工程不要直接运行此通用示例：应从已验证项目源码中选择对应程序，因为它还要求控制寄存器 Commit、UTC 初始化与协议引擎使能。
- 先做单包、再多包、再负载/背压测试；每次保存输入、输出、DMASR、耗时、PASS/FAIL 和准确的软件/XSA 版本。

### 5. 处理 AI 建议与验收

- 使用 [`templates/ai_debug_prompt.md`](templates/ai_debug_prompt.md)，要求模型将事实与假设分开，提出最小可证伪的检查项。
- 先保留首个失败的串口/ILA/软件日志，再尝试修复；只能记录实际发生过的失败、纠错和复测。
- 按 [`templates/acceptance_report.md`](templates/acceptance_report.md) 对齐验证等级，说明测试的是哪个通路、比较了多少字节、是否包含初始报文、时钟与缓存条件。

## 快速排障矩阵

| 现象 | 可证伪检查 | 不应直接断言 |
|---|---|---|
| `XAxiDma_LookupConfig == NULL` | 看生成 `xparameters.h`、SDT 与 BSP 驱动 API 是否对应 | “DMA 硬件坏了” |
| `SimpleTransfer` 返回失败 | 对照 `HasSg`、长度上限、对齐、DMA Busy、错误状态 | “驱动有 Bug” |
| S2MM Busy 永不结束 | ILA 看 TVALID/TREADY 与实际 TLAST，核对 S2MM BTT、源是否启动 | “一定是 TLAST” |
| 传输成功但数据不匹配 | CPU/DCache 顺序、Buffer 重叠、DRE/地址对齐、数据字节序与 TKEEP | “一定是 Cache” |
| B5 启动 Version/Context 丢失 | 比对 S2MM 是否先启动，Packet TLAST 与 Length，TX 开始时机 | “必然是 UDP 丢包” |
| 测试吞吐率低于 RTL | 拆分 DMA 事务窗口、PS 轮询、Cache 维护、软件重装载、网络节流 | “PL 速率只能这么高” |

## 验证范围与失效条件

- **项目实证**：DIFI 封装 IP Simple DMA IQ 回环已验证 100×256 IQ，无数据失配；B5 原始 Packet S2MM → PS UDP → PC 的 22 报文已验证。细节见 [`examples/difi-case-study.md`](examples/difi-case-study.md)。
- **新工具验证**：随附离线 Python 诊断工具提供正反例测试，能产生离线判定。它们的功能边界不应替代实际硬件检查。
- **新 C 模板**：尚未在其他真实工程编译/运行；不标记为“跨项目板级验证通过”。
- 超出板卡/缓存体系、地址不合法、DMA SG 模式、驱动版本不兼容、无 TLAST 的拓扑、有其他 IP 控制要求时，必须先调整工作流；不得照抄后宣称成功。

## 交付物索引

- [`README.md`](README.md)：快速安装、命令、退出状态、使用条件。
- [`scripts/dma_config_check.py`](scripts/dma_config_check.py)：离线 DMA 配置和内存区域审计。
- [`scripts/dma_log_analyzer.py`](scripts/dma_log_analyzer.py)：离线 UART 日志与 DMASR 解析。
- [`templates/axi_dma_simple_loopback_template.c`](templates/axi_dma_simple_loopback_template.c)：可移植的独立硬件教学模板（未上板验证）。
- [`templates/ai_debug_prompt.md`](templates/ai_debug_prompt.md)：AI 排障提示词。
- [`templates/axis_dma_probe_checklist.md`](templates/axis_dma_probe_checklist.md)：ILA/TLAST/TKEEP 现场探测清单。
- [`templates/acceptance_report.md`](templates/acceptance_report.md)：实际复现证据模板。
- [`examples/difi-case-study.md`](examples/difi-case-study.md)：已实施的 DIFI 工程案例与证据范围。
- [`tests/test_tools.py`](tests/test_tools.py)、[`tests/VALIDATION.md`](tests/VALIDATION.md)：离线单测与待测项。
