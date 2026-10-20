/*
 * DIFI 1.1 Managed IP - packaged-IP independent validation
 * Platform: Zynq-7000, Vitis 2024.2 standalone, 100-MHz PL.
 * DDR -> AXI DMA MM2S -> DIFI TX -> DIFI RX -> AXI DMA S2MM -> DDR.
 * No AXI GPIO dependency. A test timestamp is used, NOT synchronized UTC.
 * The IP example design MUST connect all RX metadata READY pins to 1.
 * TX IQ's data_available MUST follow the AXIS IQ TVALID signal.
 * Set CTRL/TIME BASE addresses to the new XSA mapping before compiling.
 */
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"
#include "difi_ip_addresses.h"

#if defined(SDT)
# define DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
#else
# define DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
#endif

#define N_SAMPLES          256U
#define NUM_ROUNDS           2U
#define DMA_SPIN_LIMIT 100000000U

/* Byte offsets within AXI4-Lite S_AXI_CTRL */
#define C_CONTROL          0x00U
#define C_COMMAND          0x04U
#define C_STATUS           0x08U
#define C_COMMIT_ERROR     0x0CU
#define C_DATA_SID         0x10U
#define C_VER_SID          0x14U
#define C_SAMPLES          0x18U
#define C_FS               0x1CU
#define C_BW               0x20U
#define C_RF_LO            0x24U
#define C_RF_HI            0x28U
#define C_CTX_PERIOD       0x2CU
#define C_VER_PERIOD       0x30U
#define C_RX_FILTER        0x34U
#define C_RX_DATA_SID      0x38U
#define C_RX_VER_SID       0x3CU
#define C_ACTIVE_SAMPLES   0x48U

/* Byte offsets within AXI4-Lite S_AXI_TIME */
#define T_SEC              0x00U
#define T_PS_LO            0x04U
#define T_PS_HI            0x08U
#define T_COMMAND          0x0CU
#define T_STATUS           0x10U

#define TEST_TIME_SEC     1700000000U /* synthetic test timestamp, not real UTC */
#define TEST_DATA_SID     0x10203040U
#define TEST_VERSION_SID  0x55667788U
#define TEST_SAMPLE_RATE   2000000U
#define TEST_BANDWIDTH     1500000U
#define TEST_RF_FREQ     915000000U

static XAxiDma Dma;
static u32 TxIQ[N_SAMPLES] __attribute__((aligned(64)));
static u32 RxIQ[N_SAMPLES] __attribute__((aligned(64)));

static void cwr(u32 offset, u32 data) {
    Xil_Out32((UINTPTR)DIFI_CTRL_BASE + offset, data);
}
static u32 crd(u32 offset) {
    return Xil_In32((UINTPTR)DIFI_CTRL_BASE + offset);
}
static void twr(u32 offset, u32 data) {
    Xil_Out32((UINTPTR)DIFI_TIME_BASE + offset, data);
}
static u32 trd(u32 offset) {
    return Xil_In32((UINTPTR)DIFI_TIME_BASE + offset);
}
static int fail(const char *why) {
    xil_printf("[FAIL] %s\r\n", why);
    return XST_FAILURE;
}
static int wait_dma(int direction, const char *name) {
    UINTPTR off = (direction == XAXIDMA_DEVICE_TO_DMA) ?
                 (UINTPTR)XAXIDMA_RX_OFFSET : (UINTPTR)XAXIDMA_TX_OFFSET;
    u32 n;
    for (n = 0; n < DMA_SPIN_LIMIT; ++n) {
        u32 sr = XAxiDma_ReadReg(Dma.RegBase + off, XAXIDMA_SR_OFFSET);
        if (sr & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("[FAIL] %s DMA error, status=%08x\r\n", name, (unsigned)sr);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma, direction))
            return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s DMA timeout, status=%08x\r\n", name,
               (unsigned)XAxiDma_ReadReg(Dma.RegBase + off, XAXIDMA_SR_OFFSET));
    return XST_FAILURE;
}
static int configure_time(void) {
    u32 k;
    if (trd(T_STATUS) & 1U)
        return fail("TIME already valid; reprogram FPGA for clean reset");
    twr(T_SEC, TEST_TIME_SEC);
    twr(T_PS_LO, 0U);
    twr(T_PS_HI, 0U);
    twr(T_COMMAND, 1U);
    for (k = 0; k < 50000U; ++k) {
        u32 s = trd(T_STATUS);
        if (s & 2U) return fail("TIME load rejected");
        if (s & 1U) {
            if (!(crd(C_STATUS) & (1U << 4)))
                return fail("time_valid not propagated to engine");
            xil_printf("[PASS] time source initialized with synthetic sec=%u\r\n",
                       (unsigned)TEST_TIME_SEC);
            return XST_SUCCESS;
        }
    }
    return fail("TIME status not valid (check S_AXI_TIME address)");
}
static int configure_engine(void) {
    u32 k;
    cwr(C_CONTROL, 0U);
    cwr(C_DATA_SID, TEST_DATA_SID);
    cwr(C_VER_SID, TEST_VERSION_SID);
    cwr(C_SAMPLES, N_SAMPLES);
    cwr(C_FS, TEST_SAMPLE_RATE);
    cwr(C_BW, TEST_BANDWIDTH);
    cwr(C_RF_LO, TEST_RF_FREQ);
    cwr(C_RF_HI, 0U);
    cwr(C_CTX_PERIOD, 0U); /* disable periodic packets, keep startup Context */
    cwr(C_VER_PERIOD, 0U); /* disable periodic packets, keep startup Version */
    cwr(C_RX_FILTER, 3U);
    cwr(C_RX_DATA_SID, TEST_DATA_SID);
    cwr(C_RX_VER_SID, TEST_VERSION_SID);
    cwr(C_COMMAND, 1U); /* shadow -> active commit */
    for (k = 0; k < 100000U; ++k)
        if (!(crd(C_STATUS) & 1U)) break;
    if (k == 100000U || crd(C_COMMIT_ERROR) != 0U ||
        (crd(C_STATUS) & (1U << 5)))
        return fail("config commit failed");
    if (crd(C_ACTIVE_SAMPLES) != N_SAMPLES)
        return fail("active samples mismatch");
    xil_printf("[PASS] config commit, active samples=%u\r\n",
               (unsigned)crd(C_ACTIVE_SAMPLES));
    return XST_SUCCESS;
}
static int loopback_round(u32 round) {
    u32 i;
    for (i = 0; i < N_SAMPLES; ++i) {
        u32 iv = (0x1000U + i + 0x0200U * round) & 0xFFFFU;
        u32 qv = (0xA000U + 3U * i + 0x0011U * round) & 0xFFFFU;
        TxIQ[i] = (iv << 16) | qv;
        RxIQ[i] = 0xDEADBEEFU;
    }
    Xil_DCacheFlushRange((INTPTR)TxIQ, (u32)sizeof(TxIQ));
    Xil_DCacheFlushRange((INTPTR)RxIQ, (u32)sizeof(RxIQ));
    Xil_DCacheInvalidateRange((INTPTR)RxIQ, (u32)sizeof(RxIQ));

    /* Always arm the receive channel first. */
    if (XAxiDma_SimpleTransfer(&Dma, (UINTPTR)RxIQ, sizeof(RxIQ),
                               XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS)
        return fail("failed to arm S2MM");
    if (XAxiDma_SimpleTransfer(&Dma, (UINTPTR)TxIQ, sizeof(TxIQ),
                               XAXIDMA_DMA_TO_DEVICE) != XST_SUCCESS)
        return fail("failed to start MM2S");
    if (wait_dma(XAXIDMA_DMA_TO_DEVICE, "MM2S") != XST_SUCCESS ||
        wait_dma(XAXIDMA_DEVICE_TO_DMA, "S2MM") != XST_SUCCESS)
        return XST_FAILURE;

    Xil_DCacheInvalidateRange((INTPTR)RxIQ, (u32)sizeof(RxIQ));
    for (i = 0; i < N_SAMPLES; ++i) {
        if (TxIQ[i] != RxIQ[i]) {
            xil_printf("[FAIL] round %u IQ[%u]: TX=%08x RX=%08x\r\n",
                       (unsigned)round, (unsigned)i,
                       (unsigned)TxIQ[i], (unsigned)RxIQ[i]);
            return XST_FAILURE;
        }
    }
    xil_printf("[PASS] round %u: 256/256 IQ match\r\n", (unsigned)round);
    return XST_SUCCESS;
}
int main(void) {
    XAxiDma_Config *dcfg;
    u32 round;
    xil_printf("\r\n=== DIFI PACKAGED IP LOOPBACK VALIDATION ===\r\n");
    xil_printf("CTRL_BASE=%08x TIME_BASE=%08x\r\n",
               (unsigned)DIFI_CTRL_BASE, (unsigned)DIFI_TIME_BASE);
    xil_printf("DMA identifier=%08x\r\n", (unsigned)DMA_IDENTIFIER);

    dcfg = XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (!dcfg || XAxiDma_CfgInitialize(&Dma, dcfg) != XST_SUCCESS ||
        XAxiDma_HasSg(&Dma))
        return fail("DMA init failed or scatter-gather mode enabled");
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    if (configure_time() != XST_SUCCESS ||
        configure_engine() != XST_SUCCESS)
        return XST_FAILURE;

    cwr(C_CONTROL, 1U); /* enable TX: startup Version and changed Context */
    usleep(10000);     /* allow startup packets to pass through internal loopback */
    if (!(crd(C_STATUS) & (1U << 3)))
        return fail("TX enable state not set");
    for (round = 0; round < NUM_ROUNDS; ++round)
        if (loopback_round(round) != XST_SUCCESS)
            return XST_FAILURE;

    xil_printf("\r\n[ALL PACKAGED-IP LOOPBACK TESTS PASSED]\r\n");
    xil_printf("[NOTE] This checks IQ equivalence, not RX metadata/error counters or UTC accuracy.\r\n");
    return XST_SUCCESS;
}
