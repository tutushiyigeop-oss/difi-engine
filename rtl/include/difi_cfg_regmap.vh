`ifndef DIFI_CFG_REGMAP_VH
`define DIFI_CFG_REGMAP_VH

// Addresses are 4-byte aligned.

// All addresses below are byte offsets from the base address.

// TX configuration takes effect after commit.
// RX configuration takes effect immediately.

`define DIFI_REG_CONTROL              8'h00

`define DIFI_REG_COMMAND              8'h04

`define DIFI_REG_STATUS               8'h08

`define DIFI_REG_LAST_COMMIT_ERROR    8'h0C

`define DIFI_REG_DATA_STREAM_ID       8'h10

`define DIFI_REG_VERSION_STREAM_ID    8'h14

// The low 16 bits hold the samples per packet.
`define DIFI_REG_SAMPLES_PER_PACKET   8'h18

// Sample rate in samples per second.
`define DIFI_REG_SAMPLE_RATE_HZ       8'h1C

// Bandwidth in Hz.
`define DIFI_REG_BANDWIDTH_HZ         8'h20

`define DIFI_REG_RF_FREQ_LOW          8'h24

`define DIFI_REG_RF_FREQ_HIGH         8'h28

`define DIFI_REG_CONTEXT_PERIOD_MS    8'h2C

`define DIFI_REG_VERSION_PERIOD_MS    8'h30

`define DIFI_REG_RX_FILTER_CTRL       8'h34

`define DIFI_REG_RX_DATA_SID          8'h38

`define DIFI_REG_RX_VERSION_SID       8'h3C

`define DIFI_REG_ACTIVE_DATA_SID      8'h40
`define DIFI_REG_ACTIVE_VERSION_SID   8'h44
`define DIFI_REG_ACTIVE_SAMPLES       8'h48
`define DIFI_REG_ACTIVE_SAMPLE_RATE   8'h4C
`define DIFI_REG_ACTIVE_BANDWIDTH     8'h50
`define DIFI_REG_ACTIVE_RF_LOW        8'h54
`define DIFI_REG_ACTIVE_RF_HIGH       8'h58
`define DIFI_REG_ACTIVE_CTX_PERIOD    8'h5C
`define DIFI_REG_ACTIVE_VER_PERIOD    8'h60

`define DIFI_CTRL_TX_ENABLE_BIT       0

// [31:1] reserved; reads return zero.

`define DIFI_CMD_COMMIT_BIT           0

// [31:1] reserved.

`define DIFI_STATUS_COMMIT_PENDING_BIT    0

// Wait to send the changed Context packet.
`define DIFI_STATUS_CTX_CHANGE_BIT        1

`define DIFI_STATUS_TX_BUSY_BIT           2

`define DIFI_STATUS_TX_ENABLE_BIT         3

`define DIFI_STATUS_TIME_VALID_BIT        4

`define DIFI_STATUS_COMMIT_ERROR_BIT      5

// [31:6] reserved; reads return zero.

`define DIFI_RX_FILTER_DATA_BIT       0

`define DIFI_RX_FILTER_VERSION_BIT    1

// [31:2] reserved; reads return zero.

`define DIFI_COMMIT_ERR_NONE          32'd0

// Each packet must contain 1..256 samples.
`define DIFI_COMMIT_ERR_SAMPLES       32'd1

`define DIFI_COMMIT_ERR_SAMPLE_RATE   32'd2

// Bandwidth must be positive and no greater than the sample rate.
`define DIFI_COMMIT_ERR_BANDWIDTH     32'd3

// The RF frequency limit is 100 GHz.
`define DIFI_COMMIT_ERR_RF_FREQ       32'd4

`define DIFI_COMMIT_ERR_BUSY          32'd5

`define DIFI_CFG_DEFAULT_TX_ENABLE       1'b0

`define DIFI_CFG_DEFAULT_DATA_SID        32'h0000_0001
`define DIFI_CFG_DEFAULT_VERSION_SID     32'h0000_0002
`define DIFI_CFG_DEFAULT_SAMPLES         16'd256

`define DIFI_CFG_DEFAULT_SAMPLE_RATE     32'd1000000
`define DIFI_CFG_DEFAULT_BANDWIDTH       32'd1000000
`define DIFI_CFG_DEFAULT_RF_FREQ         64'd0

`define DIFI_CFG_DEFAULT_CTX_PERIOD      32'd1000
`define DIFI_CFG_DEFAULT_VER_PERIOD      32'd1000

`define DIFI_CFG_DEFAULT_RX_FILTER_CTRL  2'b00

`define DIFI_CFG_DEFAULT_RX_DATA_SID     32'h0000_0001
`define DIFI_CFG_DEFAULT_RX_VERSION_SID  32'h0000_0002

// Send an initial Context packet with the changed flag after reset.

`define DIFI_CFG_DEFAULT_CTX_PENDING     1'b1
`define DIFI_CFG_DEFAULT_COMMIT_REQ      1'b0

`define DIFI_CFG_DEFAULT_COMMIT_ERROR    32'd0

// Unmapped or unaligned accesses return DECERR.
// Writes to read-only registers return SLVERR.

`define BRESP_OKAY                       2'b00
`define BRESP_SLVERR                     2'b10
`define BRESP_DECERR                     2'b11
`define RRESP_OKAY                       2'b00
`define RRESP_SLVERR                     2'b10
`define RRESP_DECERR                     2'b11

`endif 
