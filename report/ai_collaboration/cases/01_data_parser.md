# C01 — Signal Data Parser 的事务语义、错误优先级与恢复

**状态：** 技术复盘已完成；原始 AI 多轮对话的完整导出待补（E1 不完整）。

## 真实触发问题

在 Data Parser 早期开发中，用户问过 RECV 状态的 Stream ID mismatch 判断，Word0 收到 TLAST 如何判错，以及在发生 Truncated Packet Error 后应进入 IDLE 还是 DROP。现有会话上下文保留的真实提问片段：

> “我这样写判断是否发生‘Stream ID mismatch when filtering is enabled’可以吗？”
>
> “发生在RECV状态的错误的优先级应该怎么确定？”
>
> “如果在RECV状态遇到了Truncated Packet Error，下一状态是不是会返回到IDLE？”

这些是可恢复的用户提问，不代表完整逐字会话；对应的模型完整回复与用户逐轮反馈**待导出**。

## 可恢复的讨论要点（不是逐字模型回答）

- `word_count==1`、过滤使能及快照 SID 比较应建立在 `s_axis_tvalid && s_axis_tready` 上。
- 错误优先级、同一 Word 的 TLAST/TKEEP 冲突、Type/Header/Size/SID/CLASS 与 Sequence 事件需要协议明确指定，不能仅依赖 `if` 顺序模糊覆盖。
- 若错误 Word 自身已经完成 `TLAST` 握手，通常可以回 IDLE；若报文还未结束，则进入 DROP 消耗剩余 Word，直到**握手的 TLAST**，避免误将下一个错误包的中间 Word 当作新 Word0。
- 错误优先级在讨论中多次调整，正式结论应以当前 RTL + Testbench 的真实错误码行为为准，不引用单轮未冻结建议作为定论。

## 可在 Git 复核的实现

- `rtl/data/difi_data_parser.v`：`word0_accept` 只在没有 Word0 错误时置位；`truncated_packet_error`、`oversized_packet_error` 与 DROP 状态；通过整个 Packet 校验后先提交 Metadata 再输出 IQ。
- `sim/data/tb_difi_data_parser.v`：异常 TLAST、TKEEP、SID、Sequence、同拍错误优先级及背压场景。
- `rtl/include/difi_v1_1_defs.vh`：错误类型定义。
- `50802399ecf75fb9858521dab9412d022c4e69d8`：早期 Data RTL/仿真集成提交；当前最终源文件应以目标提交/分支固定 SHA 保存。

## 如何从本案提炼 Skill

使用可复用的 AXI4-Stream Monitor（稳定性及握手）和 Golden Packet Scoreboard；把“提前 TLAST”“声明末尾缺 TLAST”“非法 TKEEP”“多错误同拍”“恢复后下一包”做成互相独立的反例。`skill/axis-rtl-verification/` 的新通用部分仍需统一仿真测试。

## 待补 E1 原始证据

- [ ] 保存问题出现前后的**完整原始用户提问、模型回答**，附会话时间与出处。
- [ ] 保存模型首次建议与后续修正的直接对照，不要逆向生成所谓“当时 AI 说的话”。
- [ ] 附与会话对应的 Verilog 修改 Diff、Icarus 控制台输出和最终 Testbench PASS。
