# DIFI ENGINE CONTROL CENTER

Windows 原生 PySide6 + pyqtgraph 桌面演示台。复用仓库现有 B5/B6 Python 校验程序，提供链路动画、逐包 Timeline、独立 Sequence 监测、IQ 校验、波形、事件控制台和会话导出。启动默认 **REPLAY / OFFLINE**，不会自动发送 UDP。

## 安装与启动（Windows 11 / PowerShell）

在仓库根目录运行，要求原生 Windows Python 3.11+：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r dashboard/requirements.txt
.\.venv\Scripts\python.exe dashboard/main.py
```

也可激活虚拟环境后使用标准入口：

```powershell
.\.venv\Scripts\Activate.ps1
pip install -r dashboard/requirements.txt
python dashboard/main.py
```

若 PowerShell 执行策略不允许激活，直接使用 `.venv\Scripts\python.exe`，无需修改执行策略。双击 `dashboard/launch_dashboard.bat` 会优先使用项目 `.venv`。不要把依赖装进 Vivado/Vitis 的 Python 环境。`.venv`、会话与截图输出均由 Git 忽略。

依赖采用官方 `PySide6-Essentials` 分发（Python 中仍为 `PySide6`），提供所需 Qt Core/Gui/Widgets，避免安装未使用的 WebEngine。

Qt 固定为已在本机验证的 6.8.3；如需完全复现本机测试依赖，可安装 `dashboard/requirements-windows-lock.txt`。升级 Qt 后需重新执行 GUI 与 Replay 测试。

默认窗口适合 1920×1080，支持 2560×1440 和 Windows DPI 缩放。启动按屏幕可用区域调整尺寸；较小窗口中中央区域可滚动，右侧宽度可拖动调整，运行控制始终位于底部。

## 现场操作

1. 选择 `B5 UDP TX` 或 `B6 UDP RX`。切换会自动归档旧会话并清空当前统计；两种模式保存各自设置。
2. 保持 `Replay / Offline` 可直接点击 `Run B5 Demo` / `Run B6 Demo` 预演。需要实体板时选择 `Live / Hardware`。
3. 在 Settings 中设置 Board IPv4、PC bind IPv4、UDP Port 和每包 Timeout；B6 还可设置 Types 与 Data Rounds。
4. 完成对应板端准备后，点击 Run。运行期间禁止重复 Run、切换模式和重置。Stop 异步终止工作进程并释放资源，随后可 Reset Session。
5. 点击 Timeline 单元查看类型、序号、载荷字节、验证状态和事件时间。Waveform 可分别显示 I/Q，并用鼠标读取样本。
6. 日志支持级别筛选、暂停跟随、复制和导出。Clear Log 只清理显示，完整会话证据继续保存在输出目录。

切换界面模式不会加载 Bitstream 或 ELF。B5、B6 是独立硬件配置，不能作为同时全双工演示。

## B5：FPGA / PS → PC

板卡须运行 **B5 raw-packet export XSA/Bitstream** 和 `vitis/vitis_ws/difi_b5_udp_tx/src/difi_b5_udp_tx.c` 对应 ELF。

先通过已有 UART 终端输入板卡要求的 `UTC <UNIX_SECONDS> <NANOSECONDS>`，确认时间有效并等待 START。Dashboard 不占用串口、不执行 UTC 初始化；pyserial 缺失也不会影响主应用。设置默认 Board `192.168.1.10`、PC `192.168.1.20`、UDP `4991`、Timeout `10 s`。

Run 通过 `QProcess` 启动原始接收器：

```powershell
python -u scripts/verify/tools/difi_udp_receiver.py --board 192.168.1.10 --pc-ip 192.168.1.20 --port 4991 --timeout 10 --output dashboard/output/b5_capture.bin
```

GUI 为每次运行创建独立输出目录，实际命令的 output 位于该会话目录。接收器自行绑定 UDP 并发送一次 START，GUI 不再额外发 START。统计来自逐包 `[PASS]`，IQ 由原校验器逐样本核对。捕获文件是 **32-bit 网络序长度前缀 + UDP Payload** 连续记录，不是 PCAP；后台解码器再次调用原校验函数检查内容，并以大端有符号 I16/Q16 解码。波形显示已确认且已写入文件的最新 Data Packet；原接收器有文件缓冲，曲线可能稍晚于包统计，结束后执行严格完整解码。

## B6：PC → FPGA RX

板卡须运行 **B6 v0.2** 对应 Bitstream/XSA 和 `difi_b6_udp_rx_pro` ELF；Data-only v0.1 ELF 不适用三类报文。参考 [B6 工程复现说明](../scripts/vivado/B6_REPRODUCTION.md) 与 [板级回归归档](../report/results/vivado_rebuild/b6_udp_rx/BOARD_REGRESSION_STATUS.md)。

默认 Board `192.168.1.10`、PC `192.168.1.20`、UDP `4991`、Timeout `5 s`、Types `version,context,data`、Data Rounds `20`。Types 支持无重复子集与指定顺序。

```powershell
python -u scripts/verify/tools/difi_b6_three_types.py --board 192.168.1.10 --local-ip 192.168.1.20 --port 4991 --timeout 5 --types version,context,data --rounds 20
```

原程序先查询 STATUS，使用真实 `NEXT_ROUND / NEXT_VERSION / NEXT_CONTEXT`，然后依次发送并验证 ACK。板卡计数可以跨测试累计，GUI 不假定从零开始。Version、Context、Data 使用独立 4-bit 序号流，显示最近 16 个、回绕、不连续与重复事件。

`ACK PASS … IQ=256` 表示该包在板端已完成 Golden 比对；**ACK 不返回完整 FPGA IQ**。B6 曲线始终标记 **Golden Reference / NOT FPGA returned IQ**，由现有 `difi_b6_sender.py` 纯 Python 模型生成。Version/Context 的成功来自真实 ACK；GPIO 错误计数和 Changed Flag 无直接来源时显示 `Not Observable`，不会默认填零。

## 状态和证据口径

状态流程为 `IDLE → PREPARING → RUNNING → COMPLETED / FAILED / STOPPED`，另行保留 `LIVE` / `REPLAY` 来源。

- Expected 是目标值；已确认包数、字节数和 IQ 从零开始，仅逐包验证成功事件可增加。
- 标准目标为 Version×1、Context×1、Data×20、5,120 IQ、21,192 B UDP Payload。
- 整轮 COMPLETED 要求原程序成功摘要、实际数量符合目标、无已知错误/序号异常，以及进程退出码 0。一行 PASS 不足以判定整轮通过。
- 同一 Packet 身份重复投递不会重复计数。已观察的 Sequence 重复与不连续会记录为异常；15→0 是合法回绕。
- IQ mismatch 仅表示已观察到的样本失配。首个失败后原程序会停止，无法推算所有未检样本的失配数量；错误/超时不会被显示为“全部 IQ 无误”。

## Replay / Offline

Replay 使用显式标为 **SIMULATED TEST FIXTURE** 的样例输出和 B5 测试捕获。它通过同一个严格文本解析器、Session、动画及图表组件，不打开 UDP Socket，也不启动板卡工具的联网入口。

B6 样例从 `NEXT_ROUND=14 / NEXT_VERSION=3 / NEXT_CONTEXT=7` 开始，便于观察非零基线和序号回绕。Replay 的完成结果导出为 **REPLAY PASS (simulated fixture; not a hardware test)**，不能视为板卡实测。fixture 的文字模拟 CLI 格式，原始行都保留 `REPLAY/.../fixture` 来源。

可直接启动离线演示：

```powershell
.\.venv\Scripts\python.exe dashboard/main.py --replay B6
```

## 自动保存与导出

每次 Run 在 `dashboard/output/<时间>_<模式>_<来源>/` 下生成独立会话。原始日志逐行追加到 `raw.log.txt`；TXT/JSON/Markdown 会话快照定期自动保存并在结束时保存。时间戳为带时区的 UTC ISO 字符串，文件夹名使用本机时间。

`Export Result` 导出原始运行日志 `.txt`、结构化事件/统计/参数 `.json`、摘要 `.md` 和 `dashboard.png`。导出包含来源、状态、退出码、目标与实际数量及错误记录。`Save screenshot` 可单独保存界面。设置保存到本地 `dashboard/output/settings.json`。

## 历史性能 / 构建面板

面板中的数值均标为 **Archived Result / Historical Measurement**，可打开仓库证据：

| 历史指标 | 数值 | 来源 |
| --- | ---: | --- |
| RTL 理想 IQ 吞吐率 | 196.916 MB/s | [性能报告](../report/results/perf/performance_summary.md) |
| 板级 DMA 事务窗口 | 约 107.18 MB/s | 同上，PMU ticks 与确认的 CPU 时钟换算 |
| 板级完整软件测试窗口 | 约 25.01 MB/s | 同上 |
| Packaged IP Setup WNS | +0.411 ns | [时序报告](../report/results/packaged_ip_impl/timing_summary.rpt) |
| B5 Setup WNS | +2.206 ns | [重建结果](../report/results/vivado_rebuild/b5_raw_export/SUCCESS.txt) |
| B6 Setup WNS | +2.372 ns | [重建结果](../report/results/vivado_rebuild/b6_udp_rx/SUCCESS.txt) |

三个 Rebuild PASS 是归档构建结论。以上不是当前 UDP 吞吐率；逐包 ACK 测试也不代表网络极限吞吐。

## 测试和无设备验证

```powershell
.\.venv\Scripts\python.exe -m pytest dashboard/tests -q
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --screenshot dashboard/output/startup.png
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --replay B6 --screenshot dashboard/output/replay_b6.png
```

pytest 使用 Qt offscreen（不需要实体 FPGA），包括严格 B5/B6 输出解析、READY/ACK 错误与非零基线、计数及 15→0、长度前缀和网络字节序/I16/Q16、Replay 禁止网络、真实 QProcess helper 子进程、异常退出、Stop 和重复启动保护、GUI 渲染/Reset/切换及导出。失败响应测试使用明确的假工具输出，不访问实体设备。测试结果与本机实际运行记录见 [验证记录](VALIDATION.md)。

沙箱/受限 Windows 环境如 TEMP 不可写，可指定项目目录：

```powershell
$env:TEMP = "$PWD\dashboard\output\tmp"
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
.\.venv\Scripts\python.exe -m pytest dashboard/tests -q --basetemp dashboard/output/pytest-local
```

Qt 主线程不等待子进程；Stop 使用异步 terminate 并在必要时 kill；B5 捕获解码在后台线程执行。

## 常见问题和实体板验收

- **UDP port already in use / WinError 10048**：关闭其它 B5 接收器、旧 GUI 或占用端口的应用。
- **PC IP not assigned / WinError 10049**：将真实有线网卡设为 `192.168.1.20/24`，或在 Settings 填其实际 IPv4。
- **Timeout / 无板卡响应**：检查网线、供电、网卡子网、防火墙 UDP 放行、Bitstream/ELF 匹配；B5 还要完成 UART UTC 初始化并等待 START。根据现场实际情况配置 Windows 防火墙。
- **STATUS 缺字段 / wrong ELF**：B6 使用三类 v0.2 ELF，不能加载 B5 或 Data-only v0.1 程序。
- **B5 第二次运行超时**：原 B5 应用为一次性发送 Demo；重新运行或复位板端程序、重新初始化 UTC 后再 Run。
- **Stop 后已有成功包仍在**：这些是停止前实际验证的包，整轮显示 STOPPED；Reset 可清空当前会话。
- **无波形**：无真实来源时保持空图；B5 在捕获文件完成后解析，B6 至少观察到一个 Data ACK 后才显示参考波形。
- **串口不可用**：GUI 可运行，GPIO 详情保留不可观测；用现有串口终端完成板端初始化。当前版本未实现 UART 采集功能。

交付代码保护原 RTL、Vivado Tcl、Vitis C 与两个 CLI。实体板仍需现场确认：B5 全链路和 UART/START 时序、B6 从实际 STATUS 开始的三类 ACK、跨次累计轮数、Live Stop 后重跑、Windows 网卡/防火墙与现场 DPI/大屏。自动测试和 Replay 不替代这些硬件验收。
