# 性能与资源证据图生成器

**用途**：从原始 Vivado、Icarus 和 Zynq 串口归档文件生成初赛报告 4 张定量图。实现脚本为 `build_performance_figures.py`。

**依赖**：Python 3.9+；`matplotlib`。无需 Vivado、Vitis、额外 Python 第三方包。

**源文件（须已在仓库）**：

- `report/results/ooc/utilization.rpt`
- `report/results/ooc_new/utilization.rpt`
- `report/results/perf/difi_perf_latency.csv`
- `report/results/perf/board_IP_perf.rtf`
- `report/results/udp/validation_notes.md`

**执行**：

```powershell
cd D:\Study\project\DIFI
python -m pip install matplotlib
python scripts/figures/build_performance_figures.py --repo-root . --cpu-hz 666666667
```

输出到 `report/figures/`，每张提供 `.svg` 矢量和 `.png` 位图。

脚本在读取数据时进行基本一致性检查；不输出假的性能数据。工程改动后若原始计数变化，需审查脚本中原案例的边界断言，并根据新的测试报告重新制作新图，而不是篡改或跳过断言。**板级换算的 CPU 频率配置证据仍须最终归档。**

Matplotlib 尝试使用可用的中文字体（Noto Sans CJK / 微软雅黑 / 文泉驿 / 黑体等），SVG 保留可编辑文字。不同操作系统重新生成时应检查字体是否缺字。
