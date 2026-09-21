`ifndef DIFI_V1_1_DEFS_VH
`define DIFI_V1_1_DEFS_VH

// ============================================================
// DIFI 1.1 common definitions
// ============================================================

// Signal Data Packet
`define DIFI_DATA_PKT_TYPE       4'h1

// Header fixed fields
`define DIFI_CLASS_ID_PRESENT    1'b1
`define DIFI_PROFILE_BITS        2'b00
`define DIFI_DATA_TSM            1'b0
`define DIFI_TSI_UTC             2'b01
`define DIFI_TSF_REALTIME_PS     2'b10

// Signal Data fixed words
`define DIFI_OUI_WORD            32'h006A_621E
`define DIFI_DATA_CLASS_WORD     32'h0000_0000

// Number of words before IQ payload
`define DIFI_DATA_PROLOGUE_WORDS 16'd7

// Project limits
`define DIFI_DATA_MAX_SAMPLES    16'd256

// ============================================================
// DIFI 1.1 Error Codes
// ============================================================

// Unsupported packet type (Packet Type != 1)
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

// Reserved: 4'h8 ~ 4'hF

`endif