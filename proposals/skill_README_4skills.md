# 可复用技能包（Skill Library）

这里整理从 DIFI 1.1 FPGA 协议引擎开发过程及 AI 协作中提炼的复用工具、提示词工作流、案例模板和故障排查清单。**四个 Skill 已制作完成，但仍按照项目计划等待统一真实工程/跨项目测试，不应将离线测试等同于上板验收。**

| Skill | 适用场景 | 入口 | 现有验证范围 |
|---|---|---|---|
| Vivado Block Design 可复现构建 | BD 导出、重建、综合实现及 XSA 生成 | [`vivado-rebuild/SKILL.md`](vivado-rebuild/SKILL.md) | 本队 DIFI 专用流程完成两套真实构建及上板；通用模板跨项目测试待完成 |
| Zynq DMA 与缓存一致性调试 | AXI DMA Simple Mode、Cache、TLAST、日志诊断 | [`zynq-dma-debug/SKILL.md`](zynq-dma-debug/SKILL.md) | 原 DIFI 程序板级测试已通过；新模板与跨项目场景待验收 |
| AXI4-Stream RTL 协议验证 | 握手、背压、黄金参考、故障注入与 Scoreboard | [`axis-rtl-verification/SKILL.md`](axis-rtl-verification/SKILL.md) | 离线工具自检完成；新增 RTL 示例仿真和跨项目应用待统一验收 |
| UDP 报文端到端验证 | PC UDP 收包、序列与黄金数据、PCAP 和 DIFI 适配 | [`udp-packet-validation/SKILL.md`](udp-packet-validation/SKILL.md) | 原 DIFI UDP 链路已上板验证；新增通用工具真实链路复测待完成 |

## 如何使用

1. 选择与你的工程问题对应的 Skill，先阅读 `SKILL.md` 的适用条件、输入要求、步骤与失效边界。
2. 按所需环境执行 `scripts/` 或复制 `templates/`；不可将 DIFI 项目中的固定寄存器地址和 Stream ID 当作通用常量。
3. 将实际运行日志、失败原因、修复结果与工具版本保存到自己的工程证据目录。
4. 参见每个 Skill 的 `tests/VALIDATION.md` 和 `examples/`，区分已完成的离线检查、DIFI 原项目案例及尚待验证的跨项目复用能力。

AI 原始对话与纠错证据单独见 [`../report/ai_collaboration/`](../report/ai_collaboration/)；Skill 案例复盘不能替代提示词和模型回复原文。`manifest.tcl`、`bd.tcl` 均为可执行 Tcl，应仅运行经过审核的可信内容。
