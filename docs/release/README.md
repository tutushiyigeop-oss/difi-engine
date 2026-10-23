# DIFI 1.1 竞赛授权与发布方案

> 草案日期：2026-10-22。本目录用于决策和审核，不是已经生效的开源授权。

## 赛题要求及当前状态

AMD 2026 FPGA 创新设计竞赛**自主选题赛道**指南 §3.3.3.3 **强烈要求**通过 GitHub/Gitee 使用允许再分发的开源协议，推荐 MIT 或 Apache-2.0；§3.3.5.1～3.3.5.4 要求工程源码、可复现构建脚本、板级与综合证据、Skill、AI 协作记录，以及清晰的目录对照。

当前仓库 **Private**，默认分支 **main**，主要成果位于 **feature/rtl-integration**，尚无根目录 LICENSE；四个 Skill 已制作但集中真实/跨项目测试尚待完成。**目前不应宣称“已经公开开源”或“正式提交版本已验收”。**

## 推荐路线

1. 保持 Private，先确认共同作者、学校及项目相关权属，核查第三方素材。
2. 在确权后从 [MIT/Apache-2.0 候选方案](license_decision.md)选择真实许可证，不能借项目 LICENSE 对他人作品重新授权。
3. 审查**将公开的完整 Git 历史**及当前文件：用户名、绝对路径、凭据、PCAP 的 MAC/IP、DOCX 元数据、RTF/串口日志及聊天记录。
4. 完成 Skill 统一验证、AI 原始对话、正式报告；保留每一项的证据边界。
5. [发布操作手册](publication_playbook.md)有两条路径：历史可公开则审核后合并 main、公开原仓库；历史有敏感或授权不清内容则制作不继承原历史的干净公开快照。
6. 评委应能访问固定 URL、Tag、完整 SHA；正式发布前逐项签核 [放行清单](release_gates.md)。

## 关联材料

- [开源许可决策单](license_decision.md)
- [第三方素材与隐私清单](third_party_inventory.md)
- [发布操作手册](publication_playbook.md)
- [最终放行条件](release_gates.md)
- [设计报告中的发布方案摘要](../../report/competition/authorization_and_release_plan.md)

**本阶段不创建根 LICENSE、不修改仓库 Private 状态、不合并 main、不创建正式 Tag。**