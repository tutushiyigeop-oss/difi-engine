# DIFI 1.1 B5 UDP 链路——已发生的实测案例

## 1. 测试环境与数据路径

- 真实硬件：AMD/Xilinx XC7Z020CLG400-2，Vivado / Vitis 2024.2。
- FPGA/板卡：DIFI `difi_board_raw_packet_export`（B5），`DMA MM2S IQ → DIFI TX Packetizer → DMA S2MM full DIFI packet`。
- PS：Vitis Standalone lwIP220 RAW API、GEM0 UDP 发送；Zynq IPv4 为 `192.168.1.10`。
- PC：`192.168.1.20`、UDP 4991；PC Python `difi_udp_receiver.py` 先绑定 UDP 后发送一次 `START`，PS 从收到的控制包获取 PC IP/端口。
- 原 DIFI 发送端 Vitis 源：`vitis/vitis_ws/difi_b5_udp_tx/src/difi_b5_udp_tx.c`。
- PC 校验脚本：`scripts/verify/tools/difi_udp_receiver.py`。

**B5 与 B4/IP 回环区别**：B5 S2MM 输出原始 DIFI Packet，不是已经解析后的 IQ；不能直接拿封装 IP 的 XSA 去构建 B5 发送程序。

## 2. 原始实测结果（不是本 Skill 新版脚本的实测）

| 类别 | 个数 | 单包 UDP payload 字节 | Stream ID | Sequence |
|---|---:|---:|---:|---|
| Version | 1 | 44 | 2 | 0 |
| Context | 1 | 108 | 1 | 0 |
| Data | 20 | 1,052 | 1 | 0..15, 0..3 |

- 合计 `22` UDP 报文、`21,192` 字节 UDP payload。
- Data IQ `5,120/5,120` 正确，错误计数 `0`。
- PC 原程序结果：`[PASS] DIFI UDP full chain: 1 Version + 1 Context + 20 Data, 5120 IQ correct`。
- FPGA Vitis 程序逐包 `usleep(2000)` 人为限速；**不是网络吞吐率 benchmark**。
- `certify_source.py --difi-version 1.1` 两份分流抓包：Version `1/1`；Context `1/1`；Data `20/20`，非符合报文数 `0`，均 `Overall Result: PASS`。这并不是 DIFI Consortium 正式颁发的认证。

源证据：`report/results/udp/validation_notes.md` 与 `report/results/udp/consortium/{version,data_context}/`。

## 3. 经验来自哪些实测观察与排查

1. **网络字节序必须明确**：PS DDR 内 DIFI `u32` 为小端主机表示；发送前将每个 32-bit Word 按 MSB first 写入 UDP payload，PC 按 `!I`（网络字节序）解析。错误序不是 DIFI 兼容的另一种编码。
2. **触发式发送必须先启动接收端**：PC 先 bind 4991，发送 `START` 控制报文，FPGA 端收到后启动 Version / Context / Data，避免先发后监听错过启动包。
3. **不能只信 UDP 发送返回值**：原发射程序也打印“`udp_sendto` success does NOT prove receipt”；PC 必须 independently check packet count, size, order and payload。
4. **Wireshark GUI 解码插件不等于协议符合性**：内置 VITA49 解析和 DIFI Lua 插件注册不同；即使 `difi.packet_type` 显示字段不可用，也可以依赖 `udp.length` 及原始字段进行筛选，并使用独立参考工具验证。
5. **官方工具多 Stream ID 的口径问题**：本次 Version SID=2，Context/Data SID=1；原开源认证参考程序有跨报文保存 SID 状态的行为，混合文件可能误报。保留完整 22 包原件并分流验证，两者结论需各自标注范围。

## 4. 本技能包如何迁移

- 非 DIFI 设备：只采用 `udp_capture.py` + JSON Profile + `udp_validate.py`，自行定义 Payload、序号字段与黄金数据。
- DIFI B5 本例：运行 `difi_b5_validate.py`，再运行**未修改的第三方参考工具**。
- 换成另一种 DIFI Profile、不同 IQ 模式或不固定包序：固定向量检查器必须重写/扩展，不能直接照搬本次 PASS。

## 5. 尚待统一测试

新 Skill 的 Python 工具已在合成正反例上离线运行，**尚未使用新脚本进行新的真实 PC/FPGA 网络收发，也尚未跨到非 DIFI 工程**；待四个 Skill 全部入库后统一验收并补充报告。
