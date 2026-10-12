/*
 * DIFI Stage B3 - Full TX->RX internal AXI4-Stream loopback, Zynq-7020.
 * Vitis 2024.2 standalone. Uses AXI DMA Simple mode and dual-channel AXI GPIO.
 *
 * DDR IQ -> DMA MM2S -> Engine TX -> Engine RX -> DMA S2MM -> DDR IQ.
 * TX startup also emits Version + Context, consumed by the RX parsers.
 * The RX metadata and packet/error counters are read through AXI GPIO pages.
 *
 * IMPORTANT: Program the B3 bitstream and use its matching XSA Platform.
 * A fresh PL reset is required: startup Version/Context and counters are
 * intentionally checked from their reset values.
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
  #define DMA_IDENTIFIER  XPAR_XAXIDMA_0_BASEADDR
  #define GPIO_IDENTIFIER XPAR_XGPIO_0_BASEADDR
#else
  #define DMA_IDENTIFIER  XPAR_AXIDMA_0_DEVICE_ID
  #define GPIO_IDENTIFIER XPAR_GPIO_0_DEVICE_ID
#endif

#ifndef DIFI_CTRL_BASE
#define DIFI_CTRL_BASE 0x40000000U  /* verify in Vivado Address Editor */
#endif

#define R_CONTROL         0x00U
#define R_COMMAND         0x04U
#define R_STATUS          0x08U
#define R_COMMIT_ERROR    0x0CU
#define R_DATA_SID        0x10U
#define R_VERSION_SID     0x14U
#define R_SAMPLES         0x18U
#define R_SAMPLE_RATE     0x1CU
#define R_BANDWIDTH       0x20U
#define R_RF_LOW          0x24U
#define R_RF_HIGH         0x28U
#define R_RX_FILTER       0x34U
#define R_RX_DATA_SID     0x38U
#define R_RX_VER_SID      0x3CU
#define R_ACTIVE_DATA_SID 0x40U
#define R_ACTIVE_VER_SID  0x44U
#define R_ACTIVE_SAMPLES  0x48U
#define R_ACTIVE_RATE     0x4CU
#define R_ACTIVE_BW       0x50U
#define R_ACTIVE_RF_LOW   0x54U
#define R_ACTIVE_RF_HIGH  0x58U

#define SAMPLES           256U
#define DATA_SID          0x10203040U
#define VERSION_SID       0x55667788U
#define SAMPLE_RATE_HZ    2000000U
#define BANDWIDTH_HZ      1500000U
#define RF_FREQ_HZ        915000000U
#define TEST_SEC          0x6553F100U
#define WAIT_LIMIT        50000000U
#define COMMIT_LIMIT      1000000U

/* GPIO monitor pages: 0..28 same as Stage B2; 29/30 added by B3. */
#define PG_MAGIC      0U
#define PG_DATA_CNT   1U
#define PG_CTX_CNT    2U
#define PG_VER_CNT    3U
#define PG_E_DISP     4U
#define PG_E_DATA     5U
#define PG_E_CTX      6U
#define PG_E_VER      7U
#define PG_LAST_ERR   8U
#define PG_DATA_SID   9U
#define PG_DATA_SZQ  10U
#define PG_DATA_SEC  11U
#define PG_DATA_PSH  12U
#define PG_DATA_PSL  13U
#define PG_CTX_SID   14U
#define PG_CTX_SQC   15U
#define PG_CTX_BW    16U
#define PG_CTX_RFHI  17U
#define PG_CTX_RFLO  18U
#define PG_CTX_FS    19U
#define PG_CTX_SEC   20U
#define PG_CTX_PSH  21U
#define PG_CTX_PSL  22U
#define PG_VER_SID   23U
#define PG_VER_SQC   24U
#define PG_VER_INFO  25U
#define PG_VER_SEC   26U
#define PG_VER_PSH  27U
#define PG_VER_PSL  28U
#define PG_TX_PKTS   29U
#define PG_TX_BEATS  30U

static XAxiDma Dma;
static XGpio Gpio;
static u32 TxIQ[SAMPLES] __attribute__((aligned(64)));
static u32 RxIQ[SAMPLES] __attribute__((aligned(64)));

static void wr(u32 reg, u32 value)
{
    Xil_Out32((UINTPTR)DIFI_CTRL_BASE + reg, value);
}
static u32 rd(u32 reg)
{
    return Xil_In32((UINTPTR)DIFI_CTRL_BASE + reg);
}
static u32 page(u32 index)
{
    XGpio_DiscreteWrite(&Gpio, 1U, index & 31U);
    (void)XGpio_DiscreteRead(&Gpio, 1U); /* serialized GPIO write/read */
    return XGpio_DiscreteRead(&Gpio, 2U);
}
static int eq(const char *name, u32 got, u32 want)
{
    if (got == want) return XST_SUCCESS;
    xil_printf("[FAIL] %s expected=0x%08x got=0x%08x\r\n",
               name, (unsigned)want, (unsigned)got);
    return XST_FAILURE;
}
static u32 dma_sr(int direction)
{
    UINTPTR ch = (direction == XAXIDMA_DEVICE_TO_DMA)
                    ? (UINTPTR)XAXIDMA_RX_OFFSET : (UINTPTR)XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase + ch, XAXIDMA_SR_OFFSET);
}
static void dump_status(void)
{
    xil_printf("[DMA] MM2S=0x%08x S2MM=0x%08x\r\n",
               (unsigned)dma_sr(XAXIDMA_DMA_TO_DEVICE),
               (unsigned)dma_sr(XAXIDMA_DEVICE_TO_DMA));
    xil_printf("[MON] TX packets=%u beats=%u | RX data=%u ctx=%u ver=%u | errors=%u/%u/%u/%u\r\n",
               (unsigned)page(PG_TX_PKTS),(unsigned)page(PG_TX_BEATS),
               (unsigned)page(PG_DATA_CNT),(unsigned)page(PG_CTX_CNT),
               (unsigned)page(PG_VER_CNT),(unsigned)page(PG_E_DISP),
               (unsigned)page(PG_E_DATA),(unsigned)page(PG_E_CTX),
               (unsigned)page(PG_E_VER));
    xil_printf("[MON] Last error=0x%08x, STATUS=0x%08x\r\n",
               (unsigned)page(PG_LAST_ERR),(unsigned)rd(R_STATUS));
}
static int wait_dma(int direction, const char *name)
{
    u32 i;
    for (i=0U;i<WAIT_LIMIT;++i) {
        u32 sr = dma_sr(direction);
        if ((sr & XAXIDMA_ERR_ALL_MASK) != 0U) {
            xil_printf("[FAIL] %s DMA error SR=0x%08x\r\n",name,(unsigned)sr);
            dump_status(); return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma,direction)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s DMA timeout\r\n",name);
    dump_status(); return XST_FAILURE;
}
static int wait_count(u32 monitor_page, u32 expected, const char *name)
{
    u32 i;
    for (i=0;i<WAIT_LIMIT;++i) {
        u32 v=page(monitor_page);
        if (v == expected) return XST_SUCCESS;
        if (v > expected) break;
    }
    xil_printf("[FAIL] %s count expected=%u got=%u\r\n",
               name,(unsigned)expected,(unsigned)page(monitor_page));
    dump_status(); return XST_FAILURE;
}
static int no_rx_errors(void)
{
    if (page(PG_E_DISP)||page(PG_E_DATA)||page(PG_E_CTX)||page(PG_E_VER)) {
        xil_printf("[FAIL] Unexpected DIFI RX error event(s)\r\n");
        dump_status(); return XST_FAILURE;
    }
    return XST_SUCCESS;
}
static int commit_config(void)
{
    u32 i, status;
    wr(R_CONTROL,0U);
    if ((rd(R_STATUS) & 0x10U) == 0U) {
        xil_printf("[FAIL] time_valid not asserted; wrong B3 bitstream?\r\n");
        return XST_FAILURE;
    }
    wr(R_DATA_SID,DATA_SID);
    wr(R_VERSION_SID,VERSION_SID);
    wr(R_SAMPLES,SAMPLES);
    wr(R_SAMPLE_RATE,SAMPLE_RATE_HZ);
    wr(R_BANDWIDTH,BANDWIDTH_HZ);
    wr(R_RF_LOW,RF_FREQ_HZ);
    wr(R_RF_HIGH,0U);
    wr(R_RX_DATA_SID,DATA_SID);
    wr(R_RX_VER_SID,VERSION_SID);
    wr(R_RX_FILTER,3U); /* RX filters both enabled */
    wr(R_COMMAND,1U);   /* Shadow -> Active */
    for (i=0U;i<COMMIT_LIMIT;i++) {
        if (!(rd(R_STATUS)&1U)) break;
    }
    status=rd(R_STATUS);
    if ((status & (0x21U)) || rd(R_COMMIT_ERROR)) {
        xil_printf("[FAIL] Commit STATUS=0x%08x ERROR=0x%08x\r\n",
                   (unsigned)status,(unsigned)rd(R_COMMIT_ERROR));
        return XST_FAILURE;
    }
    if (eq("active Data SID",rd(R_ACTIVE_DATA_SID),DATA_SID) ||
        eq("active Version SID",rd(R_ACTIVE_VER_SID),VERSION_SID) ||
        eq("active samples",rd(R_ACTIVE_SAMPLES),SAMPLES) ||
        eq("active Fs",rd(R_ACTIVE_RATE),SAMPLE_RATE_HZ) ||
        eq("active BW",rd(R_ACTIVE_BW),BANDWIDTH_HZ) ||
        eq("active RF low",rd(R_ACTIVE_RF_LOW),RF_FREQ_HZ) ||
        eq("active RF high",rd(R_ACTIVE_RF_HIGH),0U)) return XST_FAILURE;
    xil_printf("[PASS] AXI4-Lite configuration/commit + RX SID filters\r\n");
    return XST_SUCCESS;
}
static int verify_initial_metadata(void)
{
    u32 vi;
    if (eq("Version SID",page(PG_VER_SID),VERSION_SID) ||
        eq("Version seq/changed",page(PG_VER_SQC),0x10U) ||
        eq("Version sec",page(PG_VER_SEC),TEST_SEC) ||
        eq("Version ps high",page(PG_VER_PSH),0U) ||
        eq("Version ps low",page(PG_VER_PSL),0U) ||
        eq("Context SID",page(PG_CTX_SID),DATA_SID) ||
        eq("Context seq/changed",page(PG_CTX_SQC),0x10U) ||
        eq("Context BW",page(PG_CTX_BW),BANDWIDTH_HZ) ||
        eq("Context RF hi",page(PG_CTX_RFHI),0U) ||
        eq("Context RF low",page(PG_CTX_RFLO),RF_FREQ_HZ) ||
        eq("Context Fs",page(PG_CTX_FS),SAMPLE_RATE_HZ) ||
        eq("Context sec",page(PG_CTX_SEC),TEST_SEC) ||
        eq("Context ps hi",page(PG_CTX_PSH),0U) ||
        eq("Context ps low",page(PG_CTX_PSL),0U)) return XST_FAILURE;
    vi = page(PG_VER_INFO);
    if ((vi & 0xFFFFU)!=0x0400U || ((vi>>16)&0x1FFU)<1U ||
        ((vi>>16)&0x1FFU)>366U) {
        xil_printf("[FAIL] Version info invalid 0x%08x\r\n",(unsigned)vi);
        return XST_FAILURE;
    }
    if (eq("TX packet count after startup",page(PG_TX_PKTS),2U) ||
        eq("TX beat count after startup",page(PG_TX_BEATS),38U)) return XST_FAILURE;
    if ((rd(R_STATUS) & 2U) != 0U) {
        xil_printf("[FAIL] Context change pending did not clear\r\n");
        return XST_FAILURE;
    }
    xil_printf("[PASS] TX->RX Version + Context metadata, 2 packets / 38 words\r\n");
    return no_rx_errors();
}
static void make_iq(u32 round)
{
    u32 i;
    for (i=0U;i<SAMPLES;i++) {
        u32 i_val=(0x1000U + i + 0x0200U*round)&0xFFFFU;
        u32 q_val=(0xA000U + 3U*i + 0x0011U*round)&0xFFFFU;
        TxIQ[i]=(i_val<<16)|q_val;
        RxIQ[i]=0xDEADBEEFU;
    }
    Xil_DCacheFlushRange((INTPTR)TxIQ,(u32)sizeof(TxIQ));
    Xil_DCacheFlushRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
    Xil_DCacheInvalidateRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
}
static int data_loopback(u32 round)
{
    int rc;
    u32 i;
    make_iq(round);
    rc=XAxiDma_SimpleTransfer(&Dma,(UINTPTR)RxIQ,
                              SAMPLES*4U,XAXIDMA_DEVICE_TO_DMA);
    if (rc!=XST_SUCCESS) {
        xil_printf("[FAIL] S2MM arm rc=%d\r\n",rc); dump_status();
        return XST_FAILURE;
    }
    xil_printf("[START] Data #%u: S2MM armed (%u B)\r\n",
               (unsigned)round,(unsigned)(SAMPLES*4U));
    rc=XAxiDma_SimpleTransfer(&Dma,(UINTPTR)TxIQ,
                              SAMPLES*4U,XAXIDMA_DMA_TO_DEVICE);
    if (rc!=XST_SUCCESS) {
        xil_printf("[FAIL] MM2S start rc=%d\r\n",rc); dump_status();
        return XST_FAILURE;
    }
    xil_printf("[START] Data #%u: MM2S started (%u B)\r\n",
               (unsigned)round,(unsigned)(SAMPLES*4U));
    if (wait_dma(XAXIDMA_DMA_TO_DEVICE,"IQ MM2S") ||
        wait_dma(XAXIDMA_DEVICE_TO_DMA,"IQ S2MM") ||
        wait_count(PG_DATA_CNT,round+1U,"Data metadata")) return XST_FAILURE;
    Xil_DCacheInvalidateRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
    if (eq("Data SID",page(PG_DATA_SID),DATA_SID) ||
        eq("Data sample_count/seq",page(PG_DATA_SZQ),(SAMPLES<<4)|(round&15U)) ||
        eq("Data time sec",page(PG_DATA_SEC),TEST_SEC) ||
        eq("Data time ps high",page(PG_DATA_PSH),0U) ||
        eq("Data time ps low",page(PG_DATA_PSL),0U)) return XST_FAILURE;
    for (i=0;i<SAMPLES;i++) {
        if (RxIQ[i]!=TxIQ[i]) {
            xil_printf("[FAIL] Round %u IQ[%u] expected=0x%08x got=0x%08x\r\n",
                       (unsigned)round,(unsigned)i,
                       (unsigned)TxIQ[i],(unsigned)RxIQ[i]);
            dump_status(); return XST_FAILURE;
        }
    }
    if (eq("TX total packets",page(PG_TX_PKTS),3U+round) ||
        eq("TX total beats",page(PG_TX_BEATS),38U+263U*(round+1U)) ||
        eq("Context count remains one",page(PG_CTX_CNT),1U) ||
        eq("Version count remains one",page(PG_VER_CNT),1U)) return XST_FAILURE;
    if (no_rx_errors()) return XST_FAILURE;
    xil_printf("[PASS] Data #%u loopback: 256/256 IQ match, seq=%u\r\n",
               (unsigned)round,(unsigned)(round&15U));
    return XST_SUCCESS;
}
int main(void)
{
    XAxiDma_Config *cfg;
    int rc;
    u32 i;
    xil_printf("\r\n============================================\r\n");
    xil_printf(" DIFI Stage B3: FPGA TX -> RX Loopback\r\n");
    xil_printf("============================================\r\n");
    xil_printf("[INFO] DIFI AXI-Lite base=0x%08x\r\n",(unsigned)DIFI_CTRL_BASE);
    cfg=XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (cfg==NULL || XAxiDma_CfgInitialize(&Dma,cfg)!=XST_SUCCESS ||
        XAxiDma_HasSg(&Dma)) {
        xil_printf("[FAIL] DMA init (must use Simple mode)\r\n");
        return XST_FAILURE;
    }
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    rc=XGpio_Initialize(&Gpio,GPIO_IDENTIFIER);
    if (rc!=XST_SUCCESS) {
        xil_printf("[FAIL] GPIO init rc=%d\r\n",rc); return XST_FAILURE;
    }
    XGpio_SetDataDirection(&Gpio,1U,0U);           /* 5-bit page select output */
    XGpio_SetDataDirection(&Gpio,2U,0xFFFFFFFFU);  /* 32-bit page data input */
    wr(R_CONTROL,0U);
    if (eq("B3 monitor ID",page(PG_MAGIC),0xB3000003U) ||
        eq("B3 page selector",page(31U),0xB3F0001FU)) {
        xil_printf("[HINT] Check B3 bitstream and GPIO CH1/CH2 connections.\r\n");
        return XST_FAILURE;
    }
    for (i=1U;i<=7U;i++) {
        if (eq("counter reset",page(i),0U)) {
            xil_printf("[HINT] Reprogram PL before this test.\r\n");
            return XST_FAILURE;
        }
    }
    if (eq("TX packet counter reset",page(PG_TX_PKTS),0U) ||
        eq("TX beat counter reset",page(PG_TX_BEATS),0U)) return XST_FAILURE;
    xil_printf("[OK] Stage B3 monitor and reset counters\r\n");
    if (commit_config()) return XST_FAILURE;

    wr(R_CONTROL,1U);
    xil_printf("[START] Engine TX enabled; waiting for Version -> Context\r\n");
    if (wait_count(PG_VER_CNT,1U,"Version RX") ||
        wait_count(PG_CTX_CNT,1U,"Context RX") ||
        verify_initial_metadata()) return XST_FAILURE;

    for (i=0U;i<2U;i++) {
        if (data_loopback(i)) return XST_FAILURE;
    }
    if (eq("final Data RX count",page(PG_DATA_CNT),2U) ||
        eq("final Context RX count",page(PG_CTX_CNT),1U) ||
        eq("final Version RX count",page(PG_VER_CNT),1U)) return XST_FAILURE;
    dump_status();
    xil_printf("\r\n[DIFI STAGE-B3 TEST PASSED]\r\n");
    return XST_SUCCESS;
}
