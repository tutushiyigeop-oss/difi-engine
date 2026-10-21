# AXI DMA Skill 运行与验收记录模板

- 项目名称：
- Git commit SHA：
- Vivado / Vitis / Board / CPU：
- 编译构建的 XSA/Bitstream SHA256 或来源：
- DMA 配置：Simple/SG；MM2S/S2MM；DRE；width；max BTT；时钟/reset
- 系统连线：MM2S → [实际 PL 模块] → S2MM；TVALID/TREADY/TLAST/TKEEP 实际路径
- 缓冲：地址/长度/对齐/Cache maintenance
- 测试口径：每包长度，传输次数，数据模式，错误注入与否

## 运行命令（记录原文）

```
<replace with real command>
```

## 结果

| 检查 | 预期 | 实际 | 判定 |
|---|---|---|---|
| 编译 | 无错误 | 待测 | PENDING |
| DMA 配置审计 | 地址/长度/对齐满足实际硬件 | 待测 | PENDING |
| TX/RX 传输 | 两通道完成，无 DMA 错误位 | 待测 | PENDING |
| 数据比对 | N/N 匹配 | 待测 | PENDING |
| TLAST 终止 | 每包准确结束 | 待测 | PENDING |
| 故障注入 | 能识别至少一种预期错误 | 待测 | PENDING |

## 诊断记录

1. 观察到的原始错误与日志（不能编造）：
2. AI 初次分析建议与可能错误：
3. 人工检查 / 修改内容：
4. 实际复测结果（附 UART 原文件路径）：
5. 剩余风险、环境依赖、失效条件：

## 结论范围

- [ ] 仅本地 Python 静态检查通过
- [ ] Vitis 模板已编译（不是上板 PASS）
- [ ] 真实 DMA 板级数据验证通过
- [ ] 已在第二个独立项目/平台迁移验证

声明：不要把某项目的成功结果推断为本通用模板已经跨项目验证通过。
