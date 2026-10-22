# 合并到 DIFI 仓库

将本 ZIP 中的 `report/ai_collaboration/` 和 `report/competition/` 拷贝/合并到 DIFI 仓库根目录。`difi_design_report_draft.md` 是上一版设计报告的**第 8 章整合更新版**，保留之前的架构图和性能图引用；建议先用 `git diff` 检查与本地最新报告的差异。不会覆盖 RTL、Skill 或原始实验日志。

第 8 章链接与五个案例摘要已集成到更新的 `difi_design_report_draft.md`。

**建议命令（在仓库根目录运行）：**

```powershell
python .\report\ai_collaboration\check_evidence.py --repo-root .
git add report/ai_collaboration/ report/competition/ai_collaboration_report.md report/competition/difi_design_report_draft.md
git diff --cached --stat
git commit -m "docs(report): add AI collaboration evidence and correction case studies"
git push origin feature/rtl-integration
```

待原始对话完成导出、四个 Skill 统一测试通过后，继续补齐这份专项报告。文件名和目录仅用英文，正文可以中文。
