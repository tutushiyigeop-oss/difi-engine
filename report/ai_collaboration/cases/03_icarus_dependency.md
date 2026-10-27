# C03 — Icarus 编译失败：头文件查找与模块源码收集

**材料性质：** 依据 2026-10-11 的已知报错、用户反馈和项目配置整理的技术回顾；错误文本为历史记录中的原始信息，其余为归纳，不是逐字模型回复。

## 1. 首次失败及修复

VS Code / DigitalIDE 一键调用 Icarus Verilog 时，用户首先得到：

```text
Include file difi_v1_1_defs.vh not found
```

AI 诊断将其归到 Verilog 预处理阶段：源码的 `include` 依赖 Icarus 的 include 搜索路径。修复方法是增加 `-I rtl/include`，或在编辑器中配置等价的头文件目录。用户反馈头文件错误随之消失。

## 2. 第二次失败与纠错

随后出现不同的报错：

```text
Unknown module type: difi_data_parser
```

这并不是头文件问题再次发生，而是编译时没有把定义 `difi_data_parser` 的 `rtl/data/difi_data_parser.v` 加入 Verilog 源文件列表。AI 判断需要从“搜索路径配置”转到“编译输入集合”；用户加入对应 RTL 文件后确认可以运行仿真。

两轮报错代表两个独立层次：

| 层次 | 故障 | 对应处理 |
| --- | --- | --- |
| 预处理 | `include` 文件不可见 | `-I` 及相对目录 |
| 设计展开 | 实例化模块的定义不存在 | 添加真实 `.v` 源文件 |
| 测试顶层 | 顶层/参数/标准不匹配 | 检查 `-s`、`-g2005` 和依赖列表 |

## 3. 工程实现对应

本仓库有 `rtl/include/difi_v1_1_defs.vh`、`rtl/data/difi_data_parser.v` 和 `sim/data/tb_difi_data_parser.v`。编辑器配置 `.vscode/property.json` 记录了当时使用的绝对路径和多个源文件路径，它反映开发环境，并不是跨机器可直接复用的构建清单。仓库根 `README.md` 中提供使用相对路径显式传入源码的 PowerShell/Icarus 示例。

## 4. 协作闭环与 Skill

真实故障 → 第一层修复 → 新错误反馈 → 修正诊断维度 → 仿真恢复。可迁移的经验是从**新报错而非既有猜测**继续定位，每个编译阶段单独验证。

关联 `skill/axis-rtl-verification/SKILL.md`；相关代码 `sim/data/tb_difi_data_parser.v` 和 `rtl/data/difi_data_parser.v`。
