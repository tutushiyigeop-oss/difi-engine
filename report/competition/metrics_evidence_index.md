# DIFI 设计报告量化结果：证据索引与口径说明

> 版本：v0.2 · 2026-10-22 · 面向 AMD 自主选题竞赛报告第 5–6 章。

## 源数据与证据链

| 报告图 | 根目录相对位置 | 主要原始来源 | 对比口径 |
|---|---|---|---|
| 图 5-1 | `report/figures/difi_ooc_resource_optimization.svg` | `report/results/ooc/utilization.rpt` 和 `report/results/ooc_new/utilization.rpt` | 相同 RTL 顶层 `difi_engine_top`、相同 Vivado/器件、OOC 综合数据 |
| 图 5-2 | `report/figures/difi_rtl_first_iq_latency.svg` | `report/results/perf/difi_perf_latency.csv` | 100 MHz、100 包 × 256 IQ、无外部背压理想 RTL TX→RX 回环 |
| 图 5-3 | `report/figures/difi_throughput_measurement_scopes.svg` | `difi_perf_latency.csv`、`report/results/perf/board_IP_perf.rtf`、PS CPU 配置确认信息 | 不同测量窗口，刻意不作为同一测试条件下的性能对比 |
| 图 6-1 | `report/figures/difi_multilayer_validation_evidence.svg` | `board_IP_perf.rtf`、`report/results/udp/validation_notes.md`、Consortium 检查文件 | 分层正确性证据，不代表长时间稳定性或全部标准项 |

## 定量计算核查

- **LUT 优化：** `(4023 - 1516) / 4023 × 100% = 62.32%`。
- **FF 优化：** `(10446 - 2202) / 10446 × 100% = 78.92%`。
- **BRAM 引入：** OOC `RAMB18` 从 `0` 变为 `1`。
- **RTL 首 IQ 延迟：** 100 包分别为首包 `266 cycles`、其余 99 包 `519 cycles`；平均 `(266 + 99 × 519) / 100 = 516.470 cycles`。
- **RTL 有效吞吐率：** `100 × 256 × 4 B × 100,000,000 Hz / 52,002 cycles / 10^6 = 196.916 MB/s`。
- **PS CPU 频率：** 用户已确认原配置约 `666.667 MHz`。图表使用 `666666667 Hz` 并假设该次测试 PMU 每 CPU cycle 计数一次。CPU 时钟配置证据仍需保存入仓库，以支撑正式定稿。
- **板级完整窗口：** `102400 B × 666666667 Hz / (2729306 ticks × 10^6) ≈ 25.012 MB/s`。
- **板级 DMA 事务窗口：** `102400 B × 666666667 Hz / (636916 ticks × 10^6) ≈ 107.183 MB/s`。
- **UDP：** `1 × 44 + 1 × 108 + 20 × 1052 = 21,192 B` UDP Payload；`20 × 256 = 5,120` IQ；本次发送有约 2 ms 的人为发包间隔，因此不报告最大 UDP 吞吐率。
- **第三方检测：** `1 Version + 1 Context + 20 Data` 参考工具 PASS；两类流因 SID 不同分别送入工具，**不等于 Consortium 正式认证**。

## 不应混用的统计

1. OOC 资源对比并非完整 PL 的实现后资源。`difi_engine_top` 优化后 OOC LUT 为 `1,516`，封装 IP routed LUT 为 `1,776`，完整系统 routed LUT 为 `4,562`，三者边界不同。
2. RTL 理想回环吞吐率不是板级 PS+DMA 或 UDP 网络吞吐率；图 5-3 只展示不同测试窗口所得结果，不能推论真实 PHY 速率或 PL 最大性能。
3. DMA 回环程序检查了 IQ 失配数 `0`，但该次性能日志的协议错误事件 `NOT_MEASURED`，不能据此宣布板级协议错误数为 0。
4. 两套 Vivado 重建工程板级复测已由开发者确认通过；原始新 XSA/Vitis/UART/PC 日志仍需补档。
5. 仅凭 100 包测试不能证明长期稳定性。

## 脚本再生成

在仓库根目录执行：

```powershell
python -m pip install matplotlib
python .\scripts\figures\build_performance_figures.py --repo-root . --cpu-hz 666666667
```

脚本**读取仓库中原有的 `.rpt`、`.csv`、`.rtf`、`.md`**，对关键数据进行断言校验，并生成 `report/figures/` 下八个 PNG/SVG 文件。不修改 `report/results/` 下原始记录。若原始记录数值变化，脚本会中止并要求核对原因，不会使用错误的默认值继续画图。

定稿前须将 CPU 配置的具体 Vivado/PS 时钟截图或导出报告与 PS 时钟校准计算存档，并修订旧的 `report/results/perf/performance_summary.md` 中“待确认”的过时表述。保留原始 UART 日志原样，以便独立审查。
