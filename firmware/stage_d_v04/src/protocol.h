/* Stage D v0.4 wire/profile validation. Portable C99; no BSP dependencies. */
#ifndef STAGE_D_V04_PROTOCOL_H
#define STAGE_D_V04_PROTOCOL_H
#include <stddef.h>
#include <stdint.h>

#define SD4_HEADER 24U
#define SD4_MAX_SAMPLES 256U
#define SD4_MAX_WORDS 263U
#define SD4_MAX_PAYLOAD (SD4_MAX_WORDS * 4U)
#define SD4_MAX_FRAME (SD4_HEADER + SD4_MAX_PAYLOAD)
#define SD4_CONFIG_BYTES 40U
#define SD4_RF_MAX UINT64_C(100000000000)
enum sd4_op { SD4_CAPS=1, SD4_OPEN=2, SD4_CONFIG=3, SD4_UTC=4,
    SD4_TX=5, SD4_RX=6, SD4_STATUS=7, SD4_CLOSE=8,
    SD4_PACKET=0x90, SD4_IQ=0x91, SD4_DONE=0x92, SD4_ERROR=0xff };
enum sd4_error { SD4_OK=0, SD4_BAD_FRAME=1, SD4_BAD_VERSION=2,
    SD4_BAD_FLAGS=3, SD4_BAD_LENGTH=4, SD4_BAD_OPERATION=5,
    SD4_BAD_SESSION=6, SD4_BAD_TXID=7, SD4_DUPLICATE_TXID=8,
    SD4_SESSION_PEER=9, SD4_SESSION_BUSY=10, SD4_NOT_OPEN=11,
    SD4_BAD_CONFIG=12, SD4_NOT_CONFIGURED=13, SD4_UTC_REQUIRED=14,
    SD4_UTC_ALREADY_SET=15, SD4_BAD_PACKET=16, SD4_RX_SEQUENCE=17,
    SD4_HW_FAULT=18, SD4_DMA_ERROR=19, SD4_UDP_ERROR=20,
    SD4_SESSION_REUSED=21, SD4_SESSION_LIMIT=22, SD4_BUSY=23 };
typedef struct {
    uint8_t op;
    uint32_t session, txid, length, code;
    const uint8_t *payload;
} sd4_frame;
typedef struct {
    uint32_t data_sid, version_sid, samples, fs, bw;
    uint64_t rf_hz;
    uint32_t rx_filter, rx_data_sid, rx_version_sid;
} sd4_config;
typedef struct { uint32_t type, sequence, samples, sid; } sd4_packet_info;
uint32_t sd4_get32(const uint8_t *p);
void sd4_put32(uint8_t *p, uint32_t v);
void sd4_header(uint8_t *p, uint8_t op, uint32_t session, uint32_t txid,
                uint32_t length, uint32_t code);
int sd4_decode(const uint8_t *p, size_t n, sd4_frame *frame);
int sd4_config_decode(const uint8_t *p, size_t n, sd4_config *config);
int sd4_txid_accept(uint32_t *last, uint32_t incoming);
/* Words are host-order uint32_t; tx=1 also checks active TX config values. */
const char *sd4_validate_packet(const uint32_t *words, uint32_t n,
                               const sd4_config *config, int tx,
                               sd4_packet_info *info);
const char *sd4_error_name(int error);
#endif
