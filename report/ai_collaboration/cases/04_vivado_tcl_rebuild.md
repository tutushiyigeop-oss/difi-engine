# C04 — Vivado Tcl 环境误判与三套独立 BD 重建

**材料性质：** 来自项目历史排错讨论、Git Tcl 脚本、Vivado 2024.2 实现报告的追溯性工程复盘，不冒充聊天逐轮原文。

## 1. 实际任务

原始 Vivado 工程内有 Zynq PS、AXI DMA、互连、自定义 RTL Module Reference 与封装 DIFI IP。仅提交 `.xpr` 或本机生成缓存不等于可复现，因此采用“导出实际 BD Tcl → 写入 manifest → 空目录重建 → 重新实现 → 导出 Bitstream/XSA”的交付路径。

涉及的脚本：

- `scripts/vivado/export_bd.tcl`
- `scripts/vivado/rebuild_bd.tcl`
- `scripts/vivado/verify_rebuilt_impl.tcl`
- `scripts/vivado/generated/{packaged_ip,b5_raw_export,b6_udp_rx}/`

## 2. AI 辅助排错与人工修正

早期环境检查使用 `[info commands open_bd_design]` 推断 BD 功能是否可用，出现 `open_bd_design unavailable` 一类误报。历史讨论和技术复盘的修正策略是：Vivado 某些 Tcl 命令可能按需注册，**静态枚举不到命令不能直接证明软件环境不支持它**。更可靠的做法是校验 Vivado 版本、工程状态和目标 Part/Top，并在实际 Vivado 会话中执行相应操作，以执行结果及返回错误定位。

随后将工作划分为四个可独立核实的层次：BD 导出/来源校验、综合与布局布线、Bitstream/XSA 生成、Vitis/实体板功能回归。这样不会因为一个 Tcl 脚本返回成功就误判整个网络链路正确。

## 3. 实际实现数据

| 目标工程 | 顶层 | Setup WNS (ns) | Hold WHS (ns) | Vivado 结果 |
| --- | --- | ---: | ---: | --- |
| `packaged_ip` | `difi_ip_test_wrapper` | +0.411 | +0.046 | Implementation / Bitstream / XSA |
| `b5_raw_export` | `difi_system_wrapper` | +2.206 | +0.021 | Implementation / Bitstream / XSA |
| `b6_udp_rx` | `difi_ip_test_wrapper` | +2.372 | +0.053 | Implementation / Bitstream / XSA |

以上由 `report/results/vivado_rebuild/<target>/SUCCESS.txt` 与同目录报告支持。开发者在后续讨论中确认独立重建工程的相应板级回归通过；该结论属于**开发者反馈层**。特别是 B6 的 `SUCCESS.txt` 保留了生成时“Vitis/board not yet retested”的原始说明，不能把工具日志事后修改成上板记录。原始三类 UDP RX 串口证据另见 `report/results/udp/rx/three_types_udp_rx.rtf`。

## 4. 对应 Git 和 Skill

- 脚本与报告提交：[`66d532bd`](https://github.com/tutushiyigeop-oss/difi-engine/commit/66d532bd5eff3ed3f0b8de5e3d041705bd7ea7ab)。
- 功能与重建入口：根 `README.md` 的 Vivado 重建章节。
- 技能沉淀：`skill/vivado-rebuild/SKILL.md`，强调版本/Part/Top、IP 和外部 RTL、实现证据及功能回归的分层对应。

**技术结论：** Tcl 工程重建的成功判据不是“导出成功”四个字，而是多层、同版本、可定位证据的组合。
