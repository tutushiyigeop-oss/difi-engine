# Stage D v0.4 board application

完整 C 源码：`src/main.c`、`src/protocol.c`、`src/protocol.h`。请同时编译两个 C 文件。中文手动建工程、编译及上板步骤见 [README_ZH.md](README_ZH.md)；源码交付包见 `dist/DIFI_Stage_D_v0_4_C_Source.zip`，不含预编译 ELF。

Independent source for custom PC IQ → real PL TX and custom DIFI → real PL RX on the existing Stage D dual-DMA design. The v0.3 workspace and hardware artifacts are preserved.

See [the SDU4 protocol and hardware limits](../../docs/STAGE_D_V04_PROTOCOL.md) before loading the application. A clean load of the existing matching Stage D bitstream is required; restarting the ELF against warm PL deliberately reports FAULT. UTC is loaded once per clean PL boot. There is no software Version-on-demand or sequence-reset register.

```powershell
# Repository root; native Windows Python. Both commands are offline builds/tests.
.venv\Scripts\python.exe firmware\stage_d_v04\build_firmware.py
.venv\Scripts\python.exe firmware\stage_d_v04\tests\run_tests.py
```

The build uses read-only existing Stage D BSP libraries and linker script plus installed Vitis 2024.2 ARM GCC. It writes only to ignored `build/`, including `difi_stage_d_v04.elf`, map and a manifest with compiler commands/source hashes. Optional `--bsp`, `--gcc`, `--linker-script`, and `--output` override local paths. It never invokes Vivado implementation, rebuilds v0.3, or programs hardware.

Host tests use installed MSVC via `vcvars64.bat` by default on this Windows machine; `--gcc` or `--vcvars` selects another installed toolchain. They validate framing, configuration, sequence transaction guards and DIFI profiles. They exercise no FPGA or network hardware.

Local verification on 2026-10-25:

- Vitis 2024.2 ARM compilation/link: PASS with `-Wall -Wextra` and no reported warnings.
- Native Windows MSVC C11 host tests: PASS with `/W4 /WX`.
- Independent read-only review against the current scheduler, packetizer, parsers and register map: no concrete firmware defect identified.
- Latest built ELF SHA256: `c1030423a27eb53cc790beddbcb8330d9d7d492ea29095fc079f64e20a76bbb4`.
- Physical v0.4 board acceptance: **not performed**. No hardware was programmed by these scripts or this verification.

Protected v0.3 source SHA256: `ff36143b1d42290b2c6cb9b9df19a219fb21c74dfb2a3daf1af770ce20d2498c`; protected v0.3 ELF SHA256: `36c88a5da159f70a2df2564499d973ae63a2137f637d05a357a3e965adc0d2c3`. These files remain in the existing ignored Vitis workspace; the new maintained source is this directory.
