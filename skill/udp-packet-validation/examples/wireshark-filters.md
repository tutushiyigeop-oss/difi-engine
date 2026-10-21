# Wireshark 抓包、显示过滤与转格式

## 1. 选择正确网卡

- PC: 192.168.1.20 /24，板卡: 192.168.1.10，端口: UDP/4991（仅 DIFI 本次示例）。
- 选择连接板卡的物理网卡，抓包时先启动 Wireshark，再启动 PC 监听/发送 `START`。

## 2. 两种过滤器不能混用

**抓包过滤器（Capture Filter，BPF）**：

```text
udp and src host 192.168.1.10 and dst host 192.168.1.20 and dst port 4991
```

**显示过滤器（Display Filter）**：

```text
ip.src == 192.168.1.10 && ip.dst == 192.168.1.20 && udp.dstport == 4991
```

仅按此次固定长度选择：

```text
udp.length == 52      # Version UDP 头8 + payload44
udp.length == 116     # Context UDP 头8 + payload108
udp.length == 1060    # Data UDP 头8 + payload1052
```

写进 Wireshark 过滤框时只粘贴左边表达式，不要输入这里示例的 `#` 注释。

如果 `difi.packet_type == 0x5` 显示红色，通常是字段未注册或 Lua 插件未生效；这与真实帧符合性没有必然联系。优先用上述 `udp.length` 过滤或展开 `UDP payload`，再进行独立验证。

## 3. 保存真实证据

1. 保存原始完整 22 包 `.pcapng`，不要覆盖。
2. 分别保存全 22 包列表、Version、Context、Data 字段截图；截图不替代原始 PCAP。
3. 要给本 Skill 离线解析时，使用 Wireshark `File → Save As` 选择 `pcap` 经典格式；也可以使用 TShark：

```powershell
tshark -r input.pcapng -F pcap -w output.pcap
```

4. 若原件含与实验无关的 UDP/ARP，请先单独使用显示过滤器选择报文，通过 Wireshark 的 Export Specified Packets 保存；保留原始文件与过滤导出文件。
5. 对第三方参考验证可先将报文分流（见 `consortium-validation.md`）。

**注意**：PCAP → PCAP 的过滤可以改变可见数量，不能基于“只导出符合长度的包”得出完整网络没有丢/错包的结论。
