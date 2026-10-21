# Skill 自检记录（2026-10-21）

以下针对本次生成的**通用化模板代码**，不应与之前 DIFI 专用脚本在 Vivado/板级的真实测试混同。

## 本地已执行

```text
python skill/vivado-rebuild/tests/test_static.py
[PASS] all 10 required artifacts and SKILL frontmatter
[PASS] Tcl files load, config has required keys, path and identity guards work
[NOTE] Static checks only; Vivado/vitis/board run is not simulated

python skill/vivado-rebuild/tests/test_mock.py
[PASS] mocked export creates BD, manifest, and copied user XDC
[PASS] mocked rebuild creates independent XPR; no original project overwritten
[PASS] overwrite prevention blocks pre-existing rebuild directory
[NOTE] Vivado IP graph, timing, Vitis, and hardware are NOT simulated
```

- 环境：Linux Python 3 + `tclsh`；没有真实 Vivado 工具链。
- 自检覆盖：Tcl 脚本可载入、配置字段、仓库根目录越界防护、错误工程身份拒绝、导出文件落盘、虚拟重建与覆盖保护。
- **未覆盖**：真实 `write_bd_tcl` 生成的 IP 配置与连线恢复、Module Reference 复杂用法、`check_timing`/报告命令实际兼容性、实现、Bitstream、XSA 与实际板级功能。
- 下一项真实验收：在第二个非 DIFI 的公开最小 AXI BD 工程中执行此通用模板的导出→重建→综合→实现，并归档真实 Vivado 日志。

DIFI 两套专用脚本的真实 Vivado 实测已另载于 [`../examples/difi-case-study.md`](../examples/difi-case-study.md)。
