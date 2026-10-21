# AXI4-Stream / Packet RTL 故障注入计划模板

**这张表是设计测试用例的模板，不表示全部用例已在新 Skill 上执行。**

| ID | 注入位置 | 具体操作 | 预期检查器 / 设计反应 | 检查方法 |
|---|---|---|---|---|
| F01 | AXIS 源 | 有效且未 ready 时撤销 TVALID | 源违反稳定性约束，Monitor FAIL | 每 posedge 保持断言 |
| F02 | AXIS 源 | 停顿中修改 TDATA/TKEEP/TLAST | Monitor FAIL，附首个差异 cycle | Stable-beat Monitor |
| F03 | 输出 DUT | Ready=0 时篡改输出数据寄存器 | DUT 不符合背压合同，TB 必须 FAIL | 故意坏的 RTL/对照运行 |
| F04 | 报文输入 | 提前 TLAST | 由项目规格决定错误码与抑制输出 | 期望错误事件 + 后续正常包 |
| F05 | 报文输入 | 宣告包长已满仍不拉 TLAST | 项目特定 overlong/missing last 处理 | 超时、丢弃状态和恢复 |
| F06 | 报文输入 | TKEEP 与当前报文类型不符 | 项目特定拒绝/忽略政策 | TKEEP 断言与错误码 |
| F07 | 报文输入 | 不支持的类型或保留位改变 | 正确类型/字段错误优先级 | Golden Error Code |
| F08 | 报文输入 | SID 与过滤期望不符 | 按规格丢弃或报告 | 错误计数、无无效 IQ |
| F09 | 包与包之间 | 最后一字 stall 后立即下包 | 末字保持、下一包不被吞 | Back-to-back Scoreboard |
| F10 | DUT Reset | 输出 stall 时异步/同步复位 | 按 reset 合同撤销 VALID；无陈旧残留 | Reset/重新发合法包 |
| F11 | 多路路由 | 不同包类型连续交替 | 仅在明确包界完成后切换目标 | 各输出独立 Scoreboard |
| F12 | 响应侧 Metadata | Metadata READY 连续拉低 | Payload 按项目承诺的次序与时机出现 | Metadata handshake 断言 |

## DIFI 项目中特别注意

现有 Data Parser 设计要求一个合格 Data 包完整接收后，先完成 `m_meta_valid && m_meta_ready`，然后才输出 IQ；格式/时序以当前 RTL、接口规格和测试用例为准。Sequence 不连续的策略是**报告错误但不直接把已经合法的数据包视为格式错误丢弃**。这两个条件不能被通用 Packet Checker 擅自替代。

测试结果至少包括：`case_id`, `input_condition`, `expected_error`, `observed_error`, `number_of_output_samples`, `recovery_result`, `seed`。
