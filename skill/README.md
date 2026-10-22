# 可复用技能包（Skill Library）

本目录依据 AMD 自主选题赛道关于 Skill 沉淀的要求，汇总在真实 DIFI 工程开发与大模型协作中提炼的工作流、模板、脚本和失败条件。**四个 Skill 均已制作完成；本轮暂缓统一真实工程/跨项目验收。**

| Skill | 范围与入口 | 已具备的证据 | 仍待完成 |
| --- | --- | --- | --- |
| [`vivado-rebuild`](vivado-rebuild/SKILL.md) | BD Tcl 导出、依赖审计、空目录重建、实现与 XSA | DIFI **专用脚本**两套真实工程工具构建与开发者确认的板级回归；新通用模板有静态/模拟检查 | 新通用模板在真实 Vivado 工程、跨项目及异机环境中实测 |
| [`zynq-dma-debug`](zynq-dma-debug/SKILL.md) | AXI DMA Simple Mode、S2MM/MM2S、缓存、TLAST、日志诊断 | DIFI 原有 DMA 代码已上板；Skill 离线 Python 工具测试 | 新通用 C 模板 Vitis 编译及其他项目复用 |
| [`axis-rtl-verification`](axis-rtl-verification/SKILL.md) | AXI4-Stream 握手、背压、TLAST、Golden/Scoreboard、错误注入 | DIFI 原有 RTL Testbench；Skill 离线 CSV 检查器测试 | Skill 自带示例/错误 RTL 的 Icarus 实测和跨项目复用 |
| [`udp-packet-validation`](udp-packet-validation/SKILL.md) | UDP 监听、PCAP、数据长度/序列/Golden 校验，DIFI 示例适配 | DIFI 原有 B5 UDP 22 包、5120 IQ 与第三方参考工具记录；Skill 合成测试 | 新通用 UDP 工具接入真实板级链路及跨项目复用 |

## 使用与证据边界

1. 每个 Skill 均从其 `SKILL.md` 开始阅读，配有使用方法、适用场景和失效条件，必要时参阅 `README.md`、`examples/`、`tests/`。
2. **原 DIFI 项目已通过**不等于 **新通用 Skill 已完成真实/跨项目验证**。离线单元测试也不等同于板级实测。
3. AI 对话与纠错轨迹另在 [`report/ai_collaboration/`](../report/ai_collaboration/) 归档；当前仍需补齐完整原始交互。
4. `bd.tcl` 与 `manifest.tcl` 是可执行 Tcl，运行前应审查并只使用可信仓库内容；自定义 IP、外部约束和第三方工具按许可证和实际环境另行核实。

统一验收完成后再更新每个 Skill 的真实结果，并汇总为 `report/skill_validation_report.md`。不要在现阶段写“全部 Skill 已验收通过”。
