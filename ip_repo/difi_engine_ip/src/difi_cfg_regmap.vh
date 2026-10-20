
`ifndef DIFI_CFG_REGMAP_VH
`define DIFI_CFG_REGMAP_VH

// ============================================================
// DIFI Engine - AXI4-Lite Configuration Register Map
//
// Register data width : 32 bits
// Register addr width : 8 bits
// Address space       : 0x00 - 0xFF
// Address alignment   : 4 bytes
//
// Addresses are offsets relative to the AXI4-Lite base address.
//
// TX configuration : Shadow -> Active via Commit
// RX configuration : Direct update
//
// Verilog-2001
// ============================================================


// ============================================================
// 1. Control / Command / Status Registers
// ============================================================

// RW: General control
`define DIFI_REG_CONTROL              8'h00

// WO: Write-one command
`define DIFI_REG_COMMAND              8'h04

// RO: Current engine status
`define DIFI_REG_STATUS               8'h08

// RO: Last configuration commit error
`define DIFI_REG_LAST_COMMIT_ERROR    8'h0C


// ============================================================
// 2. TX Shadow Configuration Registers
// ============================================================

// RW: Data / Context Stream ID
`define DIFI_REG_DATA_STREAM_ID       8'h10

// RW: Version Stream ID
`define DIFI_REG_VERSION_STREAM_ID    8'h14

// RW: Samples per Data Packet, bits [15:0]
`define DIFI_REG_SAMPLES_PER_PACKET   8'h18

// RW: Sample Rate (samples/s)
`define DIFI_REG_SAMPLE_RATE_HZ       8'h1C

// RW: Bandwidth (Hz)
`define DIFI_REG_BANDWIDTH_HZ         8'h20

// RW: RF Reference Frequency, low 32 bits
`define DIFI_REG_RF_FREQ_LOW          8'h24

// RW: RF Reference Frequency, high 32 bits
`define DIFI_REG_RF_FREQ_HIGH         8'h28

// RW: Context periodic interval (ms)
`define DIFI_REG_CONTEXT_PERIOD_MS    8'h2C

// RW: Version periodic interval (ms)
`define DIFI_REG_VERSION_PERIOD_MS    8'h30


// ============================================================
// 3. RX Filter Configuration Registers
// ============================================================

// RW: RX filter enable bits
`define DIFI_REG_RX_FILTER_CTRL       8'h34

// RW: Expected Data / Context Stream ID
`define DIFI_REG_RX_DATA_SID          8'h38

// RW: Expected Version Stream ID
`define DIFI_REG_RX_VERSION_SID       8'h3C


// ============================================================
// 4. TX Active Configuration Readback Registers
// ============================================================

// All registers in this section are read-only.

`define DIFI_REG_ACTIVE_DATA_SID      8'h40
`define DIFI_REG_ACTIVE_VERSION_SID   8'h44
`define DIFI_REG_ACTIVE_SAMPLES       8'h48
`define DIFI_REG_ACTIVE_SAMPLE_RATE   8'h4C
`define DIFI_REG_ACTIVE_BANDWIDTH     8'h50
`define DIFI_REG_ACTIVE_RF_LOW        8'h54
`define DIFI_REG_ACTIVE_RF_HIGH       8'h58
`define DIFI_REG_ACTIVE_CTX_PERIOD    8'h5C
`define DIFI_REG_ACTIVE_VER_PERIOD    8'h60


// ============================================================
// 5. CONTROL Register Bit Definitions
// Address: 0x00
// ============================================================

// Bit 0: TX Enable
// 1 = Allow Scheduler to start new packets
// 0 = Stop starting new packets
`define DIFI_CTRL_TX_ENABLE_BIT       0

// Bits [31:1]: Reserved, read as zero


// ============================================================
// 6. COMMAND Register Bit Definitions
// Address: 0x04
// ============================================================

// Bit 0: Configuration Commit
// Write 1 to request Shadow -> Active commit.
// Write 0 has no effect.
// This is a command, not a stored level bit.
`define DIFI_CMD_COMMIT_BIT           0

// Bits [31:1]: Reserved
// Reads return zero.


// ============================================================
// 7. STATUS Register Bit Definitions
// Address: 0x08
// ============================================================

// A commit is waiting for Scheduler ACK
`define DIFI_STATUS_COMMIT_PENDING_BIT    0

// A changed Context Packet must be announced
`define DIFI_STATUS_CTX_CHANGE_BIT        1

// Scheduler currently owns a TX packet
`define DIFI_STATUS_TX_BUSY_BIT           2

// Current TX enable state
`define DIFI_STATUS_TX_ENABLE_BIT         3

// External Time Source validity
`define DIFI_STATUS_TIME_VALID_BIT        4

// Last commit error is nonzero
`define DIFI_STATUS_COMMIT_ERROR_BIT      5

// Bits [31:6]: Reserved, read as zero


// ============================================================
// 8. RX_FILTER_CTRL Register Bit Definitions
// Address: 0x34
// ============================================================

// Enable Data and Context Stream ID filtering
`define DIFI_RX_FILTER_DATA_BIT       0

// Enable Version Stream ID filtering
`define DIFI_RX_FILTER_VERSION_BIT    1

// Bits [31:2]: Reserved, read as zero


// ============================================================
// 9. Configuration Commit Error Codes
// LAST_COMMIT_ERROR Register: 0x0C
//
// These are configuration errors, not DIFI parser errors.
// ============================================================

// No error
`define DIFI_COMMIT_ERR_NONE          32'd0

// Samples per packet outside 1..256
`define DIFI_COMMIT_ERR_SAMPLES       32'd1

// Sample Rate is zero
`define DIFI_COMMIT_ERR_SAMPLE_RATE   32'd2

// Bandwidth is zero or greater than Sample Rate
`define DIFI_COMMIT_ERR_BANDWIDTH     32'd3

// RF Frequency exceeds 100 GHz
`define DIFI_COMMIT_ERR_RF_FREQ       32'd4

// Another commit is already pending
`define DIFI_COMMIT_ERR_BUSY          32'd5


// ============================================================
// 10. Reset Default Values
// ============================================================

// Control
`define DIFI_CFG_DEFAULT_TX_ENABLE       1'b0

// TX Configuration
`define DIFI_CFG_DEFAULT_DATA_SID        32'h0000_0001
`define DIFI_CFG_DEFAULT_VERSION_SID     32'h0000_0002
`define DIFI_CFG_DEFAULT_SAMPLES         16'd256

`define DIFI_CFG_DEFAULT_SAMPLE_RATE     32'd1000000
`define DIFI_CFG_DEFAULT_BANDWIDTH       32'd1000000
`define DIFI_CFG_DEFAULT_RF_FREQ         64'd0

`define DIFI_CFG_DEFAULT_CTX_PERIOD      32'd1000
`define DIFI_CFG_DEFAULT_VER_PERIOD      32'd1000

// RX Configuration
`define DIFI_CFG_DEFAULT_RX_FILTER_CTRL  2'b00

`define DIFI_CFG_DEFAULT_RX_DATA_SID     32'h0000_0001
`define DIFI_CFG_DEFAULT_RX_VERSION_SID  32'h0000_0002

// Reset requires initial changed Context announcement.
// Commit request itself is cleared on reset.
`define DIFI_CFG_DEFAULT_CTX_PENDING     1'b1
`define DIFI_CFG_DEFAULT_COMMIT_REQ      1'b0

// Commit error
`define DIFI_CFG_DEFAULT_COMMIT_ERROR    32'd0


// ============================================================
// 11. Reserved Address Space
// ============================================================
//
// 0x64 - 0xFF : Reserved for future registers.
//
// Unmapped or unaligned accesses shall return DECERR.
// Writes to read-only registers shall return SLVERR.
//
// All register offsets are byte addresses.
// ============================================================

// ============================================================
// 12. BRESP/RRESP Encode
// ============================================================
`define BRESP_OKAY                       2'b00
`define BRESP_SLVERR                     2'b10
`define BRESP_DECERR                     2'b11
`define RRESP_OKAY                       2'b00
`define RRESP_SLVERR                     2'b10
`define RRESP_DECERR                     2'b11


`endif // DIFI_CFG_REGMAP_VH
