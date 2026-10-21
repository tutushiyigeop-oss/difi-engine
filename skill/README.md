# 可复用技能包（Skill Library）

本目录根据 AMD 自主选题赛道 3.3.5.2 的要求，记录在**真实工程开发及大模型协作**中沉淀的方法、模板、校验工具和失效边界。它与 `report/` 下的真实交互记录、测试原始数据相互引用，不能相互替代。

## 已完成

| 技能包 | 适用范围 | 入口 | 已验证效果与限制 |
|---|---|---|---|
| **Vivado Block Design 可复现构建** | IP Integrator 工程导出、重建、综合实现、XSA 与板级分层验证 | [`vivado-rebuild/SKILL.md`](vivado-rebuild/SKILL.md) | DIFI 两套原生工程已重建、工具实现和用户确认的板级验证；新通用模板尚未跨项目 Vivado 实测 |

## 后续规划（尚未制作，非已验证 Skill）

- `zynq-dma-debug`：AXI DMA、缓存一致性与 TLAST 调试。
- `axis-rtl-verification`：AXI4-Stream Testbench、背压与错误注入。
- `udp-packet-validation`：Zynq lwIP UDP 到 PC 的抓包与黄金参考检查。

## 使用说明

每个 Skill 均包含适用条件、具体命令、输入输出、实际效果、来源问题以及失效条件。请从其 `SKILL.md` 进入，先区分本项目已实测的专用脚本和面向其他项目的模板。目录内部程序与模板仅接受**可信来源**；生成的 `manifest.tcl`、`bd.tcl` 也是可执行 Tcl，禁止未经审查地运行网络下载版本。
