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

`endif