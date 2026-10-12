/*
 * DIFI Stage B2: Real Zynq-7020 RX board test, Vivado/Vitis 2024.2.
 * Packet DDR => AXI DMA MM2S => DIFI RX Dispatch/Parsers.
 * Valid Data => IQ AXIS => AXI DMA S2MM => DDR.
 * RX Metadata/Error snapshots => B2 board adapter => AXI GPIO dual channel.
 *
 * IMPORTANT: Use the Stage B2 XSA/bitstream. Stage A/B1 XSA WILL NOT WORK.
 * AXI GPIO CH1 = 5-bit output to dbg_page; CH2 = 32-bit input dbg_rdata.
 * Current AXI4-Lite base 0x40000000, GPIO 0x41200000 (verify Address Editor).
 * TX must remain disabled (CONTROL=0); no GPIO start pulses in Stage B2.
 */
#include <stddef.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xgpio.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"

#if defined(SDT)
  #define DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
  #define GPIO_IDENTIFIER XPAR_XGPIO_0_BASEADDR
#else
  #define DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
  #define GPIO_IDENTIFIER XPAR_GPIO_0_DEVICE_ID
#endif

#ifndef DIFI_CTRL_BASE
#define DIFI_CTRL_BASE 0x40000000U
#endif

#define CTRL_REG_CONTROL      0x00U
#define CTRL_REG_RX_FILTER    0x34U
#define CTRL_REG_RX_DATA_SID  0x38U
#define CTRL_REG_RX_VER_SID   0x3CU

#define DATA_SID        0x10203040U
#define VERSION_SID     0x55667788U
#define TEST_SEC        0x6553F100U
#define SAMPLES         256U
#define DATA_WORDS      (7U + SAMPLES)
#define CTX_WORDS       27U
#define VER_WORDS       11U
#define BAD_WORDS       8U
#define SAMPLE_RATE_HZ  2000000U
#define BANDWIDTH_HZ    1500000U
#define RF_FREQ_HZ      915000000ULL
#define POLL_LIMIT      50000000U
#define EVENT_POLL      1000000U

/* Both buffers are cacheline aligned and reside in DMA-addressable DDR. */
static u32 TxWords[272] __attribute__((aligned(64)));
static u32 RxIQ[272] __attribute__((aligned(64)));
static XAxiDma Dma;
static XGpio Gpio;

/* Monitoring page numbers implemented in difi_engine_board_b2.v */
#define PG_MAGIC     0U
#define PG_DATA_CNT  1U
#define PG_CTX_CNT   2U
#define PG_VER_CNT   3U
#define PG_E_DISP    4U
#define PG_E_DATA    5U
#define PG_E_CTX     6U
#define PG_E_VER     7U
#define PG_LAST_ERR  8U
#define PG_DATA_SID  9U
#define PG_DATA_SZQ 10U
#define PG_DATA_SEC 11U
#define PG_DATA_PSH 12U
#define PG_DATA_PSL 13U
#define PG_CTX_SID  14U
#define PG_CTX_SQC  15U
#define PG_CTX_BW   16U
#define PG_CTX_RFHI 17U
#define PG_CTX_RFLO 18U
#define PG_CTX_FS   19U
#define PG_CTX_SEC  20U
#define PG_CTX_PSH  21U
#define PG_CTX_PSL  22U
#define PG_VER_SID  23U
#define PG_VER_SQC  24U
#define PG_VER_INFO 25U
#define PG_VER_SEC  26U
#define PG_VER_PSH  27U
#define PG_VER_PSL  28U

static u32 read_page(u32 page)
{
    XGpio_DiscreteWrite(&Gpio, 1U, page & 31U);
    (void)XGpio_DiscreteRead(&Gpio, 1U); /* order GPIO page write before read */
    return XGpio_DiscreteRead(&Gpio, 2U);
}

static int expect32(const char *tag, u32 got, u32 want)
{
    if (got == want) return XST_SUCCESS;
    xil_printf("[FAIL] %s got=0x%08x expected=0x%08x\r\n",
               tag, (unsigned)got, (unsigned)want);
    return XST_FAILURE;
}

static u32 dma_sr(int dir)
{
    UINTPTR ch = (dir == XAXIDMA_DEVICE_TO_DMA) ?
                 (UINTPTR)XAXIDMA_RX_OFFSET : (UINTPTR)XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase + ch, XAXIDMA_SR_OFFSET);
}

static void dump_status(void)
{
    xil_printf("[DMA] MM2S=0x%08x S2MM=0x%08x\r\n",
               (unsigned)dma_sr(XAXIDMA_DMA_TO_DEVICE),
               (unsigned)dma_sr(XAXIDMA_DEVICE_TO_DMA));
    xil_printf("[MON] data=%u ctx=%u ver=%u errors=%u/%u/%u/%u last=0x%08x\r\n",
               (unsigned)read_page(PG_DATA_CNT), (unsigned)read_page(PG_CTX_CNT),
               (unsigned)read_page(PG_VER_CNT), (unsigned)read_page(PG_E_DISP),
               (unsigned)read_page(PG_E_DATA), (unsigned)read_page(PG_E_CTX),
               (unsigned)read_page(PG_E_VER), (unsigned)read_page(PG_LAST_ERR));
}

static int wait_dma(int dir, const char *label)
{
    u32 i;
    for (i = 0; i < POLL_LIMIT; i++) {
        u32 sr = dma_sr(dir);
        if ((sr & XAXIDMA_ERR_ALL_MASK) != 0U) {
            xil_printf("[FAIL] %s DMA error SR=0x%08x\r\n",label,(unsigned)sr);
            dump_status(); return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma, dir)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s DMA timeout\r\n",label);
    dump_status(); return XST_FAILURE;
}

static int wait_page(u32 page, u32 target, const char *label)
{
    u32 i;
    for (i = 0; i < EVENT_POLL; i++) {
        if (read_page(page) == target) return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s count=%u expected=%u\r\n", label,
               (unsigned)read_page(page), (unsigned)target);
    dump_status(); return XST_FAILURE;
}

static void prepare_buf(void)
{
    u32 i;
    for (i = 0; i < 272U; i++) { TxWords[i] = 0; RxIQ[i] = 0xDEADBEEFU; }
}

static int tx_packet(u32 words, const char *label)
{
    int ret;
    Xil_DCacheFlushRange((INTPTR)TxWords, (u32)sizeof(TxWords));
    ret = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)TxWords,
                                 words * 4U, XAXIDMA_DMA_TO_DEVICE);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] %s MM2S start rc=%d\r\n",label,ret);
        dump_status(); return XST_FAILURE;
    }
    xil_printf("[START] %s MM2S: %u B\r\n",label,(unsigned)(words * 4U));
    return wait_dma(XAXIDMA_DMA_TO_DEVICE, label);
}

static int arm_iq_rx(void)
{
    int ret;
    Xil_DCacheFlushRange((INTPTR)RxIQ, (u32)sizeof(RxIQ));
    Xil_DCacheInvalidateRange((INTPTR)RxIQ, (u32)sizeof(RxIQ));
    ret = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)RxIQ,
                                 SAMPLES * 4U, XAXIDMA_DEVICE_TO_DMA);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] IQ S2MM start rc=%d\r\n",ret);
        dump_status(); return XST_FAILURE;
    }
    xil_printf("[START] IQ S2MM: 1024 B\r\n");
    return XST_SUCCESS;
}

static void build_data(void)
{
    u32 i;
    prepare_buf();
    TxWords[0] = 0x18600107U; TxWords[1] = DATA_SID;
    TxWords[2] = 0x006A621EU; TxWords[3] = 0U;
    TxWords[4] = TEST_SEC; TxWords[5] = 0U; TxWords[6] = 0U;
    for (i = 0; i < SAMPLES; i++) {
        TxWords[i+7U] = (((0x1000U+i)&0xFFFFU)<<16) |
                        ((0xA000U+3U*i)&0xFFFFU);
    }
}

static void build_context(void)
{
    u64 b = ((u64)BANDWIDTH_HZ) << 20;
    u64 f = ((u64)RF_FREQ_HZ) << 20;
    u64 s = ((u64)SAMPLE_RATE_HZ) << 20;
    prepare_buf();
    TxWords[0] = 0x4960001BU; TxWords[1] = DATA_SID;
    TxWords[2] = 0x006A621EU; TxWords[3] = 0x00000001U;
    TxWords[4] = TEST_SEC;
    TxWords[7] = 0xFBB98000U; TxWords[8] = 0x00000064U;
    TxWords[9] = (u32)(b>>32); TxWords[10] = (u32)b;
    TxWords[13] = (u32)(f>>32); TxWords[14] = (u32)f;
    TxWords[19] = (u32)(s>>32); TxWords[20] = (u32)s;
    TxWords[25] = 0xA00003CFU; TxWords[26] = 0U;
}

static void build_version(void)
{
    prepare_buf();
    TxWords[0] = 0x5960000BU; TxWords[1] = VERSION_SID;
    TxWords[2] = 0x006A621EU; TxWords[3] = 0x00010004U;
    TxWords[4] = TEST_SEC;
    TxWords[7] = 0x80000002U; TxWords[8] = 0x0000000CU;
    TxWords[9] = 0x00000004U; TxWords[10] = 0x34FC0400U;
}

static int test_version(void)
{
    build_version();
    if (tx_packet(VER_WORDS,"Version") != XST_SUCCESS ||
        wait_page(PG_VER_CNT,1U,"Version Metadata") != XST_SUCCESS) return XST_FAILURE;
    if (expect32("Version SID",read_page(PG_VER_SID),VERSION_SID) ||
        expect32("Version seq/change",read_page(PG_VER_SQC),0x10U) ||
        expect32("Version info",read_page(PG_VER_INFO),0x34FC0400U) ||
        expect32("Version timestamp seconds",read_page(PG_VER_SEC),TEST_SEC) ||
        expect32("Version timestamp ps H",read_page(PG_VER_PSH),0U) ||
        expect32("Version timestamp ps L",read_page(PG_VER_PSL),0U)) return XST_FAILURE;
    xil_printf("[PASS] Version Parser: metadata and info verified\r\n");
    return XST_SUCCESS;
}

static int test_context(void)
{
    build_context();
    if (tx_packet(CTX_WORDS,"Context") != XST_SUCCESS ||
        wait_page(PG_CTX_CNT,1U,"Context Metadata") != XST_SUCCESS) return XST_FAILURE;
    if (expect32("Context SID",read_page(PG_CTX_SID),DATA_SID) ||
        expect32("Context seq/change",read_page(PG_CTX_SQC),0x10U) ||
        expect32("Context BW",read_page(PG_CTX_BW),BANDWIDTH_HZ) ||
        expect32("Context RF high",read_page(PG_CTX_RFHI),0U) ||
        expect32("Context RF low",read_page(PG_CTX_RFLO),915000000U) ||
        expect32("Context Fs",read_page(PG_CTX_FS),SAMPLE_RATE_HZ) ||
        expect32("Context timestamp seconds",read_page(PG_CTX_SEC),TEST_SEC) ||
        expect32("Context timestamp ps H",read_page(PG_CTX_PSH),0U) ||
        expect32("Context timestamp ps L",read_page(PG_CTX_PSL),0U)) return XST_FAILURE;
    xil_printf("[PASS] Context Parser: metadata BW/RF/Fs verified\r\n");
    return XST_SUCCESS;
}

static int test_data(void)
{
    u32 i;
    build_data();
    if (arm_iq_rx() != XST_SUCCESS) return XST_FAILURE;
    if (tx_packet(DATA_WORDS,"Data") != XST_SUCCESS) return XST_FAILURE;
    if (wait_dma(XAXIDMA_DEVICE_TO_DMA,"IQ") != XST_SUCCESS ||
        wait_page(PG_DATA_CNT,1U,"Data Metadata") != XST_SUCCESS) return XST_FAILURE;
    Xil_DCacheInvalidateRange((INTPTR)RxIQ, (u32)sizeof(RxIQ));
    if (expect32("Data SID",read_page(PG_DATA_SID),DATA_SID) ||
        expect32("Data seq/count",read_page(PG_DATA_SZQ),(SAMPLES<<4)) ||
        expect32("Data timestamp",read_page(PG_DATA_SEC),TEST_SEC) ||
        expect32("Data timestamp ps H",read_page(PG_DATA_PSH),0U) ||
        expect32("Data timestamp ps L",read_page(PG_DATA_PSL),0U)) return XST_FAILURE;
    for (i = 0; i < SAMPLES; i++) {
        if (RxIQ[i] != TxWords[i+7U]) {
            xil_printf("[FAIL] IQ[%u] exp=0x%08x got=0x%08x\r\n",
                       (unsigned)i,(unsigned)TxWords[i+7U],(unsigned)RxIQ[i]);
            return XST_FAILURE;
        }
    }
    xil_printf("[PASS] Data Parser: all 256 IQ words and metadata match\r\n");
    return XST_SUCCESS;
}

static int test_invalid_type(void)
{
    prepare_buf();
    TxWords[0] = 0xF8600008U; /* Not one of DIFI types 1/4/5 */
    if (tx_packet(BAD_WORDS,"InvalidType") != XST_SUCCESS ||
        wait_page(PG_E_DISP,1U,"Dispatch error") != XST_SUCCESS) return XST_FAILURE;
    if (expect32("dispatch error code",read_page(PG_LAST_ERR),0x00000101U) ||
        expect32("Data count unchanged",read_page(PG_DATA_CNT),1U) ||
        expect32("Context count unchanged",read_page(PG_CTX_CNT),1U) ||
        expect32("Version count unchanged",read_page(PG_VER_CNT),1U)) return XST_FAILURE;
    xil_printf("[PASS] Unsupported type rejected by RX Dispatch\r\n");
    return XST_SUCCESS;
}

int main(void)
{
    XAxiDma_Config *cfg;
    int rc;
    u32 i;
    xil_printf("\r\n===========================================\r\n");
    xil_printf(" DIFI Stage B2: Full Engine RX + DMA\r\n");
    xil_printf("===========================================\r\n");
    xil_printf("[INFO] DIFI CTRL base = 0x%08x\r\n",(unsigned)DIFI_CTRL_BASE);
    cfg = XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (cfg == NULL || XAxiDma_CfgInitialize(&Dma,cfg) != XST_SUCCESS ||
        XAxiDma_HasSg(&Dma)) {
        xil_printf("[FAIL] DMA init/config\r\n"); return XST_FAILURE;
    }
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    rc = XGpio_Initialize(&Gpio, GPIO_IDENTIFIER);
    if (rc != XST_SUCCESS) { xil_printf("[FAIL] GPIO init %d\r\n",rc); return XST_FAILURE; }
    XGpio_SetDataDirection(&Gpio,1U,0U);            /* debug page output */
    XGpio_SetDataDirection(&Gpio,2U,0xFFFFFFFFU);   /* monitor data input */

    Xil_Out32((UINTPTR)DIFI_CTRL_BASE+CTRL_REG_CONTROL,0U); /* TX off */
    if (expect32("monitor ID",read_page(PG_MAGIC),0xB2000002U)) {
        xil_printf("[HINT] Check B2 bitstream, AXI GPIO dual channel pin wiring.\r\n");
        return XST_FAILURE;
    }
    if (expect32("monitor page selector",read_page(31U),0xB2F0001FU)) {
        xil_printf("[HINT] GPIO CH1 must drive dbg_page[4:0].\r\n");
        return XST_FAILURE;
    }
    xil_printf("[OK] B2 metadata monitor detected and page selector works\r\n");
    for (i = 1U; i <= 7U; i++) {
        if (expect32("initial count",read_page(i),0U)) {
            xil_printf("[HINT] Reprogram B2 PL to reset counters before test.\r\n");
            return XST_FAILURE;
        }
    }
    Xil_Out32((UINTPTR)DIFI_CTRL_BASE+CTRL_REG_RX_DATA_SID,DATA_SID);
    Xil_Out32((UINTPTR)DIFI_CTRL_BASE+CTRL_REG_RX_VER_SID,VERSION_SID);
    Xil_Out32((UINTPTR)DIFI_CTRL_BASE+CTRL_REG_RX_FILTER,3U);
    if (expect32("RX Filter",Xil_In32((UINTPTR)DIFI_CTRL_BASE+CTRL_REG_RX_FILTER),3U)) return XST_FAILURE;
    xil_printf("[OK] RX Stream ID filtering enabled\r\n");

    if (test_version() != XST_SUCCESS || test_context() != XST_SUCCESS ||
        test_data() != XST_SUCCESS || test_invalid_type() != XST_SUCCESS) {
        dump_status(); return XST_FAILURE;
    }
    if (read_page(PG_E_DATA) || read_page(PG_E_CTX) || read_page(PG_E_VER)) {
        xil_printf("[FAIL] Unexpected parser error\r\n"); dump_status(); return XST_FAILURE;
    }
    dump_status();
    xil_printf("\r\n[DIFI STAGE-B2 TEST PASSED]\r\n");
    return XST_SUCCESS;
}
