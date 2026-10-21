`ifndef DIFI_V1_1_DEFS_VH
`define DIFI_V1_1_DEFS_VH

`define DIFI_CLASS_ID_PRESENT       1'b1

`define DIFI_PROFILE_BITS           2'b00

`define DIFI_TSI_UTC                2'b01

// The fractional timestamp is in picoseconds.
`define DIFI_TSF_REALTIME_PS        2'b10

`define DIFI_OUI_WORD               32'h006A_621E

`define DIFI_ZERO_WORD              32'h0000_0000

`define DIFI_TKEEP_FULL             4'b1111

`define DIFI_FREQ_FRAC_BITS         6'd20

`define DIFI_DATA_PKT_TYPE          4'h1

`define DIFI_DATA_TSM               1'b0

`define DIFI_DATA_CLASS_WORD        32'h0000_0000

`define DIFI_DATA_PROLOGUE_WORDS    16'd7

`define DIFI_DATA_MAX_SAMPLES       16'd256

`define DIFI_CONTEXT_PKT_TYPE       4'h4

`define DIFI_CONTEXT_TSM            1'b1

`define DIFI_CONTEXT_HEADER_BASE    32'h4960_001B

`define DIFI_CONTEXT_PKT_WORDS      16'd27

`define DIFI_CONTEXT_LAST_WORD      5'd26

`define DIFI_CONTEXT_CLASS_WORD     32'h0000_0001

`define DIFI_CONTEXT_REF_POINT      32'h0000_0064

`define DIFI_CONTEXT_CIF_CHANGED    32'hFBB9_8000

`define DIFI_CONTEXT_CIF_NO_CHANGE  32'h7BB9_8000

`define DIFI_CONTEXT_DPF_WORD0      32'hA000_03CF

`define DIFI_CONTEXT_DPF_WORD1      32'h0000_0000

// Encode frequency fields by shifting the Hz value left by DIFI_FREQ_FRAC_BITS.

`define DIFI_VERSION_PKT_TYPE       4'h5

`define DIFI_VERSION_TSM            1'b1

`define DIFI_VERSION_HEADER_BASE    32'h5960_000B

`define DIFI_VERSION_PKT_WORDS      16'd11

`define DIFI_VERSION_LAST_WORD      5'd10

`define DIFI_VERSION_CLASS_WORD     32'h0001_0004

`define DIFI_VERSION_CIF_CHANGED    32'h8000_0002

`define DIFI_VERSION_CIF_NO_CHANGE  32'h0000_0002

`define DIFI_VERSION_CIF1_WORD      32'h0000_000C

`define DIFI_VERSION_V49_SPEC_WORD  32'h0000_0004

// [31:25] Build Year Offset = build_year - 2000
// [24:16] Build Day of Year = 1..366
// [15:10] Revision
// [ 9: 6] Type
// [ 5: 0] ICD Version

// Module parameters set the build year and day.

`define DIFI_VERSION_REVISION       6'd1
`define DIFI_VERSION_TYPE           4'd0
`define DIFI_VERSION_ICD_VERSION    6'd0

// Mark the first packet after reset as changed and later packets as unchanged.

// Changing VERSION_STREAM_ID at runtime does not set the changed flag again.

`define DIFI_ERR_UNSUPPORTED_TYPE   4'h1

`define DIFI_ERR_HEADER             4'h2

`define DIFI_ERR_SIZE               4'h3

`define DIFI_ERR_CLASS              4'h4

`define DIFI_ERR_STREAM_ID          4'h5

// Report sequence discontinuities without discarding the packet.
`define DIFI_ERR_SEQ                4'h6

`define DIFI_ERR_TRUNCATED          4'h7

`define DIFI_ERR_CONTEXT_FIELD      4'h8

`define DIFI_ERR_VERSION_FIELD      4'h9

`endif 