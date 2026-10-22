# 性能与资源证据图交付包 · 合并指南

本 ZIP 可以合并解压到 `D:\Study\project\DIFI\`。

## 包含内容

- `report/figures/` 新增 4 张图，分别有 SVG 和 PNG（共 8 文件）。
- `report/competition/difi_design_report_draft.md` 更新为 v0.2，在 5、6 章嵌入图 5-1、5-2、5-3、6-1；保留此前 3.1/3.2 的架构图引用。
- `report/competition/report_action_checklist.md` 标记已完成证据图任务。
- `report/competition/metrics_evidence_index.md` 列出原始证据、计算公式、测量口径及待补事项。
- `scripts/figures/build_performance_figures.py` 原始报告驱动的绘图工具；`README_metrics.md` 为操作说明。

## 使用

先确保之前的 **架构图 v1** 已合并进仓库（本包不会重复携带那两张架构图）。然后在根目录：

```powershell
cd D:\Study\project\DIFI
python -m pip install matplotlib
python scripts/figures/build_performance_figures.py --repo-root . --cpu-hz 666666667

git status --short
git diff -- report/competition/difi_design_report_draft.md
git add report/figures/ report/competition/ scripts/figures/
git diff --cached --stat
git commit -m "docs(report): add performance and resource evidence figures"
git push origin feature/rtl-integration
```

`build_performance_figures.py` 默认从仓库 `report/results/` 读取原始数据，若发现计数或格式不匹配会直接失败。这是为了防止将不同版本的 RTL、报告混用。

## 真实性与边界

图中的统计由当前 GitHub 仓库归档的原始 `.rpt/.csv/.rtf/.md` 公开数值核对；生成工具已用与这些数值一致的离线输入完成出图，最终可在本机使用**原始归档文件**再运行一次再生检查。此处没有进行新的 FPGA/RTL/PS 板级测试。

- OOC 综合资源≠已实现封装 IP 资源≠完整系统资源。
- PS CPU `666.667 MHz` 由开发者确认，性能换算仍依赖 PMU 时钟行为与实际 PS 配置；最终需保存设置证据。
- UDP 测试存在人为 2 ms/包间隔，不作为 UDP 吞吐率测量。
- 4 个 Skill 均保留“制作完成、待集中统一验收”状态。
