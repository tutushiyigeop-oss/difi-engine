# Stage D 交互式半双工实验平台

本次升级增加 Stage D v0.3/v0.4 工作区，保留已经验收的 B5/B6 Legacy 和原 Replay。**软件实现、软件模拟测试、固件编译已经完成；新增 Stage D GUI Live 和 v0.4 固件仍待实体板验收。** 原 v0.3 板级成果属于已有基线，不会被本次软件测试替代。

## 直接开始

仓库根目录 PowerShell：

```powershell
# 项目已有独立 .venv，无需修改 Vivado/Vitis 环境。
.\.venv\Scripts\python.exe dashboard/main.py

# 自动执行两轮明确标记的离线 TX/RX 演示，不发送 UDP。
.\.venv\Scripts\python.exe dashboard/main.py --replay STAGED

# 直接查看输入/返回/误差叠加页面。
.\.venv\Scripts\python.exe dashboard/main.py --replay STAGED --page waveform
```

首次安装时：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r dashboard/requirements.txt
```

也可双击 `dashboard/launch_dashboard.bat`。启动默认 Stage D、Replay / Offline、DISCONNECTED；不会自动连接板卡。

## 页面与数据来源

| 页面 | 操作 |
|---|---|
| Overview | IP/端口、Connect/Disconnect、一次性 UTC、版本/能力/STATUS、统计与当前链路 |
| Packet Editor | Data/Context/Version、SID、1–256 IQ、频率、时间、过滤；只读协议字段、完整 Hex/Word 解释、合法 `.difi` 导入 |
| IQ Generator | 复数正弦、实数正弦、常量、方波、Chirp、确定性伪随机；CSV/BIN 导入、单样本编辑、保存/读取 preset |
| Waveform / Compare | Local、实际 TX、实际 RX、参考叠加；误差曲线、逐样本表、失配/首个位置/最大误差 |
| Timeline / Metadata | 事务顺序、按 TX/RX 分开的各类型序号、回绕、原始 Packet 解析和可观测状态 |
| Log Console | 来源、时间和级别，筛选、复制及导出 |
| Export / Archived Metrics | 完整证据/截图、原始文件校验重载；原历史指标保持独立 |

LOCAL PREVIEW 是 PC 本地输入；LIVE 的 FPGA TX CAPTURE 由实际 TX Packet Payload 解码；LIVE 的 FPGA RX S2MM 只有收到真实 IQ 字节后才显示。Replay 曲线始终加 SIMULATED/REPLAY 标识。离线加载原 Live 证据时加 OFFLINE ARCHIVE，不表示当前重新执行实测。旧 B6 继续显示 Golden Reference / NOT FPGA returned IQ。

I/Q 为 signed int16，范围 −32768…32767；每个网络 Word 的高 16 bit 为 I，低 16 bit 为 Q。BIN 导入明确选择大端/小端，网络交换固定大端。生成器 UI 相位单位为度；模型/preset 中相位单位为弧度。

## 原 v0.3 固件怎么用

1. 手动运行原先验收的 Stage D Bitstream + v0.3 ELF。PC 有线网卡设为实际可用的 `192.168.1.20/24`，板卡默认 `192.168.1.10:4991`。
2. 顶部选 Live / Hardware，在 Overview 核对 IP/端口后点击 Connect。客户端先发只读 STATUS，识别旧固件后不会发送 v0.4 CONFIG/上传命令。
3. 仅当 STATUS 显示 `UTC=0` 时点击 Initialize UTC once。已初始化时跳过，不重复设置时间。
4. 方向 TX、Rounds 2、勾选 TX → RX → TX cycles，Run experiment。第一轮实际捕获 Version/Context/Data，第二轮通常只有 Data；实际 TX 原始字节缓存后送回 RX，`IQD3` 后的 1024 B 才是 RX 实际 IQ。
5. 到 Waveform / Compare 查看；最后 Export full evidence + screenshot。

旧固件固定 256 IQ、Data SID 1、Version SID 2、最多 16 个 TX；TX IQ 来自板端固定 Pattern，本地编辑器的任意 IQ 不会被上传。手动 TX 结束后为 WAITING_RX，只能先 RX 完成本连接缓存的数据。必须保持同一 UDP 源端口；缓存或会话 owner 丢失时不能假装恢复，按原板端流程干净重载。

可在 Offline firmware fixture 选择 v0.3 练习相同限制，该下拉框不改变实际板卡固件。

## 自定义 v0.4 怎么用

先按 [固件说明](../firmware/stage_d_v04/README.md) 构建，或使用本机已生成、被 Git 忽略的 `firmware/stage_d_v04/build/difi_stage_d_v04.elf`。**这个 ELF 尚未上板验收。**

```powershell
.\.venv\Scripts\python.exe firmware/stage_d_v04/build_firmware.py
.\.venv\Scripts\python.exe firmware/stage_d_v04/tests/run_tests.py
```

构建读取现有 Stage D BSP 与链接脚本，写入独立 `build/`，不运行 Vivado、不替换 v0.3、不下载硬件。工具/BSP 路径可通过 `--gcc / --bsp / --linker-script` 覆盖。

1. 在 Vitis 2024.2 中手动配置现有 Stage D Bitstream，再运行新 ELF。必须从干净 PL 状态开始；只重启 ELF 而保留旧 PL 状态会报告 `WARM_PL_RELOAD_REQUIRED`。
2. GUI 选 Live → Connect，确认 Protocol 4 / CAPS；仅在 UTC 无效时初始化一次。
3. Packet Editor 设置合法 Profile。IQ Generator 生成/导入/编辑数据；样本数与 Profile 同步。
4. 自定义 TX：Packet type 选 DATA、方向 TX。Run 会先确认配置生效，再上传实际 IQ，让 DMA1/PL 真正封装，接收真实 Packet。可勾选 cycles 自动接着 RX。
5. 自定义 RX：选 DATA、CONTEXT 或 VERSION，方向 RX。发送的是预览验证通过的实际 Packet；Data 走 DMA0 S2MM，Metadata 走 monitor/GPIO。
6. Waveform 选择 TX/RX 或 Overlay 查看。完成后导出整个证据目录，可断开后离线重载校验。

没有软件 Version-on-demand/序号复位寄存器：TX 只支持 Data 事务，启动 Version 与配置变化 Context 由 FPGA 调度器自动产生；不支持的按钮不会伪装执行。TX 时间戳使用一次 UTC 初始化后的 PL 时钟；编辑器时间字段作用于本地/RX Packet。

TX、RX 各类型使用独立序号。v0.4 自动交替时保留实际 TX 原始捕获；必要时只管理 RX 输入 Header 的序号，IQ Payload 不变，实际发送的 RX `.difi` 会单独保存。

## 状态、停止与证据

连接/事务状态与测试结果分开：READY 只表示板端已确认可执行下一事务，不代表整轮测试 PASS。Stop 请求会进入 DRAINING，完成当前受控事务/状态确认后停止后续轮次；不能将未执行的轮次补为成功。超时不自动重发非幂等 TX/RX；状态不明时保留证据并按现场验收单恢复。

每次新的完整 Run 使用独立证据 Session；v0.3 手动 TX→RX 配对保留同一证据 Session。底层连接、源端口、固件 Session 与序号不会因此重置。更改模式/来源前必须 Disconnect。

自动保存目录：`dashboard/output/stage_d/<时间>_<来源>_<会话>/`。导出包含 `experiment.json/.txt/.md`、`operator_log.json`，以及每个事务的 `.difi`、参考/实际 `.bin/.csv` 和 `comparison.csv`。手动完整导出附 `dashboard.png`。未发送的编辑器参数单列为 local preview，不能覆盖实际应用配置。

## 兼容、验收和回退

SDU4 消息格式、能力、会话/事务号、错误和限制见 [协议说明](../docs/STAGE_D_V04_PROTOCOL.md)。完整现场步骤和待填证据表见 [实体板验收单](STAGE_D_LIVE_ACCEPTANCE.md)。软件测试结果见 [升级验证记录](STAGE_D_VALIDATION.md)。

原 B5/B6 可通过顶部切换，或直接启动：

```powershell
.\.venv\Scripts\python.exe dashboard/main.py --mode B5
.\.venv\Scripts\python.exe dashboard/main.py --mode B6
```

它们仍需各自匹配的原 Bitstream/ELF；B5 仍需原 UART UTC 步骤。恢复 Stage D v0.3 时手动加载保留的原 Bitstream/ELF，不覆盖文件，也无需破坏性 Git 回滚。

本次主要目录：

```text
dashboard/app/experiment/
  profile.py, iq.py, models.py       # 合法 Packet/IQ 与证据模型
  client.py, controller.py, replay.py # 后台 UDP、互斥状态与离线源
  exporter.py                        # 原始证据导出/校验重载
  editors.py, waveforms.py, panel.py  # 分页原生 Qt 界面
dashboard/tests/test_experiment_*.py, test_stage_d_*.py
firmware/stage_d_v04/
  src/main.c, protocol.c, protocol.h
  build_firmware.py, tests/, README.md
docs/STAGE_D_V04_PROTOCOL.md
```
