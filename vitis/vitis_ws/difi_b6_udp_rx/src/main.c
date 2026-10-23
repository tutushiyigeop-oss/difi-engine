/*
 * DIFI Stage B6: PC UDP -> Zynq GEM0/lwIP -> DDR -> AXI DMA MM2S
 *  -> DIFI PL RX Parser -> AXI DMA S2MM -> PS Golden IQ check -> UDP ACK.
 *
 * Target: Zynq-7020, Vitis 2024.2, Standalone, lwip220 RAW_API, NO_SYS=1.
 * This is new integration code; requires your matching B6 XSA and on-board test.
 * The B6 BD MUST route M_AXIS_MM2S to S_AXIS_RX_PKT and M_AXIS_IQ to
 * S_AXIS_S2MM; direct DIFI TX->RX loopback MUST be disconnected.
 *
 * Scope v0.1: 1..N valid Data packets, 256 IQ each; no Context/Version
 * metadata receipt or hardware error-counter claims.
 */
#include <stdio.h>
#include <string.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xscugic.h"
#include "xscutimer.h"
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "lwip/etharp.h"
#include "lwip/priv/tcp_priv.h"
#include "netif/xadapter.h"
#include "b6_config.h"

#if !NO_SYS
#error "B6 requires lwip220 Standalone RAW_API with NO_SYS=1"
#endif
#ifndef XPAR_XEMACPS_0_BASEADDR
#error "Missing GEM0; check the B6 XSA (and link B5's MIO 52/53 MDIO settings)"
#endif

/* Match the DMA identifier selection proven in the existing B5 app. */
#ifdef SDT
# if defined(XPAR_XAXIDMA_0_BASEADDR)
#  define DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
# elif defined(XPAR_AXIDMA_0_BASEADDR)
#  define DMA_IDENTIFIER XPAR_AXIDMA_0_BASEADDR
# elif defined(XPAR_AXI_DMA_0_BASEADDR)
#  define DMA_IDENTIFIER XPAR_AXI_DMA_0_BASEADDR
# else
#  error "No AXI DMA address macro; inspect new B6 xparameters.h"
# endif
#else
# if defined(XPAR_AXIDMA_0_DEVICE_ID)
#  define DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
# elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
#  define DMA_IDENTIFIER XPAR_AXI_DMA_0_DEVICE_ID
# else
#  error "No AXI DMA Device ID macro; inspect new B6 xparameters.h"
# endif
#endif

static XAxiDma Dma;
static XScuTimer ScuTimer;
static struct netif BoardNetif;
static struct udp_pcb *UdpPcb;
static volatile u32 TimerTicks;
static u32 LastFast, LastSlow, LastArp;

/* DMA buffers stay in reachable DDR, never on the stack. */
static u32 TxPacketWords[B6_DMA_PAD_WORDS] __attribute__((aligned(64)));
static u32 RxIQ[B6_IQ_SAMPLES] __attribute__((aligned(64)));

/* RAW API callbacks run during xemacif_input() in this single-thread app.
 * Never spin on DMA or hold a pbuf while in the callback. */
static u8 UdpStaging[B6_PACKET_BYTES];
static unsigned PendingLength;
static int Pending;
static ip_addr_t PendingIp;
static u16_t PendingPort;
static u32 ExpectedRound;
static u32 PassCount;
static u32 FailCount;

static void ctrl_wr(u32 offset, u32 value)
{
    Xil_Out32((UINTPTR)B6_CTRL_BASE + offset, value);
}
static int fail(const char *what)
{
    xil_printf("[FAIL] %s\r\n", what);
    return XST_FAILURE;
}

static int init_difi_rx(void)
{
    ctrl_wr(B6_REG_CONTROL, 0U); /* TX disabled. RX remains active. */
    ctrl_wr(B6_REG_RX_DATA_SID, B6_DATA_SID);
    ctrl_wr(B6_REG_RX_VER_SID, B6_VERSION_SID);
    ctrl_wr(B6_REG_RX_FILTER, 1U); /* Data SID filter only. */
    if ((Xil_In32((UINTPTR)B6_CTRL_BASE + B6_REG_RX_FILTER) & 3U) != 1U ||
        Xil_In32((UINTPTR)B6_CTRL_BASE + B6_REG_RX_DATA_SID) != B6_DATA_SID)
        return fail("DIFI RX AXI-Lite register readback failed; check B6 address");
    xil_printf("[PASS] RX configured: TX=OFF Data SID=%u filter=ON\r\n",
               (unsigned)B6_DATA_SID);
    return XST_SUCCESS;
}

static int init_dma(void)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (!cfg || XAxiDma_CfgInitialize(&Dma, cfg) != XST_SUCCESS ||
        XAxiDma_HasSg(&Dma))
        return fail("AXI DMA init failed or SG enabled (need Simple Mode)");
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    xil_printf("[PASS] AXI DMA initialized, identifier=%08x\r\n",
               (unsigned)DMA_IDENTIFIER);
    return XST_SUCCESS;
}

static u32 dma_status(int direction)
{
    u32 offset = direction == XAXIDMA_DEVICE_TO_DMA ?
        XAXIDMA_RX_OFFSET : XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase + offset, XAXIDMA_SR_OFFSET);
}

static int wait_dma(int direction, const char *name)
{
    u32 start = TimerTicks, spin;
    for (spin = 0U; spin < B6_DMA_SPIN_LIMIT; ++spin) {
        u32 status = dma_status(direction);
        if (status & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("[FAIL] %s DMA status=%08x\r\n", name, (unsigned)status);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma, direction)) return XST_SUCCESS;
        if ((u32)(TimerTicks - start) >= B6_DMA_TIMEOUT_TICKS) break;
    }
    xil_printf("[FAIL] %s timeout; status=%08x (spin=%u)\r\n",
               name, (unsigned)dma_status(direction), (unsigned)spin);
    return XST_FAILURE;
}

static void reset_dma_on_error(void)
{
    u32 spin;
    XAxiDma_Reset(&Dma);
    for (spin = 0U; spin < B6_DMA_SPIN_LIMIT; ++spin)
        if (XAxiDma_ResetIsDone(&Dma)) break;
    xil_printf("[WARN] DMA reset after error; reset_done=%u. "
               "If PL parser remains stuck, reprogram B6 bitstream.\r\n",
               (unsigned)XAxiDma_ResetIsDone(&Dma));
}

static void timer_irq(void *context)
{
    XScuTimer_ClearInterruptStatus((XScuTimer *)context);
    ++TimerTicks;
}

static int init_irq_timer(void)
{
    XScuTimer_Config *cfg = XScuTimer_LookupConfig(XPAR_SCUTIMER_BASEADDR);
    if (!cfg || XScuTimer_CfgInitialize(&ScuTimer, cfg, cfg->BaseAddr) != XST_SUCCESS)
        return fail("SCU Timer config not available");
    XScuTimer_EnableAutoReload(&ScuTimer);
    XScuTimer_LoadTimer(&ScuTimer, B6_PS_CPU_HZ / (2U * B6_TIMER_HZ));
    XScuTimer_ClearInterruptStatus(&ScuTimer);
    Xil_ExceptionInit();
    if (XScuGic_DeviceInitialize(XPAR_SCUGIC_DIST_BASEADDR) != XST_SUCCESS)
        return fail("SCU GIC initialization failed");
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
        (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
        (void *)XPAR_SCUGIC_CPU_BASEADDR);
    XScuGic_RegisterHandler(XPAR_SCUGIC_CPU_BASEADDR, XPAR_SCUTIMER_INTR,
        (Xil_ExceptionHandler)timer_irq, (void *)&ScuTimer);
    XScuGic_EnableIntr(XPAR_SCUGIC_DIST_BASEADDR, XPAR_SCUTIMER_INTR);
    return XST_SUCCESS;
}

static int udp_text_reply(const ip_addr_t *dst, u16_t port, const char *message)
{
    u16_t len = (u16_t)strlen(message);
    struct pbuf *out = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    err_t e;
    if (!out) { xil_printf("[FAIL] ACK allocation failed\r\n"); return XST_FAILURE; }
    if (pbuf_take(out, message, len) != ERR_OK) {
        pbuf_free(out);
        return fail("ACK pbuf_take failed");
    }
    e = udp_sendto(UdpPcb, out, dst, port);
    pbuf_free(out);
    if (e != ERR_OK) {
        xil_printf("[FAIL] ACK send error=%d\r\n", (int)e);
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

static void on_udp_packet(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                          const ip_addr_t *src, u16_t src_port)
{
    (void)arg; (void)pcb;
    if (!p) return;

    /* Status query is not a DIFI packet and is answered immediately. */
    if (p->tot_len == 6U) {
        char cmd[6];
        if (pbuf_copy_partial(p, cmd, sizeof(cmd), 0U) == sizeof(cmd) &&
            memcmp(cmd, "STATUS", 6U) == 0) {
            char reply[80];
            (void)snprintf(reply, sizeof(reply), "READY NEXT_ROUND=%u PASSED=%u FAILED=%u",
                (unsigned)ExpectedRound, (unsigned)PassCount, (unsigned)FailCount);
            (void)udp_text_reply(src, src_port, reply);
            pbuf_free(p);
            return;
        }
    }
    if (Pending) {
        (void)udp_text_reply(src, src_port, "ACK FAIL REASON=BUSY");
        pbuf_free(p);
        return;
    }
    if (p->tot_len != B6_PACKET_BYTES) {
        (void)udp_text_reply(src, src_port, "ACK FAIL REASON=UDP_SIZE");
        pbuf_free(p);
        return;
    }
    if (pbuf_copy_partial(p, UdpStaging, B6_PACKET_BYTES, 0U) != B6_PACKET_BYTES) {
        (void)udp_text_reply(src, src_port, "ACK FAIL REASON=UDP_COPY");
        pbuf_free(p);
        return;
    }
    ip_addr_copy(PendingIp, *src);
    PendingPort = src_port;
    PendingLength = B6_PACKET_BYTES;
    Pending = 1;
    pbuf_free(p);
}

static void pump_net(void)
{
    u32 now;
    xemacif_input(&BoardNetif);
    now = TimerTicks;
    if ((u32)(now - LastFast) >= 5U) { LastFast = now; tcp_fasttmr(); }
    if ((u32)(now - LastSlow) >= 10U) { LastSlow = now; tcp_slowtmr(); }
    if ((u32)(now - LastArp) >= 100U) { LastArp = now; etharp_tmr(); }
}

static int init_network(void)
{
    ip_addr_t addr, mask, gw;
    unsigned char mac[6] = {B6_MAC0,B6_MAC1,B6_MAC2,B6_MAC3,B6_MAC4,B6_MAC5};
    if (init_irq_timer() != XST_SUCCESS) return XST_FAILURE;
    IP4_ADDR(&addr, BOARD_IP0, BOARD_IP1, BOARD_IP2, BOARD_IP3);
    IP4_ADDR(&mask, BOARD_NETMASK0, BOARD_NETMASK1, BOARD_NETMASK2, BOARD_NETMASK3);
    IP4_ADDR(&gw, BOARD_GATEWAY0, BOARD_GATEWAY1, BOARD_GATEWAY2, BOARD_GATEWAY3);
    lwip_init();
    if (!xemac_add(&BoardNetif, &addr, &mask, &gw, mac, XPAR_XEMACPS_0_BASEADDR))
        return fail("xemac_add failed; check B6 GEM0/PHY/MDIO (MIO 52/53)");
    netif_set_default(&BoardNetif);
    netif_set_up(&BoardNetif);
    UdpPcb = udp_new();
    if (!UdpPcb) return fail("udp_new failed");
    if (udp_bind(UdpPcb, IP_ADDR_ANY, B6_UDP_PORT) != ERR_OK)
        return fail("UDP port bind failed");
    udp_recv(UdpPcb, on_udp_packet, NULL);
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    XScuTimer_EnableInterrupt(&ScuTimer);
    XScuTimer_Start(&ScuTimer);
    xil_printf("[PASS] GEM0 UDP listening at %u.%u.%u.%u:%u\r\n",
        (unsigned)BOARD_IP0,(unsigned)BOARD_IP1,(unsigned)BOARD_IP2,
        (unsigned)BOARD_IP3,(unsigned)B6_UDP_PORT);
    return XST_SUCCESS;
}

static u32 expected_iq_word(u32 round, u32 index)
{
    u32 i_part, q_part;
    static const u32 edge[4] = {
        0x0001FFFFU, 0x7FFF8000U, 0xFFFE0003U, 0x00000000U
    };
    if (index < 4U) return edge[index];
    i_part = (0x1000U + index + 0x200U * round) & 0xFFFFU;
    q_part = (0xA000U + 3U * index + 0x11U * round) & 0xFFFFU;
    return (i_part << 16) | q_part;
}

/* Returns a short stable reason code; it does not claim FPGA error visibility. */
static const char *check_header_and_unmarshal(unsigned bytes)
{
    unsigned i;
    u32 word0, expected_header;
    if (bytes != B6_PACKET_BYTES) return "SIZE";
    for (i = 0U; i < B6_PACKET_WORDS; ++i) {
        unsigned off = 4U * i;
        TxPacketWords[i] = ((u32)UdpStaging[off] << 24) |
                           ((u32)UdpStaging[off+1U] << 16) |
                           ((u32)UdpStaging[off+2U] << 8) |
                           (u32)UdpStaging[off+3U];
    }
    word0 = TxPacketWords[0];
    expected_header = 0x18600107U | ((ExpectedRound & 15U) << 16);
    if (word0 != expected_header) return "DATA_WORD0_OR_SEQ";
    if (TxPacketWords[1] != B6_DATA_SID) return "STREAM_ID";
    if (TxPacketWords[2] != 0x006A621EU || TxPacketWords[3] != 0U)
        return "OUI_OR_CLASS";
    return NULL;
}

/* Stage Data packet; the PL parser must emit exactly 256 IQ words. */
static const char *run_rx_dma(void)
{
    unsigned i;
    int rc;
    memset(RxIQ, 0xA5, sizeof(RxIQ));
    Xil_DCacheFlushRange((INTPTR)RxIQ, B6_IQ_BYTES);
    Xil_DCacheFlushRange((INTPTR)TxPacketWords, B6_PACKET_BYTES);

    /* Arm S2MM before MM2S. PL outputs IQ only after full packet validates. */
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)RxIQ, B6_IQ_BYTES,
                                XAXIDMA_DEVICE_TO_DMA);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] arm S2MM rc=%d\r\n", rc);
        reset_dma_on_error();
        return "S2MM_ARM";
    }
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)TxPacketWords, B6_PACKET_BYTES,
                                XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) {
        xil_printf("[FAIL] start MM2S rc=%d\r\n", rc);
        reset_dma_on_error();
        return "MM2S_START";
    }
    if (wait_dma(XAXIDMA_DMA_TO_DEVICE, "MM2S") != XST_SUCCESS) {
        reset_dma_on_error();
        return "MM2S_TIMEOUT_OR_ERR";
    }
    if (wait_dma(XAXIDMA_DEVICE_TO_DMA, "S2MM") != XST_SUCCESS) {
        reset_dma_on_error();
        return "S2MM_TIMEOUT_OR_ERR";
    }
    xil_printf("[DMA] MM2S=1052B S2MM=1024B complete\r\n");
    Xil_DCacheInvalidateRange((INTPTR)RxIQ, B6_IQ_BYTES);
    for (i = 0U; i < B6_IQ_SAMPLES; ++i) {
        u32 golden = expected_iq_word(ExpectedRound, i);
        if (RxIQ[i] != golden) {
            xil_printf("[FAIL] IQ mismatch round=%u idx=%u got=%08x expect=%08x\r\n",
                (unsigned)ExpectedRound, i, (unsigned)RxIQ[i], (unsigned)golden);
            return "IQ_MISMATCH";
        }
    }
    return NULL;
}

static void process_pending(void)
{
    const char *reason;
    char reply[128];
    u32 round = ExpectedRound;
    u32 seq = ExpectedRound & 15U;
    unsigned bytes = PendingLength;
    reason = check_header_and_unmarshal(bytes);
    if (!reason) reason = run_rx_dma();
    if (reason) {
        ++FailCount;
        xil_printf("[FAIL] B6 round=%u reason=%s\r\n", (unsigned)round, reason);
        (void)snprintf(reply, sizeof(reply), "ACK FAIL ROUND=%u REASON=%s",
                       (unsigned)round, reason);
    } else {
        ++PassCount;
        ++ExpectedRound;
        xil_printf("[PASS] B6 round=%u seq=%u IQ=256/256\r\n",
            (unsigned)round, (unsigned)seq);
        (void)snprintf(reply, sizeof(reply), "ACK PASS ROUND=%u SEQ=%u IQ=256",
                       (unsigned)round, (unsigned)seq);
    }
    (void)udp_text_reply(&PendingIp, PendingPort, reply);
    Pending = 0;
}

int main(void)
{
    xil_printf("\r\n=== DIFI B6 UDP RX -> PL PARSER, Vitis 2024.2 ===\r\n");
    xil_printf("[INFO] B6 XSA required: MM2S->S_AXIS_RX_PKT, M_AXIS_IQ->S2MM\r\n");
    xil_printf("[INFO] CTRL=%08x DMA=%08x\r\n",
        (unsigned)B6_CTRL_BASE, (unsigned)DMA_IDENTIFIER);
    if (init_dma() != XST_SUCCESS || init_difi_rx() != XST_SUCCESS ||
        init_network() != XST_SUCCESS) {
        xil_printf("[FATAL] B6 startup failed; stop and fix XSA/platform\r\n");
        for (;;) { }
    }
    xil_printf("[READY] Send STATUS then a 1052-byte DIFI Data packet to port %u\r\n",
        (unsigned)B6_UDP_PORT);
    for (;;) {
        pump_net();
        if (Pending) process_pending();
    }
}
