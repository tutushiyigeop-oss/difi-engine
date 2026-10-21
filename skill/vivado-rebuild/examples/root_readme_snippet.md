# 可加入仓库根目录 README.md 的小节（复制时去掉本行说明）

## 可复用 Skill 技能包

仓库的 [`skill/`](skill/README.md) 提供从本项目实际研发及 AI 协作过程中沉淀的可复用工具。目前已完成 [`vivado-rebuild`](skill/vivado-rebuild/SKILL.md)：从原始 Vivado BD 导出 Tcl、重建独立工程、验证实现和生成 XSA，再执行新平台板级测试。DIFI 两套工程的专用构建流程已实际通过；通用可配置模板还需在其他真实 Vivado 工程进行跨项目验证，详见 Skill 的 [验收边界](skill/vivado-rebuild/README.md)。
