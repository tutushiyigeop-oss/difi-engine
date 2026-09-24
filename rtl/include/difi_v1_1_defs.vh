`ifndef DIFI_V1_1_DEFS_VH
`define DIFI_V1_1_DEFS_VH

// ============================================================
// DIFI 1.1 Protocol Definitions
// Project Profile: FPGA Digital IF Protocol Engine
//
// Supported packet types:
//   1. Signal Data Packet
//   2. Signal Context Packet
//   3. Version Context Packet
//
// All constants follow the frozen project specifications.
// ============================================================


// ============================================================
// 1. Common Protocol Definitions
// ============================================================

// ------------------------------------------------------------
// 1.1 Common Header Fields
// ------------------------------------------------------------

// Class ID Present
`define DIFI_CLASS_ID_PRESENT       1'b1

// Reserved / Profile Bits
`define DIFI_PROFILE_BITS           2'b00

// Timestamp Integer Type: UTC
`define DIFI_TSI_UTC                2'b01

// Timestamp Fractional Type: Real-Time (picoseconds)
`define DIFI_TSF_REALTIME_PS        2'b10


// ------------------------------------------------------------
// 1.2 Common Fixed Words
// ------------------------------------------------------------

// Organizationally Unique Identifier (OUI)
`define DIFI_OUI_WORD               32'h006A_621E

// Common zero-filled word
`define DIFI_ZERO_WORD              32'h0000_0000


// ------------------------------------------------------------
// 1.3 Common AXI4-Stream Definitions
// ------------------------------------------------------------

// All DIFI packet words are 32-bit aligned
`define DIFI_TKEEP_FULL             4'b1111


// ------------------------------------------------------------
// 1.4 Common Encoding Parameters
// ------------------------------------------------------------

// Frequency fields use 20 fractional bits:
// raw_value = frequency_hz << 20
`define DIFI_FREQ_FRAC_BITS         6'd20


// ============================================================
// 2. Signal Data Packet Definitions
// ============================================================

// ------------------------------------------------------------
// 2.1 Packet Type and Header
// ------------------------------------------------------------

`define DIFI_DATA_PKT_TYPE          4'h1

// Data Packet: TSM = 0
`define DIFI_DATA_TSM               1'b0


// ------------------------------------------------------------
// 2.2 Fixed Protocol Words
// ------------------------------------------------------------

// Word3: ICC = 0x0000, PCC = 0x0000
`define DIFI_DATA_CLASS_WORD        32'h0000_0000


// ------------------------------------------------------------
// 2.3 Packet Length and Project Limits
// ------------------------------------------------------------

// Number of words before IQ payload
`define DIFI_DATA_PROLOGUE_WORDS    16'd7

// Maximum number of I16/Q16 samples per packet
`define DIFI_DATA_MAX_SAMPLES       16'd256


// ============================================================
// 3. Signal Context Packet Definitions
// ============================================================

// ------------------------------------------------------------
// 3.1 Packet Type and Header
// ------------------------------------------------------------

`define DIFI_CONTEXT_PKT_TYPE       4'h4

// Context Packet: TSM = 1
`define DIFI_CONTEXT_TSM            1'b1

// Word0 base header, excluding the sequence number
// Type=4, C=1, TSM=1, TSI=UTC, TSF=Real-Time, Size=27
//
// Word0 = HEADER_BASE | (context_seq << 16)
`define DIFI_CONTEXT_HEADER_BASE    32'h4960_001B


// ------------------------------------------------------------
// 3.2 Packet Length
// ------------------------------------------------------------

// Fixed packet length: 27 words (108 bytes)
`define DIFI_CONTEXT_PKT_WORDS      16'd27

// Last word index: Word26
`define DIFI_CONTEXT_LAST_WORD      5'd26


// ------------------------------------------------------------
// 3.3 Fixed Protocol Words
// ------------------------------------------------------------

// Word3: ICC = 0x0000, PCC = 0x0001
`define DIFI_CONTEXT_CLASS_WORD     32'h0000_0001

// Word8: Reference Point Identifier
`define DIFI_CONTEXT_REF_POINT      32'h0000_0064


// ------------------------------------------------------------
// 3.4 Context Indicator Field (CIF0)
// ------------------------------------------------------------

// Word7: Context Change = 1
// Used for initial Context or configuration changes
`define DIFI_CONTEXT_CIF_CHANGED    32'hFBB9_8000

// Word7: Context Change = 0
// Used for periodic Context retransmission
`define DIFI_CONTEXT_CIF_NO_CHANGE  32'h7BB9_8000


// ------------------------------------------------------------
// 3.5 Data Packet Payload Format (DPF)
// ------------------------------------------------------------

// Word25: Link-efficient, complex Cartesian,
// signed fixed-point, I16/Q16
`define DIFI_CONTEXT_DPF_WORD0      32'hA000_03CF

// Word26: Repeat Count = 0, Vector Size = 0
`define DIFI_CONTEXT_DPF_WORD1      32'h0000_0000


// ------------------------------------------------------------
// 3.6 Other Fixed Context Fields
// ------------------------------------------------------------

// The following fields are fixed to zero in this project:
//
// Word11-12 : IF Reference Frequency
// Word15-16 : IF Band Offset
// Word17    : Reference Level
// Word18    : Gain / Attenuation
// Word21-22 : Timestamp Adjustment
// Word23    : Timestamp Calibration Time
// Word24    : State / Event Indicators
//
// Use `DIFI_ZERO_WORD for these fields.
//
// Dynamic fields:
// Word1     : Data Stream ID
// Word4-6   : Timestamp
// Word9-10  : Bandwidth
// Word13-14 : RF Reference Frequency
// Word19-20 : Sample Rate
//
// Dynamic frequency fields use:
// raw_value = zero_extended_frequency_hz <<
//             `DIFI_FREQ_FRAC_BITS
//
// Configuration validation belongs to the upstream cfg_regs.
// ============================================================


// ============================================================
// 4. Version Context Packet Definitions
// ============================================================

// ------------------------------------------------------------
// 4.1 Packet Type and Header
// ------------------------------------------------------------

`define DIFI_VERSION_PKT_TYPE       4'h5

// Version Context Packet: TSM = 1
`define DIFI_VERSION_TSM            1'b1

// Word0 base header, excluding the sequence number
// Type=5, C=1, TSM=1, TSI=UTC, TSF=Real-Time, Size=11
//
// Word0 = HEADER_BASE | (version_seq << 16)
`define DIFI_VERSION_HEADER_BASE    32'h5960_000B


// ------------------------------------------------------------
// 4.2 Packet Length
// ------------------------------------------------------------

// Fixed packet length: 11 words (44 bytes)
`define DIFI_VERSION_PKT_WORDS      16'd11

// Last word index: Word10
`define DIFI_VERSION_LAST_WORD      5'd10


// ------------------------------------------------------------
// 4.3 Fixed Protocol Words
// ------------------------------------------------------------

// Word3: ICC = 0x0001, PCC = 0x0004
`define DIFI_VERSION_CLASS_WORD     32'h0001_0004


// ------------------------------------------------------------
// 4.4 Context Indicator Fields
// ------------------------------------------------------------

// Word7: CIF0, Context Change = 1
// Used for the first complete Version Context Packet after reset
`define DIFI_VERSION_CIF_CHANGED    32'h8000_0002

// Word7: CIF0, Context Change = 0
// Used for subsequent periodic Version Context Packets
`define DIFI_VERSION_CIF_NO_CHANGE  32'h0000_0002

// Word8: CIF1
`define DIFI_VERSION_CIF1_WORD      32'h0000_000C


// ------------------------------------------------------------
// 4.5 VITA 49.2 Specification Version
// ------------------------------------------------------------

// Word9: VITA 49.2 Specification Version
`define DIFI_VERSION_V49_SPEC_WORD  32'h0000_0004


// ------------------------------------------------------------
// 4.6 Version Information
// ------------------------------------------------------------

// Word10 layout:
//
// [31:25] Build Year Offset = build_year - 2000
// [24:16] Build Day of Year = 1..366
// [15:10] Revision
// [ 9: 6] Type
// [ 5: 0] ICD Version
//
// Build Year Offset and Build Day of Year are compile-time
// parameters of difi_version_generator and are therefore not
// defined as fixed protocol constants here.
//
// DIFI 1.1 project profile fixes:
// Revision = 1
// Type     = 0
// ICD      = 0

`define DIFI_VERSION_REVISION       6'd1
`define DIFI_VERSION_TYPE           4'd0
`define DIFI_VERSION_ICD_VERSION    6'd0


// ------------------------------------------------------------
// 4.7 Version Packet Word Map
// ------------------------------------------------------------

// Word0     : Header
// Word1     : Version Stream ID
// Word2     : OUI
// Word3     : ICC / PCC
// Word4     : Integer Timestamp
// Word5-6   : Fractional Timestamp
// Word7     : CIF0
// Word8     : CIF1
// Word9     : VITA 49.2 Specification Version
// Word10    : Version Information
//
// Dynamic fields:
// Word0     : Version Sequence Number
// Word1     : Version Stream ID
// Word4-6   : Timestamp
//
// Compile-time fields:
// Word10    : Build Year Offset / Build Day of Year
//
// first_version_pending is maintained internally by
// difi_version_generator:
//
//   first complete packet after reset:
//       CIF0 = `DIFI_VERSION_CIF_CHANGED
//
//   subsequent packets:
//       CIF0 = `DIFI_VERSION_CIF_NO_CHANGE
//
// Changing VERSION_STREAM_ID at runtime does not assert the
// Version Context Change bit again.
// ============================================================


// ============================================================
// 5. DIFI 1.1 Error Codes
// ============================================================

// ------------------------------------------------------------
// 5.1 Common Parser Error Codes
// ------------------------------------------------------------

// Unsupported packet type
`define DIFI_ERR_UNSUPPORTED_TYPE   4'h1

// Invalid fixed header fields (C / Reserved / TSM / TSI / TSF)
`define DIFI_ERR_HEADER             4'h2

// Invalid packet size, length mismatch, or invalid TKEEP
`define DIFI_ERR_SIZE               4'h3

// Invalid OUI, ICC, or PCC
`define DIFI_ERR_CLASS              4'h4

// Stream ID mismatch when filtering is enabled
`define DIFI_ERR_STREAM_ID          4'h5

// Sequence discontinuity (report only, do not discard)
`define DIFI_ERR_SEQ                4'h6

// TLAST asserted before the declared packet length
`define DIFI_ERR_TRUNCATED          4'h7


// ------------------------------------------------------------
// 5.2 Signal Context Parser Error Codes
// ------------------------------------------------------------

// Invalid CIF0, Reference Point, frequency fields,
// Data Packet Payload Format, or timestamp
`define DIFI_ERR_CONTEXT_FIELD      4'h8


// ------------------------------------------------------------
// 5.3 Version Context Parser Error Codes
// ------------------------------------------------------------

// Invalid Version CIF, VITA version, build information,
// or timestamp
`define DIFI_ERR_VERSION_FIELD      4'h9


// ------------------------------------------------------------
// 5.4 Reserved Error Codes
// ------------------------------------------------------------

// 4'hA - 4'hF: Reserved for future extensions


`endif // DIFI_V1_1_DEFS_VH