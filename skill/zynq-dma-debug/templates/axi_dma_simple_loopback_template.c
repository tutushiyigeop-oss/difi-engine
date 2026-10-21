/*
 * Educational template: bare-metal AXI DMA Simple Mode polling loopback.
 * Zynq-7000 / Vitis standalone, with AXI DMA MM2S connected directly to S2MM
 * through a VALID loopback-compatible AXI4-Stream path. NOT DIFI board code.
 *
 * IMPORTANT: Do not run unless the actual Vivado BD has the specified path,
 * clock/reset, cacheable DDR buffers and TLAST behavior. The user must confirm
 * the platform and address map; this example has not been built/on-board tested.
 *
 * Set DMA_LOOPBACK_HW_CONFIRMED in the project C flags after reviewing BD.
 */
#ifndef DMA_LOOPBACK_HW_CONFIRMED
#error "Define DMA_LOOPBACK_HW_CONFIRMED only after verifying hardware MM2S->S2MM path and TLAST."
#endif

#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xstatus.h"
#include <string.h>

#define WORDS 256U
#define SPIN_LIMIT 20000000U

/* SDT Vitis platforms use the base address for LookupConfig; legacy BSPs
 * usually use device ID. These macros depend on the generated xparameters.h. */
#ifdef SDT
# if defined(XPAR_XAXIDMA_0_BASEADDR)
#  define DMA_LOOKUP XPAR_XAXIDMA_0_BASEADDR
# elif defined(XPAR_AXIDMA_0_BASEADDR)
#  define DMA_LOOKUP XPAR_AXIDMA_0_BASEADDR
# elif defined(XPAR_AXI_DMA_0_BASEADDR)
#  define DMA_LOOKUP XPAR_AXI_DMA_0_BASEADDR
# else
#  error "No AXI DMA base address; inspect generated xparameters.h"
# endif
#else
# if defined(XPAR_AXIDMA_0_DEVICE_ID)
#  define DMA_LOOKUP XPAR_AXIDMA_0_DEVICE_ID
# elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
#  define DMA_LOOKUP XPAR_AXI_DMA_0_DEVICE_ID
# else
#  error "No AXI DMA device ID; inspect generated xparameters.h"
# endif
#endif

static XAxiDma Dma;
/* 64-byte alignment is conservative for the demo's cache-line maintenance. */
static u32 tx_words[WORDS] __attribute__((aligned(64)));
static u32 rx_words[WORDS] __attribute__((aligned(64)));

static u32 read_sr(int direction)
{
    u32 channel_off = (direction == XAXIDMA_DEVICE_TO_DMA) ?
        XAXIDMA_RX_OFFSET : XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase, channel_off + XAXIDMA_SR_OFFSET);
}

static int wait_channel(int direction, const char *label)
{
    u32 i;
    for (i = 0U; i < SPIN_LIMIT; ++i) {
        u32 status = read_sr(direction);
        if ((status & XAXIDMA_ERR_ALL_MASK) != 0U) {
            xil_printf("[FAIL] %s DMA error SR=%08x\r\n", label, (unsigned)status);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma, direction)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s DMA timeout SR=%08x\r\n", label,
               (unsigned)read_sr(direction));
    return XST_FAILURE;
}

int main(void)
{
    u32 i;
    int rc;
    XAxiDma_Config *config;
    xil_printf("\r\nAXI DMA Simple Mode loopback TEMPLATE\r\n");
    config = XAxiDma_LookupConfig(DMA_LOOKUP);
    if (!config) {
        xil_printf("[FAIL] DMA lookup config not found\r\n");
        return XST_FAILURE;
    }
    rc = XAxiDma_CfgInitialize(&Dma, config);
    if (rc != XST_SUCCESS || XAxiDma_HasSg(&Dma)) {
        xil_printf("[FAIL] DMA initialize failed or SG is enabled\r\n");
        return XST_FAILURE;
    }
    /* Polling mode: disable interrupts on both channels. */
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    for (i = 0U; i < WORDS; ++i) tx_words[i] = (0xA5300000U ^ i);
    memset(rx_words, 0xA5, sizeof(rx_words));
    /* CPU -> MM2S: write back CPU-produced data before DMA reads it. */
    Xil_DCacheFlushRange((INTPTR)tx_words, (u32)sizeof(tx_words));
    /* CPU touched RX sentinel: clean first so dirty cache lines cannot later
     * overwrite DMA output. Keep CPU off rx_words until S2MM completes. */
    Xil_DCacheFlushRange((INTPTR)rx_words, (u32)sizeof(rx_words));

    /* Arm S2MM before MM2S. Hardware must generate one TLAST per packet. */
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)rx_words,
                                (u32)sizeof(rx_words), XAXIDMA_DEVICE_TO_DMA);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] start S2MM rc=%d SR=%08x\r\n", rc,
                   (unsigned)read_sr(XAXIDMA_DEVICE_TO_DMA));
        return XST_FAILURE;
    }
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)tx_words,
                                (u32)sizeof(tx_words), XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] start MM2S rc=%d SR=%08x\r\n", rc,
                   (unsigned)read_sr(XAXIDMA_DMA_TO_DEVICE));
        return XST_FAILURE;
    }
    if (wait_channel(XAXIDMA_DMA_TO_DEVICE, "MM2S") != XST_SUCCESS ||
        wait_channel(XAXIDMA_DEVICE_TO_DMA, "S2MM") != XST_SUCCESS)
        return XST_FAILURE;

    /* S2MM -> CPU: discard cache lines before reading DDR results. */
    Xil_DCacheInvalidateRange((INTPTR)rx_words, (u32)sizeof(rx_words));
    for (i = 0U; i < WORDS; ++i) {
        if (rx_words[i] != tx_words[i]) {
            xil_printf("[FAIL] word=%u expected=%08x got=%08x\r\n",
                       (unsigned)i, (unsigned)tx_words[i], (unsigned)rx_words[i]);
            return XST_FAILURE;
        }
    }
    xil_printf("[PASS] DMA Simple Mode loopback, %u words correct\r\n", (unsigned)WORDS);
    return XST_SUCCESS;
}
