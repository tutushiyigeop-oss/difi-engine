# B6 v0.2 original-board project evidence (NOT independent rebuild)

Source: Vivado 2024.2 routed implementation, XC7Z020-CLG400-2, `difi_ip_test_wrapper`; acquired 2026-10-23 from the user's real B6 v0.2 project. Files were uploaded by project owner and statically inspected against the actual BD Tcl and XSA metadata. The reports have their host name and local machine path redacted for later publication. The original report SHA256 values allow comparing with the locally retained unredacted originals.

- Setup WNS = +2.372 ns, TNS = 0, Hold WHS = +0.053 ns, THS = 0; PL FCLK0 = 100 MHz.
- Total design LUT = 4,336; FF = 6,204; RAMB36E1 = 2; RAMB18E1 = 1; DSP = 0.
- Original DRC report includes warnings (e.g. REQP-1840 and LUT/SLICE checks); there is no blanket `zero DRC warning` claim.
- XSA contains FPGA bitstream; SHA256: `32878bef391c4e06d190454ce198aa5bf8feaf2f82e8362a590f1d7758419b7c`. The .xsa is **not** included or committed. This hash does not prove the XSA is identical to the one used for the earlier hardware UART test: pairing still requires user verification.
- B6 verified UART evidence is already in `report/results/udp/rx/three_types_udp_rx.rtf`.
- The BD exports no separate external XDC; `manifest.tcl` preserves source design name/part/2024.2 version. External dependencies for rebuild: IP repository at `ip_repo/`, Module Reference source `rtl/board/difi_b6_rx_meta_monitor.v`, tool built-in AXI/PS IP.
- PS `PCW_ACT_APU_PERIPHERAL_FREQMHZ` in BD Tcl: `666.666687` MHz (Vivado's display representation). Project owner confirms PS CPU 666.666666 MHz for reported performance calculations. Do not confuse this with the PL 100 MHz.

| Uploaded original | Archived output | Original SHA256 | Archived SHA256 |
|---|---|---|---|
| `bd.tcl` | `scripts/vivado/generated/b6_udp_rx/bd.tcl` | `e9b7aae9f03f1a5d60f4dfc1f87e943f4047c7f41a32d90e4daf4ec7d4966e43` | `e9b7aae9f03f1a5d60f4dfc1f87e943f4047c7f41a32d90e4daf4ec7d4966e43` |
| `manifest.tcl` | `scripts/vivado/generated/b6_udp_rx/manifest.tcl` | `90df7573a7277efc2eb6454bf9f674abd5814d4e339c20b2014a13ba26367973` | `90df7573a7277efc2eb6454bf9f674abd5814d4e339c20b2014a13ba26367973` |
| `export_info.txt` | `scripts/vivado/generated/b6_udp_rx/export_info.txt` | `619a3a6c63307d90805dec11857f01c9da758195e7eef16deb9a607143c51933` | `619a3a6c63307d90805dec11857f01c9da758195e7eef16deb9a607143c51933` |
| `capture_info.txt` | `report/results/b6_impl/capture_info.txt` | `fe83d150de7bf9ad15344e173cb9916e386dd5bf25e22bbebac1e19f899e78c3` | `fe83d150de7bf9ad15344e173cb9916e386dd5bf25e22bbebac1e19f899e78c3` |
| `utilization(5).rpt` | `report/results/b6_impl/utilization.rpt` | `c16051023c4b3d1f3a11a531a377384dacb92c153bc8113f11b58f6b9704afad` | `c4e62f752dd952382e3d4fa5f4b93394716274fcd8eaf7f40a8ebf769729c08a` |
| `timing_summary(5).rpt` | `report/results/b6_impl/timing_summary.rpt` | `8ac45249d85e5d509263b6c395430b1f14b2b3a1c42f8edfd15bad4f9f05c2d2` | `50aa5368aff3af74ad096386d52356d17ae2fa3c51557ffddb1369d1be0cdab0` |
| `drc(3).rpt` | `report/results/b6_impl/drc.rpt` | `f0cb2d09aa5a82f23ca06ed6be493fe31cc4826ffca2f90e1744231a0fcb92ff` | `2a6f6baa0c5ad60a340262cb3353125b50591abe542a861ac59a85c83050605d` |
| `clocks.rpt` | `report/results/b6_impl/clocks.rpt` | `8eb2d22222762f8965f479128c6dc9d3a1cd266d21385742371cb0023b508860` | `e127a38a5a08970bfcc9d89dd9a2069e4eacddf2662c9648f42ecf908782e191` |

**This package alone is NOT proof of independent B6 BD rebuild or a second board run.** A successful fresh Vivado implementation must create separate reports in `report/results/vivado_rebuild/b6_udp_rx/` and a new XSA, followed by Vitis board verification.
