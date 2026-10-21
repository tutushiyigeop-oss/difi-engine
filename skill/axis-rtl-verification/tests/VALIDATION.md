# AXI4-Stream Skill 当前验证状态（2026-10-21）

## 已完成的检查（制作期间）

- Python 标准库测试套件 `tests/test_tools.py`：**28/28 PASS**，包含输出背压保持、非法 TKEEP、包长/TLAST、Golden 顺序、样例故意损坏、X/Z 拒绝、配置策略和最低覆盖要求。
- 有正例 `tests/fixtures/trace_pass.csv` 与故意错误 `tests/fixtures/trace_invalid_stall.csv`；后者必须让命令退出码非零。
- Python 源码语法编译与技能包 ZIP 文件校验。

## 未完成、留待最终统一验证

- Icarus Verilog 正确 DUT + Testbench 实际编译运行；当前制作环境没有 `iverilog/vvp`，不能冒称已通过。
- 故意错误 DUT 在 Icarus 实际模拟时被抓到。
- 在使用者自己的 DIFI RTL Testbench 重新跑一轮完整回归。
- 脱离 DIFI 的其他 RTL 项目跨项目复用验收。

## 后续统一验证命令

```powershell
python skill/axis-rtl-verification/tests/test_tools.py
python skill/axis-rtl-verification/tests/run_iverilog.py --require-tools
```

建议把测试原始输出保存到 `report/results/skill/axis-rtl-verification/`，并填写 `templates/acceptance_report.md`。不要将 SKIP 标为 PASS。
