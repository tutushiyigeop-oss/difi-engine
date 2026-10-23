# DIFI 设计报告量化结果：证据索引与口径说明

> 版本：v0.3 · 2026-10-23 · 面向 AMD 自主选题竞赛报告第 5–6 章。

## 源数据与证据链

| 报告图 | 根目录相对位置 | 主要原始来源 | 对比口径 |
|---|---|---|---|
| 图 5-1 | `report/figures/difi_ooc_resource_optimization.svg` | `report/results/ooc/utilization.rpt` 和 `report/results/ooc_new/utilization.rpt` | 相同 RTL 顶层 `difi_engine_top`、相同 Vivado/器件、OOC 综合数据 |
| 图 5-2 | `report/figures/difi_rtl_first_iq_latency.svg` | `report/results/perf/difi_perf_latency.csv` | 100 MHz、100 包 × 256 IQ、无外部背压理想 RTL TX→RX 回环 |
| 图 5-3 | `report/figures/difi_throughput_measurement_scopes.svg` | `difi_perf_latency.csv`、`report/results/perf/board_IP_perf.rtf`、PS CPU 配置确认信息 | 不同测量窗口，刻意不作为同一测试条件下的性能对比 |
| 图 6-1 | `report/figures/difi_multilayer_validation_evidence.svg` | `board_IP_perf.rtf`、`report/results/udp/tx/validation_notes.md`、Consortium 检查文件 | 分层正确性证据，不代表长时间稳定性或全部标准项 |

## 定量计算核查

- **LUT 优化：** `(4023 - 1516) / 4023 × 100% = 62.32%`。
- **FF 优化：** `(10446 - 2202) / 10446 × 100% = 78.92%`。
- **BRAM 引入：** OOC `RAMB18` 从 `0` 变为 `1`。
- **RTL 首 IQ 延迟：** 100 包分别为首包 `266 cycles`、其余 99 包 `519 cycles`；平均 `(266 + 99 × 519) / 100 = 516.470 cycles`。
- **RTL 有效吞吐率：** `100 × 256 × 4 B × 100,000,000 Hz / 52,002 cycles / 10^6 = 196.916 MB/s`。
- **PS CPU 频率：** 已确认 **666.666666 MHz（666666666 Hz）**，三位小数显示为 666.667 MHz。PMU 换算依照该次测试每 CPU cycle 计数一次的设置；归档该次 XSA/PS 配置映射是证据关联事项，不是频率未确认。
- **板级完整窗口：** `102400 B × 666666666 Hz / (2729306 ticks × 10^6) ≈ 25.012 MB/s`。
- **板级 DMA 事务窗口：** `102400 B × 666666666 Hz / (636916 ticks × 10^6) ≈ 107.183 MB/s`。
- **B5 UDP TX：** `1 × 44 + 1 × 108 + 20 × 1052 = 21,192 B` UDP Payload；`20 × 256 = 5,120` IQ；发送端人为加入约 2 ms 的间隔，不报告最大 UDP 吞吐率。
- **B6 UDP RX：** 1 Version + 1 Context + 20 Data；Version/Context Metadata 各一次握手，Data `20 × 256 = 5,120 IQ` 均由 PL RX 恢复并在 PS 校验，Data Sequence 覆盖 `15→0`。依据：`report/results/udp/rx/three_types_udp_rx.rtf`；不等于全双工性能测试。
- **第三方检测：** `1 Version + 1 Context + 20 Data` 参考工具 PASS；两类流因 SID 不同分别送入工具，**不等于 Consortium 正式认证**。

## 不应混用的统计

1. OOC 资源对比并非完整 PL 的实现后资源。`difi_engine_top` 优化后 OOC LUT 为 `1,516`，封装 IP routed LUT 为 `1,776`，完整系统 routed LUT 为 `4,562`，三者边界不同。
2. RTL 理想回环吞吐率不是板级 PS+DMA 或 UDP 网络吞吐率；图 5-3 只展示不同测试窗口所得结果，不能推论真实 PHY 速率或 PL 最大性能。
3. DMA 回环程序检查了 IQ 失配数 `0`，但该次性能日志的协议错误事件 `NOT_MEASURED`，不能据此宣布板级协议错误数为 0。
4. 封装 IP、B5 与 B6 **三套 Vivado 独立重建工程**的板级回归均由开发者确认通过。原始新 XSA/Vitis/UART/PC 日志及版本配对仍需补档；B6 的工具 PASS 见 `report/results/vivado_rebuild/b6_udp_rx/SUCCESS.txt`，开发者回归确认见同目录 `BOARD_REGRESSION_STATUS.md`。
5. 仅凭 100 包测试不能证明长期稳定性。

## 脚本再生成

在仓库根目录执行：

```powershell
python -m pip install matplotlib
python .\scripts\figures\build_performance_figures.py --repo-root . --cpu-hz 666666666
```

脚本**读取仓库中原有的 `.rpt`、`.csv`、`.rtf`、`.md`**，对关键数据进行断言校验，并生成 `report/figures/` 下八个 PNG/SVG 文件。不修改 `report/results/` 下原始记录。若原始记录数值变化，脚本会中止并要求核对原因，不会使用错误的默认值继续画图。

CPU 频率已确认，且 `report/results/perf/performance_summary.md` 已同步。定稿前仍应将实际测试 XSA 对应的 PS 时钟配置原始文件/截图与 PMU 计数记录关联归档；原始 UART 日志保留原样。
