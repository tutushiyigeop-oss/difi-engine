# Zynq AXI DMA Debug Skill

> 交付类型：**错误排查清单 + 离线校验脚本 + C 模板 + AI 提示词 + DIFI 已验证案例**。
>
> 范围：**Zynq-7000、AXI DMA Simple Mode、Vitis Standalone** 为主；其他器件或 Linux/Scatter-Gather 需要针对性改写。

[AI Skill 指南](SKILL.md) · [真实案例](examples/difi-case-study.md) · [测试状态](tests/VALIDATION.md)

## 安装

将整个 `skill/zynq-dma-debug/` 放入项目的 `skill/` 中，不要覆盖已有的 `skill/vivado-rebuild/` 或 `skill/README.md`。合并目录索引的示例在发行包 `INTEGRATION/skill_README_update.md`。

本 Skill 的**离线**工具只要求 Python 3.9+ 标准库，Windows PowerShell 可直接使用。无需单独下载第三方依赖，也不访问网络。

## 快速开始：先做离线检查

在 DIFI 仓库根目录：

```powershell
# 分析真实 UART 纯文本（请先保存为 UTF-8 txt；RTF 不能直接当文本日志输入）
python .\skill\zynq-dma-debug\scripts\dma_log_analyzer.py `
  .\skill\zynq-dma-debug\tests\fixtures_pass.log --expected-samples 25600

# 故意含有 DMA 错误的演示日志：应返回 FAIL、退出码 1
python .\skill\zynq-dma-debug\scripts\dma_log_analyzer.py `
  .\skill\zynq-dma-debug\tests\fixtures_fail.log

# 示例配置是虚拟地址，仅用于离线审计；不可用作板卡 DDR 地址
python .\skill\zynq-dma-debug\scripts\dma_config_check.py `
  .\skill\zynq-dma-debug\templates\example_transfer_plan.json

# 自检（现在可以不做，统一测试时执行）
python .\skill\zynq-dma-debug\tests\test_tools.py
```

| 程序 | 返回码 0 | 返回码 1 | 返回码 2 |
|---|---|---|---|
| `dma_log_analyzer.py` | `PASS_EVIDENCE_ONLY`（有文本成功证据） | `FAIL`（有文本错误证据） | `INCONCLUSIVE`（缺少结果） |
| `dma_config_check.py` | `PASS_STATIC_ONLY` 或 `PASS_WITH_CAUTIONS` | `FAIL`（发现配置问题） | `INCOMPLETE`（字段缺失） |

**重要**：静态检验不保证 DDR 地址实际有效、不保证 AXI4-Stream 含 TLAST，也无法证明缓存同步正确。两工具输出 JSON，可以用 `--output output.json` 归档。

## 三步调试方法

1. **核对硬件**：确认 Simple Mode、MM2S/S2MM、DRE、时钟复位、地址、AXI4-Stream `TLAST` 和实际的最大 BTT；从 `.xsa`/Vivado 和 `xparameters.h` 获取真实值。
2. **核对软件**：用实际 `XAxiDma_LookupConfig` / `SimpleTransfer` 返回码和两个 DMASR 状态定位初步失败阶段；按真实 Buffer 长度做 `Flush`/`Invalidate`，S2MM 先准备。
3. **单包最小化**：读回每个词与黄金参考比较；收集日志后才逐步恢复连续包、背压、计时。必要时用 ILA 同时观察 TVALID/TREADY/TLAST。

详细决策树见 [SKILL.md](SKILL.md#快速排障矩阵)，波形探测见 [ILA/TLAST 检查表](templates/axis_dma_probe_checklist.md)。

## C 代码模板的使用前提

`templates/axi_dma_simple_loopback_template.c` 是**纯 MM2S→S2MM AXI4-Stream 循环测试**，不是 DIFI/IP 启动程序。运行前必须：

- Vivado BD 确认存在能产生 TLAST 的完整数据通路；BSP 为与新 XSA 匹配的 Standalone 驱动。
- 结合 `xparameters.h` 确认 DMA 宏和 SDT/legacy 区别、DRE 配置、DDR 缓冲实际可用。
- 专门为模板定义编译宏 `DMA_LOOPBACK_HW_CONFIRMED`（未确认硬件时，编译有意失败防误用）。
- 如 IP 还需要额外寄存器配置、时间初始化、Start 信号，必须在 DMA 开始前完成；不能直接在 DIFI 上照抄这个 main。

模板**尚未被声明为已编译通过或已上板通过**；当前仅代表待移植的受控示例。

## 与 DIFI 项目现有实现的关系

建议保留原始已验证的 Vitis C 源码不变。工程回环和 UDP 两条不同路径见 [真实案例](examples/difi-case-study.md)。如 DIFI 有其他模块使能、调度启动问题，应首先使用原工程已验证的初始化代码，不要为了使用 Skill 替换它。

## 竞赛交付与归档

- `skill/zynq-dma-debug/` 是可复用工作流与工具。
- `report/` 保存真实 AI 交互、失败日志、修改前后补丁和复测证据，两者互相引用，不能互相替代。
- `tests/` 的模拟日志是**测试夹具**，不是代表新增的真实板级故障。
- Git 提交应排除 Vitis IDE/BSP 缓存和秘密配置，保留原始 `.c/.h`、模板、测试输出与必要报告。

可用的提交信息：`feat(skill): add Zynq AXI DMA troubleshooting workflow and offline checks`。
