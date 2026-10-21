# Vivado Rebuild Skill

> 技能类型：案例模板 + Tcl 校验工具 + 大模型协作工作流 + 踩坑清单。符合 AMD 自主选题赛道“适用场景、使用方法、验证效果、失效条件、问题来源”的技能包要求。

[查看技能定义](SKILL.md) · [DIFI 实测案例](examples/difi-case-study.md) · [AI 协作模板](templates/ai_workflow.md) · [验收记录模板](templates/acceptance_report.md)

## 范围和限制

适用于已有 Vivado IP Integrator Block Design 的工程。能从原工程导出真实 BD 连接信息、重建空工程并自动验证综合实现；**不自动推导不存在的 RTL、第三方 IP 或外部 XDC**。本模板目前以 Verilog 顶层为主，VHDL-only、多 BD/跨工程引用与特殊约束可能需要人工扩展。

设计约束：不对原工程执行 `reset_run` 或修改原有硬件，重建目录必须不存在。所有 Tcl 配置必须来自可信仓库；`source` 可执行任意 Tcl 代码，不要执行不可信快照。

## 两条使用路径

| 路径 | 使用者 | 当前验证范围 |
|---|---|---|
| DIFI 专用 | 本项目参赛队伍 | 已完成两套 BD 导出、独立重建、全流程实现、XSA，以及开发者确认的板级功能测试 |
| 通用模板 | 其他有 Vivado BD 的团队 | 已做 Tcl 静态检查；通用模板未跨项目上板验证 |

**本项目直接用现有 `scripts/vivado/` 下的 DIFI 已验证脚本，不需要切换到通用模板。** 参见 [DIFI 实测案例](examples/difi-case-study.md)。

## 通用流程（用于其他 Vivado 工程）

### 1. 准备可提交的仓库依赖

目录示意：

```text
my_project/
├── rtl/                       # RTL / Module Reference
├── ip_repo/                   # 自定义 IP，包括 component.xml
├── constraints/               # 可能存在的用户 XDC
├── skill/vivado-rebuild/      # 本技能包
├── scripts/vivado/config/
│   └── example_project.tcl   # 从模板复制、按真实工程修改
└── .gitignore
```

从 `skill/vivado-rebuild/templates/project_config.tcl` 复制一份到 `scripts/vivado/config/example_project.tcl`。配置里的所有相对路径均以仓库根目录为准，**不是以配置文件目录为准**。

确认 `name`、`bd_name`、`top`、`part` 正确；`rtl_globs` 需要列出全部 RTL/模块引用源文件，也可以写空列表 `{}`（完全依赖自定义封装 IP 时）；`ip_repo_dirs` 填**IP Repository 根目录**，不是某个 `component.xml` 的具体文件路径。不要把 `.gen/.runs` 路径填进去。

### 2. 从已经完成的原工程导出 BD

在 **Vivado GUI → Tcl Console**，原工程处于打开状态时执行：

```tcl
source D:/checkout/my_project/skill/vivado-rebuild/scripts/export_bd_generic.tcl
vrskill::export_bd scripts/vivado/config/example_project.tcl D:/checkout/my_project
```

- 会核对原工程的工具版本、Part、Top 和指定 BD 是否一致。
- 对真实 BD 调用 `write_bd_tcl -force`；保存 `bd.tcl`、`manifest.tcl`、`export_info.txt`，并复制当前 `constrs_1` 中可访问的用户 `.xdc` 文件。
- 可能提示外部 IP 仓库路径，**需要人工检查**，否则重建可能失败。
- 导出过程会执行 BD 的验证与保存，原工程有未保存的修改时应先手工备份或提交。

### 3. 空目录重建

在 **Windows PowerShell 的仓库根目录**执行：

```powershell
cd D:\checkout\my_project
vivado -mode batch -source skill/vivado-rebuild/scripts/rebuild_generic.tcl -tclargs scripts/vivado/config/example_project.tcl
```

如果 `vivado` 不在 PATH，使用 Vivado 2024.2 Tcl Shell 或安装目录中的 `vivado.bat`。脚本会：

1. 先检查快照存在、源文件模式能够匹配、IP 目录和 XDC 可访问。
2. 拒绝覆盖已有的 `build_rel` 目录。
3. 创建独立工程；先载入 RTL、自定义 IP，再恢复 BD。
4. 调用 `validate_bd_design`、`generate_target`、`make_wrapper`；设定顶层并保存 `.xpr`。

如果重建失败，不要立即删除文件，优先保留完整日志。清理并重试时必须由使用者核对后**手工重命名**新工程目录。

### 4. 新工程综合、实现与导出 XSA

```powershell
vivado -mode batch -source skill/vivado-rebuild/scripts/verify_impl_generic.tcl -tclargs scripts/vivado/config/example_project.tcl
```

成功后 `report_rel` 下预计包含：

```text
utilization.rpt
timing_summary.rpt
drc.rpt
clocks.rpt
check_timing.rpt
SUCCESS.txt
```

生成的 `.bit`、`.xsa` 在 `build_rel` 的新工程目录中。`SUCCESS.txt` 仅证明 Vivado 工具构建与定量时序门槛完成；**还需要人工审核不完全/未约束时序路径、DRC、CDC**。

### 5. 软件及板级回归

使用**新 XSA**在 Vitis 中重建 Platform、BSP 与应用；下载对应**新 Bitstream**。对照原测试运行相同输入，保存原始 UART/PC 输出，并填写 [验收模板](templates/acceptance_report.md)。跨软件/硬件环境时需手动检查 PS 时钟、GEM MIO、AXI 地址等依赖。

## 如何归档到 Git

`.gitignore` 示例（按实际路径调整）：

```gitignore
/vivado/
/vitis/vitis_ws_rebuilt/
.Xil/
*.jou
```

**注意**：建议不要全局忽略 `*.log`，因为原始验证日志也是竞赛证据。将自动生成的大型 Vivado 工程忽略于 `/vivado/` 下，验证结果主动归档至 `report/results/`。`/vivado/` 前面的 `/` 很重要，避免连 `scripts/vivado/` 一起忽略。

若已有生成文件被 Git 跟踪，修改 `.gitignore` 不能自动移除；先 `git ls-files` 核对，再执行 `git rm -r --cached -- <generated_workspace>`（**不会删除本地文件**），提交后远端才会清理当前版本。

## 验证、失败边界和通用性

| 验证类型 | 状态 |
|---|---|
| DIFI 专用 Tcl 在原工程导出 BD | 已实测 |
| DIFI 两套工程的新目录重建 | 已实测 |
| DIFI 两套 Vivado 工程综合/实现/Bitstream/XSA | 已实测，有 WNS/WHS 数值与 SUCCESS 证据 |
| DIFI 两套新 XSA 对应的板级功能 | 开发者已确认通过；原始上板日志应另外归档 |
| **本 Skill 的新通用模板**在 DIFI 以外的工程 | **未实测**，仅通过 Tcl 静态/约束检查 |

如果发生 IP 参数升级、板卡或器件改变、RTL 逻辑改动、外部不可访问文件或违反时序约束，请不要继续沿用旧的 PASS 结论。

## 本地自检（不需要 Vivado）

在仓库根目录：

```powershell
python skill/vivado-rebuild/tests/test_static.py
```

它检查技能包必需文件、模板字段、Tcl 解析以及路径/工程身份保护。还可执行模拟控制流程检查（使用临时目录和替身 Vivado Tcl 命令）：

```powershell
python skill/vivado-rebuild/tests/test_mock.py
```

两种检查都**不代表完成了真实 Vivado 的综合或板级测试**。
