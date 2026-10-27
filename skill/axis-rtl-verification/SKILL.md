---
name: axis-rtl-verification
description: >-
  为 AXI4-Stream RTL 模块设计可执行的握手、背压、包边界、黄金模型和异常恢复验证；
  提供 Verilog 自检查 Testbench、周期级 CSV 离线检测器、可控错误样例与审计模板。
  适用于 FPGA 网络数据流、DMA 周边、报文解析器、视频流等场景。
---

# AXI4-Stream RTL 协议验证技能包

## 何时使用

- RTL 采用 `TVALID/TREADY` 传输，需要证明只在握手时消费或计数数据。
- 设计具有 `TDATA/TKEEP/TLAST`，需要覆盖背压保持、包长和边界情况。
- DUT 有 FIFO、报文封装、解包、转发或路由，需要按事务建立独立黄金模型与 Scoreboard。
- 需要验证异常输入、错误码优先级、恢复到下一包或超时保护。
- 使用大模型编写 Testbench，希望通过**故意错误 RTL/错误 trace**检验检查器确实有效。

**不要直接用于**：无 AXIS 接口的设计；多时钟域 CDC 的形式化证明；未明确 TLAST 语义的数据流；希望仅凭一次仿真证明时序闭合或所有协议情况已覆盖的场景。

## 所需输入

1. DUT 模块端口清单、时钟和 Reset 语义，AXIS 数据宽度与可选边带信号。
2. 事务定义：一包由什么条件开始/结束、`TLAST` 是否存在、`TKEEP` 是否允许空洞或零掩码。
3. 流控约束：是否允许持续背压、是否有内部缓冲、是否存在合法的丢弃/插包/延迟行为。
4. 可独立推导预期结果的黄金模型：不要复用 DUT 用来生成结果的可疑内部状态。
5. 异常策略：遇到坏包是丢弃、上报错误、还是允许部分 Payload；错误码及优先级以项目规格为准。
6. 可执行仿真环境：Icarus Verilog / Vivado XSIM；离线脚本只需 Python 3 标准库。

## 面向 AI 的工作流

1. **先复述协议契约**：列出每个 AXIS 端口、位宽、时钟域、握手、包边界、错误和恢复要求；有歧义先询问。
2. **把检查分类**：基础 AXIS 握手不变量、项目特定包格式、参考数据、流控、重置、错误与覆盖率。基础不变量不依赖协议字段编码。
3. **建立黄金基准**：按 *accepted beats* 而非纯时钟周期更新期望队列；以输出实际握手消费队列。对于 Packetizer/Parser 等转换型 DUT，为不同输入输出建立独立格式转换参考。
4. **主动施加背压**：输入 TVALID 间隔、输出 TREADY 周期性拉低、特别在首字/末字/TLAST 和 Metadata 握手期间暂停；检查 `TVALID=1 && TREADY=0` 下一周期必须保持 TVALID、TDATA、TKEEP、TLAST。
5. **注入明确可判定的错误**：如早 TLAST、尾部缺 TLAST、非法类型、Stream ID 不符、TKEEP 不符；每项规定“错误事件数、错误码、是否允许输出、如何恢复”。
6. **执行正反例**：正确 RTL 必须通过；已知故意破坏输出保持的 RTL 必须失败。不能用只检查 `[PASS]` 字符串的空 Testbench。
7. **记录覆盖与限制**：至少留存编译命令、seed、仿真日志、检查项覆盖矩阵和失败波形；随机测例应复现固定 seed。
8. **明确证据边界**：软件 CSV Checker PASS 不等于 DUT 功能正确；Testbench PASS 不等于 Formal Verification、综合时序或上板通过。

## 快速入口

- [`../README.md`](../README.md)：Skill 入口；实际运行命令和复用方法见本文。
- [`scripts/axis_trace_check.py`](scripts/axis_trace_check.py)：对单路周期采样 CSV 检查 AXIS 保持规则、包边界以及黄金 beat 序列。
- [`scripts/generate_golden.py`](scripts/generate_golden.py)：独立生成演示用 Golden CSV，**仅适用于示例数据图案**。
- [`templates/axis_register_slice.v`](templates/axis_register_slice.v)：教学用单级寄存器 AXIS Relay。
- [`templates/tb_axis_register_slice.v`](templates/tb_axis_register_slice.v)：含握手计数、Scoreboard、背压、watchdog 和 Trace 输出的 Testbench。
- [`tests/mutants/axis_register_slice_buggy.v`](tests/mutants/axis_register_slice_buggy.v)：故意违反 Stall Stability 的错误设计。
- [`templates/fault_injection_plan.md`](templates/fault_injection_plan.md)：针对包协议的异常注入模板。
- [`templates/coverage_matrix.md`](templates/coverage_matrix.md)：交付验证覆盖矩阵模板。
- [`templates/ai_workflow.md`](templates/ai_workflow.md)：AI 提示词与自我纠错记录模板。
- [`examples/difi-case-study.md`](examples/difi-case-study.md)：DIFI 仓库中的真实设计来源与局限。

## 使用方法与成功判据

**离线自检**（不需要 Vivado、Icarus）：

```powershell
python skill/axis-rtl-verification/tests/test_tools.py
python skill/axis-rtl-verification/scripts/axis_trace_check.py `
    skill/axis-rtl-verification/tests/fixtures/trace_pass.csv `
    --golden skill/axis-rtl-verification/tests/fixtures/golden_pass.csv `
    --allow-partial-last --min-words 2 --max-words 3 --min-stalled-cycles 2
```

**真实 Icarus 小工程回归**（需要 `iverilog` + `vvp`）：

```powershell
python skill/axis-rtl-verification/tests/run_iverilog.py --require-tools
```

此回归期望正确 DUT 通过，错误 DUT 以指定稳定性/Scoreboard 错误失败。`--require-tools` 避免缺少 Icarus 时把 SKIP 误判为成功。

**迁移到自己的 RTL**：仅把模板当框架；重新连接真实 DUT、替换 Golden Model、确定包级约束和异常期望，追加自己的 TB 仿真命令并运行正反例。不要用教学 Relay 的 PASS 代替真实 Packetizer/Parser PASS。

## 关键边界

- AXI4-Stream 基础协议并**不普遍规定**：TKEEP 一定从最低字节连续、不可全零、只有末字能部分有效。这些属于 DIFI/特定应用的更严格规范。本工具 `--keep-policy packet` 默认验证严格报文配置；使用 `--keep-policy nonzero` 或 `--keep-policy any` 处理其他业务语义。
- Python CSV 检查器只分析 **单条 AXIS 通道逐周期采样**。无法独立判断跨通道对应关系、缓存溢出、DIFI 包头字段、错误码、跨时钟行为或无观测内部状态的死锁。需要 DUT 专项 Testbench。
- 正确采样必须每个时钟沿连续一行；缺周期、重排和 X/Z 应导致拒绝。TVALID=0 时 TDATA 不属于有效载荷，可变化。
- 复位期间允许取消未完成传输；复位后若项目要求清除输出与错误状态，要另设检查。
- 现有 DIFI Testbench 已包含大量异常注入用例，但本 Skill 的新通用 Relay、故意错误 DUT **尚未在用户本机 Icarus/Vivado 实跑**；当前仅完成 Python 单元测试与静态检查。

## 来源、实际问题和已验证效果

来源于仓库 `sim/data/tb_difi_data_packetizer.v`、`sim/data/tb_difi_data_parser.v`、`sim/rx/tb_difi_rx_dispatch.v`、`sim/top/tb_difi_engine_top.v`、`sim/perf/tb_difi_engine_perf.v`，以及相应 RTL。项目针对：

- 只有在 `TVALID && TREADY` 时才能推进输入/输出 Word 计数。
- 背压时首字/尾字及 `TKEEP/TLAST` 必须保持。
- Data Parser 完整收包校验后才输出 Metadata/IQ，并在错误情况下不错误释放 Payload。
- 提前 TLAST、缺 TLAST、非法字段、SID 过滤、Sequence 失配与错误优先级。
- 100×256 IQ RTL 回环中的黄金数据/Metadata/错误事件核查。

其中 DIFI 工程此前已有通过的 RTL 仿真及性能记录（见 `report/results/perf/`）；**新 Skill 工具当前只有离线 Python 测试证据**。两种证据不可互换。
