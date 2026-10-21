# Vivado 可复现构建验收记录模板

- 工程名称：
- 目标设备 / Part：
- Vivado 版本：
- 原工程 Git Commit SHA：
- 导出日期、人员与运行设备：
- 重建环境：
- 是否使用**全新**目录：

| 验收层 | 检查项 | 结果（PASS/FAIL/NOT RUN） | 原始证据路径 |
|---|---|---|---|
| 快照 | 原工程 BD 由 `write_bd_tcl` 导出 | | |
| 依赖 | RTL、自定义 IP、XDC 均在交付仓库 | | |
| BD | 新工程 `validate_bd_design` | | |
| 生成 | 新工程 Wrapper 和 Top 正确 | | |
| 综合 | `synth_1` Complete | | |
| 实现 | `impl_1` write_bitstream Complete | | |
| 时序 | Setup WNS / Hold WHS；时钟及 unconstrained paths 检查 | | |
| 资源/DRC | `utilization.rpt` 和 `drc.rpt` 审核 | | |
| 硬件 | 新工程 `.bit` 与含 Bitstream 的 XSA | | |
| 软件 | 用新 XSA 重建 Vitis Platform/BSP/Application | | |
| 板级 | **新 bitstream** 下载后的真实功能测试 | | |

## 数据和指标

- 原工程 WNS / 重建工程 WNS：
- 原工程 LUT / FF / BRAM / DSP：
- 重建工程 LUT / FF / BRAM / DSP：
- 实际测试功能与数据规模：
- 相关 UART / PC 输出摘要：
- 工程差异与环境依赖：

## 结论与适用范围

说明结论严格对应哪一层，不要将 BD 校验、综合完成、Bitstream 生成或者上传旧平台的板级日志误写为完整重建验证。
