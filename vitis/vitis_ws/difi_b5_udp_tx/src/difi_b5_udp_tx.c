/* Send raw B5 DIFI packets over UDP: 1 Version, 1 Context, and 20 Data packets. Requires B5 raw-packet export hardware. */
#include <string.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xscutimer.h"
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "lwip/etharp.h"
#include "lwip/priv/tcp_priv.h"
#include "netif/xadapter.h"

#if !NO_SYS
#error "Requires lwip220 standalone RAW_API and NO_SYS=1"
#endif
#ifndef XPAR_XEMACPS_0_BASEADDR
#error "This B5 hardware platform has no PS GEM0. Check B5 XSA / PS Ethernet settings."
#endif
#ifdef SDT
# if defined(XPAR_XAXIDMA_0_BASEADDR)
#  define DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
# elif defined(XPAR_AXIDMA_0_BASEADDR)
#  define DMA_IDENTIFIER XPAR_AXIDMA_0_BASEADDR
# elif defined(XPAR_AXI_DMA_0_BASEADDR)
#  define DMA_IDENTIFIER XPAR_AXI_DMA_0_BASEADDR
# else
#  error "DMA base missing: check B5 XSA/xparameters.h"
# endif
#else
# if defined(XPAR_AXIDMA_0_DEVICE_ID)
#  define DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
# elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
#  define DMA_IDENTIFIER XPAR_AXI_DMA_0_DEVICE_ID
# else
#  error "DMA ID missing: check xparameters.h"
# endif
#endif

/* Addresses must match the B5 hardware configuration. */
#define B5_CTRL_BASE      ((UINTPTR)0x40000000U)
#define B5_TIME_BASE      ((UINTPTR)0x40001000U)

#define BOARD_IP0 192
#define BOARD_IP1 168
#define BOARD_IP2 1
#define BOARD_IP3 10
#define UDP_PORT 4991U
#define CPU_CLOCK_HZ 666666667U       
#define TIMER_TICKS_PER_SEC 20U      

#define DATA_PACKETS     20U
#define IQ_SAMPLES       256U
#define VERSION_WORDS    11U
#define CONTEXT_WORDS    27U
#define DATA_WORDS       (7U + IQ_SAMPLES)
#define RX_PAD_WORDS     272U
#define POLL_LIMIT       75000000U
#define DATA_SID         1U
#define VERSION_SID      2U

#define C_CONTROL       0x00U
#define C_COMMAND       0x04U
#define C_STATUS        0x08U
#define C_LAST_ERROR    0x0CU
#define C_DATA_SID      0x10U
#define C_VER_SID       0x14U
#define C_SAMPLES       0x18U
#define C_FS            0x1CU
#define C_BW            0x20U
#define C_RF_LO         0x24U
#define C_RF_HI         0x28U
#define C_CTX_PERIOD    0x2CU
#define C_VER_PERIOD    0x30U
#define C_ACTIVE_DATA   0x40U
#define C_ACTIVE_SAMPLES 0x48U
#define C_ACTIVE_CTX_PERIOD 0x5CU
#define C_ACTIVE_VER_PERIOD 0x60U
#define T_SEC           0x00U
#define T_PS_LO         0x04U
#define T_PS_HI         0x08U
#define T_COMMAND       0x0CU
#define T_STATUS        0x10U
#define ST_PENDING      0x01U
#define ST_ENABLED      0x08U
#define ST_TIME_VALID   0x10U
#define ST_COMMIT_ERROR 0x20U

extern char inbyte(void);
static XAxiDma Dma;
static u32 TxIQ[IQ_SAMPLES] __attribute__((aligned(64)));
static u32 RxWords[RX_PAD_WORDS] __attribute__((aligned(64)));
static struct netif board_netif;
static struct udp_pcb *pcb = NULL;
static XScuTimer scu_timer;
static volatile unsigned int ticks_50ms;
static unsigned int last_fast, last_slow, last_arp;
static int start_requested;
static ip_addr_t pc_ip;
static u16_t pc_port;

static void cwr(u32 off, u32 val) { Xil_Out32(B5_CTRL_BASE + off, val); }
static u32 crd(u32 off) { return Xil_In32(B5_CTRL_BASE + off); }
static void twr(u32 off, u32 val) { Xil_Out32(B5_TIME_BASE + off, val); }
static u32 trd(u32 off) { return Xil_In32(B5_TIME_BASE + off); }
static int fail(const char *msg) { xil_printf("[FAIL] %s\r\n", msg); return XST_FAILURE; }

static void uart_getline(char *line, unsigned capacity)
{
    unsigned n = 0U;
    int skip_lf = 0;
    if (capacity == 0U) return;
    for (;;) {
        char ch = inbyte();
        if (skip_lf && ch == '\n') { skip_lf = 0; continue; }
        skip_lf = 0;
        if (ch == '\r' || ch == '\n') {
            if (ch == '\r') skip_lf = 1;
            line[n] = '\0'; xil_printf("\r\n"); return;
        }
        if (ch == '\b' || (unsigned char)ch == 127U) {
            if (n) { --n; xil_printf("\b \b"); }
            continue;
        }
        if ((unsigned char)ch < 32U) continue;
        if (n+1U < capacity) { line[n++] = ch; xil_printf("%c", (int)ch); }
    }
}

static int parse_u32(const char **p, u32 *out)
{
    u64 v = 0ULL;
    unsigned count = 0;
    while (**p == ' ' || **p == '\t') ++(*p);
    while (**p >= '0' && **p <= '9') {
        ++count;
        v = v*10ULL + (u32)(**p-'0');
        if (v > 0xFFFFFFFFULL) return XST_FAILURE;
        ++(*p);
    }
    if (!count) return XST_FAILURE;
    *out = (u32)v; return XST_SUCCESS;
}

static int configure_time(void)
{
    char line[96];
    u32 sec=0U, ns=0U, i, status;
    u64 ps;
    if (trd(T_STATUS)&1U) return fail("Time already valid. Re-download B5 bitstream for reset.");
    for (;;) {
        const char *p;
        xil_printf("[WAIT_UTC] Type: UTC <UNIX_SECONDS> <NANOSECONDS>\r\n");
        xil_printf("[INFO] Disable PC terminal local echo.\r\n");
        uart_getline(line, sizeof(line));
        p = line;
        if (line[0]=='U' && line[1]=='T' && line[2]=='C' && line[3]==' ') {
            p += 4;
            if (!parse_u32(&p, &sec) && !parse_u32(&p, &ns)) {
                while (*p==' ' || *p=='\t') ++p;
                if (*p=='\0' && ns < 1000000000U) break;
            }
        }
        xil_printf("[WARN] Bad UTC command, retry.\r\n");
    }
    ps=(u64)ns*1000ULL;
    twr(T_SEC,sec); twr(T_PS_LO,(u32)ps); twr(T_PS_HI,(u32)(ps>>32));
    twr(T_COMMAND,1U);
    for (i=0U;i<POLL_LIMIT;++i) {
        status=trd(T_STATUS);
        if (status&2U) return fail("Time load rejected");
        if ((status&1U)&&(crd(C_STATUS)&ST_TIME_VALID)) break;
    }
    if (i==POLL_LIMIT) return fail("Time load timeout");
    xil_printf("[PASS] Time valid; UART Unix seconds=%u\r\n",(unsigned)sec);
    return XST_SUCCESS;
}

static int configure_difi(void)
{
    u32 i, st;
    cwr(C_CONTROL,0U);
    cwr(C_DATA_SID,DATA_SID); cwr(C_VER_SID,VERSION_SID);
    cwr(C_SAMPLES,IQ_SAMPLES);
    cwr(C_FS,20000000U); cwr(C_BW,10000000U);
    cwr(C_RF_LO,100000000U); cwr(C_RF_HI,0U);
    cwr(C_CTX_PERIOD,0U); cwr(C_VER_PERIOD,0U);
    cwr(C_COMMAND,1U);
    for (i=0U;i<POLL_LIMIT;++i) {
        st=crd(C_STATUS);
        if (st&ST_COMMIT_ERROR) {
            xil_printf("[FAIL] DIFI commit error code=%08x\r\n", (unsigned)crd(C_LAST_ERROR));
            return XST_FAILURE;
        }
        if (!(st&ST_PENDING) && crd(C_ACTIVE_SAMPLES)==IQ_SAMPLES &&
            crd(C_ACTIVE_DATA)==DATA_SID && crd(C_ACTIVE_CTX_PERIOD)==0U &&
            crd(C_ACTIVE_VER_PERIOD)==0U) break;
    }
    if (i==POLL_LIMIT) return fail("DIFI commit timeout");
    if (!(crd(C_STATUS)&ST_TIME_VALID) || (crd(C_STATUS)&ST_ENABLED))
        return fail("unexpected CTRL status after commit");
    xil_printf("[PASS] DIFI configured: samples=256, periodic=OFF\r\n");
    return XST_SUCCESS;
}

static int init_dma(void)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (!cfg || XAxiDma_CfgInitialize(&Dma,cfg)!=XST_SUCCESS || XAxiDma_HasSg(&Dma))
        return fail("AXI DMA initialization failed or Scatter-Gather enabled");
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}
static u32 dma_sr(int direction)
{
    u32 off=(direction==XAXIDMA_DEVICE_TO_DMA)?XAXIDMA_RX_OFFSET:XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase,off+XAXIDMA_SR_OFFSET);
}
static int dma_wait(int direction)
{
    u32 i;
    for (i=0;i<POLL_LIMIT;++i) {
        u32 status=dma_sr(direction);
        if (status & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("[FAIL] DMA dir=%d status=%08x\r\n",direction,(unsigned)status);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma,direction)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] DMA timeout dir=%d status=%08x\r\n",direction,(unsigned)dma_sr(direction));
    return XST_FAILURE;
}
static int arm_rx(u32 words)
{
    int rc;
    if (words>RX_PAD_WORDS) return fail("RX buffer too short");
    memset(RxWords,0xA5,sizeof(RxWords));
    Xil_DCacheFlushRange((INTPTR)RxWords,(u32)sizeof(RxWords));
    rc=XAxiDma_SimpleTransfer(&Dma,(UINTPTR)RxWords,words*4U,XAXIDMA_DEVICE_TO_DMA);
    if (rc!=XST_SUCCESS) { xil_printf("[FAIL] S2MM arm rc=%d\r\n",rc); }
    return rc;
}
static void make_iq(u32 round)
{
    u32 i;
    for (i=0;i<IQ_SAMPLES;++i) {
        u32 iv=(0x1000U+i+0x200U*round)&0xFFFFU;
        u32 qv=(0xA000U+3U*i+0x11U*round)&0xFFFFU;
        TxIQ[i]=(iv<<16)|qv;
    }
    TxIQ[0]=0x0001FFFFU; TxIQ[1]=0x7FFF8000U;
    TxIQ[2]=0xFFFE0003U; TxIQ[3]=0x00000000U;
    Xil_DCacheFlushRange((INTPTR)TxIQ,(u32)sizeof(TxIQ));
}

static int verify_packet(u32 words,u32 type,u32 seq,u32 round)
{
    u32 i,w0,expected;
    Xil_DCacheInvalidateRange((INTPTR)RxWords,(u32)sizeof(RxWords));
    w0=RxWords[0];
    expected=(type<<28)|0x08600000U|((seq&15U)<<16)|words;
    if (type==4U || type==5U) expected|=0x01000000U;
    if (w0!=expected || RxWords[1]!=(type==5U?VERSION_SID:DATA_SID) ||
        RxWords[2]!=0x006A621EU) {
        xil_printf("[FAIL] malformed packet w0=%08x exp=%08x sid=%08x\r\n",
                   (unsigned)w0,(unsigned)expected,(unsigned)RxWords[1]);
        return XST_FAILURE;
    }
    if (type==1U) {
        if (RxWords[3]!=0U) return fail("Data class ID mismatch");
        for (i=0U;i<IQ_SAMPLES;++i)
            if (RxWords[7U+i]!=TxIQ[i]) {
                xil_printf("[FAIL] IQ mismatch round=%u index=%u\r\n",(unsigned)round,(unsigned)i);
                return XST_FAILURE;
            }
    } else if (type==5U) {
        if (RxWords[3]!=0x00010004U || RxWords[7]!=0x80000002U)
            return fail("Version metadata mismatch");
    } else if (type==4U) {
        if (RxWords[3]!=0x00000001U || RxWords[7]!=0xFBB98000U ||
            RxWords[25]!=0xA00003CFU) return fail("Context metadata mismatch");
    }
    return XST_SUCCESS;
}

static void timer_irq(void *context)
{
    XScuTimer_ClearInterruptStatus((XScuTimer *)context);
    ++ticks_50ms;
}
static int init_interrupts_and_timer(void)
{
    XScuTimer_Config *config;
    config=XScuTimer_LookupConfig(XPAR_SCUTIMER_BASEADDR);
    if (!config || XScuTimer_CfgInitialize(&scu_timer,config,config->BaseAddr)!=XST_SUCCESS)
        return fail("SCU timer config unavailable");
    XScuTimer_EnableAutoReload(&scu_timer);
    XScuTimer_LoadTimer(&scu_timer,CPU_CLOCK_HZ/(2U*TIMER_TICKS_PER_SEC));
    XScuTimer_ClearInterruptStatus(&scu_timer);
    Xil_ExceptionInit();
    if (XScuGic_DeviceInitialize(XPAR_SCUGIC_DIST_BASEADDR)!=XST_SUCCESS)
        return fail("GIC init failed");
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
              (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
              (void *)XPAR_SCUGIC_CPU_BASEADDR);
    XScuGic_RegisterHandler(XPAR_SCUGIC_CPU_BASEADDR,XPAR_SCUTIMER_INTR,
                             (Xil_ExceptionHandler)timer_irq,(void *)&scu_timer);
    XScuGic_EnableIntr(XPAR_SCUGIC_DIST_BASEADDR,XPAR_SCUTIMER_INTR);
    return XST_SUCCESS;
}
static void pump_net(void)
{
    unsigned int now;
    xemacif_input(&board_netif);
    now=ticks_50ms;
    if ((unsigned int)(now-last_fast)>=5U) { last_fast=now; tcp_fasttmr(); }
    if ((unsigned int)(now-last_slow)>=10U) { last_slow=now; tcp_slowtmr(); }
    if ((unsigned int)(now-last_arp)>=100U) { last_arp=now; etharp_tmr(); }
}

static void on_udp_control(void *arg,struct udp_pcb *p,struct pbuf *pkt,
                           const ip_addr_t *addr,u16_t port)
{
    char cmd[8]={0};
    (void)arg; (void)p;
    if (!pkt) return;
    if (pkt->tot_len == 5U && pbuf_copy_partial(pkt,cmd,5U,0U)==5U &&
        memcmp(cmd,"START",5)==0) {
        ip_addr_copy(pc_ip,*addr);
        pc_port=port;
        start_requested=1;
        xil_printf("[UDP] START received from PC, src_port=%u\r\n",(unsigned)port);
    }
    pbuf_free(pkt);
}
static int init_network(void)
{
    ip_addr_t addr,netmask,gateway;
    unsigned char mac[]={0x02,0x0A,0x35,0x00,0x01,0x02};
    if (init_interrupts_and_timer()!=XST_SUCCESS) return XST_FAILURE;
    IP4_ADDR(&addr,BOARD_IP0,BOARD_IP1,BOARD_IP2,BOARD_IP3);
    IP4_ADDR(&netmask,255,255,255,0);
    IP4_ADDR(&gateway,192,168,1,1);
    lwip_init();
    if (!xemac_add(&board_netif,&addr,&netmask,&gateway,mac,
                    XPAR_XEMACPS_0_BASEADDR)) return fail("xemac_add failed: PS GEM0/PHY/XSA");
    netif_set_default(&board_netif);
    netif_set_up(&board_netif);
    pcb=udp_new();
    if (!pcb) return fail("udp_new failed");
    if (udp_bind(pcb,IP_ADDR_ANY,UDP_PORT)!=ERR_OK) return fail("udp_bind failed");
    udp_recv(pcb,on_udp_control,NULL);
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    XScuTimer_EnableInterrupt(&scu_timer);
    XScuTimer_Start(&scu_timer);
    xil_printf("[PASS] PS GEM0 UDP ready: %u.%u.%u.%u:%u\r\n",
               BOARD_IP0,BOARD_IP1,BOARD_IP2,BOARD_IP3,UDP_PORT);
    return XST_SUCCESS;
}

static int udp_send_captured(u32 words,u32 type,u32 seq)
{
    struct pbuf *p;
    unsigned char *bytes;
    u32 i;
    err_t rc;
    p=pbuf_alloc(PBUF_TRANSPORT,(u16_t)(words*4U),PBUF_RAM);
    if (!p || p->next || p->len != words*4U) {
        if (p) pbuf_free(p);
        return fail("UDP TX pbuf allocation failed / unexpected pbuf chain");
    }
    /* Send UDP data in big-endian byte order. */
    bytes=(unsigned char *)p->payload;
    for (i=0U;i<words;++i) {
        u32 w=RxWords[i];
        bytes[4U*i+0U]=(unsigned char)(w>>24);
        bytes[4U*i+1U]=(unsigned char)(w>>16);
        bytes[4U*i+2U]=(unsigned char)(w>>8);
        bytes[4U*i+3U]=(unsigned char)w;
    }
    rc=udp_sendto(pcb,p,&pc_ip,pc_port);
    pbuf_free(p);
    if (rc!=ERR_OK) { xil_printf("[FAIL] udp_sendto err=%d\r\n",(int)rc); return XST_FAILURE; }
    xil_printf("[UDP_TX] type=%u seq=%u payload_bytes=%u\r\n",
               (unsigned)type,(unsigned)seq,(unsigned)(words*4U));
    return XST_SUCCESS;
}

static int capture_startup(void)
{
    /* Arm S2MM before enabling TX to avoid losing the first Version packet. */
    if (arm_rx(VERSION_WORDS)!=XST_SUCCESS) return XST_FAILURE;
    cwr(C_CONTROL,1U);
    if (dma_wait(XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS ||
        verify_packet(VERSION_WORDS,5U,0U,0U)!=XST_SUCCESS ||
        udp_send_captured(VERSION_WORDS,5U,0U)!=XST_SUCCESS) return XST_FAILURE;
    pump_net(); usleep(2000U);
    if (arm_rx(CONTEXT_WORDS)!=XST_SUCCESS ||
        dma_wait(XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS ||
        verify_packet(CONTEXT_WORDS,4U,0U,0U)!=XST_SUCCESS ||
        udp_send_captured(CONTEXT_WORDS,4U,0U)!=XST_SUCCESS) return XST_FAILURE;
    pump_net(); usleep(2000U);
    return XST_SUCCESS;
}
static int capture_data(u32 round)
{
    make_iq(round);
    if (arm_rx(DATA_WORDS)!=XST_SUCCESS) return XST_FAILURE;
    if (XAxiDma_SimpleTransfer(&Dma,(UINTPTR)TxIQ,IQ_SAMPLES*4U,
                               XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)
        return fail("MM2S IQ submit failed");
    if (dma_wait(XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS ||
        dma_wait(XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS ||
        verify_packet(DATA_WORDS,1U,round&15U,round)!=XST_SUCCESS ||
        udp_send_captured(DATA_WORDS,1U,round&15U)!=XST_SUCCESS)
        return XST_FAILURE;
    pump_net(); usleep(2000U);  /* Pace transmissions for functional checks. */
    return XST_SUCCESS;
}
int main(void)
{
    u32 i;
    int success=0;
    xil_printf("\r\n=== DIFI B5 RAW UDP EXPORT, Vitis 2024.2 ===\r\n");
    xil_printf("[INFO] Requires B5 raw-packet export XSA (NOT TX->RX loopback)\r\n");
    xil_printf("[INFO] CTRL=%08x TIME=%08x DMA=%08x\r\n",
       (unsigned)B5_CTRL_BASE,(unsigned)B5_TIME_BASE,(unsigned)DMA_IDENTIFIER);
    if (init_dma()!=XST_SUCCESS || configure_time()!=XST_SUCCESS ||
        configure_difi()!=XST_SUCCESS || init_network()!=XST_SUCCESS) goto done;
    xil_printf("[WAIT] On PC run pc/difi_udp_receiver.py; its START triggers export\r\n");
    while (!start_requested) pump_net();
    xil_printf("[INFO] Sending 1 Version + 1 Context + %u Data packets\r\n",
               (unsigned)DATA_PACKETS);
    if (capture_startup()!=XST_SUCCESS) goto done;
    for (i=0U;i<DATA_PACKETS;++i)
        if (capture_data(i)!=XST_SUCCESS) goto done;
    xil_printf("[PASS] UDP export complete: Version=1 Context=1 Data=%u IQ=%u\r\n",
               (unsigned)DATA_PACKETS,(unsigned)(DATA_PACKETS*IQ_SAMPLES));
    success=1;
done:
    cwr(C_CONTROL,0U);
    if (!success) xil_printf("[FAIL] B5 UDP export incomplete\r\n");
    else xil_printf("[NOTE] Check PC received all packets: udp_sendto success does NOT prove receipt.\r\n");
    for (;;) pump_net();   
    return XST_SUCCESS;
}
