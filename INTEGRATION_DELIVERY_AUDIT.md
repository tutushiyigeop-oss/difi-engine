# 如何合并本次交付审查与演示规划包

这份包**没有覆盖原有 `README.md`、`skill/README.md`、`scripts/vivado/README.md`、`LICENSE` 或任何 RTL/Vitis 项目文件**；也未在 GitHub 上提交任何修改。适合先作为报告与检查工具加入现有仓库，再人工修订 P0/P1 项。

在 Windows 中解压至 `D:\Study\project\DIFI\`（不带额外顶层目录），然后执行：

```powershell
cd D:\Study\project\DIFI
python .\scripts\audit\test_check_submission.py
python .\scripts\audit\check_submission.py --repo-root . --output report/competition/local_audit_result.md
```

也可执行 `--strict`，存在 P0/P1 会以错误码退出；这说明整改待办尚在，不等于 RTL 测试失败。

文件清单：
- `report/competition/delivery_audit_20261022.md`：基于真实 GitHub 分支的审查快照。
- `report/competition/submission_gates.md`：整理、最终验收与发布三个阶段的任务门槛。
- `report/competition/demo_plan.md`：演示分镜、证据与录制准备。
- `report/competition/demo_narration.md`：可用的口播稿，必须配真实镜头。
- `report/competition/demo_evidence_manifest.csv`：可拍摄/已有素材清单，已按相对路径注明。
- `scripts/audit/check_submission.py`：本地只读检查；仅在指定 `--output` 时生成一份报告。
- `scripts/audit/test_check_submission.py`：最小单元测试，不依赖 Vivado/Vitis。
- `proposals/README_revision_notes.md`：根 README 和构建文档的准确修订建议（供人工合并）。
- `proposals/skill_README_4skills.md`：四个 Skill 索引推荐版本（先审核，再替换现有 `skill/README.md`）。

Git 操作建议：

```powershell
git status --short
git add report/competition/delivery_audit_20261022.md report/competition/submission_gates.md `
        report/competition/demo_plan.md report/competition/demo_narration.md `
        report/competition/demo_evidence_manifest.csv scripts/audit/
git diff --cached --stat
# 确认之后再 commit/push
```

建议先独立提交审查报告与演示规划，不要现在改变 `main`、仓库公开状态或大规模重命名。许可证需先明确项目代码权利归属及第三方资料的分发许可。请按 AMD 最终公告决定公开时间和视频格式。
