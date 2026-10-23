# AMD 自主选题赛道：接下来工作的执行清单

> 文档基准：2026-10-22；四个 Skill 已制作，统一验证暂缓。此文件可放入 `report/competition/`。

## 本周先完成（不需要重新上板）

- [ ] 审阅 `difi_design_report_draft.md` 的技术结论与表达范围。
- [ ] 确认项目简介、正式参赛题目、参赛队员、指导教师等封面信息。
- [x] 绘制 RTL 收发架构图、B5 真实系统架构图（SVG + 高清 PNG），核对 RX/B5 边界，并已插入报告初稿。
- [ ] 在 Vivado 打开 `difi_ip_test` 与 B5 `difi_system`，各保存一张真正的 BD 截图。
- [x] 从已归档的 OOC Report、RTL latency CSV、板级 PMU 日志、UDP 验证记录制作四张证据图（SVG + PNG），并嵌入报告 5/6 章。
- [x] B5 UDP Wireshark 的 22 包总览及 Version / Context / Data 四张截图已入库 `report/results/udp/tx/screenshots/`；视频录制前仍需核对清晰度。
- [x] 同步修订旧性能汇总里的“待校准”措辞；保留原始 PMU ticks 与按开发者确认约 666.667 MHz 的换算值。
- [ ] 归档与实际测试 XSA 对应的 PS CPU 时钟配置原始证据（截图/配置文件），确认数值对应关系。
- [ ] 收集新 XSA 对应的 Vitis 编译和实际板级结果（已有测试不用重跑，只补原始日志）。

## AI 协作记录（可以与报告并行）

每个案例用同一格式：

1. 真实需求及首次模型提示词（原文或明确截取的片段）。
2. 模型的关键建议/生成内容与版本。
3. 实际执行/仿真/板级检查结果（日志、截图、Git diff）。
4. 错误或局限：模型哪里判断错了、遗漏了什么。
5. 用户反馈及模型纠正建议（保留原始记录）。
6. 人工修改和复测结果。
7. 从中抽象出的 Skill 规则与失效条件。

优先整理 `open_bd_design unavailable` → 修改环境检查 → BD 导出/重建 PASS，材料连贯且日志明确。

## 最终提交前集中完成

- [ ] 四个 Skill 的静态/真实/跨项目验收，形成 `report/skill_validation_report.md`。
- [ ] 新通用脚本及验证器正反例测试的最终日志归档。
- [x] 已同步 README、Vivado 构建文档和四套 Skill 目录的“已制作/待统一验收”口径；正式发版仍须对最新分支重新审查。
- [ ] 仓库的开源许可证及第三方工具授权审查。
- [ ] 统一 `.gitignore`、检查 Git 中是否混入生成 Workspace。
- [ ] 冻结分支 SHA / Tag，进行一次完整复现与演示。
- [ ] 完成竞赛提交格式、PPT/视频等以官方最新通知为准的项目文件。

## B6 更新（2026-10-23）

- [x] B6 Data-only 与三类报文板级 UART 结果归档 `report/results/udp/rx/`。
- [x] B6 v0.2 Vitis 源码、Metadata Monitor RTL、PC 三类发包器入库。
- [x] B6 v0.2 真实 BD Tcl、原始及独立重建实现报告、XSA 生成证据均已入库。
- [x] 开发者确认重建的新 XSA 已通过三类 UDP RX 板级回归（2026-10-23）。
- [ ] 补档此次重建 XSA 对应的 PC/串口/Vitis 原始日志与哈希匹配证据。
- [ ] 录制 B6 实时视频和对应 PC 完整控制台日志。
