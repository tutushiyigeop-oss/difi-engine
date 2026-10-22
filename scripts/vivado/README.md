# DIFI Vivado Block Design export/rebuild (Vivado 2024.2)

> **Current status (2026-10-22):** Both actual Vivado BD snapshots (`generated/{packaged_ip,b5_raw_export}/bd.tcl` and manifests) have been exported from the working original projects and committed. Each has been rebuilt into an independent XPR; the associated implementation scripts generated bitstream and XSA with positive setup/hold slack. The developer subsequently confirmed board-level regression of both rebuilt projects. Fresh-board Vitis/UART transcripts remain to be archived, and this repository has **not** yet been independently reproduced on an unrelated machine. The existing scripts and reports are **real project-specific tools**, not a claim that the new generic `skill/vivado-rebuild/` template has passed cross-project testing.

## 1. Identifying the two original projects

| Target | BD | Original top | Purpose |
|---|---|---|---|
| `packaged_ip` | `difi_ip_test.bd` | `difi_ip_test_wrapper` | Packaged DIFI IP TX → RX loopback; DMA S2MM sees decoded IQ |
| `b5_raw_export` | `difi_system.bd` | `difi_system_wrapper` | DMA S2MM sees **complete raw DIFI packets**, then PS sends UDP |

**Important:** B4 also uses `difi_system.bd` / `difi_system_wrapper`. `export_bd.tcl` additionally detects the B5 module/source `difi_board_raw_packet_export` / `difi_engine_board_b5.v`. Never export the old B4 loopback as B5.

## 2. Export the real BD from an open Vivado project

The scripts are already committed in this repository. The original export commands below are for auditing/re-exporting a known-good source project; you **do not need to re-export** before rebuilding from the already committed snapshots.

### Packaged-IP project

1. In Vivado 2024.2 **open your existing known-good packaged-IP loopback project**. It must have top `difi_ip_test_wrapper` and BD `difi_ip_test`.
2. Paste these **two separate Tcl Console lines**:

```tcl
source D:/Study/project/DIFI/scripts/vivado/export_bd.tcl
difi::export_bd packaged_ip
```

### B5 raw-packet export project

1. **Open the existing B5 raw-packet export Vivado project**, NOT the B4 TX→RX loopback and NOT the packaged-IP loopback. Top is `difi_system_wrapper` and BD is `difi_system`.
2. Run:

```tcl
source D:/Study/project/DIFI/scripts/vivado/export_bd.tcl
difi::export_bd b5_raw_export
```

The following real snapshot files **are already present in the repository** (re-exporting replaces the snapshot and requires renewed comparison):

```text
scripts/vivado/
├── export_bd.tcl
├── rebuild_bd.tcl
├── README.md
└── generated/
    ├── packaged_ip/
    │   ├── bd.tcl             (real exported snapshot; committed)
    │   ├── manifest.tcl       (generated locally; must check in)
    │   ├── export_info.txt    (audit)
    │   └── constraints/      (if user XDCs exist)
    └── b5_raw_export/
        ├── bd.tcl
        ├── manifest.tcl
        ├── export_info.txt
        └── constraints/
```

This uses AMD Vivado `write_bd_tcl -force`, preserving **actual** PS configuration, IP parameters, AXI connections and address segments rather than inventing them. The `manifest.tcl` records the part, version, design, top and copied project XDC names. `export_info.txt` records BD cell names/VLNVs and original custom-IP search paths for review.

**After export:** inspect `bd.tcl` and `export_info.txt` for absolute external paths or required custom IP repositories. `write_bd_tcl` is an automation aid, not a guarantee that external dependencies magically become relocatable. Make sure B5 PS GEM0/PHY MIO configuration matches your working board.

## 3. Rebuild an independent fresh Vivado project

**Close Vivado**, then in Windows PowerShell, from your DIFI checkout root:

```powershell
cd D:\Study\project\DIFI

# Replace with the actual path to vivado.bat/vivado.exe if not on PATH.
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs packaged_ip
```

Or for B5:

```powershell
vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b5_raw_export
```

Outputs (ignored by `.gitignore`):

```text
vivado/rebuilt/packaged_ip/difi_rebuilt_packaged_ip.xpr
vivado/rebuilt/b5_raw_export/difi_rebuilt_b5_raw_export.xpr
```

The script:

1. Requires the already committed, **real exported** `bd.tcl` and `manifest.tcl`; does not fabricate design data.
2. Rejects a mismatched Vivado version or existing output project directory.
3. Rebuilds the relevant custom RTL/IP dependency **before** sourcing the original BD Tcl.
4. Runs `validate_bd_design`, copies saved XDCs into the constraints fileset, generates IP targets, makes an HDL wrapper and updates compile order.
5. Stops **before** synthesis, implementation and bitstream generation. A passing message means only that the **new Block Design validates**.

For packaged IP, `ip_repo/difi_engine_ip/component.xml` must exist and match the exported custom IP. For B5, the committed `rtl/` sources and `rtl/board/difi_engine_board_b5.v` must be compatible with the exported module-reference ports. Rebuilding requires the original source to have been synchronized with the committed RTL/IP version.

**If Vivado reports missing IP or incorrect ports**, first inspect the exported `export_info.txt` and your current IP repository. Do not 'fix' the error by quietly changing PS/PL wiring without updating the evidence and rerunning tests.

## 4. Verify post-rebuild implementation and XSA

After a **new, independent** BD rebuild, use the committed implementation script from a fresh Vivado 2024.2 batch session:

```powershell
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs packaged_ip
vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b5_raw_export
```

The script starts synthesis and implementation through bitstream generation, writes timing/utilization/DRC/clock reports, checks timing, exports a bitstream-containing XSA, and writes `report/results/vivado_rebuild/<target>/SUCCESS.txt`. **It refuses to overwrite an existing SUCCESS.txt**; to re-run a target, review/archive previous evidence and handle its generated rebuild directory deliberately. Do not run the commands above blindly in the current, already verified workspace.

Actual archived outcomes:

| Target | Post-route WNS | Post-route WHS | XSA / Bitstream | Board status |
| --- | ---: | ---: | --- | --- |
| `packaged_ip` | +0.411 ns | +0.046 ns | Generated, Vivado PASS | Developer confirmed PASS; raw new-XSA UART/Vitis evidence to archive |
| `b5_raw_export` | +2.206 ns | +0.021 ns | Generated, Vivado PASS | Developer confirmed PASS; raw new-XSA PC/UART evidence to archive |

Evidence: [`packaged_ip/SUCCESS.txt`](../../report/results/vivado_rebuild/packaged_ip/SUCCESS.txt) and [`b5_raw_export/SUCCESS.txt`](../../report/results/vivado_rebuild/b5_raw_export/SUCCESS.txt). The SUCCESS file is a **tool-build acceptance**, not itself a board test certificate. The archived user-reported board test happened after those files were generated.

Open each **new** XPR in Vivado 2024.2 when inspecting the reconstructed design. Compare these parameters with the original proven implementation:

- Device: `xc7z020clg400-2`, PL clock 100 MHz, PS CPU approximately 666.667 MHz.
- B5: PS GEM0 interface and board-specific MIO/PHY config; DMA MM2S IQ → `difi_board_raw_packet_export` → DMA S2MM **raw** DIFI packet.
- Packaged IP: TX Packet → RX Packet internal loopback; DMA S2MM **decoded IQ**.
- Correct AXI4-Lite control/time address map (test software commonly uses `0x40000000` / `0x40001000`, must match Address Editor), DMA device location, interrupt configuration, constraints.

The archived runs **have already completed** implementation/bitstream generation and XSA export using `verify_rebuilt_impl.tcl`. For any **new** reproduction, rebind the newly generated XSA in a Vitis 2024.2 SDT Platform, enable `lwip220` for B5 networking, download the matching bitstream and execute the benchmark/UDP acceptance programs. Vivado-only PASS never substitutes for this board-level step; on-board developer confirmations and missing original fresh-XSA runtime logs must be kept distinct.

Original evidence to compare:

- `report/results/packaged_ip_impl/{utilization,timing_summary}.rpt`
- `report/results/b5_impl/{utilization,timing_summary}.rpt`
- `report/results/udp/validation_notes.md`

## 5. Commit only source and the exported snapshots

```powershell
git status --short
git add scripts/vivado
# Review the diff / exported files (including any original machine paths) before committing.
git diff --cached --stat
git commit -m "build(vivado): export and reproduce packaged-IP and B5 block designs"
git push origin feature/rtl-integration
```

Do not commit `vivado/rebuilt/`, regenerated IP cache, synthesized run files, or private external library paths; these are output artifacts, not portable source.

## 6. Diagnostic checklist

| Error | What to check |
|---|---|
| `TOP ... expected ...` | Wrong original Vivado project (packaged IP vs B4 vs B5). |
| `unknown command open_bd_design` | Confirm Vivado IP Integrator commands are available; try `help open_bd_design` and `open_bd_design <bd_file>`. |
| `B5 ... not found` | Original project does not include B5 export RTL/module; open verified B5 project. |
| `Missing .../bd.tcl` | Haven't run `export_bd.tcl` from the **real** project, or not committed its output. |
| `Missing custom IP` | `ip_repo/` out of sync, or original project needed additional external IP repositories. |
| `module reference not found` | Source RTL list/version doesn't match the BD snapshot. |
| `validate_bd_design` fails | The project isn't yet reproduced; inspect PS settings, IP VLNVs, AXI and source dependencies. |
| Rebuilt project validates but ELF fails | BD validation is not a substitute for implementation, XSA matching or Standalone/lwIP BSP configuration. |
