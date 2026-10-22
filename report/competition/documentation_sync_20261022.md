# Documentation consistency update — 2026-10-22

> Target: `feature/rtl-integration`. This file records document-only changes. It is **not** a Skill acceptance report or a new FPGA test report.

## Confirmed and synchronized

| Topic | Current engineering evidence | Documentation correction |
| --- | --- | --- |
| Vivado BD export/rebuild | `scripts/vivado/generated/{packaged_ip,b5_raw_export}/` contains actual BD Tcl and manifests | Root README and `scripts/vivado/README.md` now state snapshots already exist, with real rebuild instructions |
| Implementation | `report/results/vivado_rebuild/*/SUCCESS.txt`: packaged WNS +0.411 ns/WHS +0.046 ns; B5 WNS +2.206 ns/WHS +0.021 ns; XSA/bitstream generated | Distinguish tool-level PASS from later developer-confirmed board regression and unarchived original run logs |
| Skills | Four populated Skill directories under `skill/` | All marked **authored, pending integrated real-world/cross-project acceptance** |
| Performance | `report/results/perf/board_IP_perf.rtf` stores PMU ticks 2,729,306 and 636,916; developer subsequently reported PS CPU ≈666.667 MHz | `performance_summary.md` now gives conditional provenance and computed ~25.01/~107.18 MB/s, not raw measured PL throughput |
| AI collaboration | `report/ai_collaboration/` includes case studies and evidence pointers | Original verbatim model/user interactions still to be collected; retrospective summaries are not raw conversations |

## Outstanding release gates — intentionally not claimed completed

1. **License and distribution rights:** no root `LICENSE` yet. Decide copyright ownership, third-party IP/document dependencies and whether MIT/Apache-2.0 (or another permitted license) is appropriate **before** publishing. This update does not create a license on the author's behalf.
2. **Repository visibility:** repository currently private; default branch is `main`. When ready, decide whether/how to grant judge access, merge accepted changes to `main`, then pin a submission SHA or tag.
3. **Reproduced board logs:** original Vitis/UART/PC outputs from running the two **rebuilt** XSA/bitstreams should be saved with clear dates and hashes. Vivado `SUCCESS.txt` alone is not board evidence.
4. **PS clock provenance:** save a matching Vivado/PS clock configuration screenshot or equivalent auditable XSA/BD evidence for the ~666.667 MHz figure. Generated BD Tcl explicitly shows FCLK0=100 MHz; that is **not** proof of PS CPU frequency by itself.
5. **Skill validation:** the four newly created generic Skills have offline checks, but still need the planned combined real Vivado/Vitis/Icarus/network and cross-project evaluation.
6. **AI E1 dialogues:** export the original prompts and model replies for the five case studies, retaining corrections and timestamps.
7. **External reproducibility:** existing project-specific Vivado runs passed, but fresh unrelated-machine end-to-end reproduction remains a separate acceptance step.
8. **Formal submission:** native Vivado BD screenshots, presentation/video, final report review, third-party license checks and judging access remain to be completed.

## Boundaries and non-actions

- No RTL, firmware or Vivado/Vitis output files were edited by this document sync.
- No `LICENSE` was silently chosen and no visibility/default-branch setting was changed.
- Files with English uppercase letters are **not inherently invalid** under the English-path requirement; non-ASCII characters, whitespace and problematic special characters should be audited separately.
- The sample Markdown link inside the fenced root-README snippet in `docs/architecture/README.md` is intentionally root-relative **example code**, not a broken live hyperlink in that document.
- Removed the root `INTEGRATION.md` packaging note after retaining actionable release status here.

## Next review

Use `report/competition/report_action_checklist.md`, `report/ai_collaboration/README.md`, and `skill/README.md`. Before release, run the repository audit tool and verify the fixed reference SHA, license/rights, and judge access.
