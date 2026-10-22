# C04 — Vivado Tcl 检测误报与双工程独立重建

**状态：** 两套 E3 工具构建 PASS；开发者已确认板级回归，需补新版板级原始日志；AI 逐字 E1 待导出。

## 触发问题

为了让 Vivado Block Design 不依赖本机 `.xpr` 与缓存，开发了：

- `scripts/vivado/export_bd.tcl`
- `scripts/vivado/rebuild_bd.tcl`
- `scripts/vivado/verify_rebuilt_impl.tcl`

早期 Tcl 环境检查尝试使用 `[info commands open_bd_design]` 判断 Vivado 能否操作 Block Design，出现 `open_bd_design unavailable` 类型误报。修正思路是避免把按需加载命令未出现在静态枚举中视为无 Vivado 环境，而以 `version -short`、`current_project` 等实际环境/工程操作确认。

## 可复核的最终结果

| 工程 | Top | Setup WNS | Hold WHS | 结果 |
|---|---|---:|---:|---|
| `packaged_ip` | `difi_ip_test_wrapper` | +0.411 ns | +0.046 ns | Implemented + Bitstream + XSA |
| `b5_raw_export` | `difi_system_wrapper` | +2.206 ns | +0.021 ns | Implemented + Bitstream + XSA |

证据：`report/results/vivado_rebuild/{packaged_ip,b5_raw_export}/SUCCESS.txt`，以及对应 `timing_summary.rpt`/`utilization.rpt`/`drc.rpt`。

**证据时间线说明：** `SUCCESS.txt` 生成时原备注是“Vitis/board not yet retested”；后来开发者在聊天中明确表示“两套重建工程的板级测试都通过”。这是先后两个阶段，并非相互排斥；如果竞赛评委要求 E3 实测佐证，应再放入新 XSA 对应的 Vitis 构建输出、板级 UART/PC 记录及日期。

## AI 纠错价值

从“静态探测 Tcl 命令”转为“在正确软件上下文执行并验证”，并把**BD 恢复、Synthesis/Implementation/Timing、Bitstream/XSA、Vitis/Board**划成四个独立验收层。不能由一个 Tcl 命令成功直接推断整套软硬件可复现。

## 技能包对应

`skill/vivado-rebuild/` 提炼了版本、Part/Top、Module Reference、自定义 IP Repo、XDC、Timing、Bitstream/XSA 的跨项目检查表；新通用模板尚待统一跨项目实测。

## 待补

- [ ] 原始 Tcl 错误命令、完整日志及 AI 最初与修正后的回答。
- [ ] Tcl 修改前后 Diff、对应 Git SHA。
- [ ] 两套重建后上板 UART/Vitis/PC 日志并明确 XSA 来源。
