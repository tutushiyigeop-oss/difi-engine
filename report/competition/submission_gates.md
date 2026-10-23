# AMD DIFI 工程最终交付门槛（按依赖顺序）

> 当前遵从“先完成材料，最后集中验收 Skill”的安排。每项只能在证据齐全时打勾。

## A. 可不重新上板的整理工作

- [ ] 许可证：完成源码权属、第三方组件及 MIT/Apache-2.0 许可核查；最终根目录含 `LICENSE`。
- [x] 根 README：已说明三套真实 Tcl 快照与 B6 v0.2 的区别及重建边界。
- [x] `scripts/vivado/README.md`：已同步历史两套及 B6 独立重建的工程状态。
- [x] `skill/README.md`：已统一为“已制作、待统一验收”。
- [x] `report/results/perf/performance_summary.md`：PS CPU 频率 666.666666 MHz 已确认并同步。
- [ ] 将既有测试与原始 XSA 的时钟设置进行文件级关联归档。
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

## B6 v0.2 交付

- [x] Version/Context/Data 三类 UDP RX 串口证据、PC 发包脚本、PS 软件和监控 RTL 已归档。
- [x] B6 v0.2 真实 BD Tcl/manifest、原始及独立重建的 Vivado 实现报告已提交，新 XSA 已生成。
- [x] B6 独立新 XSA 三类 UDP RX 板级回归由开发者确认通过（2026-10-23）。
- [x] B6 独立重建 XSA、Bitstream SHA256 已归档。
- [ ] 归档本次新 XSA 对应的 Vitis/UART/PC 原始运行日志、ELF SHA256 及版本关联；不得以旧串口记录代替。
- [ ] B6 实时录屏及完整 PC 控制台原始记录。
