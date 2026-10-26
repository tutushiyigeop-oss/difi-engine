# Stage D v0.4 — SDU4 custom-IQ firmware protocol

Source: `firmware/stage_d_v04/src/`. This is an independent application for the **existing Stage D dual-DMA hardware**. The v0.3 source/ELF, RTL, Block Design, bitstream and XSA are not modified. Building the application does not download or run it on the board.

**Evidence boundary:** the new application has been compiled and linked with the installed Vitis 2024.2 Cortex-A9 toolchain and the existing Stage D standalone/lwIP BSP. Portable protocol tests have executed under Windows MSVC. These are software/build results; **v0.4 physical-board acceptance remains pending**.

## Existing hardware and actual data paths

| Direction | Real hardware path | Returned evidence |
|---|---|---|
| TX | Request's custom IQ → PS DDR → **DMA1 MM2S** → PL DIFI packetizer → **DMA1 S2MM** | `PACKET` contains the actual PL-produced DIFI bytes, including auto-generated metadata |
| RX Data | Request's legal DIFI → PS DDR → **DMA0 MM2S** → PL parser → **DMA0 S2MM** | `IQ` contains the actual S2MM words, compared with the input payload |
| RX Version/Context | Request's legal DIFI → **DMA0 MM2S** → PL metadata parser → monitor → AXI GPIO → PS | `DONE` reports actual count/sequence/changed-bit checks and monitor snapshots |

No IQ returned to the PC is reconstructed with a Python/PS Golden generator. TX accepts arbitrary I16/Q16 bit patterns. The maximum is 256 samples, and the minimum is one sample. RX Data may contain **any legal 1–256 sample count**, independently of the current TX `samples` setting.

Hardware references: `rtl/data/difi_data_packetizer.v`, `rtl/data/difi_data_parser.v`, `rtl/context/difi_context_parser.v`, `rtl/version/difi_version_parser.v`, `rtl/tx/difi_tx_scheduler.v`, `rtl/common/difi_cfg_regs.v`, `rtl/include/difi_cfg_regmap.vh`, and `rtl/board/difi_b6_rx_meta_monitor.v`.

The addresses are unchanged: control `0x40000000`, UTC `0x40001000`, metadata monitor `0x41200000`, RX DMA0 `0x40400000`, TX DMA1 `0x40410000`. The firmware verifies the DMA0/DMA1 BSP mappings.

## Startup, UTC, and hardware limits

1. Manually load the existing matching Stage D bitstream and then the new v0.4 ELF. The firmware and build scripts do not program hardware.
2. The firmware requires a clean PL state. A valid UTC, enabled/busy TX engine, nonzero metadata counters/errors, or unquiescent DMA at ELF startup produces `STATE=FAULT REASON=WARM_PL_RELOAD_REQUIRED`. Reloading only the ELF after v0.3/v0.4 traffic cannot reconstruct unobservable PL TX startup/sequence state.
3. At clean startup, TX stays disabled, a safe default configuration is committed, and both periodic metadata intervals are zero. Client `CONFIG` is still required. The firmware does not start TX while initializing networking.
4. Load UTC exactly once per clean PL boot. It is independent of `OPEN`/`CLOSE`: closing a session does not reset the hardware clock. A later session reads `UTC=1` and must skip `UTC`.
5. There is no software sequence reset or Version-on-demand trigger in this hardware. The first TX after PL reset produces the scheduler's startup Version, then pending Context, then Data. A successful later configuration commit creates a pending changed Context, which is captured on the next TX. A Version SID change after startup does not itself generate a new Version packet. The UI must not offer standalone TX Version/Context as if such a trigger existed.

`difi_tx_scheduler.v` gives priority to startup Version, changed Context, pending periodic metadata, then Data. Firmware captures actual packets until Data arrives, checks their independent sequence counters, and limits capture to five packets. It never fabricates a metadata packet to complete a requested flow. Periodic intervals are held at zero; first metadata starts also clear any previously latched periodic pending flags.

## Discovery and session lifecycle

The board listens at **192.168.1.10:4991**, netmask `/24`, gateway `192.168.1.1`. PC source IP/port is learned from `OPEN`.

Send the six ASCII bytes `STATUS` before sending any v4-only command. This is read-only discovery and is also understood by the older v0.3 application. A v4 response starts with:

```text
STATUS PROTO=4 STATE=READY UTC=0 SESSION=0 CONFIGURED=0 NEXT_DATA=0 NEXT_CONTEXT=0 NEXT_VERSION=0 RX_DATA_NEXT=0 RX_CONTEXT_NEXT=0 RX_VERSION_NEXT=0 ENGINE=... MON_COUNT=... MON_DETAIL=... REASON=NONE
```

`STATE` can be `READY`, `TX_ACTIVE`, `RX_ACTIVE`, or `FAULT`. UDP is serviced in the main loop; a request queued while a bounded DMA operation runs may be answered after that operation finishes. An old v0.3 response without `PROTO=4` must not be treated as supporting custom v4 requests.

Choose a new, nonzero 32-bit session ID and a nonzero transaction ID. A normal flow is:

```text
ASCII STATUS → CAPS → OPEN → CONFIG → UTC (only if UTC=0)
             → TX and/or RX transactions → STATUS → CLOSE
```

CONFIG and UTC may be issued in either order while hardware is safely idle. TX/RX require both a successful CONFIG in the current session and valid UTC.

`OPEN` binds the session to the source **IP address and UDP port**. All operational requests must match both peer and session. Transaction IDs strictly increase, including control requests; a duplicate or older ID receives `ERROR DUPLICATE_TXID` and cannot re-execute TX/RX. IDs are consumed **before** applying a valid operation, including operations rejected later for invalid configuration or packet contents. Do not retransmit a TX/RX after a timeout expecting another DMA execution: its outcome is unknown to that client until reconciled with status/evidence. The server does not cache/replay successful multi-frame replies.

CAPS may precede OPEN using the chosen nonzero session ID. An outstanding discovery probe tracks its peer/session/last transaction ID. After OPEN, CAPS has the same bound-peer and monotonic-ID checks as all other operations. ASCII STATUS remains public and read-only.

The firmware remembers up to 64 opened session IDs for the lifetime of its clean boot, rejecting reuse after CLOSE to prevent delayed packets from reopening and replaying old DMA transactions. Exhaustion returns `SESSION_LIMIT`; it does not silently discard replay protection. Use fresh IDs. Hardware TX/RX sequence counters persist across CLOSE/OPEN/config changes. There is no idle peer takeover or time-based expiry.

## Binary envelope

All integers and all returned DIFI/IQ words are **big-endian**. The header is 24 bytes, equivalent to Python `struct.Struct('!4sBBHIIII')`.

| Offset | Bytes | Field | Value |
|---:|---:|---|---|
| 0 | 4 | Magic | ASCII `SDU4` |
| 4 | 1 | Version | `4` |
| 5 | 1 | Operation | Table below |
| 6 | 2 | Flags | Must be zero |
| 8 | 4 | Session | Client-selected nonzero ID; echoed in replies |
| 12 | 4 | Transaction | Strictly increasing nonzero ID; echoed in replies |
| 16 | 4 | Payload length | Must exactly equal datagram size minus 24 |
| 20 | 4 | Code | Requests/success replies: `0`; ERROR: nonzero |

No trailing bytes, unknown version, reserved flags, unknown operation, nonzero request code, or oversized payload are accepted. Maximum payload is 1,052 bytes; maximum framed datagram is 1,076 bytes.

| Request | Value | Payload | Successful reply |
|---|---:|---|---|
| CAPS | `0x01` | Empty | `0x81`, ASCII capabilities |
| OPEN | `0x02` | Empty | `0x82`, ASCII status with bound `SESSION` |
| CONFIG | `0x03` | 40-byte configuration below | `0x83`, verified active configuration |
| UTC | `0x04` | `!II`: seconds, nanoseconds | `0x84`, `STATE=READY UTC=1` |
| TX | `0x05` | N custom network-order I16/Q16 words | One or more `0x90 PACKET`, then `0x92 DONE` |
| RX | `0x06` | One complete legal DIFI packet | Data: `0x91 IQ`, then `0x92 DONE`; metadata: `0x92 DONE` |
| STATUS | `0x07` | Empty | `0x87`, ASCII status |
| CLOSE | `0x08` | Empty | `0x88`, ASCII status with `SESSION=0` |
| ERROR | `0xff` | ASCII reason/state | Nonzero error code in header |

TX/RX do not use `0x85`/`0x86` acknowledgements. Every result fragment for a transaction echoes that transaction's session/ID. UDP does not guarantee order or delivery; clients must correlate the exact identities, recognize actual packet types, and require both the expected data fragments and DONE before claiming success. All actual S2MM IQ samples must be received and compared.

CAPS payload:

```text
PROTO=4 MIN_SAMPLES=1 MAX_SAMPLES=256 CUSTOM_TX=1 CUSTOM_RX=1 TX_TYPES=DATA RX_TYPES=VERSION,CONTEXT,DATA AUTO_META=1 VERSION_ON_DEMAND=0 CONFIG=1 UTC_ONCE=1 SEQUENCE_RESET=0 MAX_SESSIONS=64
```

## CONFIG and readback

CONFIG is exactly `!IIIIIQIII` (40 bytes):

| Offset | Type | Field | Constraint |
|---:|---|---|---|
| 0 | u32 | Data SID | Any 32-bit value |
| 4 | u32 | Version SID | Any 32-bit value |
| 8 | u32 | TX samples/packet | 1–256 |
| 12 | u32 | Sample rate, Hz | 1–2³²−1 |
| 16 | u32 | Bandwidth, Hz | 1–sample rate |
| 20 | u64 | RF frequency, Hz | 0–100,000,000,000 |
| 28 | u32 | RX filter | Bits 0=data/context, 1=version; no other bits |
| 32 | u32 | RX expected Data/Context SID | Any 32-bit value |
| 36 | u32 | RX expected Version SID | Any 32-bit value |

The firmware prevalidates values, checks all four DMA channels and disabled/not-busy TX, writes real shadow registers and immediate RX filters, issues COMMIT, polls pending/error state, and compares **every** active TX field and both zero periodic intervals plus all immediate RX filter registers. Configuration is not acknowledged solely because a write was attempted.

Example verified reply:

```text
STATE=READY DATA_SID=1 VERSION_SID=2 SAMPLES=37 FS=20000000 BW=10000000 RF_HZ=100000000 RX_FILTER=3 RX_DATA_SID=1 RX_VERSION_SID=2 CONTEXT_PENDING=1
```

## DIFI validation and independent sequences

Prevalidation runs before RX DMA submission. It checks exact datagram/Word0 size, packet type, class-present/profile/TSM/TSI/TSF bits, SID filters, OUI/class ID, and picosecond range. Context also checks changed/no-change CIF, reference point, all reserved zero fields, integer-Hz Q20 fields, positive/bounded sample rate and bandwidth, RF bound/sign and payload format. Version also checks CIF0/CIF1, V49 specification, day-of-year 1–366, revision/type/ICD. Invalid requests are rejected without arming an IQ S2MM transfer that could then stall after a PL drop.

TX and RX sequences are independent 4-bit per-type streams:

- `NEXT_DATA`, `NEXT_CONTEXT`, `NEXT_VERSION`: next expected actual TX packetizer/generator sequence.
- `RX_DATA_NEXT`, `RX_CONTEXT_NEXT`, `RX_VERSION_NEXT`: firmware's expected incoming RX sequence; initially zero, incremented modulo 16 only after actual PL acceptance and verification.

RX prevalidation requires the applicable RX next value, including the first packet. This is stricter than the RTL's unrestricted first sequence and prevents a sequence diagnostic from becoming an apparent valid comparison. Changing SID does not reset this firmware policy. Sending multiple manual TX packets before echoing one to RX can therefore produce `RX_SEQUENCE`; use the independent RX value in a custom packet. There is no automatic sequence rewrite of an edited DIFI packet.

DONE example:

```text
STATE=READY TYPE=DATA SEQ=0 SAMPLES=37 PACKETS=3 NEXT_DATA=1 NEXT_CONTEXT=1 NEXT_VERSION=1 RX_DATA_NEXT=0 RX_CONTEXT_NEXT=0 RX_VERSION_NEXT=0 META=0 MON_COUNT=00000000 MON_DETAIL=00000000
```

For RX metadata, `SAMPLES=0 PACKETS=1 META=1` and TYPE is VERSION/CONTEXT. For TX, PACKETS counts actual captured Data plus auto metadata in that transaction. IQ samples are individual I/Q pairs (one 32-bit word each), not the count of scalar components.

GPIO monitor `MON_COUNT` is `[31:16] Version accepted`, `[15:0] Context accepted`. `MON_DETAIL` is `[31:28] Data errors`, `[27:24] dispatch errors`, `[23:20] Version errors`, `[19:16] Context errors`, `[9] Version changed`, `[8] Context changed`, `[7:4] Version sequence`, `[3:0] Context sequence`. RX metadata verifies the relevant count increments exactly once, the other count is stable, sequence/changed bits agree, and error counters do not change. Saturated observation counters are rejected instead of claimed as fresh acceptance evidence.

## DMA/cache safety and faults

The lwIP callback only stages a datagram into a bounded buffer. A separate working copy is processed in the main loop, allowing network polling during bounded DMA waits without overwriting the active command.

All DMA buffers are 64-byte aligned and reserve whole cache lines. Input buffers are flushed before MM2S. Receive buffers are initialized/flushed before S2MM and invalidated after completion. Packet and IQ lengths are checked against the actual S2MM length register. A submitted transfer must reach `IDLE`; fresh unstarted channels may be `HALTED=1, IDLE=0` only in the separate transition guard. No DMA reset is used to disguise a failed transfer as successful completion.

Before returning READY/DONE, the firmware disables TX, polls real scheduler busy/enabled status, and verifies all four DMA channels are halted or idle without error bits and no pending commit. An uncertain transfer, parser/metadata discrepancy, configuration readback failure or failed result transmission latches FAULT. No further operational request is allowed; ASCII STATUS remains available. Reload the existing Stage D hardware and ELF before acceptance retry. CLOSE only releases a healthy, safely idle session; it is not an abort command for a stalled DMA.

Error header codes: `1 BAD_FRAME`, `2 BAD_VERSION`, `3 BAD_FLAGS`, `4 BAD_LENGTH`, `5 BAD_OPERATION`, `6 BAD_SESSION`, `7 BAD_TXID`, `8 DUPLICATE_TXID`, `9 SESSION_PEER`, `10 SESSION_BUSY`, `11 NOT_OPEN`, `12 BAD_CONFIG`, `13 NOT_CONFIGURED`, `14 UTC_REQUIRED`, `15 UTC_ALREADY_SET`, `16 BAD_PACKET`, `17 RX_SEQUENCE`, `18 HW_FAULT`, `19 DMA_ERROR`, `20 UDP_ERROR`, `21 SESSION_REUSED`, `22 SESSION_LIMIT`, `23 BUSY`. Payload includes `STATE` and a more specific `REASON` where available. A malformed unframed command receives a plain error and never reaches DMA.

## Reproducible local build and tests

From the repository root, using native Windows Python:

```powershell
.venv\Scripts\python.exe firmware\stage_d_v04\build_firmware.py
.venv\Scripts\python.exe firmware\stage_d_v04\tests\run_tests.py
```

The build script uses the installed Vitis 2024.2 `arm-none-eabi-gcc.exe`, the read-only existing `difi_half_duplex_platform` standalone BSP, and a copied linker script. It compiles only the new `main.c`/`protocol.c` into ignored `firmware/stage_d_v04/build/`. Output includes `difi_stage_d_v04.elf`, map, object files and `build_manifest.json` containing source hashes, exact compiler/linker arguments, ELF hash and `programmed_hardware=false`. It invokes neither Vivado implementation nor a hardware debug/download command and does not rebuild the v0.3 component/platform.

On another Vitis 2024.2 machine, supply `--gcc <arm-none-eabi-gcc.exe> --bsp <matching standalone domain> --linker-script <matching Stage D lscript.ld>`. The supplied BSP must match the existing Stage D XSA, standalone Cortex-A9 hard-float, lwIP220 RAW_API `NO_SYS=1`, dual Simple DMA and GEM0. To prepare an independent BSP manually in Vitis Unified, create a **new** platform from the existing Stage D XSA and standalone Cortex-A9 domain, enable lwIP RAW_API, then pass its generated domain path. Keep the v0.3 workspace separate. No new bitstream or XSA is required for these software capabilities.

Portable tests use installed Windows MSVC `/std:c11 /W4 /WX` via `vcvars64.bat` on this machine; `--gcc <native gcc>` selects GCC instead. They verify byte-order/framing, lengths, transaction duplicate/wrap rejection, configuration boundaries, 1/2/255/256 sample packets, full Context/Version fields and malformed values. They do not emulate actual DMA or establish board acceptance.

Required physical acceptance after loading the existing matching hardware and new ELF: discover version; OPEN/config readback; one-time UTC; TX custom IQ at N=1,37,256 and both signed I/Q extremes; inspect actual startup/commit metadata; RX actual IQ at N=1,37,256; metadata count/changed/sequence checks; 15→0 wrap per direction/type; rejected malformed DIFI and wrong source/session/duplicate transaction without extra DMA; repeated TX/RX/config/close/open; and timeout/drain/FAULT behavior. Archive actual UART and PC logs with source/session/transaction IDs.
