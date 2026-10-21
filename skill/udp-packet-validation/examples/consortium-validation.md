# DIFI Consortium 参考工具独立验证（仅 DIFI 1.1 专用）

## 背景

`DIFI-Consortium/DIFI-Certification` 提供的 `certify_source.py` 是独立的开源参考校验工具。**本 Skill 自己的 `difi_b5_validate.py` 只检查固定 B5 测试向量**，不可当成第三方 DIFI 符合性检查。

该公开参考工具需在使用前查阅原仓库 README、环境和许可。下载工具及依赖应在可信环境进行：

```powershell
git clone https://github.com/DIFI-Consortium/DIFI-Certification.git
cd DIFI-Certification
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 分离两个合法 Stream ID

本次 B5 Version SID=2，Context/Data SID=1。建议保存完整抓包原件，并创建两个**不修改原 UDP payload**的 PCAP 副本：

```powershell
python skill/udp-packet-validation/scripts/split_difi_pcap.py `
  --pcap report/results/udp/difi_b5_udp_22.pcap `
  --board-ip 192.168.1.10 --pc-ip 192.168.1.20 --port 4991 `
  --outdir report/results/udp/skill_split
```

预期 Version `1` 包、Context+Data `21` 包。此分流器按类型 nibble 与 SID 匹配，不验证完整 DIFI 字段；若遇到不认识的目标报文应拒绝而非静默丢弃。

## 在第三方工具目录单独运行

```powershell
.\.venv\Scripts\python.exe .\certify_source.py --pcap D:\Study\project\DIFI\report\results\udp\skill_split\version_flow.pcap --difi-version 1.1
.\.venv\Scripts\python.exe .\certify_source.py --pcap D:\Study\project\DIFI\report\results\udp\skill_split\data_context_flow.pcap --difi-version 1.1
```

注意 `certify_source.py` 当前 README/脚本的选项应当以你安装的那个版本为准；写入报告时记录 SHA256/commit、工具输出、输入 SHA256，不单独依赖 PASS 这一个单词。

- Version：符合1，不符合0；
- Context/Data：符合1/20，不符合0；
- `No data packets found, cannot plot PSD` 对 Version-only 输入是预期现象；不能据此认为 Version 不合格。
- 如果官方工具从 GitHub ZIP 下载，`fatal: not a git repository` 可能仅影响版本哈希记录，应以实际 Process Exit Code、计数器和 Overall Result 判断。
- 分离合法 SID 是针对此次参考工具的已知处理行为；**不能由此证明所有跨流一致性、所有 DIFI v1.1 选项都通过**。

本项目已有 `scripts/verify/tools/certify_difi_pcap.ps1` 用于标准化导出第三方工具结果。它有自己的 PCAP 文件名和工具路径参数规范；不要直接把新的分流目录随意代入并宣称自动成功。

## 结论措辞

✅ “使用 DIFI Consortium 开源参考工具，指定 DIFI v1.1，对两个分流 PCAP 的相应类型报文检查全部 PASS。”

❌ “已获得 DIFI Consortium 官方认证 / 完成全部 DIFI 1.1 一致性认证。”
