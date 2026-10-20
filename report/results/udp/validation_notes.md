# DIFI 1.1 UDP 端到端验证记录

**测试日期：** 2026-10-20

## 1. 测试平台

- FPGA：AMD/Xilinx Zynq-7020，xc7z020clg400-2
- 开发工具：Vivado / Vitis 2024.2
- 协议版本：DIFI 1.1
- 发送端：Zynq PS Ethernet（192.168.1.10）
- 接收端：Windows PC（192.168.1.20）
- 通信协议：UDP
- 验证工具：Wireshark、DIFI Consortium DIFI-Certification 开源参考工具

## 2. UDP 端到端验证结果

| 报文类型 | 数量 | 报文负载大小 | 验证结果 |
|---|---:|---:|---|
| Version Packet | 1 | 44 B | PASS |
| Context Packet | 1 | 108 B | PASS |
| Signal Data Packet | 20 | 1052 B/包 | PASS |

共成功接收 22 个 DIFI Packet，总计 21,192 Byte UDP 有效载荷。

所有 Data Packet 的 IQ 样本均正确，共验证 5,120 个 IQ Sample，失配数为 0。

Data Packet Sequence Number 按 0～15 循环，并成功验证从 15 到 0 的回绕。

## 3. DIFI Consortium 参考工具验证

采用 DIFI Consortium 的 `certify_source.py`，明确指定 `--difi-version 1.1`，分别对 Version 流以及 Context/Data 流进行验证。

| 验证项目 | 符合要求 | 不符合要求 |
|---|---:|---:|
| Version Packet | 1 | 0 |
| Context Packet | 1 | 0 |
| Signal Data Packet | 20 | 0 |

两个独立测试均返回 `Overall Result: PASS`。

需要说明：本次采用参考工具分别检查两个 Stream ID 的报文，验证结果不等同于 DIFI Consortium 的正式认证，也不代表覆盖全部协议测试项目。

## 4. 测试结论

本次测试成功完成 FPGA DIFI Packetizer → AXI DMA → Zynq PS → UDP → PC 的数据传输链路。

PC 端自定义接收程序验证全部 22 个报文及 5,120 个 IQ 样本正确；DIFI Consortium 开源参考工具对 Version、Context、Signal Data 三类报文的本轮检查均通过。

因此，可以确认当前实现已具备 DIFI 1.1 基础报文生成、实际 UDP 传输以及独立参考工具验证的完整功能闭环。

本轮 UDP 发送程序存在人为设置的报文间隔，不将其用于网络最大吞吐率评估。