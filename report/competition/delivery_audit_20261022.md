# DIFI 1.1 FPGA 竞赛仓库交付审查（v0.1）

> 核查日期：2026-10-22  
> 仓库：`tutushiyigeop-oss/difi-engine`  
> 对象：`feature/rtl-integration`，检查时最新 SHA：`087c024bb8f3e9fe17cfc3246a3bea93a7ba19ff`  
> 方法：读取 GitHub 仓库元数据、当前分支文件树、README/Skill/报告/Tcl，以及已保存的原始实验结果。不涉及新 Vivado/Vitis/Skill 实测。  
> 说明：这是**审查快照**；提交前必须对当时的最终 Commit 再检查一次。

## 结论

工程代码、四个 Skill、脚本和重要性能/UDP 证据已经具备。优先阻碍评委理解和复现的不是 RTL 功能，而是**仓库公开性、默认分支、许可证与部分过时的复现文档**。请先完成非破坏性的文档及开源治理，再执行最后的 Skill/硬件统一验收。

## 阻断性风险（P0）

| ID | 现状/证据 | 为什么重要 | 建议动作 | 状态 |
|---|---|---|---|---|
| P0-01 | GitHub 仓库元数据 `private=true` | 公开仓库地址不能保证评委可直接访问 | 先审查敏感信息/第三方资料，正式提交时按赛事要求公开，或采用赛事允许的授权访问方式 | 未完成 |
| P0-02 | `default_branch=main`；已检查的重要新增资料均在 `feature/rtl-integration` | 打开仓库主页可能看不到最新工程 | 冻结可验证版本后合并/快进到 `main`，建立 Tag，并核对主页 | 未完成 |
| P0-03 | 根目录没有 `LICENSE`，GitHub 元数据 `license=null` | AMD 指南强烈建议可再分发开源许可，推荐 MIT/Apache-2.0 | 审核自有源码权属及第三方组件；经项目负责人确认，加入适当许可证及依赖声明 | 未完成 |
| P0-04 | 根目录 `README.md` 第 5.3 节仍称“未提交可自动重建两套完整 BD 的 .tcl … 成套产物” | 与现存 `scripts/vivado/generated/{packaged_ip,b5_raw_export}/bd.tcl`、重建脚本与 PASS 结果矛盾 | 不要求提交大体积 `.bit/.xsa`；准确说明已提交脚本、快照、报告，运行时再生成 bitstream/XSA | 未完成 |

注意：P0-04 **不能**改成“已经将 `.bit/.xsa` 上传 GitHub”。实际仓库提交的是源码、Tcl 快照和日志，生成工程位于本地忽略目录。

## 重要整改（P1）

| ID | 现状/证据 | 建议动作 |
|---|---|---|
| P1-01 | `skill/README.md` 仍只有 `vivado-rebuild` 归入“已完成”，后三项写作尚未制作；但目录已有四个 Skill | 更新索引，四个标为“**已制作、待统一实测**”，不要称通用模板已跨项目通过 |
| P1-02 | `scripts/vivado/README.md` 开头仍描述“尚未生成真实快照，尚未执行实现/Vitis 回归” | 依据 `report/results/vivado_rebuild/*/SUCCESS.txt` 及用户完成的重建后板级测试事实更新；原始板级日志是否归档需单独注明 |
| P1-03 | `report/results/perf/performance_summary.md` 仍写“CPU 频率待确认”，而根 README/设计报告按 666.667 MHz 换算 | 统一证据链，补引用 Vivado PS 时钟参数的来源，并同步修订老摘要。PMU 硬件计数假设也需保留 |
| P1-04 | `report/ai_collaboration/raw/` 只有说明文件，尚无五个案例的原始 AI 对话 | 用真实导出/截图补 E1；事后技术复盘不可伪装成完整模型回复 |
| P1-05 | `INTEGRATION.md` 留在仓库根目录，内容是某次 ZIP 合并说明 | 保留归档价值时移至合适文档目录；主 README 要成为唯一清晰入口 |
| P1-06 | `docs/interface/`、`docs/protocol/`、`verification/reports/` 存在历史大写文件或目录名（详见脚本扫描） | 指南要求小写英文、数字、下划线、连字符；建议提交前集中检查和有计划改名（同步更新链接/脚本）。在 Windows 上处理纯大小写改名须使用临时文件名 |
| P1-07 | 新 XSA 的两套板级回归开发者已确认，但 `SUCCESS.txt` 原始证据仅覆盖 Vivado 工具层 | 将新 XSA 与实际运行 UART/PC 日志匹配，留存可复核的时序和 SHA，不要求为了整理文档重复执行已通过测试 |

## 已确认的良好基础

- 文件树检查：**487** 个 Git Tree 条目，其中 **341** 个文件、**146** 个目录；当前所有路径均未检测到中文或空格。
- 当前根 README 的 **59 个 Markdown 相对链接**经目标路径核对，均可在当前分支的文件树中找到对应文件或目录。
- 四个 Skill 目录均存在：`vivado-rebuild`、`zynq-dma-debug`、`axis-rtl-verification`、`udp-packet-validation`。
- `scripts/vivado/generated/packaged_ip/`、`scripts/vivado/generated/b5_raw_export/` 均有已提交 `bd.tcl`/`manifest.tcl`，两套 `report/results/vivado_rebuild/*/SUCCESS.txt` 均存在。
- UDP 证据含完整 `report/results/udp/difi_b5_udp_22.pcapng`、三类报文截图与参考工具日志。应如实称“参考工具检查 PASS”，不是官方 DIFI 认证。
- DIFI PS/PL 与 UDP 的两种硬件工程边界在最新报告中已有区分；请保持这个正确叙事。
- `docs/architecture/README.md` 中出现的 `report/figures/...` 链接位于标记为“仓库根 README 引用示例”的**Markdown 代码块**中，**不是文档实际断链**。审查脚本应该排除代码块里的示例文本。

## 交付规范与公开发布

AMD 2026 自主选题指南 3.3.3.3 强烈要求在 GitHub/Gitee 开源，推荐 MIT 或 Apache-2.0；3.3.5.4 说明推荐目录非强制，采用其他目录结构需在根 README 给出对照。工具版本指南推荐 2026.1 或 2025.2，若使用本项目的 Vivado/Vitis **2024.2**，必须在报告中声明并保证脚本可复现。当前 README 已作了这个版本披露；下一轮仍需让实际第三方执行者测试。

## 核对来源（仓库内路径）

- `README.md`
- `skill/README.md`
- `scripts/vivado/README.md`
- `scripts/vivado/generated/{packaged_ip,b5_raw_export}/`
- `report/results/vivado_rebuild/{packaged_ip,b5_raw_export}/SUCCESS.txt`
- `report/results/perf/performance_summary.md`
- `report/results/udp/validation_notes.md`
- `report/ai_collaboration/README.md`、`report/ai_collaboration/raw/README.md`
- `report/competition/difi_design_report_draft.md`

请运行 `python scripts/audit/check_submission.py --repo-root . --output report/competition/local_audit_result.md`，以你最终本地 checkout 的真实文件进行第二轮扫描。本包提供的是检查工具，不自动修改现有源码、Git 分支或许可证。
