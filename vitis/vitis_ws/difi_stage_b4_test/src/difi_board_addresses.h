#ifndef DIFI_BOARD_ADDRESSES_H
#define DIFI_BOARD_ADDRESSES_H

#include "xparameters.h"

#define DIFI_CTRL_BASE  0x40000000U
#define DIFI_TIME_BASE  0x40001000U

#if DIFI_CTRL_BASE == DIFI_TIME_BASE
#error "S_AXI_CTRL and S_AXI_TIME must have different base addresses"
#endif

#endif
