# DIFI 1.1 FPGA 协议引擎：大模型协作、自我纠错与 Skill 提炼记录（初稿）

**报告状态：** v0.1，2026-10-22；当前为可核查的技术复盘，**E1 原始逐轮对话仍待导出**。本材料作为 `difi_design_report_draft.md` 第 8、9 章的详细附录。技术结果来自代码和实验报告；AI 贡献部分来自可恢复的历史交互要点，不能用结果倒推并伪造模型输出。

## 1. 对照 AMD 赛题要求

AMD 选题指南 3.3.3.1 要求提交体现大模型协作的交互记录（提示词、模型回答和自我纠错轨迹）；3.3.5.2 要求将可复用经验整理为 `skill/`；3.3.5.3 要求设计报告交代 AI 协作与 Skill 提炼过程。因此本项目采用“**真实需求—模型分析/建议—人工决策—代码/工具修改—实验检验—失败再反馈—Skill 沉淀**”的证据链，而不是把 AI 对话截图作为唯一成果。

工具环境以真实记录为准：AMD/Xilinx Zynq-7020，Vivado/Vitis 2024.2，Icarus Verilog，PC Python/Wireshark；项目 Git 分支 `feature/rtl-integration`。2024.2 与指南推荐的 2025.2/2026.1 不同，已在主报告说明。

## 2. 人机协作原则

| 工程阶段 | 模型承担的工作（依实际可恢复的讨论归纳） | 人工负责事项 | 验收信号 |
|---|---|---|---|
| 协议/接口设计 | 理解需求、比较优先级、指出 AXIS 时序风险 | 定接口约束、确定错误语义、审查 RTL | Testbench/时序逻辑 |
| 编译/仿真纠错 | 从错误日志定位源码/头文件依赖 | 修改配置、重跑工具、记录输出 | 真正编译通过，而非 AI 声称 |
| 资源优化 | 对 OOC 报告提出 BRAM 推断诊断思路 | 实施同步读改造并保持行为正确 | 同口径综合前后报告 |
| 工程构建 | 编写/修改 Tcl、识别环境检查与依赖问题 | 在 Vivado 环境导出、重建、上板 | 成功实现、Bitstream/XSA、板级回归 |
| 协议联网验证 | 讨论字节序、抓包和参考程序局限 | 运行 PS/PC 程序、采集 PCAP、复核 PASS | PC 数据黄金比对和第三方结果 |

**证据缺口**：目前既有 Git Commit、源码和实验报告，但原始 AI 交互尚未全部归档。下文“模型建议”除有明确可恢复语句的地方外均是**讨论要点转述**，不是 AI 原始逐字回复。不可写作“AI 自动完成 RTL 并独立测试”。

## 3. 五个代表性协作案例

### C01：Data Parser 错误判定和 AXI4-Stream 事务语义

初期编写 Signal Data Parser 时，讨论过 Word0 与后续字段的 TLAST、TKEEP、Stream ID 过滤、错误优先级和 DROP 恢复。可恢复的**用户原句片段**包括：

> “我这样写判断是否发生‘Stream ID mismatch when filtering is enabled’可以吗？”
>
> “发生在RECV状态的错误的优先级应该怎么确定？”
>
> “如果在RECV状态遇到了Truncated Packet Error，下一状态是不是会返回到IDLE？”

工程检查点：只在 `TVALID && TREADY` 握手时接受 Word；只有合法 Word0 才缓存必要字段；在错误包内 drain 至 `TLAST`；成功完成整包校验后输出 Metadata/IQ；区分会丢弃报文的结构错误和只报告事件的 Sequence 错误。

本项目 Testbench 中构造了同拍错误冲突、提前/缺失 TLAST、各位置 TKEEP 异常、SID 过滤、Sequence 回绕等场景。**准确的错误优先级以最终 RTL 和 Testbench 为准；不要把交流中某一轮的临时建议当作最终规范。**

参见 [`C01`](../ai_collaboration/cases/01_data_parser.md)。关联 Skill：`axis-rtl-verification`。

### C02：以综合数据驱动 BRAM 优化

项目首次对 `difi_engine_top` 进行 OOC 综合时，`difi_data_parser` 的整包缓存使 FF/LUT 占用突出；历史讨论指出组合式异步数组读取不利于 Block RAM 推断，建议使用**同步读存储体 + 读出预取寄存器，并用真实握手控制读地址推进**。修改后重新运行 RTL 仿真与 OOC 综合。

| 资源 | 优化前 | 优化后 | 变化 |
|---|---:|---:|---:|
| 整体 LUT | 4,023 | 1,516 | -62.32% |
| 整体 FF | 10,446 | 2,202 | -78.92% |
| RAMB18 | 0 | 1 | +1 |
| Data Parser LUT | 2,797 | 283 | -89.88% |
| Data Parser FF | 8,487 | 243 | -97.14% |

统计对象均为**同一顶层 `difi_engine_top` 的 OOC Synthesis**，与后续 Routed 封装 IP 的资源数不同，不能混用。Git 提交记录显示改动与两份资源报告一起存入 `40f3c987…`，不是单凭 AI 回答认定优化完成。

参见 [`C02`](../ai_collaboration/cases/02_bram_optimization.md)。关联 Skill：`axis-rtl-verification` 与 `vivado-rebuild` 的报告校验思路。

### C03：Icarus Verilog 的 `include` 与实际编译模块依赖

2026-10-11 在 VS Code / DigitalIDE 一键 Icarus 仿真中出现 `Include file difi_v1_1_defs.vh not found`，通过配置 `-I` 搜索路径解决；随后又出现 `Unknown module type: difi_data_parser`，因为 `-I` 仅提供**头文件搜索**，不会自动把 `rtl/data/difi_data_parser.v` 作为模块编译输入。用户随后确认把 RTL 文件加入编译输入后能运行仿真。

这个过程体现“**首次修复只解决一个依赖层次，新的真实错误促使模型继续修正判断**”。应保存两轮真实 PowerShell/VS Code 输出和 JSON 配置差异，而不是只保留最终 PASS 截图。

参见 [`C03`](../ai_collaboration/cases/03_icarus_dependency.md)。关联 Skill：`axis-rtl-verification`。

### C04：Vivado Tcl 误判环境与跨工作空间重建

已验证脚本经历了初版 Vivado 环境检查误判：使用 `[info commands open_bd_design]` 探测按需加载的 Tcl 命令会错误报告不可用；后续改为检查实际 Vivado 环境/当前工程，并以真实命令运行结果为准。工程需明确 BD、RTL Module Reference、封装 IP、XDC 和 XSA 的依赖。

在真实 Vivado 2024.2 中，封装 IP 与 B5 两套工程均完成独立导出、重建、实现、Bitstream/XSA，Setup WNS 分别为 **+0.411 ns / +2.206 ns**。开发者进一步在对话中确认两套重建工程均已上板通过；**当前 Git 中 `SUCCESS.txt` 是实现阶段形成的文件，其内仍写“Vitis/board not yet retested”，应另外归档上板日志，避免证据时间线混乱。**

参见 [`C04`](../ai_collaboration/cases/04_vivado_tcl_rebuild.md)。关联 Skill：`vivado-rebuild`。

### C05：DIFI 1.1 UDP 链路、字节序和第三方参考工具

在 B5 设计中，DIFI Packet 由 PL 生成、S2MM 写回 DDR，PS 使用 lwIP/GEM0 通过 UDP 发送到 PC。PC 端验证：Version **1 包×44 B**、Context **1 包×108 B**、Data **20 包×1052 B**，共 22 包、21,192 B UDP Payload、5,120 IQ，样本失配 0。

参考工具最初在混合 SID 的流上可能将 Version SID=2 与 Data/Context SID=1 视为同一流的 SID 变化；后续按 SID 分流，分别运行 DIFI Consortium 原版 `certify_source.py --difi-version 1.1`，得到 Version 1/0、Context 1/0、Data 20/0 的合规/不合规统计。**此举是参考工具使用适配，不代表协议流允许随意混用 Stream ID，也不代表已获正式 DIFI Certification**。原始用户反馈与模型回答待补导出。

参见 [`C05`](../ai_collaboration/cases/05_udp_reference_validation.md)。关联 Skill：`udp-packet-validation`。

## 4. 从问题到技能包的具体映射

| Skill | 来自哪些实际问题 | 可复用能力 | 当前统一验收状态 |
|---|---|---|---|
| `vivado-rebuild` | C04；BD 导出误判、IP 依赖、复现一致性 | 导出/重建/实现/验收检查表 | DIFI 专用构建已实测；新通用模板待跨项目验收 |
| `zynq-dma-debug` | 板级 PS↔PL DMA 调试/Cache/接收先启动观察；C05 关联 | DMA 状态/缓存/传输边界诊断 | 离线工具自检已完成；新 C 模板待 Vitis/板级验收 |
| `axis-rtl-verification` | C01、C02、C03 | AXIS Monitor/Scoreboard、Golden、错误注入 | 离线自检已完成；真实 Icarus/移植验收待统一进行 |
| `udp-packet-validation` | C05；PC UDP 捕获及参考工具分流 | 报文/PCAP/Sequence/Golden 校验 | 离线自检已完成；新工具真实链路验收待统一进行 |

## 5. AI 的失误、适用边界与人工决策

- **不能只相信 AI 的诊断**：`include` 修好之后依然无法实例化 DUT，必须根据新日志继续定位；Vivado `info commands` 的静态判断也曾导致误报。
- **不能以仿真通过代替硬件正确**：RTL、OOC、Routed Timing、Vitis、UART/UDP 属于不同层次；每层分别记录 PASS 与版本。
- **不能把第三方工具适配写成修改官方标准**：保留参考工具原版及 SHA256、按其 SID 假设分流。
- **不能用口头结论覆盖旧日志**：上板已由开发者确认，但早期 `SUCCESS.txt` 只证明工具实现；需要后续版本的独立板级证据。
- **不能凭 Git 改动证明 AI 贡献**：正式评审需要原始提示词/模型回答/反馈纠错导出，而不是事后归纳。

## 6. 下一次补齐材料的操作步骤

1. 从 ChatGPT 原始对话中选取 C01—C05 的**最少两轮**关键交互；按时间保存到 `report/ai_collaboration/raw/`（建议 UTF-8 Markdown），并用会话截图或平台导出核对。
2. 原样保留模型第一版不完善建议及用户反驳/日志反馈。只在正文另外标“技术分析”，绝不润色成对话原话。
3. 逐条用 Git Commit / Diff 和实验文件对应到代码版本；补记板级重建新 XSA 的串口/PC 接收证据。
4. 在 GitHub 上检查 `skill/README.md`：若仍将后 3 个 Skill 写在“后续规划”，应改为“四项已制作、待统一验收”。
5. 统一验收四个 Skill 后，更新对应的成功/失败结论；再将本报告定稿为 `ai_collaboration_report.md`。

## 7. 原始证据清单

具体提交哈希、GitHub 链接与原始文件路径见 [`evidence_index.csv`](../ai_collaboration/evidence_index.csv)。用户提供的 AMD 原始赛题文件为 `AMD(1).pdf`，相关强制要求位于 3.3.3.1、3.3.5.2 和 3.3.5.3。
