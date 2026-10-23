# DIFI 1.1 FPGA 引擎：Vivado 重建实测案例

这是 Skill 的来源案例，不要求第三方项目采用 DIFI 特定文件名。专用脚本属于主仓库的 `scripts/vivado/`，本 Skill 不复制另一套专用脚本以避免日后分叉。

## 已核实的原始工程

| 工程 | BD / Wrapper | 用途 |
|---|---|---|
| `packaged_ip` | `difi_ip_test` / `difi_ip_test_wrapper` | 封装 IP 的 DIFI TX→RX IQ 回环 |
| `b5_raw_export` | `difi_system` / `difi_system_wrapper` | 生成完整 DIFI Packet，供 PS 使用 lwIP UDP 发送 |

B4 旧回环工程也曾使用 `difi_system`。**必须检查 B5 是否包含 `difi_board_raw_packet_export` 模块，不能仅按 BD 名称判断。**

## 实际操作（DIFI 专用已验证路径）

在封装 IP 原始工程的 **Vivado Tcl Console**：

```tcl
source D:/Study/project/DIFI/scripts/vivado/export_bd.tcl
difi::export_bd packaged_ip
```

在 B5 原始工程的 Vivado Tcl Console：

```tcl
source D:/Study/project/DIFI/scripts/vivado/export_bd.tcl
difi::export_bd b5_raw_export
```

在仓库根目录 PowerShell 中，用 Vivado 2024.2 执行：

```powershell
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs packaged_ip
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b5_raw_export
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs packaged_ip
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b5_raw_export
```

已由开发者反馈：三套重建工程对应**新 XSA**的 Vitis 应用板级测试均通过。工程重建及功能回归阶段已收束。

## 已记录的 Vivado 实现结果（真实上传的 SUCCESS 报告）

| 检查项 | packaged_ip | b5_raw_export |
|---|---:|---:|
| Vivado | 2024.2 | 2024.2 |
| FPGA Part | xc7z020clg400-2 | xc7z020clg400-2 |
| Synthesis | Complete | Complete |
| Implementation / Bitstream | Complete | Complete |
| Setup WNS | +0.411 ns | +2.206 ns |
| Hold WHS | +0.046 ns | +0.021 ns |
| 含 bitstream 的 XSA | 已导出 | 已导出 |

参考原始证据：

- `report/results/vivado_rebuild/packaged_ip/SUCCESS.txt`
- `report/results/vivado_rebuild/b5_raw_export/SUCCESS.txt`
- 进一步参见对应目录中的 timing/utilization/DRC 报告

> 这些是已上传的验收结果，不等于通用模板跨项目测试成功。重建后板级验证结果来自开发者确认，不擅自补写未提供的原始日志内容和吞吐率。

## 大模型协作与真实纠错轨迹

1. **失败现象**：初版 `export_bd.tcl` 调用 `info commands open_bd_design` 判断环境，报告 `open_bd_design unavailable`，未进入真实导出。
2. **原因定位**：Vivado 可按需加载 Tcl 命令，预先要求它一定出现在 `info commands` 可能导致误判。
3. **修改方案**：改用可执行的 `version -short`、`current_project` 检查运行环境，再调用真实 IP Integrator 命令。
4. **复测结果**：Vivado 2024.2 成功导出 BD，随后三套设计均被重建，实现完成并生成 XSA。
5. **边界**：这一修复解决了**误报环境错误**，并不保证 IP 兼容、外部 XDC、AXI 地址或板级程序天然正确。

这些条目是对已发生协作的归纳，不是假装原始完整提示词/模型回复。参赛正式协作记录应附原始聊天导出或截图。

## 对其他题目的可迁移部分

- 从真实原工程执行 `write_bd_tcl`，而非手工重新画连接图。
- 在重建前加入自定义 IP 仓库和 Module Reference RTL。
- 将 Tcl 快照、RTL 源码与 XDC 持久化到版本库，自动生成的大工程保留在忽略目录。
- 对全新的工程进行从 BD→实现→Bitstream→XSA→板级的分层验收。
