# B6 v0.2 UDP RX：工程复现与证据清单（2026-10-23）

## 已入库且具有板级证据

- `rtl/board/difi_b6_rx_meta_monitor.v`：Version/Context Metadata 有效握手、Sequence/Changed 与错误事件监测。
- `vitis/vitis_ws/difi_b6_udp_rx_pro/src/{main.c,b6_config.h}`：三类报文 PS lwIP RAW API 接收与 DMA 测试；`B6_MON_BASE=0x41200000` 须与真实 XSA 对应。
- `scripts/verify/tools/difi_b6_three_types.py`，与 `difi_b6_sender.py` 在同目录。
- `report/results/udp/rx/three_types_udp_rx.rtf`：Version×1、Context×1，20 Data×256 IQ 全部匹配；15→0 序号回绕。
- 旧 `difi_b6_udp_rx/src/` 属于 Data-only v0.1，不是当前三类正式演示版本。

## 必须保留的硬件连接

1. PS GEM0/PHY/MDIO 与 B5 已成功联网的开发板 MIO 配置一致，MDIO 为 MIO 52/53。
2. AXI DMA MM2S 接 DIFI `S_AXIS_RX_PKT`，DIFI `M_AXIS_IQ` 接 DMA S2MM；不使用旧 TX→RX 内部回环。
3. Version/Context Metadata READY 正确处理，不给这两类报文启动等待 IQ 的 S2MM。
4. Metadata Monitor 与 DIFI IP 同一 PL clock/reset；两路 32-bit GPIO 输入分别连接计数和详情；Vitis 读取地址须匹配 Address Editor。

## 当前复现状态（2026-10-23）

- [x] 真实 B6 BD Tcl、manifest、IP 与 RTL 依赖已入库：`scripts/vivado/generated/b6_udp_rx/`。
- [x] 原始 B6 Routed 证据已入库：`report/results/b6_impl/`。
- [x] 全新工程重建通过：`report/results/vivado_rebuild/b6_udp_rx/SUCCESS.txt`，WNS +2.372 ns，WHS +0.053 ns；Bitstream/XSA 已生成。
- [x] 开发者确认重建 XSA 上板 Version、Context、Data 三类 UDP RX 回归 PASS。
- [x] 新 XSA SHA256 和 Bitstream SHA256 已由开发者本机计算并入库，见 [`BOARD_REGRESSION_STATUS.md`](../../report/results/vivado_rebuild/b6_udp_rx/BOARD_REGRESSION_STATUS.md)。
- [ ] 仍缺本轮 Vitis/UART/PC 原始记录、ELF 哈希及实际测试版本绑定。
- [ ] 异机完整复现、Context/Version Metadata 全字段 PS 读回、无 ACK 连续吞吐、同时全双工测试均未完成。

保留早期原始 `three_types_udp_rx.rtf` 的真实历史定位，不作为新 XSA 回归日志。见 [B6 板级回归记录](../../report/results/vivado_rebuild/b6_udp_rx/BOARD_REGRESSION_STATUS.md)。

从全新目录重建（Vivado 2024.2，每条单行命令；不要覆盖已成功工程）：

```powershell
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b6_udp_rx
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b6_udp_rx
```

在新 XSA 上配套创建 Vitis Platform 并运行 `difi_b6_udp_rx_pro`；PC 端运行 `scripts/verify/tools/difi_b6_three_types.py`，须单独保存板级和 PC 原始输出。
