/* Stage B1: check configuration and Version, Context, and Data packets. */

#include <stddef.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"

#if defined(SDT)
  #ifndef XPAR_XAXIDMA_0_BASEADDR
    #error "Missing XPAR_XAXIDMA_0_BASEADDR; rebuild Platform from B1 XSA"
  #endif
  #define DIFI_DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
#else
  #define DIFI_DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
#endif

#ifndef DIFI_CTRL_BASE
#define DIFI_CTRL_BASE       0x40000000U
#endif

#define REG_CONTROL          0x00U
#define REG_COMMAND          0x04U
#define REG_STATUS           0x08U
#define REG_COMMIT_ERROR     0x0CU
#define REG_DATA_SID         0x10U
#define REG_VERSION_SID      0x14U
#define REG_SAMPLES          0x18U
#define REG_SAMPLE_RATE      0x1CU
#define REG_BANDWIDTH        0x20U
#define REG_RF_LOW           0x24U
#define REG_RF_HIGH          0x28U
#define REG_ACTIVE_DATA_SID  0x40U
#define REG_ACTIVE_VER_SID   0x44U
#define REG_ACTIVE_SAMPLES   0x48U
#define REG_ACTIVE_RATE      0x4CU
#define REG_ACTIVE_BW        0x50U
#define REG_ACTIVE_RF_LOW    0x54U
#define REG_ACTIVE_RF_HIGH   0x58U

#define ST_COMMIT_PENDING    0x01U
#define ST_CONTEXT_PENDING   0x02U
#define ST_TX_ENABLE         0x08U
#define ST_TIME_VALID        0x10U
#define ST_COMMIT_ERROR      0x20U

#define IQ_SAMPLES           256U
#define VERSION_WORDS        11U
#define CONTEXT_WORDS        27U
#define DATA_HEADER_WORDS    7U
#define DATA_WORDS           (DATA_HEADER_WORDS + IQ_SAMPLES)
#define RX_CAPACITY_WORDS    272U
#define POLL_LIMIT           50000000U
#define COMMIT_POLL_LIMIT    1000000U

#define TEST_DATA_SID        0x10203040U
#define TEST_VERSION_SID     0x55667788U
#define TEST_SAMPLE_RATE_HZ  2000000U
#define TEST_BANDWIDTH_HZ    1500000U
#define TEST_RF_FREQ_HZ      915000000U
#define TEST_TIME_SEC        0x6553F100U

static XAxiDma Dma;
static u32 TxWords[IQ_SAMPLES] __attribute__((aligned(64)));
static u32 RxWords[RX_CAPACITY_WORDS] __attribute__((aligned(64)));

static void reg_write(u32 offset, u32 value)
{
    Xil_Out32((UINTPTR)DIFI_CTRL_BASE + offset, value);
}

static u32 reg_read(u32 offset)
{
    return Xil_In32((UINTPTR)DIFI_CTRL_BASE + offset);
}

static u32 dma_status(int direction)
{
    UINTPTR channel = (direction == XAXIDMA_DEVICE_TO_DMA)
                        ? (UINTPTR)XAXIDMA_RX_OFFSET
                        : (UINTPTR)XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase + channel, XAXIDMA_SR_OFFSET);
}

static void dump_dma(void)
{
    xil_printf("[DMA] MM2S_DMASR=0x%08x S2MM_DMASR=0x%08x\r\n",
               (unsigned)dma_status(XAXIDMA_DMA_TO_DEVICE),
               (unsigned)dma_status(XAXIDMA_DEVICE_TO_DMA));
}

static int wait_dma(int direction, const char *name)
{
    u32 i;
    for (i = 0; i < POLL_LIMIT; ++i) {
        u32 sr = dma_status(direction);
        if ((sr & XAXIDMA_ERR_ALL_MASK) != 0U) {
            xil_printf("[FAIL] %s DMA error SR=0x%08x\r\n", name, (unsigned)sr);
            dump_dma();
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma, direction)) {
            return XST_SUCCESS;
        }
    }
    xil_printf("[FAIL] %s DMA timeout\r\n", name);
    dump_dma();
    xil_printf("[DEBUG] DIFI STATUS=0x%08x\r\n", (unsigned)reg_read(REG_STATUS));
    return XST_FAILURE;
}

static int check_word(const char *kind, u32 index, u32 got, u32 expected)
{
    if (got == expected) {
        return 0;
    }
    xil_printf("[MISMATCH] %s word[%u] exp=0x%08x got=0x%08x\r\n",
               kind, (unsigned)index, (unsigned)expected, (unsigned)got);
    return 1;
}

static int check_register(u32 offset, u32 expected, const char *name)
{
    u32 actual = reg_read(offset);
    if (actual != expected) {
        xil_printf("[FAIL] Active %s: exp=0x%08x got=0x%08x\r\n",
                   name, (unsigned)expected, (unsigned)actual);
        return XST_FAILURE;
    }
    xil_printf("[OK] Active %s=0x%08x\r\n", name, (unsigned)actual);
    return XST_SUCCESS;
}

static int commit_configuration(void)
{
    u32 i;
    u32 status;
    
    reg_write(REG_CONTROL, 0U);
    status = reg_read(REG_STATUS);
    xil_printf("[CFG] Initial STATUS=0x%08x\r\n", (unsigned)status);
    if ((status & ST_TIME_VALID) == 0U) {
        xil_printf("[FAIL] Stage B1 time_valid is 0 (check PL/XSA)\r\n");
        return XST_FAILURE;
    }
    if ((status & ST_COMMIT_PENDING) != 0U) {
        xil_printf("[FAIL] Old commit is still pending. Reprogram PL first.\r\n");
        return XST_FAILURE;
    }

    reg_write(REG_DATA_SID, TEST_DATA_SID);
    reg_write(REG_VERSION_SID, TEST_VERSION_SID);
    reg_write(REG_SAMPLES, IQ_SAMPLES);
    reg_write(REG_SAMPLE_RATE, TEST_SAMPLE_RATE_HZ);
    reg_write(REG_BANDWIDTH, TEST_BANDWIDTH_HZ);
    reg_write(REG_RF_LOW, TEST_RF_FREQ_HZ);
    reg_write(REG_RF_HIGH, 0U);
    reg_write(REG_COMMAND, 1U); 

    for (i = 0; i < COMMIT_POLL_LIMIT; ++i) {
        status = reg_read(REG_STATUS);
        if ((status & ST_COMMIT_PENDING) == 0U) {
            break;
        }
    }
    status = reg_read(REG_STATUS);
    if ((status & ST_COMMIT_PENDING) != 0U ||
        (status & ST_COMMIT_ERROR) != 0U ||
        reg_read(REG_COMMIT_ERROR) != 0U) {
        xil_printf("[FAIL] Config commit STATUS=0x%08x ERR=%u\r\n",
                   (unsigned)status, (unsigned)reg_read(REG_COMMIT_ERROR));
        return XST_FAILURE;
    }

    if (check_register(REG_ACTIVE_DATA_SID, TEST_DATA_SID, "Data SID") != XST_SUCCESS ||
        check_register(REG_ACTIVE_VER_SID, TEST_VERSION_SID, "Version SID") != XST_SUCCESS ||
        check_register(REG_ACTIVE_SAMPLES, IQ_SAMPLES, "Samples") != XST_SUCCESS ||
        check_register(REG_ACTIVE_RATE, TEST_SAMPLE_RATE_HZ, "Sample Rate") != XST_SUCCESS ||
        check_register(REG_ACTIVE_BW, TEST_BANDWIDTH_HZ, "Bandwidth") != XST_SUCCESS ||
        check_register(REG_ACTIVE_RF_LOW, TEST_RF_FREQ_HZ, "RF Low") != XST_SUCCESS ||
        check_register(REG_ACTIVE_RF_HIGH, 0U, "RF High") != XST_SUCCESS) {
        return XST_FAILURE;
    }
    xil_printf("[PASS] AXI4-Lite Shadow->Active commit\r\n");
    return XST_SUCCESS;
}

static void prepare_iq(void)
{
    u32 i;
    for (i = 0U; i < IQ_SAMPLES; ++i) {
        u32 i16 = (0x1000U + i) & 0xFFFFU;
        u32 q16 = (0xA000U + (3U * i)) & 0xFFFFU;
        TxWords[i] = (i16 << 16) | q16;
    }
    Xil_DCacheFlushRange((INTPTR)TxWords, (u32)sizeof(TxWords));
}

static int arm_rx(u32 packet_words, const char *name)
{
    u32 i;
    int rc;
    if (packet_words > RX_CAPACITY_WORDS) {
        return XST_FAILURE;
    }
    for (i = 0U; i < RX_CAPACITY_WORDS; ++i) {
        RxWords[i] = 0xDEADBEEFU;
    }
    Xil_DCacheFlushRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    Xil_DCacheInvalidateRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)RxWords,
                                packet_words * 4U, XAXIDMA_DEVICE_TO_DMA);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] Arm %s S2MM rc=%d\r\n", name, rc);
        dump_dma();
        return XST_FAILURE;
    }
    xil_printf("[START] %s S2MM armed (%u B)\r\n", name,
               (unsigned)(packet_words * 4U));
    return XST_SUCCESS;
}

static int finish_rx(const char *name)
{
    if (wait_dma(XAXIDMA_DEVICE_TO_DMA, name) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    Xil_DCacheInvalidateRange((INTPTR)RxWords, (u32)sizeof(RxWords));
    xil_printf("[OK] %s received: Word0=0x%08x SID=0x%08x\r\n",
               name, (unsigned)RxWords[0], (unsigned)RxWords[1]);
    return XST_SUCCESS;
}

static int verify_version(void)
{
    const u32 expected[10] = {
        0x5960000BU, TEST_VERSION_SID, 0x006A621EU, 0x00010004U,
        TEST_TIME_SEC, 0U, 0U, 0x80000002U, 0x0000000CU, 0x00000004U
    };
    u32 i, errors = 0U;
    for (i = 0; i < 10U; ++i) {
        errors += (u32)check_word("Version", i, RxWords[i], expected[i]);
    }
    /* The build date may vary; check only Revision, Type, and ICD. */
    if ((RxWords[10] & 0xFFFFU) != 0x0400U) {
        errors += (u32)check_word("Version", 10, RxWords[10] & 0xFFFFU, 0x0400U);
    }
    xil_printf("[VERSION] Build info=0x%08x\r\n", (unsigned)RxWords[10]);
    if (errors != 0U) {
        xil_printf("[FAIL] Version errors=%u\r\n", (unsigned)errors);
        return XST_FAILURE;
    }
    xil_printf("[PASS] Version Packet: 11 words\r\n");
    return XST_SUCCESS;
}

static int verify_context(void)
{
    u32 expected[CONTEXT_WORDS] = {0U};
    u32 i, errors = 0U;
    const u64 bw_scaled = ((u64)TEST_BANDWIDTH_HZ) << 20;
    const u64 rf_scaled = ((u64)TEST_RF_FREQ_HZ) << 20;
    const u64 rate_scaled = ((u64)TEST_SAMPLE_RATE_HZ) << 20;

    expected[0] = 0x4960001BU;
    expected[1] = TEST_DATA_SID;
    expected[2] = 0x006A621EU;
    expected[3] = 0x00000001U;
    expected[4] = TEST_TIME_SEC;
    expected[7] = 0xFBB98000U; 
    expected[8] = 0x00000064U;
    expected[9] = (u32)(bw_scaled >> 32);
    expected[10] = (u32)bw_scaled;
    expected[13] = (u32)(rf_scaled >> 32);
    expected[14] = (u32)rf_scaled;
    expected[19] = (u32)(rate_scaled >> 32);
    expected[20] = (u32)rate_scaled;
    expected[25] = 0xA00003CFU;

    for (i = 0; i < CONTEXT_WORDS; ++i) {
        errors += (u32)check_word("Context", i, RxWords[i], expected[i]);
    }
    if (errors != 0U) {
        xil_printf("[FAIL] Context errors=%u\r\n", (unsigned)errors);
        return XST_FAILURE;
    }
    xil_printf("[PASS] Context Packet: 27 words, BW/RF/Fs/DPF match\r\n");
    return XST_SUCCESS;
}

static int verify_data(void)
{
    u32 i, errors = 0U;
    const u32 header[DATA_HEADER_WORDS] = {
        0x18600107U, TEST_DATA_SID, 0x006A621EU, 0U,
        TEST_TIME_SEC, 0U, 0U
    };
    for (i = 0; i < DATA_HEADER_WORDS; ++i) {
        errors += (u32)check_word("Data", i, RxWords[i], header[i]);
    }
    for (i = 0U; i < IQ_SAMPLES; ++i) {
        if (RxWords[DATA_HEADER_WORDS + i] != TxWords[i]) {
            if (errors < 12U) {
                xil_printf("[MISMATCH] IQ[%u] exp=0x%08x got=0x%08x\r\n",
                           (unsigned)i, (unsigned)TxWords[i],
                           (unsigned)RxWords[DATA_HEADER_WORDS + i]);
            }
            errors++;
        }
    }
    if (errors != 0U) {
        xil_printf("[FAIL] Data errors=%u\r\n", (unsigned)errors);
        return XST_FAILURE;
    }
    xil_printf("[PASS] Data Packet: 7 header + 256 IQ samples\r\n");
    return XST_SUCCESS;
}

int main(void)
{
    XAxiDma_Config *cfg;
    int rc;
    u32 status;

    xil_printf("\r\n============================================\r\n");
    xil_printf(" DIFI Stage-B1: TX + AXI4-Lite + AXI DMA\r\n");
    xil_printf(" Version(44B) -> Context(108B) -> Data(1052B)\r\n");
    xil_printf("============================================\r\n");
    xil_printf("[INFO] DIFI AXI4-Lite base=0x%08x\r\n", (unsigned)DIFI_CTRL_BASE);

    cfg = XAxiDma_LookupConfig(DIFI_DMA_IDENTIFIER);
    if (cfg == NULL) {
        xil_printf("[FAIL] DMA LookupConfig=NULL (check BSP/XSA)\r\n");
        return XST_FAILURE;
    }
    rc = XAxiDma_CfgInitialize(&Dma, cfg);
    if (rc != XST_SUCCESS || XAxiDma_HasSg(&Dma)) {
        xil_printf("[FAIL] DMA initialization or SG mode, rc=%d\r\n", rc);
        return XST_FAILURE;
    }
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    xil_printf("[INIT] TX DDR=0x%08x RX DDR=0x%08x\r\n",
               (unsigned)(UINTPTR)TxWords, (unsigned)(UINTPTR)RxWords);

    if (commit_configuration() != XST_SUCCESS) {
        goto failed;
    }
    prepare_iq();

    if (arm_rx(VERSION_WORDS, "Version") != XST_SUCCESS) goto failed;
    reg_write(REG_CONTROL, 1U);
    status = reg_read(REG_STATUS);
    if ((status & ST_TX_ENABLE) == 0U) {
        xil_printf("[FAIL] TX_ENABLE readback low after enabling\r\n");
        goto failed;
    }
    xil_printf("[START] Engine TX enabled\r\n");
    if (finish_rx("Version") != XST_SUCCESS) goto failed;
    if (verify_version() != XST_SUCCESS) goto failed;

    if (arm_rx(CONTEXT_WORDS, "Context") != XST_SUCCESS) goto failed;
    if (finish_rx("Context") != XST_SUCCESS) goto failed;
    if (verify_context() != XST_SUCCESS) goto failed;

    if (arm_rx(DATA_WORDS, "Data") != XST_SUCCESS) goto failed;
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)TxWords,
                                IQ_SAMPLES * 4U, XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] MM2S start rc=%d\r\n", rc);
        dump_dma();
        goto failed;
    }
    xil_printf("[START] MM2S armed (1024 B IQ)\r\n");
    if (wait_dma(XAXIDMA_DMA_TO_DEVICE, "MM2S") != XST_SUCCESS) goto failed;
    if (finish_rx("Data") != XST_SUCCESS) goto failed;
    if (verify_data() != XST_SUCCESS) goto failed;

    status = reg_read(REG_STATUS);
    xil_printf("[CFG] Final STATUS=0x%08x (Context pending should clear)\r\n",
               (unsigned)status);
    dump_dma();
    reg_write(REG_CONTROL, 0U);
    xil_printf("\r\n[DIFI STAGE-B1 TEST PASSED]\r\n");
    return XST_SUCCESS;

failed:
    reg_write(REG_CONTROL, 0U);
    xil_printf("\r\n[DIFI STAGE-B1 TEST FAILED]\r\n");
    return XST_FAILURE;
}
