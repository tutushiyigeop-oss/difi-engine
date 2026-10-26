# Stage D 升级验证记录 · 2026-10-25

**实现与软件验证完成；新 Stage D GUI Live 集成和 v0.4 实体板验收尚未执行。** 用户已确认的原 v0.3 固定 Profile 板级成果保留为基线。本记录不将 Replay、localhost 模拟器、编译通过称为新硬件 PASS。

## 实际环境与测试结果

- Windows 11，原生 Python 3.12.7，项目独立 `.venv`。
- Qt / PySide6 Essentials 6.8.3，pyqtgraph 0.14.0。
- 当前分支 `feature/rtl-integration`；开始时工作区干净，基线 HEAD `05210bf`。
- 最终 Python 回归：**296 passed in 16.77s**，包含原 101 项用例。

```powershell
.\.venv\Scripts\python.exe -m pytest dashboard/tests -q --basetemp dashboard/output/upgrade-final-003
```

新增 UDP 联调用例仅绑定 `127.0.0.1`，模拟 v0.3/v0.4，不向 `192.168.1.10` 或其他开发板地址发包。本机沙箱会丢弃回环报文，因此整套测试在经过批准的沙箱外执行。GUI/模型测试不需要开发板。

覆盖包括全部 1–256 样本长度、指定边界 1/2/64/255/256、int16 极值、六类生成器、相位/种子、CSV/BIN/preset、Word0/OUI/Class/CIF/DPF/时间/尺寸、过滤与独立序号、v0.3 同 socket/缓存回放、v0.4 会话/事务关联/能力/配置回读、迟到/重复/冲突/异常帧、超时/Stop、端口释放、原始字节导出和篡改拒绝、归档重导出、实际配置与未发送预览分离、Qt 页面和 B5/B6 回归。

## Windows 原生 GUI

已实际运行原生 `windows` Qt 平台：

```powershell
$env:QT_QPA_PLATFORM = 'windows'
$env:QT_SCALE_FACTOR = '0.8' # 仅该截图进程：本机 125% DPI 的等效 100% 渲染
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --replay STAGED --screenshot dashboard/output/stage_d_overview_20261025.png
.\.venv\Scripts\python.exe dashboard/main.py --smoke-test --replay STAGED --page waveform --screenshot dashboard/output/stage_d_waveform_20261025.png
```

原生窗口冒烟输出：

```text
SMOKE PASS: Qt=windows source=REPLAY mode=STAGED state=COMPLETED packets=8 IQ=1024
```

这是两轮离线 TX/RX 的总 Packet/IQ 统计，始终标为 REPLAY。已检查 Overview 和 Waveform 截图。分页布局与可滚动内容保证小窗口仍可操作，底部 Run/Stop/方向控件独立于页面滚动。未改变系统 DPI 设置。

## 独立固件构建与 C 测试

实际执行：

```powershell
.\.venv\Scripts\python.exe firmware/stage_d_v04/build_firmware.py
.\.venv\Scripts\python.exe firmware/stage_d_v04/tests/run_tests.py
```

- Vitis 2024.2 Cortex-A9 ARM GCC 编译/链接成功，`-Wall -Wextra` 无报告警告。
- ELF：`firmware/stage_d_v04/build/difi_stage_d_v04.elf`。
- ELF SHA256：`c1030423a27eb53cc790beddbcb8330d9d7d492ea29095fc079f64e20a76bbb4`。
- Windows MSVC C11 主机测试成功，`/W4 /WX`；验证 SDU4 framing/endian/length、事务保护、配置边界、1–256 IQ 和 metadata Profile。
- 独立检查当前 RTL、AXI 寄存器、DMA Halted/Idle、缓存边界和 v0.3 实现，未发现具体接口缺陷；这不代替实际硬件验证。

没有运行 Vivado Implementation，没有修改/重新生成 XSA/Bitstream，没有连接 debug server、下载 ELF 或控制 FPGA。生成物仅写入已忽略的独立 `build/`。

## 保护与改动范围

原 v0.3 文件与收尾时哈希一致：

| 文件 | SHA256 |
|---|---|
| `vitis/vitis_ws_rebuilt/difi_stage_d_udp_half_duplex/src/main.c` | `ff36143b1d42290b2c6cb9b9df19a219fb21c74dfb2a3daf1af770ce20d2498c` |
| 同组件 `build/difi_stage_d_udp_half_duplex.elf` | `36c88a5da159f70a2df2564499d973ae63a2137f637d05a357a3e965adc0d2c3` |
| `scripts/verify/tools/stage_d_udp_cycle.py` | `f4b8858566e8eb734bfa5013ad111fe3bbd6a349c2668bce8f57e4c0540b7c8b` |

修改既有文件：`dashboard/main.py`、`dashboard/app/main_window.py`、`dashboard/README.md`、根 `README.md`（简短入口）。旧 B5/B6 Runner、Session、Parser 和 CLI 保留。

新增文件：

```text
dashboard/app/experiment/__init__.py
dashboard/app/experiment/profile.py
dashboard/app/experiment/iq.py
dashboard/app/experiment/models.py
dashboard/app/experiment/client.py
dashboard/app/experiment/controller.py
dashboard/app/experiment/replay.py
dashboard/app/experiment/exporter.py
dashboard/app/experiment/editors.py
dashboard/app/experiment/waveforms.py
dashboard/app/experiment/panel.py
dashboard/tests/test_experiment_models.py
dashboard/tests/test_experiment_iq.py
dashboard/tests/test_experiment_gui.py
dashboard/tests/test_stage_d_client.py
dashboard/tests/test_stage_d_controller.py
dashboard/tests/test_stage_d_export.py
dashboard/STAGE_D_GUIDE.md
dashboard/STAGE_D_LIVE_ACCEPTANCE.md
dashboard/STAGE_D_VALIDATION.md
docs/STAGE_D_V04_PROTOCOL.md
firmware/stage_d_v04/README.md
firmware/stage_d_v04/build_firmware.py
firmware/stage_d_v04/src/main.c
firmware/stage_d_v04/src/protocol.c
firmware/stage_d_v04/src/protocol.h
firmware/stage_d_v04/tests/run_tests.py
firmware/stage_d_v04/tests/test_protocol.c
```

原 RTL、Tcl、Vitis v0.3 工程与验证报告未修改；未提交或推送 Git。

## 完成、待验与不支持

| 项目 | 状态 |
|---|---|
| M1：v0.3 GUI 接入、真实字节解码、固定交替及导出 | 实现/软件模拟通过；新增 GUI Live 待板级验证 |
| M2：合法 Packet/IQ 模型、编辑/导入/比较 | 实现及自动测试通过 |
| M3：独立 v0.4 实际 DMA 数据通路固件 | ARM 构建/主机协议测试通过；尚未上板 |
| M4：能力协商、配置驱动、分页界面、实测来源与证据 | 实现/软件联调/Windows GUI 通过；真实 DMA/网络仍待板级验收 |
| M5：现有与新增回归、文档和恢复步骤 | 本机可执行部分完成 |

明确不支持：同时全双工、TX Version-on-demand、PL 序号软件复位、反复 UTC 重置、超时后自动重试 TX/RX、v0.3 任意 IQ 上传或变长配置。只重启 v0.4 ELF 而保留暖 PL 会被安全拒绝；需手动重载已有匹配 Bitstream。v0.4 开启 Session 总数上限为每次干净启动 64 个。

实体板部署、故障恢复、跨次累积序号及现场 DPI/网卡/防火墙验收按 [现场验收单](STAGE_D_LIVE_ACCEPTANCE.md) 执行；使用和兼容步骤见 [指南](STAGE_D_GUIDE.md)。
