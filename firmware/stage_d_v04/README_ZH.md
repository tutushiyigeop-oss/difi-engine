# DIFI Stage D v0.4 完整 C 源码与自行编译、上板说明

本目录提供可编辑的完整板端 C 程序。程序采用 AMD/Xilinx standalone BSP + lwIP RAW API，运行于 Zynq Cortex-A9；不是 Windows 控制台程序，也不是仅供查看的伪代码。

交付源码为 `src/main.c`、`src/protocol.c`、`src/protocol.h`。必须将两个 `.c` 文件一起编译，头文件放入包含路径。它们不依赖 v0.3 的 `main.c`。

2026-10-25 已使用本机 Vitis 2024.2 ARM 工具链编译、链接通过，主机协议 C 测试通过；**尚未进行 v0.4 实体板验证**。这些结果不能代替你实际下载后对 DMA、网口及 FPGA 通路的验收。

## 1. 源码内容

| 文件 | 内容 |
|---|---|
| `src/main.c` | 完整 `main()`、PS 网络与定时中断初始化、UDP 服务、会话/事务控制、UTC 和 Profile 寄存器操作、DMA1 自定义 IQ → PL TX → 实际 DIFI 捕获、DMA0 DIFI → PL RX → 实际 IQ 回传、错误与状态处理 |
| `src/protocol.c` | SDU4 帧编解码、网络字节序转换、配置边界校验、事务号及 DIFI 包校验 |
| `src/protocol.h` | 完整协议常量、数据结构、错误码和函数声明 |
| `build_firmware.py` | 可选命令行构建脚本；只编译，不下载或操作板卡 |
| `tests/test_protocol.c`、`tests/run_tests.py` | 可选的主机 C 协议测试；不含实体 DMA 测试 |

源码包 `DIFI_Stage_D_v0_4_C_Source.zip` 额外包含：

- `reference/lscript.ld`：本机此前验证构建使用的参考链接脚本，保留 AMD 原始版权说明。
- `docs/STAGE_D_V04_PROTOCOL.md`：板端通信协议和现有硬件限制。
- `SHA256SUMS.txt`：包内各文件的 SHA-256，用于核对源码是否一致。

源码包不含 `.elf`、`.o`、预编译 BSP 库、XSA 或 Bitstream。硬件相关头文件和库由你本机匹配平台的 BSP 生成；这属于正常 Vitis 应用依赖。

## 2. 使用的硬件平台

使用既有 Stage D 半双工、双 DMA 硬件平台，处理器选择 `ps7_cortexa9_0`。本次 C 程序不要求重新修改 RTL 或重新实现 Vivado。

本仓库既有文件：

```text
XSA:
  vitis 平台使用的对应 Stage D XSA
  当前仓库路径：vivado/rebuilt/half_duplex/stage_d_half_duplex.xsa
Bitstream:
  vivado/rebuilt/half_duplex/difi_stage_d_half_duplex.runs/impl_1/difi_ip_test_wrapper.bit
现有平台:
  vitis/vitis_ws_rebuilt/difi_half_duplex_platform
现有 BSP 导出目录:
  vitis/vitis_ws_rebuilt/difi_half_duplex_platform/export/difi_half_duplex_platform/sw/standalone_ps7_cortexa9_0
```

本程序使用的地址如下。使用其他 XSA 前需核对其地址表；仅存在两个 DMA 并不足以证明硬件匹配。

| 模块 | 基地址 |
|---|---|
| DIFI 控制寄存器 | `0x40000000` |
| UTC 时间寄存器 | `0x40001000` |
| RX metadata GPIO | `0x41200000` |
| AXI DMA0：RX 通路 | `0x40400000` |
| AXI DMA1：TX 通路 | `0x40410000` |

## 3. 在 Vitis 2024.2 中手动创建、编译

1. 打开 Vitis Unified IDE，使用现有匹配的 `difi_half_duplex_platform`。如在其他工作区使用，由上述 Stage D XSA 创建平台，选择 `ps7_cortexa9_0` 和 standalone 域，再生成 BSP。
2. 创建独立 Application Component，例如命名 `difi_stage_d_udp_v04_manual`，选择该平台及 standalone 域。可以选择 Empty Application；若从 Hello World 模板创建，删除模板的 `main()` 源文件。
3. 向新应用的 `src` 添加本交付的 **main.c、protocol.c、protocol.h 三个文件**。保留原 v0.3 应用，避免把两个版本的 `main.c` 同时加入一个工程。
4. BSP 添加/启用 `lwip220`，采用 **RAW API、`NO_SYS=1`**。沿用此前 Stage D 平台已经验证的 GEM0、PHY/MDIO、网口驱动及 BSP 网络参数。源码明确检查 RAW API 配置；不能换成 lwIP socket API 域后直接编译。
5. 编译语言为 C99，ARM 目标为 Cortex-A9。当前已验证的参数为：

   ```text
   -DSDT -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard
   -O2 -g3 -Wall -Wextra -std=c99
   ```

   `SDT` 用于本次 Vitis 2024.2 SDT BSP，必须与实际 BSP 生成方式一致。BSP `include` 和应用 `src` 加入包含目录，使用 BSP 的 `Xilinx.spec`；IDE 通常会通过平台依赖自动配置相关路径。
6. 使用匹配此平台内存布局的链接脚本。包内 `reference/lscript.ld` 是现有 Stage D 的参考，可在相同平台下复制到应用并选为链接脚本；换硬件时由你的平台生成。程序及网络缓冲区应放在 DDR，不能全部放入容量很小的 OCM。当前验证构建 BSS 约 3 MB。
7. 链接 BSP 的 `lib` 目录。此前验证构建的库组如下，IDE 如已自动加入则不要重复配置：

   ```text
   -Wl,--start-group -lxilstandalone -lxiltimer -llwip220 -lxil -lgcc -lc -Wl,--end-group
   ```

8. Build 新应用，确认生成的是新应用自己的 ELF。`undefined reference to sd4_*` 通常说明遗漏编译 `protocol.c`；`multiple definition of main` 通常说明模板入口尚未删除；找不到 `lwip/*` 则应检查所选域、BSP 库和包含路径。

所有 BSP 参数、PS 初始化和网口设置都应以已经验证的 Stage D 平台为基础；不要为了消除编译错误随意更改驱动类型或寄存器地址。

## 4. 可选：由你自己执行命令行编译

在原仓库根目录，本机默认路径已配置，可由你运行：

```powershell
.\.venv\Scripts\python.exe firmware/stage_d_v04/build_firmware.py
```

若从 ZIP 解压到独立目录，在解压后的源码包根目录执行下面命令，并替换为你的实际路径。这里显式指定三个路径，不依赖原仓库位置：

```powershell
python .\build_firmware.py `
  --gcc 'D:\software\xilinx_2024.2\Vitis\2024.2\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe' `
  --bsp 'D:\Study\project\DIFI\vitis\vitis_ws_rebuilt\difi_half_duplex_platform\export\difi_half_duplex_platform\sw\standalone_ps7_cortexa9_0' `
  --linker-script '.\reference\lscript.ld' `
  --output '.\build'
```

输出为 `build/difi_stage_d_v04.elf`、Map 和 `build_manifest.json`。构建脚本只读取指定的 BSP，不修改原 v0.3 工程；它不执行下载或烧写。

## 5. 由你手动上板

1. 连接 JTAG、UART 和网线，关闭占用同一 UDP 会话的旧程序。
2. 在 Vitis 调试/下载配置中完成匹配硬件的 PS 初始化，**重新加载既有匹配 Stage D Bitstream，使 PL 处于干净状态**，再加载、运行你自己刚编译的新 ELF。
3. 按原 Stage D 已验证的 UART 设置查看日志。程序应报告 v0.4，并监听 `192.168.1.10:4991`。只有 `READY` 状态才进入后续实验。
4. PC 有线网卡设置为 `192.168.1.20/24`，与板卡直连或接入相同网段。放行相应 Python 程序的 UDP。
5. 在原仓库根目录运行：

   ```powershell
   .\.venv\Scripts\python.exe dashboard/main.py
   ```

6. Dashboard 顶部选 `Stage D · UDP Half-Duplex`，选择 `Live / Hardware`。Board IPv4 为 `192.168.1.10`，PC bind IPv4 为实际网卡地址 `192.168.1.20`，目标端口 `4991`，源端口 `0`，首次超时可用 `10 s`。
7. 点击 `Connect`，核对 `PROTO=4`、`STATE=READY`，以及 `CUSTOM_TX=1`、`CUSTOM_RX=1`。若仍为 Protocol 3，检查实际运行的是否为新 ELF。
8. 仅当状态为 `UTC=0` 时点击一次 `Initialize UTC once`。然后在 Packet Editor 配置参数，在 Overview 点击 `Apply profile to FPGA`，确认配置成功。
9. 首次建议使用 256 个样本、1 个 round，勾选 TX → RX → TX 循环。核对 TX 捕获与 RX IQ 均来自实际 DMA，并检查 Mismatch 为 0、Max |Δ| 为 0、最终回到 READY；再分别测试 N=1、2、64、255、256 及不同自定义 IQ。

网络参数在 `src/main.c` 的 `init_network()` 中；UDP 端口由 `UDP_PORT` 定义。如需改网段，同时调整 PC 和 GUI 配置后重新编译。

## 6. 实体测试时必须了解的行为

- 单次 Data 为 1～256 个 I16/Q16 样本。v0.4 使用 SDU4 帧，与 v0.3 的固定命令、IQD3 返回格式不同。
- 同一连接锁定源 IP/端口，事务号递增。通信超时后先检查真实状态，不能盲目重发 TX/RX。
- 第一次 TX 可实际捕获 Startup Version、Context、Data；后续 CONFIG 后可能增加 Context，不能假定每次只有一个包。
- 既有硬件没有软件可用的“任意重置 TX 序号”或“按需发送 Version”寄存器；本程序不伪造这些功能。
- UTC 每次干净 PL 启动只设置一次。只重启 ELF 不会复位 PL 序号、UTC 和 Startup 状态；状态异常时保存日志，再重新加载匹配 Bitstream 和新 ELF。
- 主机测试通过、编译成功都不能作为上板通过的结论。完整现场验收表位于原仓库 `dashboard/STAGE_D_LIVE_ACCEPTANCE.md`。
