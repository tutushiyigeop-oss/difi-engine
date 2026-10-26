/* Stage D v0.4. New firmware; v0.3 is never edited.
 * DMA0: actual PL RX IQ. DMA1: custom IQ through actual PL TX.
 * Board acceptance is pending; building this ELF does not program hardware. */
#include <string.h>
#include <stdio.h>
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
#error "Requires lwip220 standalone RAW_API NO_SYS=1"
#endif
#ifndef XPAR_XEMACPS_0_BASEADDR
#error "Stage D hardware must include Zynq PS GEM0"
#endif

#if defined(SDT)
# if defined(XPAR_XAXIDMA_0_BASEADDR) && defined(XPAR_XAXIDMA_1_BASEADDR)
#  define RX_DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
#  define TX_DMA_IDENTIFIER XPAR_XAXIDMA_1_BASEADDR
# elif defined(XPAR_AXIDMA_0_BASEADDR) && defined(XPAR_AXIDMA_1_BASEADDR)
#  define RX_DMA_IDENTIFIER XPAR_AXIDMA_0_BASEADDR
#  define TX_DMA_IDENTIFIER XPAR_AXIDMA_1_BASEADDR
# elif defined(XPAR_AXI_DMA_0_BASEADDR) && defined(XPAR_AXI_DMA_1_BASEADDR)
#  define RX_DMA_IDENTIFIER XPAR_AXI_DMA_0_BASEADDR
#  define TX_DMA_IDENTIFIER XPAR_AXI_DMA_1_BASEADDR
# else
#  error "Stage D requires both DMA0 and DMA1 base addresses in the SDT BSP"
# endif
#else
# if defined(XPAR_AXIDMA_0_DEVICE_ID) && defined(XPAR_AXIDMA_1_DEVICE_ID)
#  define RX_DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
#  define TX_DMA_IDENTIFIER XPAR_AXIDMA_1_DEVICE_ID
# elif defined(XPAR_AXI_DMA_0_DEVICE_ID) && defined(XPAR_AXI_DMA_1_DEVICE_ID)
#  define RX_DMA_IDENTIFIER XPAR_AXI_DMA_0_DEVICE_ID
#  define TX_DMA_IDENTIFIER XPAR_AXI_DMA_1_DEVICE_ID
# else
#  error "Stage D requires both DMA0 and DMA1 device IDs in the BSP"
# endif
#endif

#include "protocol.h"

#define CTRL_BASE ((UINTPTR)0x40000000U)
#define TIME_BASE ((UINTPTR)0x40001000U)
#define MON_BASE ((UINTPTR)0x41200000U)
#define RX_DMA_EXPECT ((UINTPTR)0x40400000U)
#define TX_DMA_EXPECT ((UINTPTR)0x40410000U)
#define C_CONTROL 0x00U
#define C_COMMAND 0x04U
#define C_STATUS 0x08U
#define C_LAST_ERROR 0x0cU
#define C_DATA_SID 0x10U
#define C_VERSION_SID 0x14U
#define C_SAMPLES 0x18U
#define C_FS 0x1cU
#define C_BW 0x20U
#define C_RF_LO 0x24U
#define C_RF_HI 0x28U
#define C_CTX_PERIOD 0x2cU
#define C_VER_PERIOD 0x30U
#define C_RX_FILTER 0x34U
#define C_RX_DATA_SID 0x38U
#define C_RX_VERSION_SID 0x3cU
#define C_ACTIVE_DATA 0x40U
#define C_ACTIVE_VERSION 0x44U
#define C_ACTIVE_SAMPLES 0x48U
#define C_ACTIVE_FS 0x4cU
#define C_ACTIVE_BW 0x50U
#define C_ACTIVE_RF_LO 0x54U
#define C_ACTIVE_RF_HI 0x58U
#define C_ACTIVE_CTX 0x5cU
#define C_ACTIVE_VER 0x60U
#define T_SEC 0x00U
#define T_PS_LO 0x04U
#define T_PS_HI 0x08U
#define T_COMMAND 0x0cU
#define T_STATUS 0x10U
#define ST_PENDING 1U
#define ST_CONTEXT 2U
#define ST_BUSY 4U
#define ST_ENABLED 8U
#define ST_TIME_VALID 16U
#define ST_COMMIT_ERROR 32U
#define SPIN_LIMIT 80000000U
#define META_SPIN 3000000U
#define CPU_CLOCK_HZ 666666667U
#define TIMER_HZ 20U
#define UDP_PORT 4991U
#define MAX_CAPTURE_PACKETS 5U
#define MAX_SESSIONS 64U
#define MODE_READY 0U
#define MODE_TX 1U
#define MODE_RX 2U
#define MODE_FAULT 3U

static XAxiDma RxDma0,TxDma1;
/* Every cache-managed DMA buffer owns complete 64-byte cache lines. */
static u32 TxIQ[256] __attribute__((aligned(64)));
static u32 TxCapture[272] __attribute__((aligned(64)));
static u32 RxWords[272] __attribute__((aligned(64)));
static u32 RxIQ[256] __attribute__((aligned(64)));
static u32 Captures[MAX_CAPTURE_PACKETS][272] __attribute__((aligned(64)));
static u32 CaptureLengths[MAX_CAPTURE_PACKETS];
static unsigned char UdpStaging[SD4_MAX_FRAME];
static unsigned char Working[SD4_MAX_FRAME];
static unsigned char ReplyBuffer[SD4_MAX_FRAME];
static struct netif BoardNetif;
static struct udp_pcb *UdpPcb;
static XScuTimer ScuTimer;
static volatile u32 TimerTicks;
static u32 LastFast,LastSlow,LastArp;
static int PendingCommand;
static u16_t PendingLength,PendingPort;
static ip_addr_t PendingIp,SessionIp;
static u16_t SessionPort;
static u32 SessionId,LastTxid,UsedSessions[MAX_SESSIONS],SessionCount;
static u32 ProbeSession,ProbeTxid;
static ip_addr_t ProbeIp;
static u16_t ProbePort;
static u32 NextData,NextContext,NextVersion;
static u32 RxNextData,RxNextContext,RxNextVersion;
static u32 CurrentMode=MODE_READY;
static int Configured,StartupPending=1;
static const char *FaultReason="NONE";
static sd4_config Config={1,2,256,20000000,10000000,UINT64_C(100000000),3,1,2};
static void pump_net(void);

static void cwr(u32 off,u32 v){Xil_Out32(CTRL_BASE+off,v);}
static u32 crd(u32 off){return Xil_In32(CTRL_BASE+off);}
static void twr(u32 off,u32 v){Xil_Out32(TIME_BASE+off,v);}
static u32 trd(u32 off){return Xil_In32(TIME_BASE+off);}
static u32 mon_count(void){return Xil_In32(MON_BASE);}
static u32 mon_detail(void){return Xil_In32(MON_BASE+8U);}
static int time_valid(void){return (trd(T_STATUS)&1U)!=0U;}
static const char *mode_name(void)
{return CurrentMode==MODE_READY?"READY":CurrentMode==MODE_TX?"TX_ACTIVE":CurrentMode==MODE_RX?"RX_ACTIVE":"FAULT";}
static int fault(const char *reason)
{
    cwr(C_CONTROL,0U);CurrentMode=MODE_FAULT;FaultReason=reason;
    xil_printf("[FAULT] %s; reprogram the same Stage D bitstream and reload ELF\r\n",reason);
    return XST_FAILURE;
}
static u32 dma_sr(XAxiDma *dma,int direction)
{
    u32 off=direction==XAXIDMA_DEVICE_TO_DMA?XAXIDMA_RX_OFFSET:XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(dma->RegBase,off+XAXIDMA_SR_OFFSET);
}
/* Fresh unstarted Simple DMA is HALTED=1, IDLE=0. This is transition safety,
 * never transfer completion: a submitted DMA must explicitly reach IDLE. */
static int dma_quiet(u32 sr)
{return !(sr&XAXIDMA_ERR_ALL_MASK) && (sr&(XAXIDMA_HALTED_MASK|XAXIDMA_IDLE_MASK));}
static int all_dma_quiet(void)
{
    return dma_quiet(dma_sr(&RxDma0,XAXIDMA_DMA_TO_DEVICE)) &&
      dma_quiet(dma_sr(&RxDma0,XAXIDMA_DEVICE_TO_DMA)) &&
      dma_quiet(dma_sr(&TxDma1,XAXIDMA_DMA_TO_DEVICE)) &&
      dma_quiet(dma_sr(&TxDma1,XAXIDMA_DEVICE_TO_DMA));
}
static int dma_init(XAxiDma *dma,u32 identifier,UINTPTR base)
{
    XAxiDma_Config *cfg=XAxiDma_LookupConfig(identifier);
    if(!cfg || XAxiDma_CfgInitialize(dma,cfg)!=XST_SUCCESS || XAxiDma_HasSg(dma) || dma->RegBase!=base)
        return XST_FAILURE;
    XAxiDma_IntrDisable(dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}
static int dma_wait(XAxiDma *dma,int direction)
{
    u32 i,start=TimerTicks;
    for(i=0;i<SPIN_LIMIT;++i){
        u32 sr=dma_sr(dma,direction);
        if(sr&XAXIDMA_ERR_ALL_MASK)return fault("DMA_ERROR");
        if(sr&XAXIDMA_IDLE_MASK)return XST_SUCCESS;
        if((u32)(TimerTicks-start)>5U*TIMER_HZ)return fault("DMA_TIMEOUT");
        if(!(i&0x3fffU))pump_net(); /* callback stages into a separate buffer */
    }
    return fault("DMA_TIMEOUT");
}
static u32 received_bytes(XAxiDma *dma)
{return XAxiDma_ReadReg(dma->RegBase,XAXIDMA_RX_OFFSET+XAXIDMA_BUFFLEN_OFFSET);}
static int ensure_ready(void)
{
    u32 status=crd(C_STATUS);
    if(CurrentMode==MODE_FAULT)return XST_FAILURE;
    if(!all_dma_quiet() || (status&(ST_ENABLED|ST_BUSY|ST_PENDING)))return fault("DRAIN_GUARD");
    return XST_SUCCESS;
}
/* Disable TX, then wait for the real scheduler to retire its packet. Never
 * claim READY on a delay alone or automatically reset uncertain DMA state. */
static int drain(void)
{
    u32 i;cwr(C_CONTROL,0U);
    for(i=0;i<META_SPIN;++i){
        if(!(crd(C_STATUS)&(ST_ENABLED|ST_BUSY)) && all_dma_quiet()){
            CurrentMode=MODE_READY;return XST_SUCCESS;
        }
    }
    return fault("DRAIN_TIMEOUT");
}
static int commit_config(const sd4_config *c)
{
    u32 i,status;
    if(ensure_ready()!=XST_SUCCESS)return XST_FAILURE;
    cwr(C_CONTROL,0U);
    cwr(C_DATA_SID,c->data_sid);cwr(C_VERSION_SID,c->version_sid);
    cwr(C_SAMPLES,c->samples);cwr(C_FS,c->fs);cwr(C_BW,c->bw);
    cwr(C_RF_LO,(u32)c->rf_hz);cwr(C_RF_HI,(u32)(c->rf_hz>>32));
    cwr(C_CTX_PERIOD,0);cwr(C_VER_PERIOD,0); /* no unbounded periodic TX */
    cwr(C_RX_DATA_SID,c->rx_data_sid);cwr(C_RX_VERSION_SID,c->rx_version_sid);
    cwr(C_RX_FILTER,c->rx_filter);
    cwr(C_COMMAND,1U);
    for(i=0;i<META_SPIN;++i){
        status=crd(C_STATUS);
        if(status&ST_COMMIT_ERROR)return fault("CONFIG_COMMIT_ERROR");
        if(!(status&ST_PENDING))break;
    }
    if(i==META_SPIN)return fault("CONFIG_COMMIT_TIMEOUT");
    if(crd(C_ACTIVE_DATA)!=c->data_sid || crd(C_ACTIVE_VERSION)!=c->version_sid ||
       crd(C_ACTIVE_SAMPLES)!=c->samples || crd(C_ACTIVE_FS)!=c->fs || crd(C_ACTIVE_BW)!=c->bw ||
       crd(C_ACTIVE_RF_LO)!=(u32)c->rf_hz || crd(C_ACTIVE_RF_HI)!=(u32)(c->rf_hz>>32) ||
       crd(C_ACTIVE_CTX)!=0 || crd(C_ACTIVE_VER)!=0 || crd(C_RX_FILTER)!=c->rx_filter ||
       crd(C_RX_DATA_SID)!=c->rx_data_sid || crd(C_RX_VERSION_SID)!=c->rx_version_sid ||
       !(crd(C_STATUS)&ST_CONTEXT))return fault("CONFIG_READBACK");
    Config=*c;
    return ensure_ready();
}
static int set_utc(u32 seconds,u32 ns)
{
    u32 i;u64 ps=(u64)ns*1000ULL;
    if(ns>=1000000000U || time_valid())return XST_FAILURE;
    if(ensure_ready()!=XST_SUCCESS)return XST_FAILURE;
    twr(T_SEC,seconds);twr(T_PS_LO,(u32)ps);twr(T_PS_HI,(u32)(ps>>32));
    if(trd(T_SEC)!=seconds || trd(T_PS_LO)!=(u32)ps || trd(T_PS_HI)!=(u32)(ps>>32))return fault("UTC_SHADOW_READBACK");
    twr(T_COMMAND,1U);
    for(i=0;i<META_SPIN;++i){
        if(trd(T_STATUS)&2U)return fault("UTC_LOAD_REJECTED");
        if(time_valid() && (crd(C_STATUS)&ST_TIME_VALID))return ensure_ready();
    }
    return fault("UTC_LOAD_TIMEOUT");
}

static int fail(const char *reason){xil_printf("[FAIL] %s\r\n",reason);return XST_FAILURE;}
static int udp_send_raw(const ip_addr_t *dst,u16_t port,const unsigned char *bytes,u16_t n)
{
    struct pbuf *p=pbuf_alloc(PBUF_TRANSPORT,n,PBUF_RAM);err_t rc;
    if(!p)return fail("UDP_ALLOC");
    if(pbuf_take(p,bytes,n)!=ERR_OK){pbuf_free(p);return fail("UDP_COPY");}
    rc=udp_sendto(UdpPcb,p,dst,port);pbuf_free(p);
    return rc==ERR_OK?XST_SUCCESS:fail("UDP_SEND");
}
static int send_frame(const ip_addr_t *dst,u16_t port,const sd4_frame *request,
                       u8 op,u32 code,const unsigned char *payload,u32 length)
{
    if(length>SD4_MAX_PAYLOAD)return XST_FAILURE;
    sd4_header(ReplyBuffer,op,request->session,request->txid,length,code);
    if(length)memcpy(ReplyBuffer+SD4_HEADER,payload,length);
    return udp_send_raw(dst,port,ReplyBuffer,(u16_t)(SD4_HEADER+length));
}
static int send_text(const ip_addr_t *dst,u16_t port,const sd4_frame *f,u8 op,const char *text)
{return send_frame(dst,port,f,op,0,(const unsigned char *)text,(u32)strlen(text));}
static void send_error(const ip_addr_t *dst,u16_t port,const sd4_frame *f,int code,const char *reason)
{
    char text[192];
    snprintf(text,sizeof(text),"%s STATE=%s REASON=%s",sd4_error_name(code),mode_name(),reason?reason:sd4_error_name(code));
    (void)send_frame(dst,port,f,SD4_ERROR,(u32)code,(const unsigned char *)text,(u32)strlen(text));
}
static int send_words(const ip_addr_t *dst,u16_t port,const sd4_frame *f,u8 op,const u32 *words,u32 n)
{
    u32 i;
    if(n>SD4_MAX_WORDS)return XST_FAILURE;
    sd4_header(ReplyBuffer,op,f->session,f->txid,n*4U,0);
    for(i=0;i<n;++i)sd4_put32(ReplyBuffer+SD4_HEADER+4U*i,words[i]);
    return udp_send_raw(dst,port,ReplyBuffer,(u16_t)(SD4_HEADER+n*4U));
}
static void status_text(char *text,size_t size,int ascii)
{
    snprintf(text,size,
      "%sPROTO=4 STATE=%s UTC=%u SESSION=%lu CONFIGURED=%u NEXT_DATA=%lu NEXT_CONTEXT=%lu NEXT_VERSION=%lu "
      "RX_DATA_NEXT=%lu RX_CONTEXT_NEXT=%lu RX_VERSION_NEXT=%lu ENGINE=%08lx MON_COUNT=%08lx MON_DETAIL=%08lx REASON=%s",
      ascii?"STATUS ":"",mode_name(),(unsigned)time_valid(),(unsigned long)SessionId,Configured,
      (unsigned long)NextData,(unsigned long)NextContext,(unsigned long)NextVersion,
      (unsigned long)RxNextData,(unsigned long)RxNextContext,(unsigned long)RxNextVersion,
      (unsigned long)crd(C_STATUS),(unsigned long)mon_count(),(unsigned long)mon_detail(),FaultReason);
}
static int send_done(const ip_addr_t *dst,u16_t port,const sd4_frame *f,const sd4_packet_info *info,u32 packets)
{
    char text[420];
    if(ensure_ready()!=XST_SUCCESS)return XST_FAILURE;
    snprintf(text,sizeof(text),
      "STATE=READY TYPE=%s SEQ=%lu SAMPLES=%lu PACKETS=%lu NEXT_DATA=%lu NEXT_CONTEXT=%lu NEXT_VERSION=%lu "
      "RX_DATA_NEXT=%lu RX_CONTEXT_NEXT=%lu RX_VERSION_NEXT=%lu META=%u MON_COUNT=%08lx MON_DETAIL=%08lx",
      info->type==1?"DATA":info->type==4?"CONTEXT":"VERSION",
      (unsigned long)info->sequence,(unsigned long)info->samples,(unsigned long)packets,
      (unsigned long)NextData,(unsigned long)NextContext,(unsigned long)NextVersion,
      (unsigned long)RxNextData,(unsigned long)RxNextContext,(unsigned long)RxNextVersion,
      info->type!=1,(unsigned long)mon_count(),(unsigned long)mon_detail());
    return send_text(dst,port,f,SD4_DONE,text);
}
static u32 *tx_sequence(u32 type){return type==1?&NextData:type==4?&NextContext:&NextVersion;}
static u32 *rx_sequence(u32 type){return type==1?&RxNextData:type==4?&RxNextContext:&RxNextVersion;}

/* Capture each actual PL packet using its DMA S2MM byte-count register. The
 * startup Version and commit/periodic-pending Context are never built in PS. */
static int run_tx(const sd4_frame *f,const ip_addr_t *dst,u16_t port)
{
    u32 i,k,n,bytes,captured=0;sd4_packet_info info;const char *why;
    if(f->length!=Config.samples*4U)return SD4_BAD_LENGTH;
    if(ensure_ready()!=XST_SUCCESS)return SD4_HW_FAULT;
    for(i=0;i<Config.samples;++i)TxIQ[i]=sd4_get32(f->payload+4U*i);
    Xil_DCacheFlushRange((INTPTR)TxIQ,sizeof(TxIQ));
    memset(TxCapture,0xa5,sizeof(TxCapture));
    Xil_DCacheFlushRange((INTPTR)TxCapture,sizeof(TxCapture));
    CurrentMode=MODE_TX;
    if(XAxiDma_SimpleTransfer(&TxDma1,(UINTPTR)TxCapture,SD4_MAX_PAYLOAD,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)
        {fault("TX_S2MM_ARM");return SD4_DMA_ERROR;}
    if(XAxiDma_SimpleTransfer(&TxDma1,(UINTPTR)TxIQ,Config.samples*4U,XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)
        {fault("TX_MM2S_START");return SD4_DMA_ERROR;}
    cwr(C_CONTROL,1U);
    for(k=0;k<MAX_CAPTURE_PACKETS;++k){
        if(dma_wait(&TxDma1,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)return SD4_DMA_ERROR;
        bytes=received_bytes(&TxDma1);
        if(!bytes || bytes%4U || bytes>SD4_MAX_PAYLOAD){fault("TX_DMA_LENGTH");return SD4_HW_FAULT;}
        Xil_DCacheInvalidateRange((INTPTR)TxCapture,sizeof(TxCapture));n=bytes/4U;
        why=sd4_validate_packet(TxCapture,n,&Config,1,&info);
        if(why){fault(why);return SD4_HW_FAULT;}
        if(info.sequence!=*tx_sequence(info.type)){fault("TX_SEQUENCE");return SD4_HW_FAULT;}
        if(StartupPending && info.type!=5){fault("TX_MISSING_STARTUP_VERSION");return SD4_HW_FAULT;}
        if(info.type==5)StartupPending=0;
        *tx_sequence(info.type)=(info.sequence+1U)&15U;
        memcpy(Captures[k],TxCapture,bytes);CaptureLengths[k]=n;++captured;
        if(info.type==1){
            cwr(C_CONTROL,0U); /* stop scheduling immediately after data TLAST */
            for(i=0;i<Config.samples;++i)
                if(TxCapture[7U+i]!=TxIQ[i]){fault("TX_IQ_MISMATCH");return SD4_HW_FAULT;}
            break;
        }
        memset(TxCapture,0xa5,sizeof(TxCapture));
        Xil_DCacheFlushRange((INTPTR)TxCapture,sizeof(TxCapture));
        if(XAxiDma_SimpleTransfer(&TxDma1,(UINTPTR)TxCapture,SD4_MAX_PAYLOAD,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)
            {fault("TX_METADATA_REARM");return SD4_DMA_ERROR;}
    }
    if(k==MAX_CAPTURE_PACKETS){fault("TX_METADATA_LIMIT");return SD4_HW_FAULT;}
    if(dma_wait(&TxDma1,XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS || drain()!=XST_SUCCESS)return SD4_DMA_ERROR;
    if(crd(C_STATUS)&ST_CONTEXT){fault("TX_CONTEXT_NOT_DRAINED");return SD4_HW_FAULT;}
    for(i=0;i<captured;++i)
        if(send_words(dst,port,f,SD4_PACKET,Captures[i],CaptureLengths[i])!=XST_SUCCESS)
            {fault("TX_UDP_SEND");return SD4_UDP_ERROR;}
    if(send_done(dst,port,f,&info,captured)!=XST_SUCCESS){fault("TX_DONE_SEND");return SD4_UDP_ERROR;}
    return SD4_OK;
}
static int errors_saturated(u32 details)
{
    u32 shift;
    for(shift=16;shift<32;shift+=4)if(((details>>shift)&15U)==15U)return 1;
    return 0;
}
static int run_rx(const sd4_frame *f,const ip_addr_t *dst,u16_t port,const char **reason)
{
    u32 i,n=f->length/4U,before,after,detail,errors,oldv,oldc;
    sd4_packet_info info;
    for(i=0;i<n;++i)RxWords[i]=sd4_get32(f->payload+4U*i);
    *reason=sd4_validate_packet(RxWords,n,&Config,0,&info);
    if(*reason)return SD4_BAD_PACKET;
    /* Independent RX sequence, preserved across OPEN/CLOSE/config changes. */
    if(info.sequence!=*rx_sequence(info.type)){*reason="RX_SEQUENCE_EXPECTED_STATUS_RX_TYPE_NEXT";return SD4_RX_SEQUENCE;}
    before=mon_count();detail=mon_detail();errors=detail&0xffff0000U;
    oldv=before>>16;oldc=before&65535U;
    if(errors_saturated(detail) || (info.type==5 && oldv==65535U) || (info.type==4 && oldc==65535U))
        {*reason="MONITOR_SATURATED_RELOAD_PL";return SD4_HW_FAULT;}
    if(ensure_ready()!=XST_SUCCESS)return SD4_HW_FAULT;
    Xil_DCacheFlushRange((INTPTR)RxWords,sizeof(RxWords));
    CurrentMode=MODE_RX;
    if(info.type==1){
        memset(RxIQ,0xa5,sizeof(RxIQ));Xil_DCacheFlushRange((INTPTR)RxIQ,sizeof(RxIQ));
        if(XAxiDma_SimpleTransfer(&RxDma0,(UINTPTR)RxIQ,info.samples*4U,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)
            {fault("RX_S2MM_ARM");return SD4_DMA_ERROR;}
    }
    if(XAxiDma_SimpleTransfer(&RxDma0,(UINTPTR)RxWords,f->length,XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)
        {fault("RX_MM2S_START");return SD4_DMA_ERROR;}
    if(dma_wait(&RxDma0,XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)return SD4_DMA_ERROR;
    if(info.type==1){
        if(dma_wait(&RxDma0,XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)return SD4_DMA_ERROR;
        if(received_bytes(&RxDma0)!=info.samples*4U){fault("RX_DMA_LENGTH");return SD4_HW_FAULT;}
        Xil_DCacheInvalidateRange((INTPTR)RxIQ,sizeof(RxIQ));
        for(i=0;i<info.samples;++i)if(RxIQ[i]!=RxWords[7U+i]){fault("RX_IQ_MISMATCH");return SD4_HW_FAULT;}
    }else{
        for(i=0;i<META_SPIN;++i){
            after=mon_count();
            if(info.type==5?(after>>16)!=oldv:(after&65535U)!=oldc)break;
        }
        if(i==META_SPIN){fault("RX_METADATA_TIMEOUT");return SD4_HW_FAULT;}
        after=mon_count();detail=mon_detail();
        if(info.type==5){
            if((after>>16)!=oldv+1U || (after&65535U)!=oldc || ((detail>>4)&15U)!=info.sequence ||
               ((detail>>9)&1U)!=(RxWords[7]>>31)){fault("RX_VERSION_MONITOR");return SD4_HW_FAULT;}
        }else{
            if((after&65535U)!=oldc+1U || (after>>16)!=oldv || (detail&15U)!=info.sequence ||
               ((detail>>8)&1U)!=(RxWords[7]>>31)){fault("RX_CONTEXT_MONITOR");return SD4_HW_FAULT;}
        }
    }
    if((mon_detail()&0xffff0000U)!=errors){fault("RX_PARSER_ERROR");return SD4_HW_FAULT;}
    if(drain()!=XST_SUCCESS)return SD4_HW_FAULT;
    *rx_sequence(info.type)=(info.sequence+1U)&15U;
    if(info.type==1 && send_words(dst,port,f,SD4_IQ,RxIQ,info.samples)!=XST_SUCCESS)
        {fault("RX_IQ_UDP_SEND");return SD4_UDP_ERROR;}
    if(send_done(dst,port,f,&info,1)!=XST_SUCCESS){fault("RX_DONE_SEND");return SD4_UDP_ERROR;}
    return SD4_OK;
}

static void on_udp_packet(void *arg,struct udp_pcb *pcb,struct pbuf *p,const ip_addr_t *src,u16_t port)
{
    unsigned n;unsigned char head[SD4_HEADER];sd4_frame f;
    (void)arg;(void)pcb;
    if(!p)return;
    n=p->tot_len;
    /* Callback never performs DMA, AXI configuration, or session mutation. */
    if(PendingCommand || n>SD4_MAX_FRAME){
        if(n>=SD4_HEADER && pbuf_copy_partial(p,head,SD4_HEADER,0)==SD4_HEADER && !memcmp(head,"SDU4",4)){
            memset(&f,0,sizeof(f));f.session=sd4_get32(head+8);f.txid=sd4_get32(head+12);
            send_error(src,port,&f,PendingCommand?SD4_BUSY:SD4_BAD_LENGTH,NULL);
        }
        pbuf_free(p);return;
    }
    if(pbuf_copy_partial(p,UdpStaging,(u16_t)n,0)!=(u16_t)n){pbuf_free(p);return;}
    PendingLength=(u16_t)n;ip_addr_copy(PendingIp,*src);PendingPort=port;PendingCommand=1;
    pbuf_free(p);
}
static int session_seen(u32 id)
{
    u32 i;for(i=0;i<SessionCount;++i)if(UsedSessions[i]==id)return 1;
    return 0;
}
static void handle_command(void)
{
    sd4_frame f;sd4_config config;ip_addr_t dst;u16_t port,n;
    int error;u32 sec,ns;const char *reason=NULL;char text[600];
    /* Working storage cannot be overwritten by callbacks during pump_net(). */
    n=PendingLength;port=PendingPort;ip_addr_copy(dst,PendingIp);memcpy(Working,UdpStaging,n);PendingCommand=0;
    if(n==6 && !memcmp(Working,"STATUS",6)){
        if(CurrentMode==MODE_READY)(void)ensure_ready();
        status_text(text,sizeof(text),1);
        (void)udp_send_raw(&dst,port,(const unsigned char *)text,(u16_t)strlen(text));return;
    }
    memset(&f,0,sizeof(f));error=sd4_decode(Working,n,&f);
    if(error){
        if(n>=SD4_HEADER && !memcmp(Working,"SDU4",4))send_error(&dst,port,&f,error,NULL);
        else{
            const char *text_error="ERROR PROTO=4 USE_STATUS_OR_SDU4";
            (void)udp_send_raw(&dst,port,(const unsigned char *)text_error,(u16_t)strlen(text_error));
        }
        return;
    }
    if(SessionId){
        if(f.session!=SessionId){send_error(&dst,port,&f,SD4_BAD_SESSION,NULL);return;}
        if(!ip_addr_cmp(&dst,&SessionIp) || port!=SessionPort){send_error(&dst,port,&f,SD4_SESSION_PEER,NULL);return;}
        /* Consume before acting, including validation errors: retrying TX/RX
         * with the same identity can never submit the DMA a second time. */
        error=sd4_txid_accept(&LastTxid,f.txid);
        if(error){send_error(&dst,port,&f,error,NULL);return;}
    }else{
        if(f.op!=SD4_CAPS && f.op!=SD4_OPEN){send_error(&dst,port,&f,SD4_NOT_OPEN,NULL);return;}
        if(ProbeSession==f.session){
            if(!ip_addr_cmp(&dst,&ProbeIp) || port!=ProbePort){send_error(&dst,port,&f,SD4_SESSION_PEER,NULL);return;}
            error=sd4_txid_accept(&ProbeTxid,f.txid);
            if(error){send_error(&dst,port,&f,error,NULL);return;}
        }else{
            ProbeSession=f.session;ProbeTxid=f.txid;ip_addr_copy(ProbeIp,dst);ProbePort=port;
        }
    }
    if(f.op==SD4_CAPS){
        snprintf(text,sizeof(text),"PROTO=4 MIN_SAMPLES=1 MAX_SAMPLES=256 CUSTOM_TX=1 CUSTOM_RX=1 "
          "TX_TYPES=DATA RX_TYPES=VERSION,CONTEXT,DATA AUTO_META=1 VERSION_ON_DEMAND=0 CONFIG=1 UTC_ONCE=1 "
          "SEQUENCE_RESET=0 MAX_SESSIONS=%u",MAX_SESSIONS);
        (void)send_text(&dst,port,&f,SD4_CAPS|0x80,text);return;
    }
    if(f.op==SD4_STATUS){
        if(CurrentMode==MODE_READY)(void)ensure_ready();
        status_text(text,sizeof(text),0);(void)send_text(&dst,port,&f,SD4_STATUS|0x80,text);return;
    }
    if(CurrentMode==MODE_FAULT){send_error(&dst,port,&f,SD4_HW_FAULT,FaultReason);return;}
    if(ensure_ready()!=XST_SUCCESS){send_error(&dst,port,&f,SD4_HW_FAULT,FaultReason);return;}
    switch(f.op){
    case SD4_OPEN:
        if(SessionId){send_error(&dst,port,&f,SD4_SESSION_BUSY,NULL);return;}
        if(session_seen(f.session)){send_error(&dst,port,&f,SD4_SESSION_REUSED,NULL);return;}
        if(SessionCount>=MAX_SESSIONS){send_error(&dst,port,&f,SD4_SESSION_LIMIT,NULL);return;}
        SessionId=f.session;LastTxid=f.txid;ip_addr_copy(SessionIp,dst);SessionPort=port;
        UsedSessions[SessionCount++]=SessionId;Configured=0;
        status_text(text,sizeof(text),0);(void)send_text(&dst,port,&f,SD4_OPEN|0x80,text);return;
    case SD4_CONFIG:
        error=sd4_config_decode(f.payload,f.length,&config);
        if(error){send_error(&dst,port,&f,error,NULL);return;}
        if(commit_config(&config)!=XST_SUCCESS){send_error(&dst,port,&f,SD4_HW_FAULT,FaultReason);return;}
        Configured=1;
        snprintf(text,sizeof(text),"STATE=READY DATA_SID=%lu VERSION_SID=%lu SAMPLES=%lu FS=%lu BW=%lu "
          "RF_HZ=%llu RX_FILTER=%lu RX_DATA_SID=%lu RX_VERSION_SID=%lu CONTEXT_PENDING=1",
          (unsigned long)Config.data_sid,(unsigned long)Config.version_sid,(unsigned long)Config.samples,
          (unsigned long)Config.fs,(unsigned long)Config.bw,(unsigned long long)Config.rf_hz,
          (unsigned long)Config.rx_filter,(unsigned long)Config.rx_data_sid,(unsigned long)Config.rx_version_sid);
        (void)send_text(&dst,port,&f,SD4_CONFIG|0x80,text);return;
    case SD4_UTC:
        sec=sd4_get32(f.payload);ns=sd4_get32(f.payload+4);
        if(ns>=1000000000U){send_error(&dst,port,&f,SD4_BAD_CONFIG,"UTC_NANOSECONDS");return;}
        if(time_valid()){send_error(&dst,port,&f,SD4_UTC_ALREADY_SET,NULL);return;}
        if(set_utc(sec,ns)!=XST_SUCCESS){send_error(&dst,port,&f,SD4_HW_FAULT,FaultReason);return;}
        (void)send_text(&dst,port,&f,SD4_UTC|0x80,"STATE=READY UTC=1");return;
    case SD4_TX:
    case SD4_RX:
        if(!Configured){send_error(&dst,port,&f,SD4_NOT_CONFIGURED,NULL);return;}
        if(!time_valid()){send_error(&dst,port,&f,SD4_UTC_REQUIRED,NULL);return;}
        error=f.op==SD4_TX?run_tx(&f,&dst,port):run_rx(&f,&dst,port,&reason);
        if(error)send_error(&dst,port,&f,error,reason?reason:CurrentMode==MODE_FAULT?FaultReason:NULL);
        return;
    case SD4_CLOSE:
        SessionId=0;LastTxid=0;Configured=0;
        status_text(text,sizeof(text),0);(void)send_text(&dst,port,&f,SD4_CLOSE|0x80,text);return;
    default:send_error(&dst,port,&f,SD4_BAD_OPERATION,NULL);return;
    }
}

static void timer_irq(void *context)
{
    XScuTimer_ClearInterruptStatus((XScuTimer *)context);
    ++TimerTicks;
}
static int init_irq_timer(void)
{
    XScuTimer_Config *cfg = XScuTimer_LookupConfig(XPAR_SCUTIMER_BASEADDR);
    if(!cfg || XScuTimer_CfgInitialize(&ScuTimer,cfg,cfg->BaseAddr)!=XST_SUCCESS)
        return fail("SCU timer init");
    XScuTimer_EnableAutoReload(&ScuTimer);
    XScuTimer_LoadTimer(&ScuTimer,CPU_CLOCK_HZ/(2U*TIMER_HZ));
    XScuTimer_ClearInterruptStatus(&ScuTimer);
    Xil_ExceptionInit();
    if(XScuGic_DeviceInitialize(XPAR_SCUGIC_DIST_BASEADDR)!=XST_SUCCESS)
        return fail("GIC init");
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
            (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
            (void *)XPAR_SCUGIC_CPU_BASEADDR);
    XScuGic_RegisterHandler(XPAR_SCUGIC_CPU_BASEADDR,XPAR_SCUTIMER_INTR,
            (Xil_ExceptionHandler)timer_irq,(void *)&ScuTimer);
    XScuGic_EnableIntr(XPAR_SCUGIC_DIST_BASEADDR,XPAR_SCUTIMER_INTR);
    return XST_SUCCESS;
}


static void pump_net(void)
{
    u32 now;
    xemacif_input(&BoardNetif);
    now=TimerTicks;
    if((u32)(now-LastFast)>=5U){LastFast=now;tcp_fasttmr();}
    if((u32)(now-LastSlow)>=10U){LastSlow=now;tcp_slowtmr();}
    if((u32)(now-LastArp)>=100U){LastArp=now;etharp_tmr();}
}
static int init_network(void)
{
    ip_addr_t addr,mask,gw;
    unsigned char mac[6]={0x02,0x0a,0x35,0x00,0x01,0x02};
    if(init_irq_timer()!=XST_SUCCESS)return XST_FAILURE;
    IP4_ADDR(&addr,192,168,1,10);
    IP4_ADDR(&mask,255,255,255,0);
    IP4_ADDR(&gw,192,168,1,1);
    lwip_init();
    if(!xemac_add(&BoardNetif,&addr,&mask,&gw,mac,XPAR_XEMACPS_0_BASEADDR))
        return fail("xemac_add GEM0/MDIO failed");
    netif_set_default(&BoardNetif);
    netif_set_up(&BoardNetif);
    UdpPcb=udp_new();
    if(!UdpPcb)return fail("udp_new");
    if(udp_bind(UdpPcb,IP_ADDR_ANY,UDP_PORT)!=ERR_OK)return fail("UDP bind");
    udp_recv(UdpPcb,on_udp_packet,NULL);
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    XScuTimer_EnableInterrupt(&ScuTimer);
    XScuTimer_Start(&ScuTimer);
    xil_printf("[UDP] Listening 192.168.1.10:4991; ENGINE_STATE=%s; ASCII STATUS discovery\r\n",mode_name());
    return XST_SUCCESS;
}

int main(void)
{
    xil_printf("\r\n=== STAGE D v0.4 SDU4 CUSTOM IQ / REAL DUAL DMA ===\r\n");
    if(dma_init(&RxDma0,RX_DMA_IDENTIFIER,RX_DMA_EXPECT)!=XST_SUCCESS ||
       dma_init(&TxDma1,TX_DMA_IDENTIFIER,TX_DMA_EXPECT)!=XST_SUCCESS){
        xil_printf("[FATAL] Stage D DMA0/DMA1/BSP address mismatch\r\n");
        for(;;)usleep(1000000U);
    }
    Xil_Out32(MON_BASE+4U,0xffffffffU);Xil_Out32(MON_BASE+12U,0xffffffffU);
    /* There is no TX sequence/startup-pending reset/readback register. A warm
     * PL cannot be reconstructed safely from a PS restart. Refuse to guess. */
    if(time_valid() || (crd(C_STATUS)&(ST_ENABLED|ST_BUSY)) || !all_dma_quiet() || mon_count()!=0 || (mon_detail()&0xffff0000U))
        (void)fault("WARM_PL_RELOAD_REQUIRED");
    else if(commit_config(&Config)!=XST_SUCCESS)
        (void)fault("BOOT_CONFIG_FAILED");
    if(init_network()!=XST_SUCCESS){
        xil_printf("[FATAL] GEM0/LwIP init failed\r\n");
        for(;;)usleep(1000000U);
    }
    xil_printf("[INFO] Build only has not established board acceptance. STATE=%s\r\n",mode_name());
    for(;;){pump_net();if(PendingCommand)handle_command();}
    return XST_SUCCESS;
}
