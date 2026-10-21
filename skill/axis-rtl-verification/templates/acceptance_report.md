# AXIS RTL Verification Skill 验收报告（模板）

- 测试日期：`TODO`
- DUT 项目：`TODO`
- 仓库 Commit / 分支：`TODO`
- FPGA / 工具版本：`TODO`
- Python 版本：`TODO`
- Icarus / vvp 版本：`TODO`
- 操作系统：`TODO`

## 分层结果

| 层次 | 实际命令 | 结果 | 证据 |
|---|---|---|---|
| Python 离线 28 项单元测试 | `python .../tests/test_tools.py` | NOT RUN | - |
| 正例 CSV | `python .../axis_trace_check.py ...trace_pass.csv ...` | NOT RUN | - |
| 故意错误 CSV | `python .../axis_trace_check.py ...trace_invalid_stall.csv` | NOT RUN | - |
| Icarus 正确 DUT | `python .../run_iverilog.py --require-tools` | NOT RUN | - |
| Icarus 故意错误 DUT | 同上（预期拒绝） | NOT RUN | - |
| DIFI 模块 Testbench | `TODO` | NOT RUN | - |
| 非 DIFI DUT 复用 | `TODO` | NOT RUN | - |

## 观测到的有效覆盖

- 正常握手数：`TODO`
- 已完成 Packet 数：`TODO`
- 输出背压周期数：`TODO`
- 故意变异是否捕获：`TODO`
- 源输入暂停次数：`TODO`
- 错误事件数、优先级/恢复：`TODO`

## 失败 / 缺陷 / 修复

- 原始失败日志：`TODO`
- 根因确认方法：`TODO`
- 最小修复及复现命令：`TODO`
- 是否重新运行正反例：`TODO`

## 结论与限制

不得把 Python Checker PASS 当成全部 RTL 或板级验证通过；没有跑过的内容保持 NOT RUN。
