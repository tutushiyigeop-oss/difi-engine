# B6 v0.2：独立重建后板级三类 UDP RX 回归状态

> 日期：2026-10-23；目标：`feature/rtl-integration` 的 B6 v0.2。

## 独立构建证据（工具生成，已入库）

- 原始 BD：`scripts/vivado/generated/b6_udp_rx/bd.tcl`、`manifest.tcl` 与 `export_info.txt`。
- 原始工程 Routed 结果：`report/results/b6_impl/`。
- 新目录独立重建：`report/results/vivado_rebuild/b6_udp_rx/SUCCESS.txt`、`timing_summary.rpt`、`utilization.rpt`、`drc.rpt`、`clocks.rpt`。
- Vivado 2024.2，器件 `xc7z020clg400-2`，新工程已完成综合、实现、Bitstream/XSA；Setup WNS `+2.372 ns`，Hold WHS `+0.053 ns`。

## 重建 XSA 后的板级回归（开发者确认）

2026-10-23，开发者在项目对话中明确确认：**已从仓库源码和真实 B6 BD Tcl 在全新 Vivado 工程中成功重建、生成新 XSA，并在 Zynq 开发板上再次成功完成 Version、Context、Signal Data 三类 UDP RX 联测。** 这是开发者对硬件回归完成情况的确认，并非通过本文件附带的全套运行日志独立复核。

注意：`SUCCESS.txt` 内的 `Vitis/board not yet retested` 是**该 Vivado 工具报告生成时的状态**，生成后又完成了硬件回归，故不修改原始输出。`report/results/udp/rx/three_types_udp_rx.rtf` 是之前原始 B6 三类联测的 UART 记录；没有证据证明它就是此次重建 XSA 的新运行日志。

可在本机生成相应哈希（全部单行命令）：

`Get-FileHash "vivado/rebuilt/b6_udp_rx/b6_udp_rx_rebuilt.xsa" -Algorithm SHA256`

B6 当前结论：**Vivado 独立重建工具 PASS；新 XSA 板级三类 UDP RX 回归由开发者确认 PASS；原始复测日志及版本绑定仍待补证。**
