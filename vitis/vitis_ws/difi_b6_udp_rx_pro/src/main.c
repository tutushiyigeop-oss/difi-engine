/*
 * DIFI Stage B6: PC UDP -> Zynq GEM0/lwIP -> DDR -> AXI DMA MM2S
 *  -> DIFI PL RX Parser -> AXI DMA S2MM -> PS Golden IQ check -> UDP ACK.
 *
 * Target: Zynq-7020, Vitis 2024.2, Standalone, lwip220 RAW_API, NO_SYS=1.
 * This is new integration code; requires your matching B6 XSA and on-board test.
 * The B6 BD MUST route M_AXIS_MM2S to S_AXIS_RX_PKT and M_AXIS_IQ to
 * S_AXIS_S2MM; direct DIFI TX->RX loopback MUST be disconnected.
 *
 * Scope v0.2: Data IQ recovery + Context/Version parser metadata handshakes.
 * Requires a new B6 XSA with an AXI GPIO dual-channel metadata monitor.
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
static u8 UdpStaging[B6_MAX_PACKET_BYTES];
static unsigned PendingLength;
static int Pending;
static ip_addr_t PendingIp;
static u16_t PendingPort;
static u32 ExpectedRound;
static u32 PassCount;
static u32 FailCount;
static u32 ExpectedVersion;
static u32 ExpectedContext;
static u32 VersionPassCount;
static u32 ContextPassCount;

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
    ctrl_wr(B6_REG_RX_FILTER, 3U); /* Data/Context and Version SID filters. */
    if ((Xil_In32((UINTPTR)B6_CTRL_BASE + B6_REG_RX_FILTER) & 3U) != 3U ||
        Xil_In32((UINTPTR)B6_CTRL_BASE + B6_REG_RX_DATA_SID) != B6_DATA_SID ||
        Xil_In32((UINTPTR)B6_CTRL_BASE + B6_REG_RX_VER_SID) != B6_VERSION_SID)
        return fail("DIFI RX AXI-Lite register readback failed; check B6 address");
    xil_printf("[PASS] RX configured: TX=OFF Data/Context SID=%u Version SID=%u, filters=ON\r\n",
               (unsigned)B6_DATA_SID, (unsigned)B6_VERSION_SID);
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

/* One raw UDP datagram is one complete DIFI packet, never a fragmented stream. */
static void on_udp_packet(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                          const ip_addr_t *src, u16_t src_port)
{
    (void)arg; (void)pcb;
    if (!p) return;
    if (p->tot_len == 6U) {
        char cmd[6];
        if (pbuf_copy_partial(p, cmd, sizeof(cmd), 0U) == sizeof(cmd) &&
            memcmp(cmd, "STATUS", 6U) == 0) {
            char reply[180];
            (void)snprintf(reply, sizeof(reply),
                "READY NEXT_ROUND=%u PASSED=%u FAILED=%u NEXT_VERSION=%u NEXT_CONTEXT=%u VER_PASS=%u CTX_PASS=%u",
                (unsigned)ExpectedRound, (unsigned)PassCount, (unsigned)FailCount,
                (unsigned)ExpectedVersion, (unsigned)ExpectedContext,
                (unsigned)VersionPassCount, (unsigned)ContextPassCount);
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
    if (p->tot_len != B6_DATA_BYTES && p->tot_len != B6_VERSION_BYTES &&
        p->tot_len != B6_CONTEXT_BYTES) {
        (void)udp_text_reply(src, src_port, "ACK FAIL REASON=UDP_SIZE");
        pbuf_free(p);
        return;
    }
    if (pbuf_copy_partial(p, UdpStaging, p->tot_len, 0U) != p->tot_len) {
        (void)udp_text_reply(src, src_port, "ACK FAIL REASON=UDP_COPY");
        pbuf_free(p);
        return;
    }
    ip_addr_copy(PendingIp, *src);
    PendingPort = src_port;
    PendingLength = p->tot_len;
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

/* Parse network-order words before streaming to PL. This is a PC-side
 * precheck: PASS additionally requires FPGA metadata handshake / IQ output. */
static const char *check_header_and_unmarshal(unsigned bytes, u32 *type_out, u32 *seq_out)
{
    unsigned i;
    u32 type, expected_seq, base, words;
    if (bytes != B6_DATA_BYTES && bytes != B6_VERSION_BYTES &&
        bytes != B6_CONTEXT_BYTES) return "SIZE";
    words = bytes / 4U;
    for (i = 0U; i < words; ++i) {
        unsigned off = 4U * i;
        TxPacketWords[i] = ((u32)UdpStaging[off] << 24) |
                           ((u32)UdpStaging[off+1U] << 16) |
                           ((u32)UdpStaging[off+2U] << 8) |
                           (u32)UdpStaging[off+3U];
    }
    type = TxPacketWords[0] >> 28;
    if (type == B6_TYPE_DATA && bytes == B6_DATA_BYTES) {
        expected_seq = ExpectedRound & 15U;
        base = 0x18600107U;
    } else if (type == B6_TYPE_VERSION && bytes == B6_VERSION_BYTES) {
        expected_seq = ExpectedVersion & 15U;
        base = 0x5960000BU;
    } else if (type == B6_TYPE_CONTEXT && bytes == B6_CONTEXT_BYTES) {
        expected_seq = ExpectedContext & 15U;
        base = 0x4960001BU;
    } else return "TYPE_OR_SIZE";

    if (TxPacketWords[0] != (base | (expected_seq << 16))) return "WORD0_OR_SEQ";
    if (TxPacketWords[1] != (type == B6_TYPE_VERSION ? B6_VERSION_SID : B6_DATA_SID))
        return "STREAM_ID";
    if (TxPacketWords[2] != 0x006A621EU) return "OUI";
    if (type == B6_TYPE_DATA && TxPacketWords[3] != 0U) return "DATA_CLASS";
    if (type == B6_TYPE_VERSION && TxPacketWords[3] != 0x00010004U) return "VER_CLASS";
    if (type == B6_TYPE_CONTEXT && TxPacketWords[3] != 1U) return "CTX_CLASS";
    *type_out = type;
    *seq_out = expected_seq;
    return NULL;
}

/* AXI GPIO ch1/ch2 are fed by the synchronous PL metadata monitor. */
static u32 mon_count(void) { return Xil_In32((UINTPTR)B6_MON_BASE + 0x00U); }
static u32 mon_detail(void) { return Xil_In32((UINTPTR)B6_MON_BASE + 0x08U); }
static u32 ver_count(u32 counts) { return (counts >> 16) & 0xffffU; }
static u32 ctx_count(u32 counts) { return counts & 0xffffU; }

static int init_rx_monitor(void)
{
    u32 c, d;
    Xil_Out32((UINTPTR)B6_MON_BASE + 0x04U, 0xffffffffU);
    Xil_Out32((UINTPTR)B6_MON_BASE + 0x0cU, 0xffffffffU);
    c = mon_count(); d = mon_detail();
    xil_printf("[INFO] RX monitor GPIO=%08x counts=%08x detail=%08x\r\n",
        (unsigned)B6_MON_BASE, (unsigned)c, (unsigned)d);
    xil_printf("[INFO] Metadata status requires new B6 v0.2 XSA with monitor + dual AXI GPIO\r\n");
    return XST_SUCCESS;
}

/* No S2MM for Version/Context. MM2S must complete and exactly one valid
 * metadata event must be observed on the FPGA output. */
static const char *run_metadata_dma(u32 type, u32 seq, unsigned bytes)
{
    u32 before, after, errors_before, errors_after, details, i;
    u32 old_v, old_c;
    int rc;
    before = mon_count();
    errors_before = mon_detail();
    old_v = ver_count(before); old_c = ctx_count(before);
    if (old_v == 0xffffU || old_c == 0xffffU) return "MON_COUNTER_SATURATED";
    Xil_DCacheFlushRange((INTPTR)TxPacketWords, bytes);
    rc = XAxiDma_SimpleTransfer(&Dma, (UINTPTR)TxPacketWords, bytes,
                                XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) return "META_MM2S_START";
    if (wait_dma(XAXIDMA_DMA_TO_DEVICE, "META MM2S") != XST_SUCCESS) {
        reset_dma_on_error();
        return "META_MM2S_TIMEOUT_OR_ERR";
    }
    /* The metadata pulse can follow MM2S TLAST by a few FPGA clocks. */
    for (i = 0U; i < B6_MON_SPIN_LIMIT; ++i) {
        after = mon_count();
        if (type == B6_TYPE_VERSION) {
            if (ver_count(after) != old_v) break;
        } else {
            if (ctx_count(after) != old_c) break;
        }
    }
    if (i == B6_MON_SPIN_LIMIT) {
        xil_printf("[FAIL] META timeout type=%u before=%08x after=%08x detail=%08x\r\n",
            (unsigned)type, (unsigned)before, (unsigned)mon_count(),
            (unsigned)mon_detail());
        return "META_EVENT_TIMEOUT";
    }
    after = mon_count();
    details = mon_detail();
    errors_after = details;
    if (type == B6_TYPE_VERSION) {
        if (ver_count(after) != old_v + 1U || ctx_count(after) != old_c)
            return "META_COUNT_UNEXPECTED";
        if (((details >> 4) & 15U) != seq) return "META_VER_SEQ";
        if (((details >> 9) & 1U) != (ExpectedVersion == 0U ? 1U : 0U))
            return "META_VER_CHANGED";
        /* [23:20] Version parser error; [27:24] dispatch error. */
        if (((errors_before ^ errors_after) & 0x0ff00000U) != 0U)
            return "META_VER_OR_DISPATCH_ERROR";
    } else {
        if (ctx_count(after) != old_c + 1U || ver_count(after) != old_v)
            return "META_COUNT_UNEXPECTED";
        if ((details & 15U) != seq) return "META_CTX_SEQ";
        if (((details >> 8) & 1U) != (ExpectedContext == 0U ? 1U : 0U))
            return "META_CTX_CHANGED";
        /* [19:16] Context parser error; [27:24] dispatch error. */
        if (((errors_before ^ errors_after) & 0x0f0f0000U) != 0U)
            return "META_CTX_OR_DISPATCH_ERROR";
    }
    xil_printf("[PASS] PL META type=%u seq=%u count_before=%08x after=%08x\r\n",
        (unsigned)type, (unsigned)seq, (unsigned)before, (unsigned)after);
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
    char reply[160];
    u32 type = 0U, seq = 0U;
    unsigned bytes = PendingLength;
    reason = check_header_and_unmarshal(bytes, &type, &seq);
    if (!reason) {
        if (type == B6_TYPE_DATA) reason = run_rx_dma();
        else reason = run_metadata_dma(type, seq, bytes);
    }
    if (reason) {
        ++FailCount;
        xil_printf("[FAIL] B6 type=%u reason=%s\r\n", (unsigned)type, reason);
        (void)snprintf(reply, sizeof(reply), "ACK FAIL REASON=%s", reason);
    } else if (type == B6_TYPE_DATA) {
        u32 round = ExpectedRound++;
        ++PassCount;
        xil_printf("[PASS] B6 DATA round=%u seq=%u IQ=256/256\r\n",
            (unsigned)round, (unsigned)seq);
        (void)snprintf(reply, sizeof(reply), "ACK PASS ROUND=%u SEQ=%u IQ=256",
                       (unsigned)round, (unsigned)seq);
    } else if (type == B6_TYPE_VERSION) {
        ++ExpectedVersion;
        ++VersionPassCount;
        xil_printf("[PASS] B6 VERSION seq=%u PL_METADATA=1\r\n", (unsigned)seq);
        (void)snprintf(reply, sizeof(reply), "ACK PASS TYPE=VERSION SEQ=%u META=1",
                       (unsigned)seq);
    } else {
        ++ExpectedContext;
        ++ContextPassCount;
        xil_printf("[PASS] B6 CONTEXT seq=%u PL_METADATA=1\r\n", (unsigned)seq);
        (void)snprintf(reply, sizeof(reply), "ACK PASS TYPE=CONTEXT SEQ=%u META=1",
                       (unsigned)seq);
    }
    (void)udp_text_reply(&PendingIp, PendingPort, reply);
    Pending = 0;
}

int main(void)
{
    xil_printf("\r\n=== DIFI B6 v0.2 UDP RX DATA + VERSION + CONTEXT ===\r\n");
    xil_printf("[INFO] B6 XSA required: MM2S->S_AXIS_RX_PKT, M_AXIS_IQ->S2MM\r\n");
    xil_printf("[INFO] CTRL=%08x DMA=%08x\r\n",
        (unsigned)B6_CTRL_BASE, (unsigned)DMA_IDENTIFIER);
    if (init_dma() != XST_SUCCESS || init_difi_rx() != XST_SUCCESS ||
        init_rx_monitor() != XST_SUCCESS || init_network() != XST_SUCCESS) {
        xil_printf("[FATAL] B6 startup failed; stop and fix XSA/platform\r\n");
        for (;;) { }
    }
    xil_printf("[READY] Send STATUS then 44B Version / 108B Context / 1052B Data to port %u\r\n",
        (unsigned)B6_UDP_PORT);
    for (;;) {
        pump_net();
        if (Pending) process_pending();
    }
}
