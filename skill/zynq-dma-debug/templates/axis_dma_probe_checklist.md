# AXI DMA ↔ AXI4-Stream 现场探测清单

用途：S2MM 永远 Busy、数据长度不符、包内容错乱时，用 ILA/硬件调试捕获与软件寄存器联合分析。不能把“没有 ILA 波形”当成“信号正常”。

## 1. 软件最小日志（每次测试必须归档）

- 使用的 XSA / Bitstream SHA256 或确切工程提交。
- DMA mode：Simple / Scatter-Gather；MM2S、S2MM 通道是否同时存在；DRE 开关；C_SG_LENGTH_WIDTH。
- MM2S 数据物理地址、BTT；S2MM 数据物理地址、BTT、分配缓冲容量；DDR 可访问区域。
- `XAxiDma_LookupConfig`、`CfgInitialize`、`SimpleTransfer` 返回值。
- 发起前与终止/超时后的 `MM2S_DMASR`、`S2MM_DMASR` 十六进制原值。
- 实际对比了几个 32-bit word / byte，首个失配位置，源与目的数据片段。
- DMA 相关 Cache Flush / Invalidate 的先后顺序，以及是否禁用 DCache 做过隔离试验（仅限可控环境）。

## 2. ILA 建议探针

| 端口 | 要验证的事实 | 典型异常 |
|---|---|---|
| `M_AXIS_MM2S_TVALID` | MM2S 是否实际输出数据 | 长期 0，检查 DMA 配置/源 DDR |
| `M_AXIS_MM2S_TREADY` | 下游是否接受数据 | 长期 0，检查下游状态和 reset |
| `M_AXIS_MM2S_TLAST` | 是否在合法的最后一次传输上标记包尾 | 提早/未出现/持续太长 |
| `S_AXIS_S2MM_TVALID` | S2MM 端是否收到字节流 | 长期 0，检查 PL 路由 |
| `S_AXIS_S2MM_TREADY` | S2MM 是否已启动并接受数据 | RX 尚未准备、DMA error |
| `S_AXIS_S2MM_TLAST` | S2MM 是否实际看到包尾 | 未收到则可能迟迟不能完成 |
| `TKEEP` | 最后一个 beat 的有效字节掩码与长度 | 末尾有效字节数不符 |
| `ACLK`/`ARESETN` | 时钟和同步复位有效 | 设计并没有运行 |

## 3. 波形检查方法

1. 仅在 `TVALID && TREADY` 为真的时钟沿将其计为一次**成功握手**；仅凭 `TVALID` 不能计数。
2. 仅当 `TVALID && TREADY && TLAST` 同时为真时，才能认为该时刻完成一个包。
3. 计数每个握手 Beat 上 `TKEEP` 的有效字节数量，求和应与该包实际负载一致；对于固定满字示例，应为 `beat_count × 4 B`。
4. 若 IP 接收的数据不是输入 IQ（例如 DIFI 全 Packet ），应按接收内容的实际长度和变换后的包界判定，不得简单要求 TX 字节数等于 RX 字节数。
5. 结合 `DMASR` 确认是否是 Memory Mapped 侧出错，不能因为缺 TLAST 就忽略 DMAIntErr/DMASlvErr/DMADecErr 等证据。

## 4. 缓存风险点

- 在 DMA 使用的 RX 缓冲区附近摆放其他 CPU 高频修改的数据，可能造成同一个缓存行的写回/失效相互影响；优先对齐并隔离完整缓存行。
- `Xil_DCacheInvalidateRange` 并不会修正 PL 的错线或错误 TLAST，且不应在 DMA 尚在写入、CPU 同时读写 RX 的条件下当作通用同步方案。
- 对 PS Linux/ACP 或不同器件，使用操作系统/平台要求的一致性 API，不能机械复制裸机函数。

## 5. 判断结果的最低证据标准

- **软件功能通过**：无 DMA 错误、传输完成、黄金样本逐字节比对相等、字节长度与包边界正确。
- **协议接口通过**：额外确认具体 ILA/TLAST/背压覆盖或 Testbench 检查。
- **可靠吞吐率**：清楚划分系统窗口（CPU + DDR + DMA 等）和 DMA 事务窗口，不把软件吞吐率直接当成 PL 模块峰值。
