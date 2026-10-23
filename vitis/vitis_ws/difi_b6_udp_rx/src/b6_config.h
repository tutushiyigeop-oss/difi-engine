#ifndef DIFI_B6_CONFIG_H
#define DIFI_B6_CONFIG_H

/* Must match the B6 XSA Address Editor, NOT an unrelated B5/loopback XSA. */
#define B6_CTRL_BASE       0x40000000U

/* Copy the known-good B5 Ethernet setup for this board; adjust if needed. */
#define BOARD_IP0          192U
#define BOARD_IP1          168U
#define BOARD_IP2          1U
#define BOARD_IP3          10U
#define BOARD_NETMASK0     255U
#define BOARD_NETMASK1     255U
#define BOARD_NETMASK2     255U
#define BOARD_NETMASK3     0U
#define BOARD_GATEWAY0     192U
#define BOARD_GATEWAY1     168U
#define BOARD_GATEWAY2     1U
#define BOARD_GATEWAY3     1U
#define B6_UDP_PORT        4991U

/* Real MAC must be unique on your network; this is the B5 lab example. */
#define B6_MAC0 0x02U
#define B6_MAC1 0x0AU
#define B6_MAC2 0x35U
#define B6_MAC3 0x00U
#define B6_MAC4 0x01U
#define B6_MAC5 0x02U

/* Confirm from generated B6 XSA / processing_system7_0 / xparameters. */
#define B6_PS_CPU_HZ       666666667U
#define B6_TIMER_HZ       20U      /* 50 ms per SCU timer interrupt */
#define B6_DMA_TIMEOUT_TICKS 40U  /* 2 seconds if 50 ms timer runs */
#define B6_DMA_SPIN_LIMIT  150000000U /* backup guard if timer stalls */

#define B6_DATA_SID        1U
#define B6_VERSION_SID     2U
#define B6_IQ_SAMPLES      256U
#define B6_HEADER_WORDS    7U
#define B6_PACKET_WORDS    (B6_HEADER_WORDS + B6_IQ_SAMPLES)
#define B6_PACKET_BYTES    (4U * B6_PACKET_WORDS) /* 1052 bytes */
#define B6_IQ_BYTES        (4U * B6_IQ_SAMPLES)   /* 1024 bytes */
#define B6_DMA_PAD_WORDS   272U /* 1088 B; cache-line aligned buffer end */

/* RX registers: offsets from DIFI AXI4-Lite S_AXI_CTRL */
#define B6_REG_CONTROL     0x00U
#define B6_REG_RX_FILTER   0x34U
#define B6_REG_RX_DATA_SID 0x38U
#define B6_REG_RX_VER_SID  0x3CU

#endif
