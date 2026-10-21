# 离线检查状态与后续统一验收

## 已覆盖的单元测试（合成数据）

执行：

```powershell
python -m unittest discover -s skill/udp-packet-validation/tests -v
```

`make_fixtures.py` 每次用固定构造生成 Ethernet/IPv4/UDP classic PCAP 与按长度前缀编码的二进制，**不是用户实际 FPGA 抓包**。

正向：22 包 DIFI B5 顺序/包长/SID/OUI/IQ、总量21,192B/5,120 IQ、VLAN、普通 UDP 顺序、Golden 匹配、分流 1+21。

负向：IQ 位翻转、序号跳跃、短包、少包、空流、错误 SID、非法配置、未匹配的过滤器、截断文件、pcapng 输入拒绝、IP Fragment 拒绝、Profile JSON 字段错误等。

通过判断：正确样例脚本返回 0；有错误的数据返回 1；不支持的输入或损坏 PCAP/无效配置返回 2。单元测试不需要 Zynq 板卡或网络。

## 尚待四 Skill 统一测试

1. 新工具以真实 `difi_b5_udp_22.pcapng` 转 classic PCAP 的结果进行复核，并与原 `difi_udp_receiver.py` 的保存文件逐包交叉比较。
2. 在独立监听端口测试新 `udp_capture.py`；不要和老接收器争抢 4991。
3. 用 `udp_validate.py` 在非 DIFI 的真实 UDP 项目中完成至少一轮成功/失败测试，证明 Profile 的通用可迁移性。
4. 用原版 DIFI Consortium 工具重新分析按流拆分的抓包，记录每个版本与哈希。
5. 根据真实问题修复并更新 SKILL 文档，形成 `acceptance_report.md`；真实板级 PASS 与当前离线 PASS 分开。

## 本版离线执行记录

制作时独立执行了 `34` 个单元测试，全部 OK，并确认正常/错误输入的 CLI 返回码分别为 `0`/`1`，详见 `tests/OFFLINE_TEST_RESULTS.txt`。上述测试全部使用本包生成的**合成** Ethernet PCAP，不代表用户已验证新工具的硬件工作流。
