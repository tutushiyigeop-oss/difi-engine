# 根 README 修订建议（非自动覆盖补丁）

## 1. 第 5.3 节旧状态替换

将“未提交可自动重建这两套完整 Block Design 的 `.tcl` / `.xsa` / `.bit` 成套产物”一段，改为下面这一版，并对照真实测试记录再提交：

> 本仓库已提交从真实 Vivado 工程导出的两套 Block Design Tcl 快照、对应配置清单、RTL/IP 依赖及重建脚本：`scripts/vivado/generated/packaged_ip/`、`scripts/vivado/generated/b5_raw_export/`、`scripts/vivado/{export_bd,rebuild_bd,verify_rebuilt_impl}.tcl`。两套工程曾在 Vivado 2024.2 中通过独立重建、综合实现与 Bitstream/XSA 生成，工具结果详见 `report/results/vivado_rebuild/`；开发者已完成两套新工程的板级复测，相关 Vitis/UART 原始记录仍须按最终版本核对归档。由于 Bitstream、XSA 及完整 Vivado Workspace 属于再生构建产物，没有随 Git 仓库提交，使用者应运行脚本在本地生成，不能从 GitHub 直接下载现成 Bitstream。

从 DIFI 仓库根目录的 PowerShell 示例：

```powershell
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs packaged_ip
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs packaged_ip

vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b5_raw_export
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b5_raw_export
```

**重跑保护：** 上述验证脚本存在已成功的 `SUCCESS.txt` 时会拒绝覆盖；重跑之前先归档旧结果，并遵守脚本要求的新工程输出目录规则。不要在首次访问时盲目重复运行同一目录的命令。

## 2. 添加导航入口

- 设计报告：`report/competition/difi_design_report_draft.md`
- 演示图与数据：`report/figures/`
- AI 协作复盘与真实对话状态：`report/ai_collaboration/`
- 四个 Skill：`skill/README.md`
- BD Tcl 与重建操作：`scripts/vivado/README.md`
- 本地提交检查：`scripts/audit/check_submission.py`（新增后）

## 3. 不要做的事

- 不把 `SUCCESS.txt` 的工具 PASS 直接说成“包含板级实测日志”。
- 不上传 `/vivado/`、`/vitis/vitis_ws_rebuilt/`、`.runs/` 等纯生成工作区作为“复现性证明”。
- 不宣称 Vivado 2024.2 工程已通过 2025.2/2026.1 跨版本复现。
- 不把比赛建议的演示视频素材等同于官方规定的必交文件。
