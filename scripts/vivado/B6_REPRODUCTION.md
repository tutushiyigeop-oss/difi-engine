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

## 当前未入库的 B6 专属构建产物和证据

**不要把已有 `packaged_ip` Tcl 或 `b5_raw_export` Tcl 当成 B6 v0.2 BD。**

- 真实 B6 v0.2 `bd.tcl`、设计 part/版本、IP 依赖、地址清单、时钟与复位清单、manifest。
- 对应 Bitstream/XSA 的版本关联记录和 B6 专属 Routed timing/utilization/DRC 报告。
- 从独立工程复建 B6 BD、实现、新 XSA 再上板的完整验收记录。
- 对 B6 Version/Context 所有 Metadata 字段逐项读回、持续吞吐和同时全双工尚无证据，不能宣称已完成。

## 如何从本地 B6 真工程导出

Vivado 2024.2 Tcl Console 在打开正确 Block Design 后执行：

```tcl
validate_bd_design
save_bd_design
write_bd_tcl -force {D:/Study/project/DIFI/b6_udp_rx_bd.tcl}
```

人工核对脚本中 IP VLNV、时钟、GPIO 地址和 PHY 设置后，提交到独立 `scripts/vivado/generated/b6_udp_rx/`，不要覆盖已验证的旧 Tcl 快照。脚本不保证无需其他 IP/XDC 依赖即可重建，必须随后用新目录实测。


## 归档脚本已提供（2026-10-23）

现已提供 [`capture_b6_evidence.tcl`](capture_b6_evidence.tcl) 来从**本机真实 B6 v0.2 Vivado 工程**采集 BD 快照与 Routed 实现报告，操作命令、隔离暂存目录和 Git 审核清单详见 [`B6_CAPTURE_GUIDE.md`](B6_CAPTURE_GUIDE.md)。这些工具脚本已提交，不代表本机真实导出物或独立 B6 构建 PASS 已产生。
