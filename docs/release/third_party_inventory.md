# 第三方素材、生成物与敏感信息的发布审查表

> 初步库存，尚未完成逐文件授权审核；“待核查”不表示文件有问题，也不表示已经获得第三方许可。

| 类别及实际路径 | 核查重点 |
|---|---|
| `rtl/`、`vitis/vitis_ws/*/src/`、`scripts/`、`skill/` | 本项目代码的所有贡献者、外部代码片段和 AI 生成物的授权边界 |
| `ip_repo/difi_engine_ip/component.xml` 与 `xgui/*.tcl` | Vivado IP Packager 生成元数据/配置；不得误将厂商专有 IP 的实现代码打包分发 |
| `scripts/vivado/generated/*/bd.tcl` | 真实 Vivado BD 导出脚本；检查绝对路径、外部依赖、厂商生成内容及许可 |
| `docs/protocol/`、`docs/interface/` 的 DOCX | 核查是否包含未经授权复制的 DIFI/VITA 标准原文、图表或第三方规范；必要时仅保留原创实现摘要与标准引用 |
| 外部 [DIFI Consortium DIFI-Certification](https://github.com/DIFI-Consortium/DIFI-Certification) | 本项目保留验证输出并引用上游，不打包其 `certify_source.py`；当前上游未见常规根 LICENSE，GitHub 的许可证识别为 Other/NOASSERTION，**不能推定可按本项目 MIT 许可再分发上游源码** |
| Vivado、Vitis、BSP、lwIP、Wireshark、Icarus | 外部依赖按实际 EULA/许可证安装；不上传厂商工具安装包、付费 IP、未获授权的二进制 |
| `report/results/udp/`、`verification/pcap/` 与 Skill PCAP fixtures | 区分真实抓包与合成测试；检查 MAC、内网 IP、时间戳和设备标识，必要时发布脱敏副本 |
| `verification/logs/`、`report/results/perf/board_IP_perf.rtf`、Vivado `.rpt` | 检查用户名、主机名、绝对路径、账户、Token 等；注意旧 Git 提交也可能存在原始信息 |
| `report/ai_collaboration/`、屏幕录像和报告截图 | 原始模型聊天及录屏可能包含账户/个人信息；公开前脱敏并保留证据对应关系 |
| `report/figures/`、Wireshark 截图 | 自制图与第三方商标/界面素材分开核对引用与再分发条件 |

审核记录应保留：**文件路径、来源 URL、来源版本或 SHA、作者、许可/授权条款、是否修改、审核结论、审批人、日期**。

不要混淆“兼容某项 DIFI 标准”与“有权重新发行标准文档”。也不要将第三方参考工具 PASS 当成正式 DIFI Consortium 认证。