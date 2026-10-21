`ifndef DIFI_TIME_CFG_REGMAP_VH
`define DIFI_TIME_CFG_REGMAP_VH

`define DIFI_TIME_REG_SEC                8'h00 
`define DIFI_TIME_REG_PS_LO              8'h04 
`define DIFI_TIME_REG_PS_HI              8'h08 
`define DIFI_TIME_REG_COMMAND            8'h0C 
`define DIFI_TIME_REG_STATUS             8'h10 

`define DIFI_TIME_CMD_LOAD_BIT           0
`define DIFI_TIME_STATUS_VALID_BIT       0
`define DIFI_TIME_STATUS_ERROR_BIT       1

`define DIFI_TIME_AXI_OKAY               2'b00
`define DIFI_TIME_AXI_SLVERR             2'b10
`define DIFI_TIME_AXI_DECERR             2'b11

`define DIFI_TIME_DEFAULT_SHADOW_SEC      32'd0
`define DIFI_TIME_DEFAULT_SHADOW_PS       64'd0
`define DIFI_TIME_DEFAULT_LAST_ERROR      1'b0

// Time within the second, in picoseconds.
`define DIFI_TIME_PS_PER_SECOND           64'd1_000_000_000_000

// Execute the command when WSTRB[0] and the load bit are set; reads return zero.

`endif
