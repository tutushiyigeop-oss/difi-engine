# GitHub 发布操作手册（安全预检查与正式发布）

## 1. 当前状态

Private；默认 main；研发分支 feature/rtl-integration；LICENSE 待定。本手册不会对 GitHub 直接执行任何可见性或分支操作。

## 2. 本地只读检查（PowerShell）

```powershell
cd D:\Study\project\DIFI
git status --short
git branch --show-current
git fetch origin
git ls-files vivado/
git ls-files | Select-String -Pattern '\.(xsa|bit|elf|dcp|xpr)$'
python scripts/audit/check_submission.py --repo-root . --output report/competition/local_audit_result.md
```

检查**公开历史**而不只是当前工作树：

```powershell
git log --all --name-status --pretty=format:"%h %ad %s" --date=short > history_paths_review.txt
git rev-list --objects --all > history_objects_review.txt
git grep -n -I -E '(password|passwd|secret|token|api[_-]?key|PRIVATE KEY)' -- .
```

扫描可能误报、漏报；必须人工审核历史 DOCX、RTF、PCAP、代码、Actions 日志和提交信息。**不要把检查中出现的真实密钥或原始日志分享出去**，审计输出也不应直接加入公开仓库。若有真实凭据，先撤销/轮换，再参考 GitHub 官方敏感历史清理说明。

**保护本地完整 Vivado 工程：禁止机械执行 `git clean -fdx`、`git reset --hard`、`git push --force`。** Git 忽略目录中的工程不是公开仓库的一部分，也不应在清理过程中被误删。

## 3. 两种发布路径

**A. 原仓库公开**：仅在源码及可访问的**全部旧历史**版权、隐私审查通过后，审核 PR 并将竞赛版本纳入 main，由管理员在 GitHub Settings -> General / Danger Zone -> Change repository visibility 手动设置 Public。公开不只涉及最后一个 Commit。

**B. 干净快照仓库**：如果历史中有敏感信息或不适合公开的依赖，建立**不继承原始 Git 提交历史**的新公开仓库，仅导入审核过的源码、可重建脚本、合法证据、Skill、README、正式 LICENSE。这会产生新的公开 SHA；报告和比赛提交应指向新的 SHA。

如果选择“仅邀请评委访问私有仓库”，需先得到比赛认可，确认评委有可用 GitHub 账号；它不等于指南鼓励的公开开源。

## 4. 最终版本冻结（仅作未来命令示例，不要现在执行）

```powershell
git status
git fetch origin
git switch main
git pull --ff-only origin main
# 审核后的 PR 先合并，再同步
git pull --ff-only origin main
git log -1 --format="%H %s"
# 明确审批和最终验收后：
git tag -a v1.0.0-competition -m "DIFI 1.1 AMD competition submission"
git push origin v1.0.0-competition
```

正式 Tag 不得随意移动或重用。提交的 URL、完整 SHA、报告、原始证据版本须一致。正式发布后用无痕浏览器/未获私有权限账号检查访问、下载、`git clone`、文档相对链接和从零复现入口。

GitHub 说明：
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility
- https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository