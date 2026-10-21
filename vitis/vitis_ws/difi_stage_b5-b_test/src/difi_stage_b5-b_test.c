/* Stage B5-B: check startup packets and 20 Data packets. */

#include <stddef.h>
#include <string.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"

extern char inbyte(void);

#ifndef B5_CTRL_BASE
#define B5_CTRL_BASE ((UINTPTR)0x40000000U)
#endif
#ifndef B5_TIME_BASE
#define B5_TIME_BASE ((UINTPTR)0x40001000U)
#endif

#ifdef SDT
  #ifndef B5_DMA_BASE
    #if defined(XPAR_XAXIDMA_0_BASEADDR)
      #define B5_DMA_BASE XPAR_XAXIDMA_0_BASEADDR
    #elif defined(XPAR_AXIDMA_0_BASEADDR)
      #define B5_DMA_BASE XPAR_AXIDMA_0_BASEADDR
    #elif defined(XPAR_AXI_DMA_0_BASEADDR)
      #define B5_DMA_BASE XPAR_AXI_DMA_0_BASEADDR
    #else
      #error "AXI DMA base unavailable: inspect generated xparameters.h"
    #endif
  #endif
#else
  #ifndef B5_DMA_DEVICE_ID
    #if defined(XPAR_AXIDMA_0_DEVICE_ID)
      #define B5_DMA_DEVICE_ID XPAR_AXIDMA_0_DEVICE_ID
    #elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
      #define B5_DMA_DEVICE_ID XPAR_AXI_DMA_0_DEVICE_ID
    #else
      #error "AXI DMA Device ID unavailable: inspect xparameters.h"
    #endif
  #endif
#endif

#define REG_CONTROL       0x00U
#define REG_COMMAND       0x04U
#define REG_STATUS        0x08U
#define REG_COMMIT_ERROR  0x0CU
#define REG_DATA_SID      0x10U
#define REG_VERSION_SID   0x14U
#define REG_SAMPLES       0x18U
#define REG_FS            0x1CU
#define REG_BW            0x20U
#define REG_RF_LO         0x24U
#define REG_RF_HI         0x28U
#define REG_CTX_PERIOD    0x2CU
#define REG_VER_PERIOD    0x30U
#define REG_ACT_DATA_SID  0x40U
#define REG_ACT_VER_SID   0x44U
#define REG_ACT_SAMPLES   0x48U
#define REG_ACT_FS        0x4CU
#define REG_ACT_BW        0x50U
#define REG_ACT_RF_LO     0x54U
#define REG_ACT_RF_HI     0x58U
#define REG_ACT_CTX_PER   0x5CU
#define REG_ACT_VER_PER   0x60U

#define TIME_SEC          0x00U
#define TIME_PS_LO        0x04U
#define TIME_PS_HI        0x08U
#define TIME_COMMAND      0x0CU
#define TIME_STATUS       0x10U

#define ST_COMMIT_PENDING (1U << 0)
#define ST_TX_ENABLE     (1U << 3)
#define ST_TIME_VALID    (1U << 4)
#define ST_COMMIT_ERROR  (1U << 5)
#define PS_PER_SEC       1000000000000ULL

#define DATA_SID         0x00000001U
#define VERSION_SID      0x00000002U
#define SAMPLE_RATE_HZ   20000000U
#define BANDWIDTH_HZ     10000000U
#define RF_FREQ_HZ       100000000U

#define B5B_SAMPLES        256U
#define B5B_DATA_PACKETS   20U  /* Use at least 17 packets to cover sequence wrap from 15 to 0. */
#define B5B_VERSION_WORDS  11U
#define B5B_CONTEXT_WORDS  27U
#define B5B_DATA_WORDS     (7U + B5B_SAMPLES)
#define B5B_CAPTURE_COUNT  (2U + B5B_DATA_PACKETS)
#define B5B_RX_PAD_WORDS   272U 
#define B5B_POLL_LIMIT     75000000U /* Polling iteration limit, not milliseconds. */

#if B5B_DATA_PACKETS < 17
#error "Need at least 17 Data packets to test sequence 15->0 wrap"
#endif

static XAxiDma Dma;
static u32 TxIQ[B5B_SAMPLES] __attribute__((aligned(64)));
static u32 RxWords[B5B_RX_PAD_WORDS] __attribute__((aligned(64)));

/* DMA uses only TxIQ/RxWords; avoid large UART prints during consecutive captures. */
static u32 SavedPackets[B5B_CAPTURE_COUNT][B5B_DATA_WORDS];
static u16 SavedWordCounts[B5B_CAPTURE_COUNT];
static u32 SavedCount = 0U;
static u32 PreviousDataSec = 0U;
static u64 PreviousDataPS = 0ULL;
static int HavePreviousDataTime = 0;

static void ctrl_wr(u32 off, u32 val) { Xil_Out32(B5_CTRL_BASE + off, val); }
static u32 ctrl_rd(u32 off) { return Xil_In32(B5_CTRL_BASE + off); }
static void time_wr(u32 off, u32 val) { Xil_Out32(B5_TIME_BASE + off, val); }
static u32 time_rd(u32 off) { return Xil_In32(B5_TIME_BASE + off); }

static int fail(const char *reason)
{
    xil_printf("[FAIL] %s\r\n", reason);
    return XST_FAILURE;
}

static int eq(const char *label, u32 got, u32 want)
{
    if (got == want) return XST_SUCCESS;
    xil_printf("[FAIL] %s expected=%08x got=%08x\r\n", label,
               (unsigned)want, (unsigned)got);
    return XST_FAILURE;
}

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
            if (n != 0U) {
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
    }
}

static int parse_decimal(const char **p, u32 *out)
{
    u64 n = 0ULL;
    int found = 0;
    while (**p == ' ' || **p == '\t') ++(*p);
    while (**p >= '0' && **p <= '9') {
        found = 1;
        n = n * 10ULL + (u32)(**p - '0');
        if (n > 0xFFFFFFFFULL) return XST_FAILURE;
        ++(*p);
    }
    if (!found) return XST_FAILURE;
    *out = (u32)n;
    return XST_SUCCESS;
}

static int parse_utc(const char *line, u32 *sec, u32 *ns)
{
    const char *p = line;
    if (p[0]!='U'||p[1]!='T'||p[2]!='C'||p[3]!=' ') return XST_FAILURE;
    p += 4;
    if (parse_decimal(&p, sec) || parse_decimal(&p, ns)) return XST_FAILURE;
    while (*p == ' ' || *p == '\t') ++p;
    if (*p != '\0' || *ns >= 1000000000U) return XST_FAILURE;
    return XST_SUCCESS;
}

static int configure_utc(void)
{
    char line[96];
    u32 sec, ns, st, i;
    u64 ps;
    if ((time_rd(TIME_STATUS) & 1U) || (ctrl_rd(REG_STATUS) & ST_TIME_VALID))
        return fail("TIME_VALID already set: reload the fresh B5 bitstream");
    for (;;) {
        xil_printf("[WAIT_UTC] Send: UTC <UNIX_SEC> <NANOSECOND_0_TO_999999999>\r\n");
        xil_printf("[INFO] Local Echo=OFF; PS echoes each UART character\r\n");
        uart_getline(line, sizeof(line));
        if (parse_utc(line, &sec, &ns) == XST_SUCCESS) break;
        xil_printf("[WARN] UTC format invalid. Example: UTC 1760000000 123456789\r\n");
    }
    ps = (u64)ns * 1000ULL;
    time_wr(TIME_SEC, sec);
    time_wr(TIME_PS_LO, (u32)ps);
    time_wr(TIME_PS_HI, (u32)(ps >> 32));
    time_wr(TIME_COMMAND, 1U);
    for (i=0U; i<B5B_POLL_LIMIT; ++i) {
        st = time_rd(TIME_STATUS);
        if (st & 2U) return fail("TIME_STATUS error: UTC rejected");
        if ((st & 1U) && (ctrl_rd(REG_STATUS) & ST_TIME_VALID)) break;
    }
    if (i == B5B_POLL_LIMIT) return fail("UTC TIME_VALID timeout");
    xil_printf("[PASS] Time Source initialized, sec=%u ns=%u\r\n",
               (unsigned)sec, (unsigned)ns);
    return XST_SUCCESS;
}

static int commit_config(void)
{
    u32 i, st;
    ctrl_wr(REG_CONTROL, 0U);
    ctrl_wr(REG_DATA_SID, DATA_SID);
    ctrl_wr(REG_VERSION_SID, VERSION_SID);
    ctrl_wr(REG_SAMPLES, B5B_SAMPLES);
    ctrl_wr(REG_FS, SAMPLE_RATE_HZ);
    ctrl_wr(REG_BW, BANDWIDTH_HZ);
    ctrl_wr(REG_RF_LO, RF_FREQ_HZ);
    ctrl_wr(REG_RF_HI, 0U);
    
    ctrl_wr(REG_CTX_PERIOD, 0U);
    ctrl_wr(REG_VER_PERIOD, 0U);
    ctrl_wr(REG_COMMAND, 1U);
    for (i=0U; i<B5B_POLL_LIMIT; ++i) {
        st = ctrl_rd(REG_STATUS);
        if (st & ST_COMMIT_ERROR) {
            xil_printf("[FAIL] commit rejected, error=%08x\r\n",
                       (unsigned)ctrl_rd(REG_COMMIT_ERROR));
            return XST_FAILURE;
        }
        if (!(st & ST_COMMIT_PENDING) &&
            ctrl_rd(REG_ACT_SAMPLES) == B5B_SAMPLES &&
            ctrl_rd(REG_ACT_DATA_SID) == DATA_SID &&
            ctrl_rd(REG_ACT_VER_SID) == VERSION_SID &&
            ctrl_rd(REG_ACT_FS) == SAMPLE_RATE_HZ &&
            ctrl_rd(REG_ACT_BW) == BANDWIDTH_HZ &&
            ctrl_rd(REG_ACT_RF_LO) == RF_FREQ_HZ &&
            ctrl_rd(REG_ACT_RF_HI) == 0U &&
            ctrl_rd(REG_ACT_CTX_PER) == 0U &&
            ctrl_rd(REG_ACT_VER_PER) == 0U) break;
    }
    if (i == B5B_POLL_LIMIT) return fail("config commit timeout or readback mismatch");
    st = ctrl_rd(REG_STATUS);
    if (!(st & ST_TIME_VALID) || (st & ST_TX_ENABLE))
        return fail("unexpected CTRL_STATUS after configuration");
    xil_printf("[PASS] Config committed: %u samples/packet, 20 data packets, periods=0\r\n",
               (unsigned)B5B_SAMPLES);
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
    if (!cfg) return fail("XAxiDma_LookupConfig returned NULL");
    rc = XAxiDma_CfgInitialize(&Dma, cfg);
    if (rc != XST_SUCCESS) return fail("XAxiDma_CfgInitialize failed");
    if (XAxiDma_HasSg(&Dma)) return fail("AXI DMA SG mode is not supported");
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

static u32 dma_status(int dir)
{
    u32 ch = (dir == XAXIDMA_DEVICE_TO_DMA) ? XAXIDMA_RX_OFFSET : XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase, ch + XAXIDMA_SR_OFFSET);
}

static int dma_wait(int dir, const char *name)
{
    u32 i;
    for (i=0U; i<B5B_POLL_LIMIT; ++i) {
        u32 st = dma_status(dir);
        if (st & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("[FAIL] %s DMA error, SR=%08x\r\n", name, (unsigned)st);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma, dir)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s DMA timeout, SR=%08x\r\n", name,
               (unsigned)dma_status(dir));
    return XST_FAILURE;
}

static int rx_arm(u32 words)
{
    int rc;
    if (words > B5B_RX_PAD_WORDS) return fail("RX request too large");
    /* Clear old data before starting a new capture. */
    memset(RxWords, 0xA5, sizeof(RxWords));
    Xil_DCacheFlushRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)RxWords,
                                words * 4U, XAXIDMA_DEVICE_TO_DMA);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] RX S2MM arm rc=%d SR=%08x\r\n", rc,
                   (unsigned)dma_status(XAXIDMA_DEVICE_TO_DMA));
    }
    return rc;
}

static void make_iq(u32 round)
{
    u32 i;
    for (i=0U; i<B5B_SAMPLES; ++i) {
        u32 in = (0x1000U + i + 0x0200U*round) & 0xFFFFU;
        u32 qn = (0xA000U + 3U*i + 0x0011U*round) & 0xFFFFU;
        TxIQ[i] = (in << 16) | qn;
    }
    
    TxIQ[0] = 0x0001FFFFU;
    TxIQ[1] = 0x7FFF8000U;
    TxIQ[2] = 0xFFFE0003U;
    TxIQ[3] = 0x00000000U;
    Xil_DCacheFlushRange((INTPTR)TxIQ, (u32)sizeof(TxIQ));
}

static int archive_current(u32 word_count)
{
    if (SavedCount >= B5B_CAPTURE_COUNT || word_count > B5B_DATA_WORDS)
        return fail("archive capacity exhausted");
    Xil_DCacheInvalidateRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    memcpy(SavedPackets[SavedCount], RxWords, word_count * 4U);
    SavedWordCounts[SavedCount] = (u16)word_count;
    ++SavedCount;
    return XST_SUCCESS;
}

static int verify_common(u32 type, u32 length, u32 sid, u32 seq)
{
    u32 w0 = RxWords[0];
    u32 expected = (type << 28) | 0x08600000U | ((seq & 15U) << 16) | length;
    
    if (type == 4U || type == 5U) expected |= 0x01000000U;
    if (eq("Word0 header/type/count/length", w0, expected) ||
        eq("Stream ID", RxWords[1], sid) ||
        eq("DIFI OUI", RxWords[2], 0x006A621EU)) return XST_FAILURE;
    return XST_SUCCESS;
}

static int verify_timestamp(u32 sec, u64 ps, int is_data)
{
    if (ps >= PS_PER_SEC) return fail("DIFI fractional timestamp >= 1 second");
    if (is_data) {
        if (HavePreviousDataTime &&
            !(sec > PreviousDataSec ||
              (sec == PreviousDataSec && ps > PreviousDataPS)))
            return fail("Data timestamps not strictly increasing");
        PreviousDataSec = sec;
        PreviousDataPS = ps;
        HavePreviousDataTime = 1;
    }
    return XST_SUCCESS;
}

static int verify_version(void)
{
    u64 ps;
    Xil_DCacheInvalidateRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    if (verify_common(5U, B5B_VERSION_WORDS, VERSION_SID, 0U)) return XST_FAILURE;
    if (eq("Version class", RxWords[3], 0x00010004U) ||
        eq("Version changed", RxWords[7], 0x80000002U) ||
        eq("Version CIF1", RxWords[8], 0x0000000CU) ||
        eq("Version spec", RxWords[9], 0x00000004U)) return XST_FAILURE;
    ps = ((u64)RxWords[5] << 32) | RxWords[6];
    if (verify_timestamp(RxWords[4], ps, 0)) return XST_FAILURE;
    return archive_current(B5B_VERSION_WORDS);
}

static int verify_context(void)
{
    u64 ps;
    Xil_DCacheInvalidateRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    if (verify_common(4U, B5B_CONTEXT_WORDS, DATA_SID, 0U)) return XST_FAILURE;
    if (eq("Context class", RxWords[3], 0x00000001U) ||
        eq("Context CIF0", RxWords[7], 0xFBB98000U) ||
        eq("Context ref point", RxWords[8], 0x00000064U) ||
        eq("Context DPF word0", RxWords[25], 0xA00003CFU) ||
        eq("Context DPF word1", RxWords[26], 0U)) return XST_FAILURE;
    ps = ((u64)RxWords[5] << 32) | RxWords[6];
    if (verify_timestamp(RxWords[4], ps, 0)) return XST_FAILURE;
    return archive_current(B5B_CONTEXT_WORDS);
}

static int verify_data(u32 round)
{
    u32 i;
    u64 ps;
    Xil_DCacheInvalidateRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    if (verify_common(1U, B5B_DATA_WORDS, DATA_SID, round & 15U))
        return XST_FAILURE;
    if (eq("Data class", RxWords[3], 0U)) return XST_FAILURE;
    ps = ((u64)RxWords[5] << 32) | RxWords[6];
    if (verify_timestamp(RxWords[4], ps, 1)) return XST_FAILURE;
    for (i=0U; i<B5B_SAMPLES; ++i) {
        if (RxWords[7U+i] != TxIQ[i]) {
            xil_printf("[FAIL] Data round=%u IQ[%u] expected=%08x got=%08x\r\n",
                       (unsigned)round, (unsigned)i,
                       (unsigned)TxIQ[i], (unsigned)RxWords[7U+i]);
            return XST_FAILURE;
        }
    }
    return archive_current(B5B_DATA_WORDS);
}

static void dump_archive(void)
{
    u32 pkt, i;
    xil_printf("[INFO] Exporting %u verified packets; UART output may take a while\r\n",
               (unsigned)SavedCount);
    for (pkt=0U; pkt<SavedCount; ++pkt) {
        u32 words = (u32)SavedWordCounts[pkt];
        u32 type = SavedPackets[pkt][0] >> 28;
        u32 seq = (SavedPackets[pkt][0] >> 16) & 15U;
        xil_printf("[EXPORT] packet=%u type=%u words=%u seq=%u\r\n",
                   (unsigned)pkt, (unsigned)type, (unsigned)words, (unsigned)seq);
        xil_printf("[B5_START]\r\n");
        for (i=0U; i<words; ++i)
            xil_printf("W[%03u]=%08x\r\n", (unsigned)i,
                       (unsigned)SavedPackets[pkt][i]);
        xil_printf("[B5_END]\r\n");
    }
}

int main(void)
{
    u32 round;
    int rc;
    int passed = 0;
    xil_printf("\r\n=== DIFI STAGE B5-B FULL-SIZE MULTI-PACKET TEST ===\r\n");
    xil_printf("[INFO] Reuse B5-A Platform/Bitstream; fresh PL reset required\r\n");
    xil_printf("[INFO] CTRL=%08x TIME=%08x samples=%u data_packets=%u\r\n",
               (unsigned)B5_CTRL_BASE, (unsigned)B5_TIME_BASE,
               (unsigned)B5B_SAMPLES, (unsigned)B5B_DATA_PACKETS);
    xil_printf("[INFO] Sequence expectation: 0..15,0..3; no periodic packets\r\n");

    if (dma_init()) goto finish;
    ctrl_wr(REG_CONTROL, 0U);
    if (configure_utc() || commit_config()) goto finish;

    if (rx_arm(B5B_VERSION_WORDS)) goto finish;
    ctrl_wr(REG_CONTROL, 1U);
    if (dma_wait(XAXIDMA_DEVICE_TO_DMA, "Version S2MM") || verify_version())
        goto finish;
    xil_printf("[PASS] Version startup: 11 words, seq=0\r\n");

    if (rx_arm(B5B_CONTEXT_WORDS) ||
        dma_wait(XAXIDMA_DEVICE_TO_DMA, "Context S2MM") || verify_context())
        goto finish;
    xil_printf("[PASS] Changed Context: 27 words, seq=0\r\n");

    for (round=0U; round<B5B_DATA_PACKETS; ++round) {
        make_iq(round);
        
        if (rx_arm(B5B_DATA_WORDS)) goto finish;
        rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)TxIQ,
                                     B5B_SAMPLES * 4U, XAXIDMA_DMA_TO_DEVICE);
        if (rc != XST_SUCCESS) {
            xil_printf("[FAIL] MM2S start round=%u rc=%d status=%08x\r\n",
                       (unsigned)round, rc,
                       (unsigned)dma_status(XAXIDMA_DMA_TO_DEVICE));
            goto finish;
        }
        if (dma_wait(XAXIDMA_DMA_TO_DEVICE, "Data MM2S") ||
            dma_wait(XAXIDMA_DEVICE_TO_DMA, "Data S2MM") ||
            verify_data(round)) goto finish;
        xil_printf("[PASS] Data round=%u: 263 words, 256/256 IQ, seq=%u\r\n",
                   (unsigned)round, (unsigned)(round & 15U));
    }

    if (SavedCount != B5B_CAPTURE_COUNT) {
        (void)fail("captured count mismatch");
        goto finish;
    }
    passed = 1;

finish:
    ctrl_wr(REG_CONTROL, 0U);
    if (SavedCount != 0U) dump_archive();
    if (passed) {
        xil_printf("[ALL B5-B TESTS PASSED] 1 Version + 1 Context + %u Data; "
                   "%u total words, %u IQ samples\r\n",
                   (unsigned)B5B_DATA_PACKETS,
                   (unsigned)(B5B_VERSION_WORDS+B5B_CONTEXT_WORDS+
                              B5B_DATA_WORDS*B5B_DATA_PACKETS),
                   (unsigned)(B5B_SAMPLES*B5B_DATA_PACKETS));
        xil_printf("[NOTE] Test uses sequential DMA rearming, NOT gapless high-speed throughput\r\n");
        return XST_SUCCESS;
    }
    xil_printf("[B5-B TEST FAILED] Saved %u successful packets; do not claim overall PASS\r\n",
               (unsigned)SavedCount);
    return XST_FAILURE;
}
