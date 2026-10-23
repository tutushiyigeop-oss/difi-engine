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

## 当前工程状态：本阶段已完成（2026-10-23）

- [x] 真实 B6 BD Tcl、manifest、IP/RTL 依赖已入库：`scripts/vivado/generated/b6_udp_rx/`。
- [x] 原始 B6 Routed 报告已入库：`report/results/b6_impl/`。
- [x] 全新工程独立重建、综合、实现、Bitstream/XSA 均 PASS：`report/results/vivado_rebuild/b6_udp_rx/SUCCESS.txt`；Setup WNS +2.372 ns、Hold WHS +0.053 ns。
- [x] 开发者确认：独立重建新 XSA 再次完成 Version、Context、Data 三类 UDP RX 功能回归。
- [x] 独立重建 XSA 和 Bitstream 的 SHA256 已记录于 [B6 阶段验收记录](../../report/results/vivado_rebuild/b6_udp_rx/BOARD_REGRESSION_STATUS.md)。

**B6 v0.2 本阶段正式收束。** 仓库保留原始工程 UART `report/results/udp/rx/three_types_udp_rx.rtf`、Vivado 工具结果和开发者确认的复测结论，各自代表不同的证据层次。这里不声称 DIFI 官方认证、无 ACK 连续 UDP 吞吐或同时全双工。

## 从仓库复现本次已验证工程

以下是供其他环境重新构建的**单行命令**（Vivado 2024.2，仓库根目录）。开发者已成功构建的现有目录不用重新执行；脚本会拒绝覆盖。

```powershell
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b6_udp_rx
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b6_udp_rx
```

构建使用仓库中的 `ip_repo/` 和 `rtl/board/difi_b6_rx_meta_monitor.v`，硬件通过新 XSA 在 Vitis 上运行 `difi_b6_udp_rx_pro`，PC 端三类报文工具为 `scripts/verify/tools/difi_b6_three_types.py`。
