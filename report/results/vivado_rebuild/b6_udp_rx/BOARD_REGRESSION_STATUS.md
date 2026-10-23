# B6 v0.2：独立重建及三类 UDP RX 板级回归——本阶段完成

> 验收日期：2026-10-23 · Vivado/Vitis 2024.2 · XC7Z020CLG400-2 · 开发者完成板级实测并确认结论

## 本阶段验收结论

**PASS / 本阶段收束。** B6 v0.2 从已提交的真实 Block Design Tcl 和 FPGA RTL/IP 源码，在全新 Vivado 工程完成独立重建、综合、实现、Bitstream/XSA 生成，并由开发者确认使用重新构建的硬件平台再次完成 Version、Context、Signal Data 三类 UDP RX 功能回归。

本阶段采用“Vivado 工具结果 + 原始 B6 功能测试证据 + 开发者对重建后板级回归的明确确认”作为验收口径，不额外设置其他文件配对材料作为结束条件。以上属于**本项目在既定测试范围内完成的验证**，不称为第三方异机复现、正式 DIFI 认证或同时全双工性能测试。

## 已归档的工程证据

| 项目 | 证据 / 数值 |
|---|---|
| 真实 BD 快照 | `scripts/vivado/generated/b6_udp_rx/{bd.tcl,manifest.tcl,export_info.txt}` |
| 原始工程实现 | `report/results/b6_impl/` |
| 独立新工程实现 | `report/results/vivado_rebuild/b6_udp_rx/SUCCESS.txt` 及同目录时序、资源、DRC、时钟报告 |
| 综合 / 实现 / Bitstream / XSA | Vivado 2024.2 PASS |
| Setup WNS / Hold WHS | +2.372 ns / +0.053 ns |
| 原始三类 RX 真实 UART 证据 | `report/results/udp/rx/three_types_udp_rx.rtf`，Version×1、Context×1、Data×20，5,120 IQ Golden PASS |
| 独立重建后板级回归 | 开发者 2026-10-23 确认 Version / Context / Data 测试再次通过 |

`SUCCESS.txt` 由 Vivado 实现脚本在板级回归之前生成，其中的 `Vitis/board not yet retested` 是**生成当时的历史状态**；板级回归随后完成，故保留该原始文件，不进行追改。原始 B6 UART 记录同样保持其原有测试轮次，不将其改写为后续复测日志。

## 独立重建 XSA / Bitstream SHA256

开发者通过本机 PowerShell `Get-FileHash -Algorithm SHA256` 得到以下结果；值用于文件内容辨识，不单独作为实际板级加载行为的证明。

| 文件 | SHA256 |
|---|---|
| `vivado/rebuilt/b6_udp_rx/b6_udp_rx_rebuilt.xsa` | `BAA79DCA51DCA96674D38167642BC266CCC7A2D9EDA906AC1B5A543462343D20` |
| `vivado/rebuilt/b6_udp_rx/difi_rebuilt_b6_udp_rx.runs/impl_1/difi_ip_test_wrapper.bit` | `1B986023CCE7FCF3789D11E2CC62319848DC57E67400E10A5E8B5F961CAFF9B8` |

原始工程的 XSA SHA256 存在 `report/results/b6_impl/PROVENANCE.md`，与本次独立重建不同，不得混淆。大型二进制构建产物保留本地，由仓库中的源码及 Tcl 复现。

**最终状态：B6 v0.2 真实 BD 导出、独立重建、时序检查、Bitstream/XSA 生成及三类 UDP RX 板级回归均已完成。本阶段验收结束。**
