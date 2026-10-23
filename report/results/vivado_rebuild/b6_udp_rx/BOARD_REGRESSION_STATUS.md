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

## 独立重建产物文件指纹（2026-10-23 本机 PowerShell 实测）

开发者在仓库根目录执行 `Get-FileHash -Algorithm SHA256`，提供如下**独立重建工程**本地文件的 SHA256。这些哈希仅用于标识文件内容，**不能单独证明上板回归实际加载的文件版本**：

| 产物 | 相对仓库根目录的本地路径 | SHA256 |
|---|---|---|
| B6 rebuilt XSA | `vivado/rebuilt/b6_udp_rx/b6_udp_rx_rebuilt.xsa` | `BAA79DCA51DCA96674D38167642BC266CCC7A2D9EDA906AC1B5A543462343D20` |
| B6 rebuilt Bitstream | `vivado/rebuilt/b6_udp_rx/difi_rebuilt_b6_udp_rx.runs/impl_1/difi_ip_test_wrapper.bit` | `1B986023CCE7FCF3789D11E2CC62319848DC57E67400E10A5E8B5F961CAFF9B8` |

**不可混淆：** `report/results/b6_impl/PROVENANCE.md` 中 `32878bef391c4e06d190454ce198aa5bf8feaf2f82e8362a590f1d7758419b7c` 是**原始 B6 工程 XSA** 的 SHA256，不属于这次独立重建的 XSA。这些二进制产物仍在开发者本地，仓库仅保存源码、重建结果和哈希。

## 仍待补齐的板级版本证据

- [x] 独立重建 XSA SHA256。
- [x] 独立重建 Bitstream SHA256。
- [ ] Vitis ELF SHA256，以及 Vitis Platform 使用该 XSA 的配置/构建记录。
- [ ] 此次新 XSA 三类 UDP RX 复测的 UART、PC 原始输出和 Vitis 构建日志。
- [ ] 实际测试时的源代码 Git SHA，以及 XSA/Bitstream/ELF 与测试运行记录的对应关系（当前文档提交 SHA 不等于硬件生成时的源码 SHA）。

B6 当前结论：**Vivado 独立重建 PASS；开发者确认新 XSA 三类 UDP RX 上板 PASS；独立重建 XSA/Bitstream 哈希已入库，实测版本关联与复测原始日志待补。**
