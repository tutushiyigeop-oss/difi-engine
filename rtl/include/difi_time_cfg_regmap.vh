`ifndef DIFI_TIME_CFG_REGMAP_VH
`define DIFI_TIME_CFG_REGMAP_VH

// -----------------------------------------------------------------------------
// Independent DIFI UTC time initialization AXI4-Lite peripheral.
// Register addresses are 8-bit BYTE OFFSETS from S_AXI_TIME base (0x00..0xFF).
// Independent from difi_cfg_regmap.vh and its S_AXI_CTRL address space.
// Verilog-2001 / single aclk domain / WSTRB applies to RW Shadow registers.
// -----------------------------------------------------------------------------

// Register offsets
`define DIFI_TIME_REG_SEC                8'h00 // RW, UTC seconds shadow
`define DIFI_TIME_REG_PS_LO              8'h04 // RW, ps shadow [31:0]
`define DIFI_TIME_REG_PS_HI              8'h08 // RW, ps shadow [63:32]
`define DIFI_TIME_REG_COMMAND            8'h0C // WO/W1P, bit 0: atomic load
`define DIFI_TIME_REG_STATUS             8'h10 // RO, status

// Command/status bits
`define DIFI_TIME_CMD_LOAD_BIT           0
`define DIFI_TIME_STATUS_VALID_BIT       0
`define DIFI_TIME_STATUS_ERROR_BIT       1

// AXI responses; intentionally namespaced to avoid macro collision.
`define DIFI_TIME_AXI_OKAY               2'b00
`define DIFI_TIME_AXI_SLVERR             2'b10
`define DIFI_TIME_AXI_DECERR             2'b11

// Reset defaults
`define DIFI_TIME_DEFAULT_SHADOW_SEC      32'd0
`define DIFI_TIME_DEFAULT_SHADOW_PS       64'd0
`define DIFI_TIME_DEFAULT_LAST_ERROR      1'b0

// Physical seconds in picoseconds (64-bit unsigned).
`define DIFI_TIME_PS_PER_SECOND           64'd1_000_000_000_000

// Undefined/misaligned 8-bit offsets: DECERR.
// TIME_STATUS writes: SLVERR. Invalid load_ps: SLVERR, sticky error.
// COMMAND write requires WSTRB[0] && WDATA[LOAD_BIT]; reads return 0.
// Success clears LAST_ERROR; shadow writes do not clear it.
`endif
