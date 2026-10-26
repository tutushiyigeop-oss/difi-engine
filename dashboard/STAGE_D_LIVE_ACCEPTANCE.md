# Stage D 实体板操作与验收单

本文用于 Windows 11 + Zynq-7020 的现场验收，**不是已通过的板级测试报告**。用户此前确认的 Stage D v0.3 固定 Profile 板级结果属于已有基线；本次新增 GUI 的 Live 集成和 v0.4 自定义 IQ 固件仍须按下列步骤进行实体板验证。本地 Python 测试、Replay、Windows GUI 启动、ARM ELF 构建和主机 C 测试均不能代替这些操作。

协议细节见 [Stage D v0.4 协议](../docs/STAGE_D_V04_PROTOCOL.md)。原有 [Dashboard 说明](README.md) 中的 B5/B6 是不同板端配置；Stage D 则在已有双 DMA Bitstream 中依次切换 TX/RX，同一时刻只运行一个方向。

## 1. 准备与可追溯记录

在仓库根目录启动，不会因启动 GUI 自动发送 UDP：

```powershell
.\.venv\Scripts\python.exe dashboard/main.py
```

选择顶部 `Stage D · UDP Half-Duplex`。先使用 `Replay / Offline` 熟悉页面；实体板验收前应断开 Replay，切换为 `Live / Hardware`。`Offline firmware fixture` 下拉框只选择模拟固件，不能改变板卡 ELF。实际 Live 固件版本由 `Connect` 首先读取的 ASCII `STATUS` 判断。

在 Overview 中核对：

| 控件 | 建议首次验收值 | 含义 |
|---|---|---|
| Board IPv4 | `192.168.1.10` | 固件固定板卡地址 |
| PC bind IPv4 | `192.168.1.20` | 必须是实际有线网卡已配置的地址 |
| UDP destination port | `4991` | 板端 UDP 端口 |
| PC source port / 0 = auto | `0` | 同一连接将一直保留选定的源端口 |
| Timeout | `10 s` | 首次板级验收建议值；用于每个受控请求的等待 |

接好网线、电源与 UART。板卡网段为 `/24`；检查 Windows 对相应网卡/应用的 UDP 放行。关闭占用相同端口的旧接收器和测试脚本。

每项结果至少记录：操作者、本地时间、开发板、实际 Bitstream/ELF 路径与 SHA-256、GUI 代码版本、PC/Board IP 与端口、固件版本、能力及 STATUS、Profile、输入数据来源、证据目录、PASS/FAIL/未执行及原因。可用 `Get-FileHash -Algorithm SHA256 <文件>` 记录实际部署文件；不要把文件名或一次成功编译作为板端已加载的证明。

## 2. M1：原 v0.3 固定模式接入 GUI

使用原来验收过的 Stage D 硬件与 v0.3 ELF。当前本机可定位的原文件为：

- Bitstream：`vivado/rebuilt/half_duplex/difi_stage_d_half_duplex.runs/impl_1/difi_ip_test_wrapper.bit`。
- XSA：`vivado/rebuilt/half_duplex/stage_d_half_duplex.xsa`。
- 原源码：`vitis/vitis_ws_rebuilt/difi_stage_d_udp_half_duplex/src/main.c`。
- 原 ELF：`vitis/vitis_ws_rebuilt/difi_stage_d_udp_half_duplex/build/difi_stage_d_udp_half_duplex.elf`。

这些是原基线文件，不要用新固件覆盖它们。通过已有 Vitis 调试配置手动加载匹配硬件与原 ELF，并确认 UART 启动信息。若先前会话状态不明确，按原板端流程重新初始化后再开始。

1. 点击 Overview 的 `Connect`，等待识别为 Protocol 3。Capabilities 应明确显示固定 256 IQ、Data/Context SID 1、Version SID 2，不支持自定义 CONFIG/上传 IQ。
2. 首次干净启动通常应看到 `MODE=0 UTC=0 TX=0 RX=0 PENDING=0`。只有在真实 STATUS 显示 UTC 无效时，点击 `Initialize UTC once`，等待板卡确认并重新查询状态；不要连续重复加载时间。
3. 设置 `Rounds 2`，方向 TX，勾选 `TX → RX → TX · cycles`，点击 `Run experiment`。保持同一个 GUI 连接和源端口，直到两个循环全部结束。
4. 第一轮实际 TX 应取得 Version、Context、Data；第二轮通常仅 Data。原 v0.3 每包 Data 固定 256 IQ，参考采用板端已定义的固定 Pattern。GUI 不会将本地生成器中的自定义 IQ 上传给 v0.3。
5. RX 必须回放本连接缓存的真实 TX 包，按板端要求处理首轮 metadata，再验证 Data。实际 Data 返回报文应有 ASCII `IQD3` 标识，报文总长为 1,028 B：4 B 标识 + 1,024 B 网络序 IQ，即 256 个 I16/Q16 样本。
6. `Waveform / Compare` 分别查看 TX Capture、RX S2MM、Overlay 和误差表。检查每次 Data 比较的实际/参考样本数均为 256、Mismatch 为 0、Max |Δ| 为 0，且状态确认回到 `MODE=0 PENDING=0`。两轮完整交替通常留下两次 TX 和两次 RX 的事务证据。
7. 导出完整证据，然后在健康空闲状态下 `Disconnect`。

v0.3 的限制是验收条件的一部分：TX 最多 16 轮，TX 后必须先完成其待处理 RX；板端锁定 PC 源 IP/端口。重建 GUI/进程无法重新构造丢失的 TX 缓存。若连接时为 PENDING 且本连接没有原始 TX 包，GUI 应要求恢复，不应伪造缓存继续 PASS。不要在此情况下更换源端口并反复点击 Run；先保存日志，再按原基线流程重新加载硬件/ELF。

也可在 GUI 断开并释放端口后，用原命令单独复核原 v0.3 流程；不要与 GUI 同时运行：

```powershell
.\.venv\Scripts\python.exe scripts/verify/tools/stage_d_udp_cycle.py --board 192.168.1.10 --local-ip 192.168.1.20 --port 4991 --timeout 10 --rounds 2 --output dashboard/output/stage_d_v03_manual
```

以上命令会进行真实板卡通信，只应由操作者在对应固件已准备后执行。

## 3. M2：独立 v0.4 ELF 的手动部署

v0.4 使用既有 Stage D 双 DMA 硬件，不更改 RTL、BD、Bitstream 或 XSA。新源码和构建输出独立放置：

- 新源码：`firmware/stage_d_v04/src/main.c`、`protocol.c`、`protocol.h`。
- 构建入口：`firmware/stage_d_v04/build_firmware.py`。
- 新 ELF：`firmware/stage_d_v04/build/difi_stage_d_v04.elf`。
- 可追溯清单：`firmware/stage_d_v04/build/build_manifest.json`。

构建命令仅编译新应用，不下载、不运行、不对板卡编程：

```powershell
.\.venv\Scripts\python.exe firmware/stage_d_v04/build_firmware.py
.\.venv\Scripts\python.exe firmware/stage_d_v04/tests/run_tests.py
```

构建依赖本机 Vitis 2024.2 Cortex-A9 工具链与匹配 Stage D XSA 的 standalone/lwIP RAW_API BSP。默认只读取现有 `vitis/vitis_ws_rebuilt/difi_half_duplex_platform` BSP 和原 `lscript.ld`；复制链接脚本到新 build 目录。其他机器的工具、BSP 和链接脚本路径通过构建脚本参数指定，详见 [协议中的构建说明](../docs/STAGE_D_V04_PROTOCOL.md)。如使用 Vitis 新建工程，创建**独立** v0.4 应用并使用相同硬件平台，不覆盖原 v0.3 component。

操作者手动部署顺序：

1. 停止 GUI 当前任务，保存证据并断开；保留原 Bitstream 和 v0.3 ELF 的路径与哈希。
2. 在 Vitis 的硬件调试/下载流程中，**重新加载既有匹配的 Stage D Bitstream，使 PL 处于干净状态**，再加载、运行独立 `difi_stage_d_v04.elf`。按原硬件平台要求完成 PS 初始化。无需为本升级重建 Vivado 工程。
3. 记录 UART 的 v0.4 标识及实际状态。若为 `FAULT`，不要继续测试。仅重启 ELF 无法可靠重建已经运行过的 PL Startup Version、序号与 DMA 状态。
4. GUI 选择 Live、点击 `Connect`。核对 `PROTO=4`、`STATE=READY`、`CUSTOM_TX=1`、`CUSTOM_RX=1`、`CONFIG=1`、`MIN_SAMPLES=1 MAX_SAMPLES=256`。缺少能力时，相应操作不应被当作可用。
5. 当 STATUS 的 `UTC=0` 时点击一次 `Initialize UTC once`，等待确认；同一干净 PL 启动后 UTC 不能重复设置。CLOSE/OPEN 不会清零 UTC 或序号。
6. 在 Packet Editor 保持首次默认参数，回 Overview 点击 `Apply profile to FPGA`。核对返回的全部配置字段与填写值一致，再运行。首次未配置的 Run 也会由控制器先执行并确认 CONFIG；验收时建议显式 Apply，便于记录读回结果。

## 4. 自定义 IQ 与可变 N 验收矩阵

默认参数：Data SID 1、Version SID 2、Fs 20,000,000 Hz、BW 10,000,000 Hz、RF 100,000,000 Hz、RX filter 3、RX Data/Context SID 1、RX Version SID 2。

逐项执行下表；每次改 N 都核对 Packet Editor 与 IQ Generator 中的样本数一致。保持 Packet type 为 DATA，方向 TX，先使用 `Rounds 1` 和交替循环；每项都应保存本次实际证据，不以 Replay 替代。

| N | Data words | DIFI UDP Payload | RX IQ 字节数 | 结果 |
|---:|---:|---:|---:|---|
| 1 | 8 | 32 B | 4 B | 待测 |
| 2 | 9 | 36 B | 8 B | 待测 |
| 64 | 71 | 284 B | 256 B | 待测 |
| 255 | 262 | 1,048 B | 1,020 B | 待测 |
| 256 | 263 | 1,052 B | 1,024 B | 待测 |

这里的 DIFI/IQ 长度不包含 v0.4 的 24 B `SDU4` 外层；v0.4 RX 使用带会话/事务号的 `IQ` 帧，**不再使用 v0.3 的 IQD3 标识**。

每项检查：

- TX 比较的是自定义 PC 输入与实际 DMA1 S2MM 捕获的 PL DIFI Data 中的 IQ。RX 比较的是送入的合法 DIFI Payload 与实际 DMA0 S2MM 返回的 IQ。参考曲线、实际曲线和误差表应与这些字节一致。
- `actual_samples == expected_samples == N`、Mismatch 0、Max |Δ| 0，并在 DONE 后再次由真实 STATUS 确认 READY。不能以“已发送 N 个样本”代替“已收到并验证 N 个样本”。
- 首次 TX 自动产生 Startup Version → pending Context → Data。后续一次成功 CONFIG 会使 Context pending；下一次 TX 可能多返回真实 Context，不能固定假定每轮只有一个包。
- Version 只在 PL 启动/真实调度条件下产生。更改 Version SID 不会产生独立 Version-on-demand；单独 TX VERSION/CONTEXT 不应被伪装为硬件支持的命令。

### 输入种类、边界与文件

在 IQ Generator 分别验收 Complex sine、Real sine、Constant I/Q、Square、Linear chirp、Seeded pseudorandom。频率应在 Nyquist 范围内；相位 UI 单位为 degrees。相同 Seed/参数应能重建同一 PC 参考数据，且不会被标成实际 FPGA 测量。

使用 Constant 或样本表编辑至少验证以下值；建议 N≥4 时在同一包内覆盖：

```text
I=-32768, Q=32767
I=32767,  Q=-32768
I=-1,     Q=0
I=0,      Q=-1
```

CSV 输入必须为整数，支持 `I,Q`，也支持原 Stage D 的 `I_signed16,Q_signed16` 列。可用以下本地测试文件，文件中是**待发送的 PC 输入**，不是板卡实测数据：

```csv
I,Q
-32768,32767
32767,-32768
-1,0
0,-1
```

Import CSV 后应为 4 个样本；Packet Editor 同步为 N=4。原始 BIN 是逐样本 I16 后 Q16，可在导入控件选择 big/little endian；网络传输仍为 big endian。1 B/2 B/3 B 尾部残缺、32768、-32769、浮点 CSV、重复/缺失表头等均应被拒绝，不应发生环绕截断。保存并重载 reusable preset，核对精确样本、生成器参数、相位、Profile 与包类型均恢复。

## 5. Metadata RX、参数与序号

关闭交替复选框，选择方向 RX，在 Packet Editor 依次选择 VERSION、CONTEXT，各做一次真实 Run：

1. Metadata 不需要 IQ 数据，Inspector 显示有效的 44 B Version 或 108 B Context；不能因本地没有 IQ 而把合法 metadata 变成无效包。
2. DONE 应明确包含对应 TYPE、实际 SEQ、`SAMPLES=0 PACKETS=1 META=1`。Version/Context 不应返回或增加“实际 RX IQ”样本。
3. 核对返回的 `MON_COUNT / MON_DETAIL`：相关 metadata 计数恰好增加一次，另一类保持稳定，Seq/Changed 与实际输入一致，错误计数不增加。PC 显示的是板端读 GPIO 后返回的值；没有对应字段时应保持不可观测。
4. 修改合法的 Fs/BW/RF、TX SID、RX SID/filter 后先 Apply 并保存完整读回。BW 必须在 1..Fs，Fs 为非零 uint32，RF 在 0..100 GHz；RX filter bit0 管 Data/Context，bit1 管 Version。关闭相应过滤时只能说明不按 SID 拒绝，不能宣称改变了冻结的包格式。
5. TX 与 RX 的频率配置用途不同：实际 TX Context 应匹配已确认的 TX 参数；合法 RX Context 可携带独立的合法频率值。若用 GUI 编辑 Context，记下提交的 Profile 与实际输入，不把 PC 预览当作已应用配置。

在 Timeline / Metadata 中切换 TX/RX 序号观察方向，分别核对 VERSION、CONTEXT、DATA 的独立流。v0.4 使用 `NEXT_DATA/NEXT_CONTEXT/NEXT_VERSION` 与 `RX_DATA_NEXT/RX_CONTEXT_NEXT/RX_VERSION_NEXT`，CLOSE/OPEN/CONFIG 不清零，改变 SID 也不重置固件的每类型序号策略。

DATA 可在同一连接上做至少 17 次交替循环，检查各方向 15→0 合法回绕；CONTEXT 可通过重复合法 RX 检查其独立回绕，VERSION 可用重复合法 Version RX 检查。**不要要求 TX Startup Version 重发 17 次来演示回绕。** GUI 系统管理 RX Sequence，连续轮次采用板端的独立 RX next；交替循环保留真实 TX 的 IQ/metadata 内容，但必要时为 RX 管理其 Sequence。导出的 RX `.difi` 是实际发送版本，不应把修改后的 RX Header 冒称为原始 TX 捕获 Header。

## 6. Stop、超时与恢复

1. 在多轮任务运行中点击 `Stop / drain`。界面应继续响应，禁止重复启动与中途切换来源/工作区；停止不伪造 DMA 已取消。正在执行的事务会在边界内完成接收、比较和真实状态确认，再停止后续轮次。
2. 已完成的真实数据可以保留，但会话应为 STOPPED，不应把未执行轮次补为成功。Stop 不是立即重置 DMA、Bitstream 或恢复 UTC 的按钮。
3. 固件有有界 DMA 等待，GUI 同时使用配置 Timeout。可在独立恢复测试中拔线/断开板端网络，确认超时后没有自动重发 TX/RX、没有新造实际样本或全轮 PASS。此项结束后按下面的状态处理；不要在比赛演示主链路中临时做故障注入。

| 观察状态/错误 | 操作者处理 |
|---|---|
| READY，已确认本次事务完成 | 可继续下一受控请求；健康状态下 Disconnect 可释放会话 |
| v0.3 WAITING_RX，缓存仍在同一 GUI 连接 | 先完成对应 RX；不要重建源端口或假定可以再 TX |
| v0.3 PENDING、缓存丢失或 RECOVERY_REQUIRED | 保存日志，按原基线流程重新加载匹配硬件/ELF并重新开始 |
| DISCONNECTED_INDETERMINATE / timeout | 本次命令是否已执行不能确定。保留日志，不自动重复同一 TX/RX；人工查看 UART/只读 STATUS，无法可靠恢复时重新加载匹配硬件和 ELF |
| FAULT / DMA_ERROR / parser/monitor discrepancy | 固件已锁存故障，停止操作并保存证据；重新加载 Stage D Bitstream 和对应 ELF 后从干净状态开始 |
| WARM_PL_RELOAD_REQUIRED | 只重启 ELF 不足；重新加载既有匹配 Bitstream，再启动 v0.4 ELF |
| SESSION_PEER / BAD_SESSION / DUPLICATE_TXID | 核对是否旧进程/旧端口/延迟帧；不得用重试造成第二次 DMA。健康 owner 正常 CLOSE；owner 已丢失且无法确认时按干净重载恢复 |
| SESSION_LIMIT | 当前 PL 启动期已达到 64 个 opened session ID 的上限；保存证据后重新加载硬件/ELF，不规避重放保护 |
| RX_SEQUENCE | 核对独立 RX next；保存实际输入，修正下一合法请求。状态不确定或客户端已经失去会话所有权时重新初始化，不把 TX 序号强当 RX 序号 |

v0.4 的会话绑定源 IP/端口，事务号严格递增且不回绕；没有自动 owner 过期接管，也不缓存成功结果供重试。关闭/重启 GUI 不能被当作板端故障复位。STATUS 返回 READY 之前，不应宣称仅靠等待一段时间就已完成 DMA。

## 7. 原始证据、离线重载与来源隔离

每个测试结束后在 `Export / Archived Metrics` 点击 `Export full evidence + screenshot`，保留完整目录。自动保存位于 `dashboard/output/stage_d/` 下的独立会话目录。

导出至少核对：

- `experiment.json/.txt/.md`、`operator_log.json`，以及手动导出的 `dashboard.png`。
- 各 `transaction_*` 下的实际 `.difi`、`reference_iq.bin/.csv`、`actual_iq.bin/.csv`、`comparison.csv`；metadata 无 IQ 时不要求生成空“实际 IQ”。
- source、状态、参数、能力、STATUS、时间、事务号、参考依据、原始字节与校验值。实际 RX IQ 必须有返回字节佐证，不能由参考数组补造。

先健康 Disconnect，再点击 `Open exported evidence offline` 选择整个导出目录中的 `experiment.json`。此操作应校验原始文件及字节/数值一致性，显示 `OFFLINE ARCHIVE`，不连接硬件。重载为原记录的 LIVE 来源只表示历史记录，不是当前重新执行的实测。

另做一次 Replay 导出/重载，确认始终保留 `REPLAY / OFFLINE`、fixture/模拟标识，导出不得变成 LIVE FPGA PASS。连接期间禁止改变来源；Reset Session 清当前证据，不清板端 UTC、Sequence 或已导出的目录。历史吞吐率/WNS/Rebuild PASS 始终属于 Archived Result，不是当前 UDP 的实时测量。

## 8. 回退与最终签收

需要恢复原 Stage D 时，断开新 GUI 会话，手动重新加载**既有** Stage D Bitstream 和保留的原 v0.3 ELF，再按第 2 节验证。新固件独立目录不会替换原 ELF；不要通过覆盖文件来“回滚”。

需要使用旧 B5 或 B6 时，加载其各自匹配的原硬件/ELF，切换到对应 GUI 工作区；也可以单独运行未修改的原 CLI。B5 要先按原板端流程通过 UART 初始化 UTC 并等待 START：

```powershell
New-Item -ItemType Directory -Force dashboard/output | Out-Null
.\.venv\Scripts\python.exe -u scripts/verify/tools/difi_udp_receiver.py --board 192.168.1.10 --pc-ip 192.168.1.20 --port 4991 --timeout 10 --output dashboard/output/b5_capture.bin
.\.venv\Scripts\python.exe -u scripts/verify/tools/difi_b6_three_types.py --board 192.168.1.10 --local-ip 192.168.1.20 --port 4991 --timeout 5 --types version,context,data --rounds 20
```

两条命令是两个**分开的**板卡配置/测试，不要在加载同一个 ELF 后连续执行并预期均能通过。B5/B6 不与 Stage D GUI 共用一个正在运行的网络会话；B6 ACK-only 原流程仍没有实际 FPGA IQ 回传，参考曲线不能改称 S2MM 实测。

最终填写下表，附每项真实证据目录后再签收：

| 验收项 | 当前状态 | 实体结果/证据路径 |
|---|---|---|
| 原 v0.3 + 新 GUI：两次完整交替、实际 IQD3 | 待执行 | |
| v0.4：干净 PL、独立 ELF、版本/配置/UTC确认 | 待执行 | |
| N=1/2/64/255/256 的实际 TX/RX | 待执行 | |
| signed16 极值、自定义样本、CSV/BIN/preset | 待执行 | |
| Version/Context RX、实际 monitor 观测 | 待执行 | |
| 独立序号与 15→0、跨 CONFIG/CLOSE/OPEN | 待执行 | |
| Stop、超时、FAULT 恢复、不自动重复 DMA | 待执行 | |
| 原始导出、离线重载、Replay/Live 隔离 | 待执行 | |
| 原 v0.3 和 B5/B6 回退操作 | 待执行 | |

没有实体结果的行保留“待执行”，不要用本机软件测试通过数或历史归档结果代填。
