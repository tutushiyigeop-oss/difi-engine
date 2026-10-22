# DIFI 架构图交付包 · 合并指南

把 ZIP **直接解压到** `D:\Study\project\DIFI\`（保持目录结构）。

- `report/figures/`：两张正式架构图，各包含 SVG + 3600 px 宽 PNG。
- `report/competition/difi_design_report_draft.md`：在上一版 v0.1 报告相应章节 **3.1 / 3.2** 中嵌入了两张图（解压时会覆盖同名初稿，请先检查 Git diff）。
- `report/competition/report_action_checklist.md`：更新架构图任务状态，其他工作仍保持待办。
- `docs/architecture/`：架构及证据说明、README 插图范例，以及可修改的 Mermaid B5 简图。
- `scripts/figures/build_architecture_figures.py`：可重新生成 SVG / PNG 的 Python 绘图源码。

PowerShell：

```powershell
cd D:\Study\project\DIFI
git status --short
git diff -- report/competition/difi_design_report_draft.md
git add report/figures/ docs/architecture/ scripts/figures/ report/competition/
git diff --cached --stat
git commit -m "docs(architecture): add DIFI B5 system and RTL block diagrams"
git push origin feature/rtl-integration
```

**注意**：这是基于 Verilog 和 `bd.tcl` 绘制的抽象示意，不是原生 Vivado BD 截图。此次没有修改 RTL/IP/Vitis 项目，也未开展四个 Skill 的统一测试。
