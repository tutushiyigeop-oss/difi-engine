# DIFI 1.1 FPGA 协议引擎：大模型协作、自我纠错与 Skill 提炼记录（工程复盘）

**记录口径：** 本报告包含本次恢复的两份原始会话 PDF 文字抽取（R01～R04），以及原有五个基于 Git/工具结果的回顾性案例（C01～C05）；不可混称为完整项目的逐字聊天历史。

## 1. 对照 AMD 赛题要求

AMD 选题指南 3.3.3.1 要求提交体现大模型协作的交互记录（提示词、模型回答和自我纠错轨迹）；3.3.5.2 要求将可复用经验整理为 `skill/`；3.3.5.3 要求设计报告交代 AI 协作与 Skill 提炼过程。因此本项目采用“**真实需求—模型分析/建议—人工决策—代码/工具修改—实验检验—失败再反馈—Skill 沉淀**”的证据链，而不是把 AI 对话截图作为唯一成果。

工具环境：AMD/Xilinx Zynq-7020，Vivado/Vitis 2024.2，Icarus Verilog，PC Python/Wireshark；工程实现以本仓库对应 Git 提交为准。

## 从原始聊天 PDF 恢复的可审查交互记录（2026-10-27 整理）

本仓库此前 C01～C05 五个案例是历史工程技术复盘，并非原始聊天逐轮转录。本次新增来自开发者真实导出的两份 ChatGPT 会话（[原始证据与局限说明](../ai_collaboration/transcripts/README.md)），以弥补 AMD 指南 §3.3.3.1 所要求的“提示词、模型回答与自我纠错轨迹”不能由工程复盘单独证明的问题。**两份原始 PDF 及可检索文本均已归档，并与原件核对一致；本项目未主张保存了全部开发会话。**

### R01：从 AI 代写 RTL 转为人工编写、AI 逐步解释

《编写数据包器 RTL》PDF 第 1 页，模型起初直接给出完整的第一版 Data Packetizer RTL。第 19 页，开发者提出“你不用直接把完整的代码写出来……主要还是我来写”；模型随即调整为对 Packetizer 的功能合同、状态机、寄存器与 AXIS 握手提供逐步指导（第 20～39 页），随后应具体追问解答 `include` 头文件、第一个 Sample/时间/配置同步 snapshot、TREADY/TVALID 时序及 DONE 事件问题（第 70～123 页）。**纠正点是人机协作方式**：不是声称模型一次生成的代码就是最终人工作品，也不是删去最初的完整代码输出。可迁移经验纳入 `skill/axis-rtl-verification/` 的接口审查和握手验证步骤。

### R02：时序警告的初步诊断被 report_clocks 纠正

《建立Zynq工程》PDF 第 13～15 页，模型根据大量 `no_clock` 先猜测 Zynq PS 时钟或约束传播异常，建议提供 `report_clocks`。第 16 页用户贴出真实 Vivado 报告，包含 `Design : difi_tx_board_test`、`Design has no clocks defined matching '*'`。模型在第 17～19 页修改原分析：实际运行的顶层是测试模块而非 `difi_system_wrapper`，建议修正 Top 并重新综合实现，而不是盲目添加时钟约束。第 19～21 页针对新出现的旧 DCP 增量综合警告进一步解释为何与顶层更换有关。**证据链：初始假设 → 原始工具输出 → 修正根因与验证流程。**对应 `skill/vivado-rebuild/` 的 Top/Part/时钟/旧生成物一致性核查。

### R03：Vitis CMake 报错促使调整编译方案，继以 Stage A 实测反馈

同一 PDF 第 27～29 页，开发者粘贴 `Cannot find source file: difi_hello_world.c`、`No SOURCES given to target` 报错；模型依真实信息判定源文件已经更名但 CMake 仍引用旧文件，提供恢复源文件名和修改 CMake 源列表两种方案。第 30 页，开发者又粘贴实际 UART 输出：MM2S 1024 B，S2MM 1052 B，256 个 IQ 均正确，`[DIFI STAGE-A TEST PASSED]`。这里是**聊天中保留的用户原样工具反馈**，比模型自称成功强，但仍不能替代独立归档的串口原始记录。对应 `skill/zynq-dma-debug/` 的分层排错、状态/长度/TLAST/Cache/G​​olden 比对。

### R04：后续板级反馈与工程开发顺序纠错

同一 PDF 第 43～44 页记录开发者粘贴 B1 三类 Packet/AXI-Lite Commit PASS，第 48 页为 B2 RX，51～53 页为 B3 TX→RX 4 包 / 564 Word / 512 IQ / 零错误计数的结果。第 54～56 页，开发者指出 FIFO、周期触发及时间源等外围尚未做好，质疑直接转入 UDP 的建议；模型明确调整开发顺序，改为先补时间/周期逻辑，连续流测试后按实际需求决定 FIFO，再进入 UDP。这是**人工挑战 AI 方案并促使 AI 修正计划**的原始例证，不能将它写成模型一开始就给出完美顺序。

上述 R01～R04 均能在会话文本中按对应 PDF 页标记检索；文本抽取保留源顺序并仅对机器名、本地绝对路径作最小化脱敏。原始 PDF 中有折叠内容与未内嵌的图片，文本版不能冒充零遗漏逐字导出。原有五个 C 案例依旧是回顾性技术复盘，除非另找到原始完整交互，否则不能对它们使用“原始完整聊天”措辞。

## 2. 人机协作原则

| 工程阶段 | 模型承担的工作（依实际可恢复的讨论归纳） | 人工负责事项 | 验收信号 |
|---|---|---|---|
| 协议/接口设计 | 理解需求、比较优先级、指出 AXIS 时序风险 | 定接口约束、确定错误语义、审查 RTL | Testbench/时序逻辑 |
| 编译/仿真纠错 | 从错误日志定位源码/头文件依赖 | 修改配置、重跑工具、记录输出 | 真正编译通过，而非 AI 声称 |
| 资源优化 | 对 OOC 报告提出 BRAM 推断诊断思路 | 实施同步读改造并保持行为正确 | 同口径综合前后报告 |
| 工程构建 | 编写/修改 Tcl、识别环境检查与依赖问题 | 在 Vivado 环境导出、重建、上板 | 成功实现、Bitstream/XSA、板级回归 |
| 协议联网验证 | 讨论字节序、抓包和参考程序局限 | 运行 PS/PC 程序、采集 PCAP、复核 PASS | PC 数据黄金比对和第三方结果 |

**证据口径：** 文中的模型建议与交互顺序依据历史讨论重建，明确作为技术归纳；已列出的测试结果依据源码、Vivado 报告、PCAP 和工具输出核对。

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

这个过程体现“**首次修复只解决一个依赖层次，新的真实错误促使模型继续修正判断**”。两种报错分别对应 include 路径与 RTL 模块编译输入；工程文件与实际配置提供可复核的技术依据。

参见 [`C03`](../ai_collaboration/cases/03_icarus_dependency.md)。关联 Skill：`axis-rtl-verification`。

### C04：Vivado Tcl 误判环境与跨工作空间重建

已验证脚本经历了初版 Vivado 环境检查误判：使用 `[info commands open_bd_design]` 探测按需加载的 Tcl 命令会错误报告不可用；后续改为检查实际 Vivado 环境/当前工程，并以真实命令运行结果为准。工程需明确 BD、RTL Module Reference、封装 IP、XDC 和 XSA 的依赖。

在真实 Vivado 2024.2 中，封装 IP 与 B5 两套工程均完成独立导出、重建、实现、Bitstream/XSA，Setup WNS 分别为 **+0.411 ns / +2.206 ns**。开发者进一步在对话中确认两套重建工程均已上板通过；**当前 Git 中 `SUCCESS.txt` 是实现阶段形成的文件，其内仍写“Vitis/board not yet retested”，构建日志保留生成当时状态，板级回归由开发者后续确认，本阶段已收束。**

参见 [`C04`](../ai_collaboration/cases/04_vivado_tcl_rebuild.md)。关联 Skill：`vivado-rebuild`。

### C05：DIFI 1.1 UDP 链路、字节序和第三方参考工具

在 B5 设计中，DIFI Packet 由 PL 生成、S2MM 写回 DDR，PS 使用 lwIP/GEM0 通过 UDP 发送到 PC。PC 端验证：Version **1 包×44 B**、Context **1 包×108 B**、Data **20 包×1052 B**，共 22 包、21,192 B UDP Payload、5,120 IQ，样本失配 0。

参考工具最初在混合 SID 的流上可能将 Version SID=2 与 Data/Context SID=1 视为同一流的 SID 变化；后续按 SID 分流，分别运行 DIFI Consortium 原版 `certify_source.py --difi-version 1.1`，得到 Version 1/0、Context 1/0、Data 20/0 的合规/不合规统计。**此举是参考工具使用适配，不代表协议流允许随意混用 Stream ID，也不代表已获正式 DIFI Certification**。这一过程在 C05 中以追溯性技术复盘方式整理。

参见 [`C05`](../ai_collaboration/cases/05_udp_reference_validation.md)。关联 Skill：`udp-packet-validation`。

## 4. Skill 映射与复用价值

| Skill | 源于工程问题 | 复用的方法 |
|---|---|---|
| `vivado-rebuild` | C04：Vivado 环境判断、BD 重建与实现证据 | 导出真实 BD、检查依赖、在新工程中恢复并分层验证 |
| `zynq-dma-debug` | 板级 DMA 的启动顺序、Cache、TLAST 与 PS/PL 传输边界 | 将状态寄存器、数据长度与 AXIS 握手结合排查 |
| `axis-rtl-verification` | C01/C02/C03：错误包、握手、背压、BRAM 优化后的功能保持 | 事务级检查、Golden Model、异常包和明确的编译输入 |
| `udp-packet-validation` | C05：抓包解析、数据黄金比对、分流参考验证 | 分离报文输入、保留原版参考工具、解释 Profile 范围 |

上述为技能形成来源和使用方法；工程实测结论以案例中关联的 RTL、工具日志和原始测量文件为准。

## 5. 从案例得到的纠错原则

- **按新证据更新判断。** C03 中 `include` 报错消失后出现了新的 module-not-found 错误，两者属于不同依赖层；C04 中静态探测 Tcl 命令也不能代替真实 Vivado 操作。
- **先确认事务再更改数据。** C01 的握手、TLAST 分界和错误优先级都应在明确状态机契约后验证；C02 的同步 BRAM 读要求不破坏 AXIS 输出背压。
- **分开记录结果来源。** C02 的 OOC 资源、C04 的 routed timing、C05 的 PC IQ 校验及第三方工具 PASS 属于不同测量层级。不能把某一层的成功外推到其他层。
- **保留外部检查工具的独立性。** C05 按 SID 分流输入，而不是修改参考验证器来得到 PASS。
- **由人审核工程结论。** AI 提供方案、检查点和定位思路；设计决策、运行工具、保留源文件和核实证据由开发者完成。

## 6. 证据组织与复核方式

本报告是**历史协作过程的追溯性技术复盘**，并非 AI 聊天导出的逐字转录。C01～C05 五个案例均采用“工程问题 → 历史讨论与分析归纳 → 人工实施 → 代码/工具验证 → Skill 提炼”的结构，重建的建议只作归纳表述。个别可恢复的用户问题原句已在 C01 标示，不能据此推断存在完整的逐轮原始对话记录。

- 具体文件及历史提交：[`evidence_index.csv`](../ai_collaboration/evidence_index.csv)。
- 完整案例：`report/ai_collaboration/cases/01_data_parser.md` 至 `05_udp_reference_validation.md`。
- 第三方 UDP PASS 是原版开源参考工具的检查结果，不是官方认证。
- 构建工具日志记录生成时点的状态；板级复测由开发者后续反馈，不能修改历史工具日志以冒充同一次实验。

因此，五个案例作为**工程复盘与协作方法总结**构成闭环；其证据类型是当前代码/测试、Git 历史、原始工具报告和回顾性讨论分析，不把追溯记录标记为已导出的原始 AI 对话。

## 7. 相关工程交付

B6 v0.2 的三类 UDP RX 板级串口记录位于 `report/results/udp/rx/three_types_udp_rx.rtf`，所用板级应用为 `vitis/vitis_ws/difi_b6_udp_rx_pro/src/main.c`，PC 测试程序为 `scripts/verify/tools/difi_b6_three_types.py`。B6 的板级结论与 C05 的 B5 TX 第三方参考校验是两组不同验证结果。
