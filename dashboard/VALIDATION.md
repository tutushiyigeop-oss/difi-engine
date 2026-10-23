# 本机交付验证记录

验证日期：2026-10-23（Asia/Shanghai）。工作分支：`feature/dashboard-ui`。本次开发未连接实体 FPGA，未主动发送硬件 UDP，未提交或推送 Git。

## 环境

- Windows 11 x64，系统报告 Build 26300；显示器 1920×1080，DPR 1.25。
- Windows 原生 Python 3.12.7，基础解释器来自本机 Anaconda，第三方依赖独立安装到仓库 `.venv`。
- PySide6 / Qt 6.8.3（官方 Essentials 分发），pyqtgraph 0.14.0，numpy 2.5.4，pytest 9.1.1，pyserial 3.5。
- `python -m pip check`：No broken requirements found。
- 固定版本列表：[requirements-windows-lock.txt](requirements-windows-lock.txt)。

初次自动选择 Qt 6.12.0 时，QtCore 请求的 ICU 转换函数在本机 Windows ICU DLL 中不可用，导致 DLL 入口加载失败。当前 requirements 已固定为实测可用的 Qt 6.8.3；没有复制或替换任何系统 DLL，也没有修改 Anaconda / Vivado / Vitis 安装。

## 自动化测试

执行：

```powershell
.\.venv\Scripts\python.exe -m pytest dashboard/tests -q --basetemp dashboard/output/pytest-delivery-005
```

**101 passed in 4.81s**，运行平台 `win32`。Qt 测试使用 offscreen；真实子进程测试运行本地 helper Python，未启动硬件联网工具。

覆盖内容：

- B5 Version / Context / Data 原始文本、尺寸、包索引与序号一致性。
- B6 STATUS 所有必需字段、非零 NEXT_ROUND、Version/Context 独立基线。
- ACK PASS / FAIL、错误响应中嵌入 expected ACK PASS、错误 ELF、超时和绑定失败输出。
- 4-bit 序号 15→0、重复/不连续、重复事件不重复统计。
- 标准 22 包、21,192 B UDP Payload、5,120 IQ，目标与实际值分离。
- B5 网络序长度前缀、部分捕获、截断/损坏拒绝、I16/Q16 有符号边界值。
- B6 `IQ_MISMATCH` 与 B5 首个失配均记录为已观察的最低数量。
- Replay 网络创建/名称解析被禁止时仍可完成，两种来源不能混入同一 Session。
- 退出码、成功摘要、目标数量、错误事件共同决定整轮成功。
- QProcess UTF-8 分片、stdout/stderr、未换行末行、启动失败、异常退出、Stop、重复启动及输出排空期间 Stop。
- 7,000 行输出压力下 Qt 定时器仍获得运行机会，结束前不丢失待解析日志。
- GUI 启动与截图、设置校验、模式切换保护、Reset、失败后成功状态清理。
- B5 Replay 提前停止时，波形只显示已确认的最后一包，不显示捕获 Fixture 中未来的 Data。
- TXT/JSON/Markdown、最低失配、无 Data 的波形声明、Replay 来源、后台手动导出和截图。

GUI 测试曾暴露后台日志任务持有 QWidget 的生命周期问题，已改为不保留窗口的独立工作函数；全部 GUI 用例和整套测试随后通过。输出排空 Stop 用例已使用受控派发时序，避免依赖子进程退出速度。

## 原生 Windows GUI 冒烟

在 `QT_QPA_PLATFORM=windows` 下实际创建并渲染窗口，不是仅 offscreen 测试：

```powershell
$env:QT_QPA_PLATFORM = 'windows'
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --screenshot dashboard/output/startup_windows.png
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --replay B5 --screenshot dashboard/output/replay_b5_windows.png
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --replay B6 --screenshot dashboard/output/replay_b6_windows.png
```

各命令退出码 0，输出分别为：

```text
SMOKE PASS: Qt=windows source=REPLAY mode=B5 state=IDLE packets=0 IQ=0
SMOKE PASS: Qt=windows source=REPLAY mode=B5 state=COMPLETED packets=22 IQ=5120
SMOKE PASS: Qt=windows source=REPLAY mode=B6 state=COMPLETED packets=22 IQ=5120
```

已检查本机生成的原生截图，完成深色主题、数值、链路、Timeline 和来源标识的视觉复查。截图与测试输出保存在已忽略的 `dashboard/output/`。在本机 125% 缩放的小窗口中，中央工作区需要滚动查看底部波形；运行控件始终可见。没有将截图或 Replay 作为真实板卡数据证明。

紧凑布局在 1740×970 逻辑窗口可同时显示全部核心区域。另以 `QT_SCALE_FACTOR=0.8` 在本机 125% DPI 下进行等效 100% 渲染，原生 Windows B6 Replay 再次通过，完整界面预览保存为 `dashboard/output/replay_b6_overview.png`；该环境变量只用于截图进程，不修改系统显示设置或默认启动方式。

## CLI 与仓库保护

- 原 B5 `--help` 成功；原 B6 `--dry-run --rounds 2` 成功并输出 `No UDP transmitted`。
- `compileall` 与 `git diff --check` 通过。
- 除新增 `dashboard/` 外，仅修改根 README 的入口和 `.gitignore`。
- 原 `scripts/verify/tools/`、RTL、Vivado Tcl、Vitis C 及原始验证报告没有改动。
- 无远程推送、发布 Tag、破坏性 Git 操作或大型 FPGA 二进制新增。

## 初次交付时尚未完成的实体板现场验收（以下为历史记录）

1. B5：匹配 Bitstream/ELF、UART UTC 初始化、START 一次触发、完整报文捕获与真实 IQ 曲线。
2. B6 v0.2：真实 STATUS、三类 ACK、跨次累计轮数、板端 Golden 比对结果和对应链路动画。
3. Live Stop 后 UDP 端口释放及板端恢复。B5 是一次性 Demo，重跑通常要复位/重启板端应用并重新初始化 UTC。
4. 实际网卡 IPv4、以太网/防火墙配置、现场 1080p/1440p 显示与 DPI、录像字号。

当前版本未实现串口日志采集或自动 UTC 初始化；需要已有 UART 终端。ACK 不包含完整 FPGA IQ，B6 曲线始终是 Golden Reference。逐包 ACK 功能验证和归档性能指标均不能作为当前网络极限吞吐率。

## 后续实机确认（2026-10-23）

**与上文首次交付时的状态相比，开发者后来明确确认：Dashboard 的 B5 UDP TX、B6 UDP RX 两种 `Live / Hardware` 模式均已在实际开发板上成功运行，UI 可正常使用。** 因此 B5/B6 GUI 与现有板卡固定验证流程的集成验收本阶段已完成，详见 [`report/competition/dashboard_live_acceptance_20261023.md`](../report/competition/dashboard_live_acceptance_20261023.md)。

上述确认不意味着此前 Codex 的 101 项离线自动测试变成了板级测试，也不意味着已完成任意并发全双工、现场视频录制、故障恢复全场景验证。首次交付时记录仍按时间保留。
