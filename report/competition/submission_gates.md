# AMD DIFI 工程最终交付门槛（按依赖顺序）

> 当前遵从“先完成材料，最后集中验收 Skill”的安排。每项只能在证据齐全时打勾。

## A. 可不重新上板的整理工作

- [ ] 许可证：完成源码权属、第三方组件及 MIT/Apache-2.0 许可核查；最终根目录含 `LICENSE`。
- [ ] 根 README：修正两套 Vivado Tcl 快照已提交的现状；明确版本、硬件类型、BD 区别以及最短重建命令。
- [ ] `scripts/vivado/README.md`：把“待执行”状态改为真实工具 PASS、板级结果及日志存档状态。
- [ ] `skill/README.md`：四个 Skill 的状态统一为“已制作、待统一验收”。
- [ ] `report/results/perf/performance_summary.md`：CPU 时钟与 PMU 换算说明统一，并附 PS 配置证据。
- [ ] 原始 AI 聊天记录：逐字提示词/回复/纠错链路；完整性不足的案例保留待补标注。
- [ ] 导入两套原生 BD 截图；检查已存四张 UDP 截图的可读性。
- [ ] 将早期 `INTEGRATION.md` 归档到适当位置，确保根目录入口清晰。
- [ ] 运行本包 `scripts/audit/check_submission.py`，人工复核输出的路径/链接/命名问题。
- [ ] 评估历史文件名的大写情况，慎重制定 `git mv` 清理方案，避免破坏已有链接与脚本。

## B. 统一实测阶段（依照用户计划最后进行）

- [ ] 四个 Skill 自检/正反例测试及真实项目实测，区分已通过/未覆盖项。
- [ ] 跨 DIFI 项目的 Skill 复用验证，填写 `report/skill_validation_report.md`。
- [ ] 确认新 XSA 与板级 UART/PC 日志和 Bitstream 属于同一版本。
- [ ] 使用最终 Git SHA 完整执行一次原生 Vivado Tcl 重建（或在现有实测上留下版本匹配证据）。
- [ ] 录制真实板卡 UART、Wireshark 与 PC 端输出；成功时保留原始日志，不剪去错误/警告解释。

## C. 对外公开与提交

- [ ] 经审核后选择公开 GitHub 或赛事认可的授权访问方式；本仓库当前 `private=true`。
- [ ] 验证评委打开默认 `main` 能看到最新内容；最后合并 `feature/rtl-integration`。
- [ ] 创建不可随意重写的固定提交/Tag，并在报告和演示中引用同一 SHA。
- [ ] 仅发布允许再分发的文件，避免泄漏 Token/用户名/学校个人信息以及未授权文档。
- [ ] 对照大赛当期公告检查是否需要指定格式的 PDF、视频、PPT 或在线平台提交；本清单**不假设所有文件类型都是强制**。
