# UDP Packet Validation Skill

> 类型：AI 提示词工作流 + Python 校验工具 + DIFI 真实案例模板 + 踩坑清单。面向 Zynq/FPGA 输出到 PC 的 UDP 二进制数据验证；**不依赖 DIFI 的协议结构即可使用通用工具**。

[技能定义](SKILL.md) · [DIFI 真实案例](examples/difi-case-study.md) · [Wireshark 说明](examples/wireshark-filters.md) · [参考工具](examples/consortium-validation.md) · [验收报告](templates/acceptance_report.md)

## 1. 目录

```text
skill/udp-packet-validation/
├── SKILL.md
├── README.md
├── scripts/
│   ├── udp_pcap.py             # 经典 PCAP / 长度前缀 UDP 容器读写
│   ├── udp_capture.py          # 可选实时监听/保存 PC 端 UDP Payload
│   ├── udp_validate.py         # 面向任意 UDP 二进制应用的 JSON Profile 检查
│   ├── difi_b5_validate.py     # 本队 B5 固定测试向量回归工具
│   └── split_difi_pcap.py      # 按不同 Stream ID 分离 classic PCAP
├── templates/
│   ├── generic_profile.json
│   ├── ai_workflow.md
│   ├── test_matrix.md
│   └── acceptance_report.md
├── examples/
│   ├── difi-case-study.md
│   ├── wireshark-filters.md
│   └── consortium-validation.md
└── tests/
    ├── make_fixtures.py
    ├── test_tools.py
    └── VALIDATION.md
```

## 2. 不接板卡先运行离线自测

从仓库根目录：

```powershell
python -m unittest discover -s skill/udp-packet-validation/tests -v
```

可生成训练样例 PCAP（合成数据，并非真实抓包）：

```powershell
python skill/udp-packet-validation/tests/make_fixtures.py
```

然后运行正反例，正确输出时**返回码分别为 0 和 1**：

```powershell
python skill/udp-packet-validation/scripts/difi_b5_validate.py --pcap skill/udp-packet-validation/tests/fixtures/b5_synthetic_valid.pcap
python skill/udp-packet-validation/scripts/difi_b5_validate.py --pcap skill/udp-packet-validation/tests/fixtures/b5_synthetic_bad_iq.pcap
python skill/udp-packet-validation/scripts/udp_validate.py --pcap skill/udp-packet-validation/tests/fixtures/generic_valid.pcap --profile skill/udp-packet-validation/templates/generic_profile.json
python skill/udp-packet-validation/scripts/udp_validate.py --pcap skill/udp-packet-validation/tests/fixtures/generic_bad_seq.pcap --profile skill/udp-packet-validation/templates/generic_profile.json
```

**注意**：PowerShell 中运行程序显示 `[FAIL]` 是故意错误样例被正确拒绝，而不是工具失效；具体以 stderr 和退出码判断。

## 3. 通用 UDP 验证——无需 DIFI

`templates/generic_profile.json` 示例与 `generic_valid.pcap` 搭配：

```json
{
  "filter": {"src_ip": "192.168.1.10", "dst_ip": "192.168.1.20", "dst_port": 4991},
  "expected_count": 3,
  "min_payload_length": 8,
  "max_payload_length": 8,
  "sequence": {"offset": 0, "width": 1, "endian": "big", "mask": 255, "shift": 0, "start": 0, "modulus": 256}
}
```

先根据实际协议与测试条件修改计数、长度与序号字段；也支持可选 `golden_payloads_hex`，长度必须与 expected_count 一致。序号检查定义是“每个被过滤选中的包的序列值严格逐 1 递增并可取模”；如果存在多个相互独立 Stream ID 或部分报文不参与计数，需要**先分流**或编写适配器。

```powershell
python skill/udp-packet-validation/scripts/udp_validate.py --pcap PATH_TO_CAPTURE.pcap --profile PATH_TO_PROFILE.json --report report/results/udp/skill_generic_result.json
```

从 PC 接收程序生成的长度前缀文件进行检查（由于文件没有网络地址信息，Profile 中 `filter` 必须改为 `{}`）：

```powershell
python skill/udp-packet-validation/scripts/udp_validate.py --capture-bin PATH_TO_CAPTURE.bin --profile PATH_TO_PROFILE_WITHOUT_IP_FILTER.json
```

**PCAP 支持范围**：classic PCAP Ethernet（DLT=1）+ IPv4 + UDP，支持单/双 VLAN tag；非 UDP 帧跳过。既不支持 `.pcapng`、IPv6、IP 分片重组，也不检查 IPv4/UDP checksum。不支持的格式须转换或借助成熟工具，不能在本工具中误报 PASS。

## 4. PC 实时监听和归档（可选）

这个脚本默认被动监听，**不会发送任何控制包**：

```powershell
python skill/udp-packet-validation/scripts/udp_capture.py --listen 192.168.1.20 --port 4991 --count 22 --timeout 10 --src-ip 192.168.1.10 --output report/results/udp/skill_capture.bin --metadata report/results/udp/skill_capture_meta.jsonl
```

只有在确认目标为可信测试板卡后，可加：

```text
--trigger-host 192.168.1.10 --trigger-text START
```

当本地套接字已经监听后才发送 START。输出 `.bin` 为每包 `4-byte big-endian length + UDP payload`，不包含 Ethernet/IP/UDP 头、远端地址、接收时间。元数据另存在 `jsonl`；需保留 Wireshark PCAP 才能证明物理抓包细节。请勿与已在同一 `IP:port` 上监听的老 `difi_udp_receiver.py` 同时运行，否则端口冲突。

## 5. DIFI B5 专用完整检查

若有实测完整 DIFI PCAP：

```powershell
python skill/udp-packet-validation/scripts/difi_b5_validate.py --pcap report/results/udp/difi_b5_udp_22.pcap --src-ip 192.168.1.10 --dst-ip 192.168.1.20 --dst-port 4991 --report report/results/udp/skill_b5_result.json
```

如果只有旧 PC 脚本保存的 `difi_udp_capture.bin`，可改用 `--capture-bin`，但此种验证不会检查源 IP 和网络端口。该工具检查固定 B5 顺序：Version 1、Context 1、Data 20，默认 SID=2/1、每个 Data=256 IQ、序号 modulo16、网络大端与测试向量；**它不能替代 `certify_source.py`，更不等同于正式认证**。

## 6. PCAP/PCAPNG 和 DIFI Consortium

原始 `.pcapng` 请在 Wireshark 中另存或使用 TShark：

```powershell
tshark -r report/results/udp/difi_b5_udp_22.pcapng -F pcap -w report/results/udp/difi_b5_udp_22.pcap
```

如果捕获原件包含多个控制包或 ARP，先用 `ip.src`、`ip.dst`、`udp.dstport` 过滤，再导出；避免无关网络流影响固定 22 包检查。为了使用 DIFI Consortium 参考工具并规避不同合法 Stream ID 造成的混合流误报，可分离 classic PCAP：

```powershell
python skill/udp-packet-validation/scripts/split_difi_pcap.py --pcap report/results/udp/difi_b5_udp_22.pcap --board-ip 192.168.1.10 --pc-ip 192.168.1.20 --port 4991 --outdir report/results/udp/skill_split
```

再使用**外部原版** DIFI Consortium 工具分别验证，详见 [第三方验证指南](examples/consortium-validation.md)。本包**不分发**该仓库及其依赖，避免复制未确认许可的第三方源代码。

## 7. 常见失败和退出码

- **0**：检查完成且所有配置约束满足；
- **1**：已处理的报文不符合期望（例如丢包、序列错、IQ 数据错）；
- **2**：命令配置、文件/格式或依赖错误；在转换/修复前不得宣称验证完成。

测试通过只意味着**本次选中并分析的内容满足本 Profile**；不能宣称 UDP 无丢包、系统抗干扰、真实性能达到极限或任何协议正式认证。

## 8. 与现有 DIFI 工程的关系

- 继续保留项目已上板验证过的 `scripts/verify/tools/difi_udp_receiver.py`，**不要用本通用 Skill 的脚本替换它**。
- 项目原有 Vitis lwIP 发送代码位于 `vitis/vitis_ws/difi_b5_udp_tx/src/difi_b5_udp_tx.c`。
- 历史测试结论位于 `report/results/udp/validation_notes.md`；新 Skill 在其他网络/协议上的实际复用测试**待后续统一进行**。
