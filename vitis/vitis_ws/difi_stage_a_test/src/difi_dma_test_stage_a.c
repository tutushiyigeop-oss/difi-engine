/*
 * DIFI Stage-A board test: Zynq-7020, Vitis 2024.2, standalone.
 *
 * HW: AXI DMA MM2S -> difi_tx_board_test/S_AXIS_IQ
 *     difi_tx_board_test/M_AXIS_PKT -> AXI DMA S2MM
 *     AXI GPIO channel 1 bit 0 -> difi_tx_board_test/start_level
 *
 * The test wrapper fixes: stream_id=1, samples=256,
 * time_sec=1700000000 (0x6553F100), time_ps=0.
 * The DIFI Packetizer emits 7 header words + 256 IQ words = 1052 bytes.
 *
 * The buffers below should be linked into PS DDR, which is accessible
 * from the DMA through the Zynq PS S_AXI_HP0 interface.
 */

#include <stddef.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xgpio.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"

/* Support 2024.2 SDT platforms and legacy BSP configurations. */
#ifdef SDT
  #ifndef XPAR_XAXIDMA_0_BASEADDR
    #error "Missing XPAR_XAXIDMA_0_BASEADDR. Check the generated xparameters.h"
  #endif
  #ifndef XPAR_XGPIO_0_BASEADDR
    #error "Missing XPAR_XGPIO_0_BASEADDR. Check the generated xparameters.h"
  #endif
  #define DIFI_DMA_IDENTIFIER   XPAR_XAXIDMA_0_BASEADDR
  #define DIFI_GPIO_IDENTIFIER  XPAR_XGPIO_0_BASEADDR
#else
  #define DIFI_DMA_IDENTIFIER   XPAR_AXIDMA_0_DEVICE_ID
  #define DIFI_GPIO_IDENTIFIER  XPAR_GPIO_0_DEVICE_ID
#endif

#define DIFI_SAMPLES      256U
#define DIFI_HEADER_WORDS 7U
#define DIFI_PACKET_WORDS (DIFI_HEADER_WORDS + DIFI_SAMPLES)
#define TX_BYTES          (DIFI_SAMPLES * sizeof(u32))
#define RX_BYTES          (DIFI_PACKET_WORDS * sizeof(u32))
#define GPIO_CHANNEL      1U
#define POLL_LIMIT        50000000U

/* Pad the RX storage to a cacheline-aligned size: 272 words = 1088 B. */
static u32 TxBuffer[DIFI_SAMPLES] __attribute__((aligned(64)));
static u32 RxBuffer[272] __attribute__((aligned(64)));
static XAxiDma AxiDma;
static XGpio Gpio;

static u32 dma_status(int direction)
{
    UINTPTR offset = (direction == XAXIDMA_DEVICE_TO_DMA)
                        ? (UINTPTR)XAXIDMA_RX_OFFSET
                        : (UINTPTR)XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(AxiDma.RegBase + offset, XAXIDMA_SR_OFFSET);
}

static void dump_dma_status(void)
{
    xil_printf("[DMA] MM2S_DMASR=0x%08x  S2MM_DMASR=0x%08x\r\n",
               (unsigned int)dma_status(XAXIDMA_DMA_TO_DEVICE),
               (unsigned int)dma_status(XAXIDMA_DEVICE_TO_DMA));
}

static int wait_dma(int direction, const char *name)
{
    u32 i;
    u32 sr;
    for (i = 0U; i < POLL_LIMIT; ++i) {
        sr = dma_status(direction);
        if ((sr & XAXIDMA_ERR_ALL_MASK) != 0U) {
            xil_printf("[FAIL] %s DMA error; DMASR=0x%08x\r\n",
                       name, (unsigned int)sr);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&AxiDma, direction)) {
            return XST_SUCCESS;
        }
    }
    xil_printf("[FAIL] %s DMA timeout\r\n", name);
    dump_dma_status();
    return XST_FAILURE;
}

static void prepare_buffers(void)
{
    u32 i;
    for (i = 0U; i < DIFI_SAMPLES; ++i) {
        u32 i16 = (0x1000U + i) & 0xFFFFU;
        u32 q16 = (0xA000U + 3U * i) & 0xFFFFU;
        TxBuffer[i] = (i16 << 16) | q16;
    }
    for (i = 0U; i < 272U; ++i) {
        RxBuffer[i] = 0xDEADBEEFU;
    }

    /* DMA is not cache-coherent with the Zynq-7000 ARM caches over HP0. */
    Xil_DCacheFlushRange((INTPTR)TxBuffer, (u32)sizeof(TxBuffer));
    Xil_DCacheFlushRange((INTPTR)RxBuffer, (u32)sizeof(RxBuffer));
    Xil_DCacheInvalidateRange((INTPTR)RxBuffer, (u32)sizeof(RxBuffer));
}

static int validate_packet(void)
{
    u32 i;
    u32 mismatches = 0U;
    u32 seq;
    u32 expected[DIFI_HEADER_WORDS] = {
        0x18600107U,  /* Data, C=1, UTC, realtime, seq=0, size=263 */
        0x00000001U,  /* Stream ID */
        0x006A621EU,  /* OUI */
        0x00000000U,  /* ICC/PCC */
        0x6553F100U,  /* Fixed synthetic UTC integer-seconds field */
        0x00000000U,  /* Fractional timestamp high */
        0x00000000U   /* Fractional timestamp low */
    };

    xil_printf("[RX] First 9 words:\r\n");
    for (i = 0U; i < 9U; ++i) {
        xil_printf("     word[%u] = 0x%08x\r\n",
                   (unsigned int)i, (unsigned int)RxBuffer[i]);
    }

    seq = (RxBuffer[0] >> 16) & 0xFU;
    xil_printf("[RX] Packet sequence = %u\r\n", (unsigned int)seq);

    /* Sequence is expected to be zero after a fresh PL reset. The
     * remaining fixed header fields should be identical on repeat runs. */
    expected[0] |= (seq << 16);

    for (i = 0U; i < DIFI_HEADER_WORDS; ++i) {
        if (RxBuffer[i] != expected[i]) {
            xil_printf("[MISMATCH] header[%u] exp=0x%08x got=0x%08x\r\n",
                       (unsigned int)i, (unsigned int)expected[i],
                       (unsigned int)RxBuffer[i]);
            ++mismatches;
        }
    }

    for (i = 0U; i < DIFI_SAMPLES; ++i) {
        if (RxBuffer[DIFI_HEADER_WORDS + i] != TxBuffer[i]) {
            if (mismatches < 12U) {
                xil_printf("[MISMATCH] IQ[%u] exp=0x%08x got=0x%08x\r\n",
                           (unsigned int)i, (unsigned int)TxBuffer[i],
                           (unsigned int)RxBuffer[DIFI_HEADER_WORDS + i]);
            }
            ++mismatches;
        }
    }

    if (mismatches != 0U) {
        xil_printf("[FAIL] DIFI packet mismatch count: %u\r\n",
                   (unsigned int)mismatches);
        return XST_FAILURE;
    }
    xil_printf("[PASS] All 7 header words and 256 IQ payload words match!\r\n");
    return XST_SUCCESS;
}

int main(void)
{
    XAxiDma_Config *cfg;
    int status;

    xil_printf("\r\n=======================================\r\n");
    xil_printf(" DIFI Stage-A / Zynq-7020 DMA Test\r\n");
    xil_printf(" IQ: %u bytes -> DIFI: %u bytes\r\n",
               (unsigned int)TX_BYTES, (unsigned int)RX_BYTES);
    xil_printf("=======================================\r\n");

    cfg = XAxiDma_LookupConfig(DIFI_DMA_IDENTIFIER);
    if (cfg == NULL) {
        xil_printf("[FAIL] XAxiDma_LookupConfig returned NULL\r\n");
        return XST_FAILURE;
    }

    status = XAxiDma_CfgInitialize(&AxiDma, cfg);
    if (status != XST_SUCCESS) {
        xil_printf("[FAIL] AXI DMA initialization: %d\r\n", status);
        return XST_FAILURE;
    }
    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("[FAIL] DMA is in Scatter-Gather mode, not Simple mode\r\n");
        return XST_FAILURE;
    }

    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DEVICE_TO_DMA);

    status = XGpio_Initialize(&Gpio, DIFI_GPIO_IDENTIFIER);
    if (status != XST_SUCCESS) {
        xil_printf("[FAIL] AXI GPIO initialization: %d\r\n", status);
        return XST_FAILURE;
    }
    XGpio_SetDataDirection(&Gpio, GPIO_CHANNEL, 0x0U); /* output */
    XGpio_DiscreteWrite(&Gpio, GPIO_CHANNEL, 0x0U);

    xil_printf("[INIT] TX buffer = 0x%08x\r\n", (unsigned int)(UINTPTR)TxBuffer);
    xil_printf("[INIT] RX buffer = 0x%08x\r\n", (unsigned int)(UINTPTR)RxBuffer);
    prepare_buffers();

    /* Step 1: prepare the receiver before there is any stream output. */
    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBuffer,
                                    (u32)RX_BYTES, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("[FAIL] S2MM start: %d\r\n", status);
        dump_dma_status();
        return XST_FAILURE;
    }
    xil_printf("[START] S2MM armed (%u B)\r\n", (unsigned int)RX_BYTES);

    /* Step 2: cause a 0->1 transition at the PL wrapper start_level. */
    usleep(20U);
    XGpio_DiscreteWrite(&Gpio, GPIO_CHANNEL, 0x1U);
    usleep(20U);
    XGpio_DiscreteWrite(&Gpio, GPIO_CHANNEL, 0x0U);
    xil_printf("[START] GPIO start pulse sent\r\n");

    /* Step 3: provide IQ samples via DDR -> MM2S -> PL. */
    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)TxBuffer,
                                    (u32)TX_BYTES, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        xil_printf("[FAIL] MM2S start: %d\r\n", status);
        dump_dma_status();
        return XST_FAILURE;
    }
    xil_printf("[START] MM2S armed (%u B)\r\n", (unsigned int)TX_BYTES);

    if (wait_dma(XAXIDMA_DMA_TO_DEVICE, "MM2S") != XST_SUCCESS) {
        return XST_FAILURE;
    }
    xil_printf("[OK] MM2S complete\r\n");

    if (wait_dma(XAXIDMA_DEVICE_TO_DMA, "S2MM") != XST_SUCCESS) {
        return XST_FAILURE;
    }
    xil_printf("[OK] S2MM complete\r\n");
    dump_dma_status();

    /* CPU must invalidate cached copies before reading data written by DMA. */
    Xil_DCacheInvalidateRange((INTPTR)RxBuffer, (u32)sizeof(RxBuffer));

    status = validate_packet();
    if (status == XST_SUCCESS) {
        xil_printf("\r\n[DIFI STAGE-A TEST PASSED]\r\n");
    } else {
        xil_printf("\r\n[DIFI STAGE-A TEST FAILED]\r\n");
    }
    return status;
}
