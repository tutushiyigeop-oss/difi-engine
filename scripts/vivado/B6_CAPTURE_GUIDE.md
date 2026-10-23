# B6 v0.2 原生 BD 与实现证据归档操作（2026-10-23）

## 目标与边界

B6 v0.2 已有真实三类 UDP RX 的 UART 通过记录（`report/results/udp/rx/three_types_udp_rx.rtf`），但还没有提交对应 **真实 BD Tcl** 和 **B6 专属 Routed 报告**。本次交付的是**采集脚本**，并不意味着这些原始文件已经生成、提交或成功独立重建。

旧脚本 `export_bd.tcl`、`rebuild_bd.tcl`、`verify_rebuilt_impl.tcl` 仍用于已经验证的 `packaged_ip` 和 `b5_raw_export`；**本次不会修改或覆盖它们**。

## 第一步：在本机打开已经通过 B6 三类联测的 Vivado 2024.2 工程

在同一个 Vivado 工程中打开 B6 v0.2 Block Design。进入 Tcl Console，逐行运行：

```tcl
source D:/Study/project/DIFI/scripts/vivado/capture_b6_evidence.tcl
difi_b6::export_snapshot
```

采集程序会检查当前 device、单一 BD、GEM0 MDIO MIO52/53、DMA MM2S→DIFI RX Packet、DIFI IQ→DMA S2MM、Metadata Monitor 与双通道 GPIO 是否存在，执行 `validate_bd_design`，并在下列**Git 忽略目录**暂存快照：

```text
vivado/b6_archive_staging/snapshot/
  bd.tcl
  manifest.tcl
  export_info.txt
  constraints/  # 仅当工程使用了外部 XDC 时
```

**检查通过不代表全部监控信号逐线正确：** 请结合 BD 图片检查 `m_ver_valid/m_ver_ready/m_ctx_valid/m_ctx_ready`、seq、changed、error、monitor clock/reset 与 GPIO 两路信号一一对应，确认 AXI GPIO Address Editor 为实际 C 代码使用的 `0x41200000`。

若脚本报错，首先检查打开的是否为真实的 B6 v0.2 项目。**不要为了让检查通过去修改已验证的 BD**；应先看原始路径、信号端口类型，必要时调整检查程序再复核。

## 第二步：抓取真实 Routed 报告

确认 **当前工程的 `impl_1` 已跑完 Bitstream**，再在 Tcl Console 输入：

```tcl
difi_b6::capture_implementation
```

输出写到：

```text
vivado/b6_archive_staging/implementation/
  utilization.rpt
  timing_summary.rpt
  drc.rpt
  clocks.rpt
  capture_info.txt
  b6_from_verified_impl.xsa   # 如果导出成功；仅本地保留
```

此步骤只记录**当前工程**的实现结果。它不是一次新目录独立重建，也不会自动确认板级 UART 与这个 XSA 是同一构建。`capture_info.txt` 会明确保留这个证据边界。

## 第三步：先审核，再提交

检查 `bd.tcl`、`manifest.tcl`、`export_info.txt` 与 `.rpt` 是否有用户绝对路径、第三方内容、凭据；确认此 Tcl 文件确实来自 B6 v0.2 而不是旧版 IP 或 B5。然后在 PowerShell 中：

```powershell
cd D:\Study\project\DIFI

New-Item -ItemType Directory -Force scripts\vivado\generated\b6_udp_rx | Out-Null
Copy-Item vivado\b6_archive_staging\snapshot\* scripts\vivado\generated\b6_udp_rx\ -Recurse

New-Item -ItemType Directory -Force report\results\vivado_rebuild\b6_udp_rx | Out-Null
Copy-Item vivado\b6_archive_staging\implementation\*.rpt report\results\vivado_rebuild\b6_udp_rx\
Copy-Item vivado\b6_archive_staging\implementation\capture_info.txt report\results\vivado_rebuild\b6_udp_rx\

Get-FileHash vivado\b6_archive_staging\implementation\b6_from_verified_impl.xsa -Algorithm SHA256
git status --short
```

只有存在成功导出的 XSA 时才运行上述 `Get-FileHash`；哈希及其与真实运行的 ELF/Bitstream 的对应关系需人工记录。**不要把原始 `.xsa`、`.bit`、整个 `vivado/` 工作区加入 Git。**

审核确认后：

```powershell
git add scripts/vivado/generated/b6_udp_rx report/results/vivado_rebuild/b6_udp_rx
git diff --cached --stat
git commit -m "build: archive real B6 v0.2 BD snapshot and routed evidence"
git push
```

> 注意：新的 `b6_udp_rx` 快照并未纳入原 `rebuild_bd.tcl` 两目标的分支逻辑。因此即使完成本页，也只能称“真实工程快照和原始 Routed 证据已归档”；后续还需单独增加 B6 重建支持、在全新目录运行并验证新 XSA/Vitis，上板 PASS 后才可称 B6 完整复现。

## 验收与待办

- [ ] 本机执行导出脚本；审核端口连接及 AXI 地址
- [ ] 本机执行实现报告抓取、保留 XSA SHA256
- [ ] 将 B6 Tcl 与 Routed 报告提交
- [ ] 在全新工程独立重建并上板验证


## 已收到并审阅真实 B6 文件（2026-10-23）

真实 B6 BD Tcl、manifest、export_info、Routed 资源/时序/DRC/时钟报告与带 Bitstream 的 XSA 已在本次审阅中核验。**静态检查通过不等于新目录独立重建已通过。** 原项目时序 Setup WNS +2.372 ns、Hold WHS +0.053 ns；DRC 有 Warning。XSA SHA256：`32878bef391c4e06d190454ce198aa5bf8feaf2f82e8362a590f1d7758419b7c`，禁止提交 XSA 本体。

审核后的文本归档目标：

- `scripts/vivado/generated/b6_udp_rx/{bd.tcl,manifest.tcl,export_info.txt}`
- `report/results/b6_impl/{timing_summary.rpt,utilization.rpt,drc.rpt,clocks.rpt,capture_info.txt,PROVENANCE.md}`：**原始工程实现**，不是新的独立重建结果。

`rebuild_bd.tcl` 和 `verify_rebuilt_impl.tcl` 现已加入 `b6_udp_rx` 分支，但**只有在上述真实快照复制并提交后才能运行**。两者的运行结果、产物必须由本机 Vivado 实测；重建后的报告另写 `report/results/vivado_rebuild/b6_udp_rx/`。详细原始依赖为 `ip_repo/` 和 `rtl/board/difi_b6_rx_meta_monitor.v`。
