---
name: vivado-rebuild
description: >-
  从已存在且验证过的 AMD Vivado IP Integrator Block Design 提取 Tcl 快照，
  审计 RTL/IP/XDC 依赖，在全新的工程目录重建、综合、实现、导出 Bitstream/XSA，
  再分层记录板级验收。适用于自定义 IP、Zynq PS/PL、AXI DMA 等 Vivado 项目。
---

# Vivado Block Design 可复现构建

## 何时使用

- FPGA 工程可在作者电脑运行，但评委/其他队伍无法重建其 Vivado Block Design。
- 工程同时有 RTL Module Reference、自定义封装 IP、XDC 和多个板级硬件版本，需要防止误选工程。
- 准备竞赛验收或 Git 仓库瘦身，希望只提交可复现源码/脚本而不是 `.runs` 等缓存。
- 大模型被用于生成或修复 Vivado Tcl，需要验证结果而不是相信模型输出。

**不要用于**：没有可打开的原始 BD、只提供门级网表、外部闭源 IP 无法再分发、无法获得对应器件/许可证/工具版本的场景。PYNQ、Linux、Vitis BSP 的完整自动化部署也不在本 Skill 内。

## 输入与前提

1. **原始可用工程**：原始 `.xpr` 及 `.bd`，能在相应 Vivado 版本中打开。
2. **版本/器件**：目标 Part 与 Vivado 版本，初次复现必须匹配原构建环境。
3. **完整依赖**：模块引用 RTL、用户自定义 IP（`component.xml` 及源文件）、用户 XDC、处理器/时钟/地址配置。
4. **交付仓库**：上述用户文件纳入 Git；`/vivado/` 等生成目录在 `.gitignore` 内。
5. **复现测试入口**：原板级应用或测试程序、验收数据和成功/失败判据。

## 工作流

1. **确认工程身份**：读取原始项目的 `PART`、`TOP`、BD、Cell/VLNV。遇到同名 BD（如 DIFI B4/B5），必须额外检查真实的 Module Reference/IP 标识。
2. **从原工程导出快照**：调用 `write_bd_tcl -force`；记录工具版本、IP Repo、自定义约束与具体输入 RTL。*不要靠 AI 猜 IP 配置或 AXI 连线。*
3. **审计可移植性**：任何外部绝对路径、缺少的 `component.xml`、未提交的 XDC、未列入的 Module Reference RTL 都是阻断因素。
4. **空目录重建**：先添加自定义 IP 仓库与引用的 HDL，再 `source bd.tcl`、`validate_bd_design`、`generate_target` 和 `make_wrapper`。
5. **全流程构建**：运行 Synthesis、Implementation 到 `write_bitstream`；保存 Timing、Utilization、DRC、Clock、`check_timing` 报告和 XSA。
6. **最终板级回归**：必须导入**新 XSA**，并确认下载**新 Bitstream**，执行原功能测试。只有这步完成才能写“板级重建复现通过”。
7. **保留原始证据**：把首次错误、修复后的差异、完整命令、Git SHA、计时/错误日志和分层 PASS/FAIL 记录到报告。

## 使用方式：优先选择合适入口

### A. DIFI 项目（真实验证通过）

直接复用仓库现有脚本，不要重新实现另一套：

- `scripts/vivado/export_bd.tcl`
- `scripts/vivado/rebuild_bd.tcl`
- `scripts/vivado/verify_rebuilt_impl.tcl`

按 [DIFI 实测案例](examples/difi-case-study.md) 操作；三套工程的 Vivado 重建工具结果位于 `../../report/results/vivado_rebuild/`；板级反馈与实现报告应分别核对。

### B. 其他项目（可配置模板，尚待跨项目 Vivado 实测）

复制 [工程配置模板](templates/project_config.tcl)，根据真实工程填写：

- `name`、`bd_name`、`top`、`part`、`vivado_version`
- `rtl_globs`、`include_dirs`、`ip_repo_dirs`
- `snapshot_rel`、`build_rel`、`report_rel`

从仓库根目录按以下步骤执行：

1. `scripts/export_bd_generic.tcl`（原工程 GUI Tcl Console）
2. `scripts/rebuild_generic.tcl`（新 Vivado Batch）
3. `scripts/verify_impl_generic.tcl`（新 Vivado Batch）
4. 原板卡/软件测试

**证据等级**：通用 Tcl 已完成静态语法/约束检查，但截至本版**未在与 DIFI 无关的真实 Vivado 工程完成端到端测试**；不要将 DIFI 专用脚本的成功结果自动转嫁给通用版本。

## 关键失败模式

| 表现 | 常见原因 | 最小排查动作 |
|---|---|---|
| `open_bd_design unavailable` | 用 `info commands` 误判按需加载命令 | 直接执行 `version -short` / `current_project`，再尝试 IP Integrator 命令 |
| `user IP ... not found` | `ip_repo_paths` 缺失或 IP 版本不符 | 检查 `component.xml`、`update_ip_catalog -rebuild`、VLNV |
| `module reference ... unresolved` | 没有先 `add_files` 引用的 RTL | 检查 `rtl_globs`、include 路径，再 `update_compile_order` |
| BD 同名但行为不同 | 导出了错误工程版本 | 对比 BD 内 Module Reference/IP 标识与原报告 |
| 新工程跑得通但老 XSA 被加载 | Vitis Platform 没更新 | 用重建 `.xsa` 重建平台，确认新 bitstream 下载 |
| Implementation PASS 但板级错 | PS MIO/GEM、AXI 地址、时钟、DMA、XDC 或软件配置不同 | 比对原工程 address/PS/XDC、UART、PC 结果，不把 Timing PASS 当板级 PASS |
| `.gitignore` 已修改但远端仍有缓存 | Git 曾经跟踪它们 | 先审计 `git ls-files`，再经确认后 `git rm -r --cached`（仅取消跟踪） |

## 验收与失效条件

- **L1**：导出真实 `bd.tcl` 且记录依赖。
- **L2**：在新目录成功重建 BD，`validate_bd_design` 通过。
- **L3**：新的 Synthesis/Implementation/Bitstream/XSA 全部生成，Setup/Hold 满足约束，报告可审计。
- **L4**：新 Bitstream、新 XSA 对应的软件与真实板级测试通过。

有不可解析的外部 IP、缺失用户约束、时钟未约束、设计修改却沿用旧结果等情况时，不得声明 L3/L4。严格的时序签核还需要检查 `check_timing`、CDC 和 DRC，而非只看单个 WNS。

## 技能包内容

- [`../README.md`](../README.md)：Skill 使用入口与索引；通用流程见本文。
- [`scripts/`](scripts/)：通用导出、重建、实现与公共函数。
- [`templates/`](templates/)：项目配置、AI 协作提示词、验收报告。
- [`examples/difi-case-study.md`](examples/difi-case-study.md)：已发生的 DIFI 错误、修复和工具结果。
- [`tests/`](tests/)：不依赖 Vivado 的静态自检。

## 来源与边界

来源于 DIFI 1.1 FPGA 引擎的封装 IP 回环、B5 UDP TX 与 B6 UDP RX 工程。开发时出现了 Tcl 环境检查误报，并通过修复脚本检查方式、恢复 IP 依赖、重建工程和上板测试闭环确认。通用模板与专用工程脚本的输入条件不同，复用时须核对 IP、约束、器件和对应软件。
