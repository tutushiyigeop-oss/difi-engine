/*
 * B5 Zynq-7020 DIFI 1.1 RAW PACKET EXPORT - Vitis 2024.2 standalone
 *
 * Board RTL: difi_board_raw_packet_export.v (NOT original B4 wrapper)
 * No dependency on platform.h/platform.c or xtime_l.h.
 * UART input/echo follows the verified B4 final test: inbyte() + xil_printf().
 * DIFI:     TX -> DMA S2MM, with RX packet input disabled.
 *
 * Captures, in order: Version (11 words), Changed Context (27 words),
 * Data (7+4=11 words).  Stops at three packets; no UDP yet.
 *
 * IMPORTANT: Confirm CTRL/TIME/DMA addresses against YOUR exported XSA.
 * Time is supplied by UART: UTC <seconds> <nanoseconds> (without quotes).
 * Disable terminal-side Local Echo; the application echoes typed characters.
 * Supports simple (non-scatter/gather), non-Micro AXI DMA, 32-bit AXIS.
 * The S2MM buffer is rearmed between packets.  AXI TVALID must be held
 * stable by the upstream while DMA TREADY is low.
 */
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"

#include <string.h>

/* Verified B4 project: vitis/.../difi_stage_final_test/src/difi_full_board_test.c
 * Standalone BSP UART input is blocking; stdout uses xil_printf().
 * STDIN and STDOUT must both be assigned to PS UART in BSP settings.
 */
extern char inbyte(void);

/* B4 UART log reported these TWO distinct AXI4-Lite physical addresses.
 * Explicitly override these macros if the new XSA Address Editor differs.
 */
#ifndef B5_CTRL_BASE
#define B5_CTRL_BASE ((UINTPTR)0x40000000U)
#endif
#ifndef B5_TIME_BASE
#define B5_TIME_BASE ((UINTPTR)0x40001000U)
#endif

/* For SDT Vitis BSPs, XAxiDma_LookupConfig() uses base address.
 * For classic BSPs, it uses DEVICE_ID.  Names are generated from XSA.
 */
#ifdef SDT
  #ifndef B5_DMA_BASE
    #if defined(XPAR_XAXIDMA_0_BASEADDR)
      #define B5_DMA_BASE XPAR_XAXIDMA_0_BASEADDR
    #elif defined(XPAR_AXIDMA_0_BASEADDR)
      #define B5_DMA_BASE XPAR_AXIDMA_0_BASEADDR
    #elif defined(XPAR_AXI_DMA_0_BASEADDR)
      #define B5_DMA_BASE XPAR_AXI_DMA_0_BASEADDR
    #else
      #error "Define B5_DMA_BASE with AXI DMA physical base address from xparameters.h"
    #endif
  #endif
#else
  #ifndef B5_DMA_DEVICE_ID
    #if defined(XPAR_AXIDMA_0_DEVICE_ID)
      #define B5_DMA_DEVICE_ID XPAR_AXIDMA_0_DEVICE_ID
    #elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
      #define B5_DMA_DEVICE_ID XPAR_AXI_DMA_0_DEVICE_ID
    #else
      #error "Define B5_DMA_DEVICE_ID using the AXI DMA DEVICE_ID from xparameters.h"
    #endif
  #endif
#endif

/* S_AXI_CTRL register offsets (difi_cfg_regmap.vh). */
#define CTRL_CONTROL          0x00U
#define CTRL_COMMAND          0x04U
#define CTRL_STATUS           0x08U
#define CTRL_LAST_ERROR       0x0CU
#define CTRL_DATA_SID         0x10U
#define CTRL_VERSION_SID      0x14U
#define CTRL_SAMPLES          0x18U
#define CTRL_SAMPLE_RATE      0x1CU
#define CTRL_BANDWIDTH        0x20U
#define CTRL_RF_LO            0x24U
#define CTRL_RF_HI            0x28U
#define CTRL_CTX_PERIOD       0x2CU
#define CTRL_VER_PERIOD       0x30U
#define CTRL_ACTIVE_SAMPLES   0x48U
#define CTRL_ACTIVE_CTX_PER   0x5CU
#define CTRL_ACTIVE_VER_PER   0x60U

/* S_AXI_TIME register offsets (difi_time_cfg_regmap.vh). */
#define TIME_SEC              0x00U
#define TIME_PS_LO            0x04U
#define TIME_PS_HI            0x08U
#define TIME_COMMAND          0x0CU
#define TIME_STATUS           0x10U

#define ST_COMMIT_PENDING      0x01U
#define ST_CTX_CHANGE         0x02U
#define ST_TX_BUSY            0x04U
#define ST_TX_ENABLE          0x08U
#define ST_TIME_VALID         0x10U
#define ST_COMMIT_ERROR       0x20U

#define B5_IQ_WORDS           4U
#define B5_VERSION_WORDS      11U
#define B5_CONTEXT_WORDS      27U
#define B5_DATA_WORDS         (7U + B5_IQ_WORDS)
#define B5_RX_CAPACITY_WORDS  512U   /* 2048 bytes; max DIFI = 1052 bytes */
#define B5_POLL_LIMIT         25000000U  /* bounded poll count; NOT seconds */

static XAxiDma AxiDma;
static u32 RxWords[B5_RX_CAPACITY_WORDS] __attribute__((aligned(64)));
static u32 IqWords[B5_IQ_WORDS] __attribute__((aligned(64))) = {
    0x0001FFFFU, 0x7FFF8000U, 0xFFFE0003U, 0x00000000U
};

static void ctrl_write(u32 reg, u32 value)
{
    Xil_Out32(B5_CTRL_BASE + reg, value);
}
static u32 ctrl_read(u32 reg)
{
    return Xil_In32(B5_CTRL_BASE + reg);
}
static void time_write(u32 reg, u32 value)
{
    Xil_Out32(B5_TIME_BASE + reg, value);
}
static u32 time_read(u32 reg)
{
    return Xil_In32(B5_TIME_BASE + reg);
}


static int wait_time_valid(void)
{
    u32 poll;
    for (poll = 0U; poll < B5_POLL_LIMIT; poll++) {
        u32 st = time_read(TIME_STATUS);
        if ((st & 0x02U) != 0U) {
            xil_printf("[ERROR] TIME_STATUS rejected the UTC load: %08x\r\n", st);
            return XST_FAILURE;
        }
        if ((st & 0x01U) && (ctrl_read(CTRL_STATUS) & ST_TIME_VALID))
            return XST_SUCCESS;
    }
    xil_printf("[ERROR] TIME_VALID poll limit reached\r\n");
    return XST_FAILURE;
}

/* This UART input implementation is intentionally based on the proven B4
 * difi_full_board_test.c implementation.  It explicitly echoes characters:
 *   - visible printable characters
 *   - Backspace / Delete correction
 *   - one visible CRLF when ENTER is pressed
 *   - CRLF terminal mode consumes the trailing LF on the next read
 * MobaXterm "Local echo" should be OFF to avoid duplicate display.
 */
static void uart_getline(char *buf, unsigned cap)
{
    unsigned n = 0U;
    static int skip_lf_after_cr = 0;
    char c;

    if (cap == 0U) return;
    for (;;) {
        c = inbyte();

        if (skip_lf_after_cr) {
            skip_lf_after_cr = 0;
            if (c == '\n') continue;
        }
        if (c == '\r' || c == '\n') {
            buf[n] = '\0';
            xil_printf("\r\n");
            if (c == '\r') skip_lf_after_cr = 1;
            return;
        }
        if (c == '\b' || (unsigned char)c == 127U) {
            if (n > 0U) {
                --n;
                xil_printf("\b \b");
            }
            continue;
        }
        if ((unsigned char)c < 32U && c != '\t') continue;
        if (n + 1U < cap) {
            buf[n++] = c;
            xil_printf("%c", (int)c);
        }
        /* Extra input is discarded until Enter to avoid buffer overflow. */
    }
}

/* B4-compatible decimal parser, with uint32 overflow detection. */
static int parse_decimal(const char **p, u32 *out)
{
    u64 v = 0ULL;
    int found = 0;
    while (**p == ' ' || **p == '\t') ++(*p);
    while (**p >= '0' && **p <= '9') {
        found = 1;
        v = 10ULL * v + (u32)(**p - '0');
        if (v > 0xFFFFFFFFULL) return XST_FAILURE;
        ++(*p);
    }
    if (!found) return XST_FAILURE;
    *out = (u32)v;
    return XST_SUCCESS;
}

static int parse_utc(const char *line, u32 *sec, u32 *ns)
{
    const char *p = line;
    if (p[0] != 'U' || p[1] != 'T' || p[2] != 'C' || p[3] != ' ')
        return XST_FAILURE;
    p += 4;
    if (parse_decimal(&p, sec) != XST_SUCCESS) return XST_FAILURE;
    if (parse_decimal(&p, ns) != XST_SUCCESS) return XST_FAILURE;
    while (*p == ' ' || *p == '\t') ++p;
    if (*p != '\0' || *ns >= 1000000000U) return XST_FAILURE;
    return XST_SUCCESS;
}

static int read_utc_command(u32 *sec, u32 *nano)
{
    char line[96];
    for (;;) {
        xil_printf("[WAIT_UTC] Send: UTC <UNIX_SEC> <NANOSECOND_0_TO_999999999>\r\n");
        xil_printf("[INFO] UART input is echoed by FPGA PS; terminal Local Echo=OFF\r\n");
        uart_getline(line, sizeof(line));
        if (parse_utc(line, sec, nano) == XST_SUCCESS) {
            xil_printf("[UTC] sec=%u nanosecond=%u\r\n",
                       (unsigned)*sec, (unsigned)*nano);
            return XST_SUCCESS;
        }
        xil_printf("[WARN] Invalid UTC command; retry, e.g. UTC 1760000000 123456789\r\n");
    }
}

static int program_time(void)
{
    u32 sec, ns;
    u64 ps;
    if (read_utc_command(&sec, &ns) != XST_SUCCESS)
        return XST_FAILURE;
    ps = ((u64)ns) * 1000ULL;
    time_write(TIME_SEC, sec);
    time_write(TIME_PS_LO, (u32)ps);
    time_write(TIME_PS_HI, (u32)(ps >> 32));
    time_write(TIME_COMMAND, 1U);
    if (wait_time_valid() != XST_SUCCESS)
        return XST_FAILURE;
    xil_printf("[PASS] UTC initialized using S_AXI_TIME, time status=%08x\r\n",
               time_read(TIME_STATUS));
    return XST_SUCCESS;
}

static int config_difi(void)
{
    u32 poll;
    u32 st;
    ctrl_write(CTRL_CONTROL, 0U); /* disabled before commit */
    ctrl_write(CTRL_DATA_SID, 1U);
    ctrl_write(CTRL_VERSION_SID, 2U);
    ctrl_write(CTRL_SAMPLES, B5_IQ_WORDS);
    ctrl_write(CTRL_SAMPLE_RATE, 20000000U);
    ctrl_write(CTRL_BANDWIDTH, 10000000U);
    ctrl_write(CTRL_RF_LO, 100000000U);
    ctrl_write(CTRL_RF_HI, 0U);
    ctrl_write(CTRL_CTX_PERIOD, 0U);
    ctrl_write(CTRL_VER_PERIOD, 0U);
    ctrl_write(CTRL_COMMAND, 1U); /* Shadow -> Active via scheduler ACK */
    for (poll = 0U; poll < B5_POLL_LIMIT; poll++) {
        st = ctrl_read(CTRL_STATUS);
        if (st & ST_COMMIT_ERROR) {
            xil_printf("[ERROR] config commit rejected, code=%u\r\n",
                       ctrl_read(CTRL_LAST_ERROR));
            return XST_FAILURE;
        }
        if (!(st & ST_COMMIT_PENDING) &&
            ctrl_read(CTRL_ACTIVE_SAMPLES) == B5_IQ_WORDS &&
            ctrl_read(CTRL_ACTIVE_CTX_PER) == 0U &&
            ctrl_read(CTRL_ACTIVE_VER_PER) == 0U)
            break;
    }
    if (poll >= B5_POLL_LIMIT) {
        xil_printf("[ERROR] config commit poll limit reached; CTRL_STATUS=%08x\r\n",
                   ctrl_read(CTRL_STATUS));
        return XST_FAILURE;
    }
    st = ctrl_read(CTRL_STATUS);
    if (!(st & ST_TIME_VALID) || (st & ST_TX_ENABLE)) {
        xil_printf("[ERROR] unexpected CTRL_STATUS=%08x\r\n", st);
        return XST_FAILURE;
    }
    xil_printf("[PASS] config commit; samples=4, context/version periods=0\r\n");
    return XST_SUCCESS;
}

static int dma_init(void)
{
    XAxiDma_Config *cfg;
    int rc;
#ifdef SDT
    cfg = XAxiDma_LookupConfig((UINTPTR)B5_DMA_BASE);
#else
    cfg = XAxiDma_LookupConfig((u16)B5_DMA_DEVICE_ID);
#endif
    if (cfg == NULL) {
        xil_printf("[ERROR] AXI DMA configuration lookup failed\r\n");
        return XST_FAILURE;
    }
    rc = XAxiDma_CfgInitialize(&AxiDma, cfg);
    if (rc != XST_SUCCESS) {
        xil_printf("[ERROR] AXI DMA initialization: %d\r\n", rc);
        return rc;
    }
    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("[ERROR] this example requires AXI DMA simple mode, not SG\r\n");
        return XST_FAILURE;
    }
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

static u32 dma_status(int direction)
{
    u32 offset = (direction == XAXIDMA_DEVICE_TO_DMA)
               ? XAXIDMA_RX_OFFSET : XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(AxiDma.RegBase, offset + XAXIDMA_SR_OFFSET);
}

static int dma_arm_rx(u32 words)
{
    u32 bytes = words * sizeof(u32);
    int rc;
    if (words > B5_RX_CAPACITY_WORDS) return XST_FAILURE;
    memset(RxWords, 0xA5, sizeof(RxWords));
    Xil_DCacheFlushRange((UINTPTR)RxWords, sizeof(RxWords));
    rc = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxWords,
                                 bytes, XAXIDMA_DEVICE_TO_DMA);
    if (rc != XST_SUCCESS)
        xil_printf("[ERROR] arm S2MM rc=%d status=%08x\r\n",
                   rc, dma_status(XAXIDMA_DEVICE_TO_DMA));
    return rc;
}

static int dma_wait(int direction)
{
    u32 poll;
    for (poll = 0U; poll < B5_POLL_LIMIT; poll++) {
        u32 st = dma_status(direction);
        if (st & 0x70U) {  /* AXI DMA DMASlvErr/DMADecErr/DMAIntErr */
            xil_printf("[ERROR] DMA direction=%d status=%08x\r\n", direction, st);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&AxiDma, direction)) {
            if (dma_status(direction) & 0x70U) {
                xil_printf("[ERROR] DMA final status=%08x\r\n",
                           dma_status(direction));
                return XST_FAILURE;
            }
            return XST_SUCCESS;
        }
    }
    xil_printf("[ERROR] DMA poll limit reached direction=%d status=%08x\r\n",
               direction, dma_status(direction));
    return XST_FAILURE;
}

static int validate_and_dump(const char *name, u32 type, u32 words)
{
    u32 i, header;
    Xil_DCacheInvalidateRange((UINTPTR)RxWords, sizeof(RxWords));
    header = RxWords[0];
    if ((header >> 28) != type || (header & 0xFFFFU) != words) {
        xil_printf("[ERROR] %s header=%08x type=%u size=%u\r\n",
                   name, header, header >> 28, header & 0xFFFFU);
        return XST_FAILURE;
    }
    if (RxWords[2] != 0x006A621EU) {
        xil_printf("[ERROR] %s invalid OUI=%08x\r\n", name, RxWords[2]);
        return XST_FAILURE;
    }
    if ((type == 5U && (RxWords[3] != 0x00010004U ||
                        RxWords[8] != 0x0000000CU ||
                        RxWords[9] != 0x00000004U)) ||
        (type == 4U && (RxWords[3] != 0x00000001U ||
                        RxWords[7] != 0xFBB98000U ||
                        RxWords[25] != 0xA00003CFU ||
                        RxWords[26] != 0U)) ||
        (type == 1U && RxWords[3] != 0x00000000U)) {
        xil_printf("[ERROR] %s fixed DIFI fields mismatch\r\n", name);
        return XST_FAILURE;
    }
    if (type == 1U) {
        for (i = 0U; i < B5_IQ_WORDS; i++) {
            if (RxWords[7U + i] != IqWords[i]) {
                xil_printf("[ERROR] IQ[%u] expected=%08x actual=%08x\r\n",
                           i, IqWords[i], RxWords[7U + i]);
                return XST_FAILURE;
            }
        }
    }
    /* These exact delimiters / W[] formatting are consumed by
     * b5_hex_to_pcap.py and the B5 PC regression parser.
     */
    xil_printf("[B5_START]\r\n");
    for (i = 0U; i < words; i++)
        xil_printf("W[%03u]=%08x\r\n", (unsigned)i, (unsigned)RxWords[i]);
    xil_printf("[B5_END]\r\n");
    xil_printf("[PASS] %s: %u words, seq=%u\r\n",
               name, words, (header >> 16) & 0xFU);
    return XST_SUCCESS;
}

static int capture_packet(const char *name, u32 type, u32 words)
{
    int rc;
    xil_printf("[CAPTURE] arm S2MM for %s (%u bytes)\r\n", name, words * 4U);
    rc = dma_arm_rx(words);
    if (rc != XST_SUCCESS) return rc;
    if (dma_wait(XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS)
        return XST_FAILURE;
    return validate_and_dump(name, type, words);
}

int main(void)
{
    int rc;
    xil_printf("\r\n=== B5 RAW DIFI PACKET EXPORT, Zynq-7020 ===\r\n");
    xil_printf("[INFO] CTRL_BASE=%08x TIME_BASE=%08x\r\n",
               (u32)B5_CTRL_BASE, (u32)B5_TIME_BASE);
    xil_printf("[INFO] Require fresh B5 bitstream; do NOT run with B4 bitstream\r\n");

    rc = dma_init();
    if (rc != XST_SUCCESS) goto fail;
    ctrl_write(CTRL_CONTROL, 0U);
    if (program_time() != XST_SUCCESS) goto fail;
    if (config_difi() != XST_SUCCESS) goto fail;

    /* Arm S2MM BEFORE enabling TX.  Version is scheduler startup packet. */
    if (dma_arm_rx(B5_VERSION_WORDS) != XST_SUCCESS) goto fail;
    ctrl_write(CTRL_CONTROL, 1U);
    if (dma_wait(XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) goto fail;
    if (validate_and_dump("Version", 5U, B5_VERSION_WORDS) != XST_SUCCESS)
        goto fail;

    /* Scheduler next emits the initial changed Context; it safely stalls
       with TVALID asserted until S2MM is rearmed. */
    if (capture_packet("Context", 4U, B5_CONTEXT_WORDS) != XST_SUCCESS)
        goto fail;

    /* Then arm S2MM for Data; only after that feed four samples via MM2S. */
    if (dma_arm_rx(B5_DATA_WORDS) != XST_SUCCESS) goto fail;
    Xil_DCacheFlushRange((UINTPTR)IqWords, sizeof(IqWords));
    rc = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)IqWords,
                                 sizeof(IqWords), XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) {
        xil_printf("[ERROR] MM2S start rc=%d status=%08x\r\n",
                   rc, dma_status(XAXIDMA_DMA_TO_DEVICE));
        goto fail;
    }
    if (dma_wait(XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) goto fail;
    if (dma_wait(XAXIDMA_DMA_TO_DEVICE) != XST_SUCCESS) goto fail;
    if (validate_and_dump("Data", 1U, B5_DATA_WORDS) != XST_SUCCESS)
        goto fail;

    ctrl_write(CTRL_CONTROL, 0U);
    xil_printf("[ALL B5 RAW PACKET EXPORT TESTS PASSED]\r\n");
    xil_printf("[NOTE] Raw Packet -> PS DDR proven; UDP and third-party certification NOT tested.\r\n");
    return 0;

fail:
    ctrl_write(CTRL_CONTROL, 0U);
    xil_printf("[B5 TEST FAILED] Check bitstream, AXI DMA status, addresses, and UART log.\r\n");
    return 1;
}
