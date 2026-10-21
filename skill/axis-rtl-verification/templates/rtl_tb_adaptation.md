# 将 AXIS 教学示例迁移到真实 DUT：逐步清单

1. **输入**：DUT Verilog 源文件、include 文件、模块参数、协议文档和编译清单。不要依赖截图补全丢失的端口。
2. **端口映射**：每条独立通道记录 `aclk/aresetn`, `TVALID`, `TREADY`, `TDATA`, `TKEEP`, `TLAST`, `TUSER`, `TID`, `TDEST`。缺少的信号不要虚构。
3. **握手合同**：定义 `fire = tvalid && tready`；所有 beat index / Golden queue 在 `fire` 时推进。消费者允许任意合法背压；源在 stall 中保持 TVALID 与所有合法 Payload/Sideband 稳定。
4. **Golden/Scoreboard**：原样转发可用 accepted-input queue 比对输出。封包/解包、过滤或改写模块必须提供转换后的**独立参考序列**。明确何时允许丢包。
5. **TLAST 与 TKEEP**：单独写出项目格式限制。AXIS 规范本身并非强制每个 beat full TKEEP，也不强制每个应用使用 TLAST。
6. **Stimulus**：加入连续输入、随机输入空隙、零/短/长包（仅合法长度）、不同速率比、输出在首/末字的持续背压、最终恢复、背靠背包。
7. **非法包**：逐个注入，并定义期望的错误编码、次数、输出抑制及下一包恢复，参照 `fault_injection_plan.md`。
8. **全局保护**：加最大循环/超时，先确定仿真失败返回非零。Verilog `$finish` 不代表 FAIL；建议 SystemVerilog `$fatal(1, ...)` 或 Icarus 退出策略。
9. **日志**：输出 `test_name`, `seed`, `cycles`, `input_fire`, `output_fire`, `packet_count`, `stall_count`, `error_count`, `PASS/FAIL`；另存失败波形。
10. **脚本封装**：在自己项目的 `scripts/sim/` 写独立编译清单；加入所有 RTL 依赖、`-I` 目录、top module、vvp 运行和退出码验证。

## 推荐最小测试组

| 组 | 输入 | 主要断言 |
|---|---|---|
| R01 | 单个最小合法包 | 正确握手、长度、内容、TLAST |
| R02 | 最大合法包 | 存储上限、计数溢出、最后一个 beat |
| R03 | 持续输入 + 输出背压 | 数据/边带稳定，无丢失/重复 |
| R04 | 源端间歇性 TVALID | 只按握手推进，无虚假输出 |
| R05 | 连续多个包 | 包界与顺序，不跨包混淆 |
| R06 | 提前 TLAST/缺 TLAST | 按项目定义发错误/丢弃/恢复 |
| R07 | Reset during stall | 恢复后不输出陈旧数据 |
| R08 | 错误的字段/TKEEP | 与项目专属错误编码/优先级一致 |

**切忌**把一个通道的 TLAST 检查写成所有输出都必须“立即响应输入 TLAST”。Store-and-forward DUT 可以先缓存整包，再发输出；比较事务的完成顺序，而非固定周期。
