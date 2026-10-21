# AXI4-Stream RTL Verification Skill

> **内容类型**：AI 工作流 + Icarus 自检查 RTL 示例 + CSV 离线验证 + 可控错误注入 + 覆盖记录模板。
>
> **版本状态**：v1 初稿；Python 离线单测已验证，真实 RTL 示例需在统一测试阶段运行。

[核心技能定义](SKILL.md) · [DIFI 来源案例](examples/difi-case-study.md) · [故障注入矩阵](templates/fault_injection_plan.md) · [验收模板](templates/acceptance_report.md)

## 1. 能解决什么

检查 AXIS 的四个关键层次：

1. **握手层**：只在 `TVALID && TREADY` 时发生数据转移；背压时必须稳定。
2. **字节与包层**：依据项目契约检查 TKEEP、TLAST、包长、起始/末尾数据。
3. **内容层**：基于独立 Golden Model 检查握手顺序和数据，不根据绝对时钟周期误判气泡/背压。
4. **故障恢复层**：错误包被拒绝/抛错后的状态恢复，由每个真实 DUT 的测试用例负责。

## 2. 文件索引

```text
skill/axis-rtl-verification/
├── SKILL.md
├── README.md
├── scripts/
│   ├── axis_trace_check.py
│   └── generate_golden.py
├── templates/
│   ├── axis_register_slice.v
│   ├── tb_axis_register_slice.v
│   ├── fault_injection_plan.md
│   ├── coverage_matrix.md
│   ├── rtl_tb_adaptation.md
│   ├── acceptance_report.md
│   └── ai_workflow.md
├── examples/
│   └── difi-case-study.md
└── tests/
    ├── fixtures/
    │   ├── trace_pass.csv
    │   ├── golden_pass.csv
    │   └── trace_invalid_stall.csv
    ├── mutants/axis_register_slice_buggy.v
    ├── test_tools.py
    ├── run_iverilog.py
    └── VALIDATION.md
```

## 3. 先做无工具依赖的离线测试

仓库根目录：

```powershell
python .\skill\axis-rtl-verification\tests\test_tools.py
```

再手动运行正确样例：

```powershell
python .\skill\axis-rtl-verification\scripts\axis_trace_check.py `
  .\skill\axis-rtl-verification\tests\fixtures\trace_pass.csv `
  --golden .\skill\axis-rtl-verification\tests\fixtures\golden_pass.csv `
  --min-words 2 --max-words 3 --allow-partial-last --min-stalled-cycles 2
```

预期 `[PASS] cycles=10 transfers=5 packets=2 stalled_cycles=3`。

故意错误波形，**预期退出码为 1 并输出 `[FAIL]`**：

```powershell
python .\skill\axis-rtl-verification\scripts\axis_trace_check.py `
  .\skill\axis-rtl-verification\tests\fixtures\trace_invalid_stall.csv `
  --allow-partial-last
```

检查器采用 CSV 列：`cycle,aresetn,tvalid,tready,tdata,tkeep,tlast`。十六进制字段写成 `0x...`；每时钟一行，cycle 从任意非负整数开始并严格连续。`aresetn=0` 用于记录复位。Golden CSV 采用 `data,keep,last`，行顺序是**所有被握手接受的 beat 顺序**。

### 包类型不同，调整 TKEEP 策略

`--keep-policy packet`（默认）要求字节掩码从低位连续、非零，且只有传入 `--allow-partial-last` 才接受尾 beat 部分有效；它适用于某些严格报文格式，**并非 AXI4-Stream 的普遍要求**。

`--keep-policy nonzero` 只禁止零掩码；`--keep-policy any` 允许包括零和空洞在内的掩码，由真实设计的合同决定如何解释。`--allow-open-final-packet` 仅在明确不要求最后出现 TLAST 的场景使用。想检查帧大小可设置 `--min-words` / `--max-words`。

## 4. Icarus Verilog 真实 RTL 小样例（待集中实测）

安装并添加 `iverilog`、`vvp` 到 PATH 后：

```powershell
python .\skill\axis-rtl-verification\tests\run_iverilog.py --require-tools
```

脚本会执行：

- 编译教学用 1-entry AXIS Register Slice、运行带固定背压的 TB。
- 在 TB 内验证 16 个 beat，3 个 packet（4+4+8）；Scoreboard 按实际握手比较数据、TKEEP、TLAST，覆盖首/中/末字。
- 导出周期级 CSV，使用独立 Python Checker 与 Golden CSV 二次交叉检验。
- 换用故意在输出 stalled 时修改 TDATA 的错误 DUT，确认 TB 能拒绝它（**预期失败是测试通过**）。

若命令只打印 `[SKIP]`，不能将其当作 RTL 仿真通过；传 `--require-tools` 会在缺少工具时返回非零状态。

> 教学示例不是经过 AMD 官方验证的可直接用于上板的 IP。它的作用是提供独立的最小实验，帮助其他队伍快速检验其验证工具链。

## 5. 迁移到自己的 DUT

1. 阅读 [`rtl_tb_adaptation.md`](templates/rtl_tb_adaptation.md)，从 DUT 源码记录完整端口、时钟、复位、边带信号。
2. 复用 Testbench 的 handshake scoreboard、stall monitor、watchdog 思路，而**不是**照搬教学 DUT 端口或示例数据图案。
3. 若 DUT 会封装或解析报文，Golden Model 必须独立实现相应变换。单通道 CSV 比对**不能**替代跨通道功能 Scoreboard。
4. 将 [`fault_injection_plan.md`](templates/fault_injection_plan.md) 中的具体错误和预期结果修改为 DUT 自己的规格。
5. 对正确 DUT 测 PASS；对故意坏的输入/故意破坏的 RTL 测应当 FAIL。保留退出码、日志、波形和覆盖表。
6. 对随机测试固定种子、记录工具版本、Git SHA，分开记录“仿真”“综合/时序”“上板”结论。

## 6. 仓库 DIFI 测试入口（原代码，不在本 Skill 中重复复制）

- `sim/data/tb_difi_data_packetizer.v`（TKEEP、TLAST、配置快照、背压、Sequence 回绕）
- `sim/data/tb_difi_data_parser.v`（错误注入、Metadata/IQ 独立回传、错误优先级）
- `sim/rx/tb_difi_rx_dispatch.v`（类型路由、TLAST 路由锁定）
- `sim/top/tb_difi_engine_top.v`（系统级联调）
- `sim/perf/tb_difi_engine_perf.v`（100 MHz / 100×256 IQ 测试）

从这些文件本身核对 `-I rtl/include` 与模块依赖。不要因为通用小样例编译通过就推断所有 DIFI Testbench 已在当前提交重新运行。

## 7. 测试级别与使用边界

| 级别 | 可以证明什么 | 不能证明什么 |
|---|---|---|
| A：Python 离线单测 | CSV Checker 能识别准备好的正反例 | 真实 RTL 行为 |
| B：Icarus 实例 | 教学 DUT 接口及 TB 在具体仿真器中可运行，能抓到已知突变 | 所有 AXIS 接口/其他 DUT 正确 |
| C：目标 DUT Testbench | 某 DUT 在有限测试向量中满足明示契约 | 无穷状态、CDC、时序签核 |
| D：综合/板级 | 在具体板卡工具/约束下实现并运行 | 另一 FPGA 或配置必然兼容 |

见 [`tests/VALIDATION.md`](tests/VALIDATION.md) 记录当前已做与待做的检查。
