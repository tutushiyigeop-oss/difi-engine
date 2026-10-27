# 可复用 Skill 使用说明

本目录提供四个可以独立阅读和调用的工程 Skill。每个 Skill 的 `SKILL.md` 是主要使用入口，具体脚本及模板位于其 `scripts/`、`templates/` 和 `examples/` 目录。

| Skill | 使用场景 | 入口 |
| --- | --- | --- |
| Vivado Rebuild | 导出 Block Design、检查依赖、从干净目录重建工程、生成 Bitstream/XSA | [vivado-rebuild/SKILL.md](vivado-rebuild/SKILL.md) |
| Zynq DMA Debug | AXI DMA Simple Mode、Cache、一致性及 TLAST 故障排查 | [zynq-dma-debug/SKILL.md](zynq-dma-debug/SKILL.md) |
| AXIS RTL Verification | 握手、背压、报文边界、Golden Model 与故障注入 | [axis-rtl-verification/SKILL.md](axis-rtl-verification/SKILL.md) |
| UDP Packet Validation | UDP 捕获、PCAP、二进制字段解析与 DIFI 报文校验 | [udp-packet-validation/SKILL.md](udp-packet-validation/SKILL.md) |

## 使用步骤

1. 选择适合问题的 Skill，阅读相应 `SKILL.md` 中的输入要求、命令和适用边界。
2. 按文档说明准备工具链、工作目录及输入文件；先阅读命令参数，再运行对应的 `scripts/`。
3. 按需要引用 `templates/` 与 `examples/`，将工程相关的寄存器地址、Stream ID、器件型号替换为目标项目的实际值。
4. 将生成的日志、输出文件、工具版本和使用的参数保存在自己的工程记录中。

注意：Vivado Tcl 和其他外部脚本可能执行文件操作，运行前检查来源及目标目录。不要在未经备份的唯一工程副本上直接执行重建或覆盖操作。
