# C01 — Signal Data Parser：AXI4-Stream 事务、错误优先级与恢复

**材料性质：** 历史交流的追溯性技术复盘，结合当前 RTL、Testbench 和 Git 历史重构问题处理过程。保留的用户提问片段可作为交流线索；本文件不把归纳出的 AI 建议冒充逐字模型回复。

## 1. 工程问题与交流起点

Data Parser 需要将 32-bit AXI4-Stream DIFI Packet 解包为 I16/Q16 IQ，并处理不完整 Packet、Word0 非法字段、Stream ID 过滤以及输出背压。开发中的真实问题包括：

> “我这样写判断是否发生‘Stream ID mismatch when filtering is enabled’可以吗？”

> “发生在RECV状态的错误的优先级应该怎么确定？”

> “如果在RECV状态遇到了Truncated Packet Error，下一状态是不是会返回到IDLE？”

另有对 Word0 携带 `TLAST`、接收计数的含义、Payload 存储方法的讨论。核心冲突在于：什么时候接受一个 Word、如何保证只报告预期错误、错误包尾部怎样与下一包正确分界。

## 2. AI 分析与人工设计决策（依据历史讨论整理）

1. **握手是事件边界。** `s_axis_pkt_tvalid && s_axis_pkt_tready` 才代表接收了一个 Word；不能仅凭 `TVALID`、当前状态或周期数推动计数器和错误判断。IDLE/RECV/DROP 的 `TREADY` 与状态机应保持一致。
2. **Word0 校验优先于配置快照。** 只有合法 Word0 握手后才缓存 Packet Size、Sequence 和 Stream ID 过滤配置；无效 Word0 不进入正常接收路径。
3. **将结构错误与序列事件区分。** 非法 TKEEP、提前 TLAST、声明长度结束却无 TLAST 等为当前包的结构性问题；完整合法 Packet 的 Sequence discontinuity 可以报告事件，但不因此删除已经验证的 IQ。
4. **明确同拍错误的输出优先级。** 多个条件可在同一握手出现，错误码必须有固定次序，不能由不同 always 块互相覆盖。
5. **根据真正的包边界恢复。** 错误 Word 同时握手到 TLAST 时可结束当前包；否则进入 DROP，继续消耗数据直至 `TVALID && TREADY && TLAST`，再回到 IDLE。仅因为长度计数超限，不应把后续数据误当作新 Packet。

## 3. 当前 RTL 可直接核对的实现

`rtl/data/difi_data_parser.v` 定义 `ST_IDLE → ST_RECV → ST_META → ST_OUTPUT` 的正常路径和 `ST_DROP` 错误恢复路径；先完整验证再提交 Metadata、最后输出 IQ。

- **Word0：** `UNSUPPORTED_TYPE > HEADER > TRUNCATED(Word0 TLAST) > SIZE/TKEEP`。相应 `word0_accept` 要求握手且 `!word0_error`。
- **RECV：** `TRUNCATED > SIZE(超长或 TKEEP) > CLASS(OUI/Class) > STREAM_ID > SEQ`。这里的 `SEQ` 是对完整合法 Packet 的附加事件。
- **长度约定：** `word_count` 是从 Word0 开始的已握手 Word 索引；提前 TLAST 以 `word_count < packet_size_reg-1` 判断，声明末 Word 没有 TLAST 则为超长。
- **数据与输出：** `snapshot_payload[0:255]` 缓存 Payload；只在非错误握手写入。同步读出的 `payload_q` 在背压下保持，Metadata 握手触发首样本预取。
- **序列状态：** 对完整合法 Packet 更新基线；仅在同 Stream ID 的后续完整包上检查 4-bit Sequence 连续性。

## 4. 验证与纠错闭环

`sim/data/tb_difi_data_parser.v` 和相关环回测试构造了提前/缺失 TLAST、TKEEP、Stream ID 过滤、错误码优先级、背压和恢复后的下一包。历史讨论中出现过一次 TC20 失败被定位为 Testbench 重复发送 Word0，而不是 Parser 功能错误；这是“先区分测试激励错误与 DUT 错误”的典型人工复核。

本案结论的强证据是**当前 RTL 的组合判定与状态转移、可检查的 Testbench 及其 Git 历史**。历史测试反馈与工程文件分别记录，不用复盘文字替代当前运行日志。

## 5. 可复用经验

将 AXIS 的握手边界、固定错误优先级、`TLAST` 驱动的丢包恢复、可背压输出与 Golden Scoreboard 合并为独立检查项。对应 Skill：`skill/axis-rtl-verification/SKILL.md`。

**证据索引：** `rtl/data/difi_data_parser.v`、`sim/data/tb_difi_data_parser.v`、`rtl/include/difi_v1_1_defs.vh`；历史提交 `50802399ecf75fb9858521dab9412d022c4e69d8`。
