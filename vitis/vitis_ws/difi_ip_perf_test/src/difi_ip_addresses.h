#ifndef DIFI_IP_ADDRESSES_H
#define DIFI_IP_ADDRESSES_H
/* Verify against the exact XSA / Vivado Address Editor in use. */
#define DIFI_CTRL_BASE 0x40000000U
#define DIFI_TIME_BASE 0x40001000U
#if DIFI_CTRL_BASE == DIFI_TIME_BASE
#error "DIFI CTRL and TIME bases must differ"
#endif
#endif
