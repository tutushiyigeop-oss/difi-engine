/* DIFI IP performance test. Results include PS, DMA, and cache overhead, not PL-only performance. */
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "difi_perf_timer.h"
#include "sleep.h"
#include "difi_ip_addresses.h"

#if defined(SDT)
# define DMA_IDENTIFIER XPAR_XAXIDMA_0_BASEADDR
#else
# define DMA_IDENTIFIER XPAR_AXIDMA_0_DEVICE_ID
#endif

#define N_SAMPLES         256U
#define PERF_ROUNDS       100U
#define WARMUP_ROUNDS       2U
#define DMA_SPIN_LIMIT  100000000U

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

#define T_SEC              0x00U
#define T_PS_LO            0x04U
#define T_PS_HI            0x08U
#define T_COMMAND          0x0CU
#define T_STATUS           0x10U

#define TEST_TIME_SEC     1700000000U  /* Test time, not real UTC. */
#define TEST_DATA_SID     0x10203040U
#define TEST_VERSION_SID  0x55667788U
#define TEST_SAMPLE_RATE   2000000U
#define TEST_BANDWIDTH     1500000U
#define TEST_RF_FREQ     915000000U

static XAxiDma Dma;
static u32 TxIQ[N_SAMPLES] __attribute__((aligned(64)));
static u32 RxIQ[N_SAMPLES] __attribute__((aligned(64)));

static void cwr(u32 off, u32 v) { Xil_Out32((UINTPTR)DIFI_CTRL_BASE+off,v); }
static u32 crd(u32 off) { return Xil_In32((UINTPTR)DIFI_CTRL_BASE+off); }
static void twr(u32 off, u32 v) { Xil_Out32((UINTPTR)DIFI_TIME_BASE+off,v); }
static u32 trd(u32 off) { return Xil_In32((UINTPTR)DIFI_TIME_BASE+off); }

static int fail(const char *why)
{
    xil_printf("[FAIL] %s\r\n",why);
    return XST_FAILURE;
}

static int wait_dma(int direction, const char *name)
{
    UINTPTR off = (direction == XAXIDMA_DEVICE_TO_DMA) ?
                  (UINTPTR)XAXIDMA_RX_OFFSET : (UINTPTR)XAXIDMA_TX_OFFSET;
    u32 n;
    for (n=0U; n<DMA_SPIN_LIMIT; ++n) {
        u32 sr=XAxiDma_ReadReg(Dma.RegBase+off,XAXIDMA_SR_OFFSET);
        if (sr & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("[FAIL] %s DMA error SR=%08x\r\n",name,(unsigned)sr);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma,direction)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] %s DMA timeout\r\n",name);
    return XST_FAILURE;
}

static int configure_time(void)
{
    u32 k;
    if (trd(T_STATUS)&1U)
        return fail("TIME already valid; download bitstream/reset PL first");
    twr(T_SEC,TEST_TIME_SEC);
    twr(T_PS_LO,0U);
    twr(T_PS_HI,0U);
    twr(T_COMMAND,1U);
    for (k=0U; k<50000U; ++k) {
        u32 s=trd(T_STATUS);
        if (s&2U) return fail("TIME load rejected");
        if (s&1U) {
            if (!(crd(C_STATUS)&(1U<<4)))
                return fail("time_valid not propagated");
            return XST_SUCCESS;
        }
    }
    return fail("TIME invalid; check address/bitstream");
}

static int configure_engine(void)
{
    u32 k;
    cwr(C_CONTROL,0U);
    cwr(C_DATA_SID,TEST_DATA_SID);
    cwr(C_VER_SID,TEST_VERSION_SID);
    cwr(C_SAMPLES,N_SAMPLES);
    cwr(C_FS,TEST_SAMPLE_RATE);
    cwr(C_BW,TEST_BANDWIDTH);
    cwr(C_RF_LO,TEST_RF_FREQ);
    cwr(C_RF_HI,0U);
    cwr(C_CTX_PERIOD,0U);
    cwr(C_VER_PERIOD,0U);
    cwr(C_RX_FILTER,3U);
    cwr(C_RX_DATA_SID,TEST_DATA_SID);
    cwr(C_RX_VER_SID,TEST_VERSION_SID);
    cwr(C_COMMAND,1U);
    for (k=0U; k<100000U; ++k) {
        u32 status=crd(C_STATUS);
        if (status&(1U<<5)) return fail("config commit error");
        if (!(status&1U) && crd(C_ACTIVE_SAMPLES)==N_SAMPLES) break;
    }
    if (k==100000U || crd(C_COMMIT_ERROR)!=0U)
        return fail("config commit timeout/error");
    return XST_SUCCESS;
}

static void prepare_data(u32 round)
{
    u32 i;
    for (i=0U;i<N_SAMPLES;++i) {
        u32 iv=(0x1000U+i+0x0200U*round)&0xFFFFU;
        u32 qv=(0xA000U+3U*i+0x0011U*round)&0xFFFFU;
        TxIQ[i]=(iv<<16)|qv;
        RxIQ[i]=0xDEADBEEFU;
    }
    Xil_DCacheFlushRange((INTPTR)TxIQ,(u32)sizeof(TxIQ));
    Xil_DCacheFlushRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
    Xil_DCacheInvalidateRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
}

/* Arm reception before MM2S to avoid losing data output immediately. */
static int transfer_one_packet(u64 *elapsed)
{
    u64 a,b;
    a = PerfTimer_ReadTicks();
    if (XAxiDma_SimpleTransfer(&Dma,(UINTPTR)RxIQ,sizeof(RxIQ),
                               XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)
        return fail("S2MM arm failed");
    if (XAxiDma_SimpleTransfer(&Dma,(UINTPTR)TxIQ,sizeof(TxIQ),
                               XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)
        return fail("MM2S start failed");
    if (wait_dma(XAXIDMA_DMA_TO_DEVICE,"MM2S")!=XST_SUCCESS ||
        wait_dma(XAXIDMA_DEVICE_TO_DMA,"S2MM")!=XST_SUCCESS)
        return XST_FAILURE;
    b = PerfTimer_ReadTicks();
    if (b<=a) return fail("non-monotonic/zero selected hardware timer");
    *elapsed = b-a;
    return XST_SUCCESS;
}

static int check_packet(u32 round)
{
    u32 i;
    Xil_DCacheInvalidateRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
    for (i=0U;i<N_SAMPLES;++i) {
        if (TxIQ[i] != RxIQ[i]) {
            xil_printf("[FAIL] round %u IQ[%u] TX=%08x RX=%08x\r\n",
                       (unsigned)round,(unsigned)i,
                       (unsigned)TxIQ[i],(unsigned)RxIQ[i]);
            return XST_FAILURE;
        }
    }
    return XST_SUCCESS;
}

/* xil_printf does not support floats; print integer values. */
#if PERF_HAVE_TIMER_FREQ
static u32 mbps_x1000(u64 bytes, u64 ticks)
{
    if (!ticks) return 0U;
    return (u32)((bytes*PERF_TICKS_PER_SEC)/(ticks*1000ULL));
}
static void print_fixed3(const char *label,u32 milli)
{
    u32 fract=milli%1000U;
    xil_printf("%s%u.%c%c%c\r\n",label,(unsigned)(milli/1000U),
               (int)('0'+fract/100U),
               (int)('0'+(fract/10U)%10U),
               (int)('0'+fract%10U));
}
#endif

int main(void)
{
    XAxiDma_Config *cfg;
    u32 round,correct=0U,done=0U;
    u32 gt_ctl_before, gt_ctl_after, pmu_before, pmu_after, timer_kind;
    u64 gt_before, gt_after;
    u64 begin,finish,tx_elapsed;
    u64 transaction_ticks=0ULL;
    u64 wall_ticks;
    u64 measured_bytes=(u64)PERF_ROUNDS*(u64)N_SAMPLES*4ULL;

    xil_printf("\r\n=== DIFI BOARD IP PERF: ZYNQ-7020 / 100 MHz ===\r\n");
    xil_printf("[INFO] CTRL=%08x TIME=%08x DMA identifier=%08x\r\n",
               (unsigned)DIFI_CTRL_BASE,(unsigned)DIFI_TIME_BASE,
               (unsigned)DMA_IDENTIFIER);
    xil_printf("[INFO] rounds=%u warmup=%u samples/packet=%u\r\n",
               (unsigned)PERF_ROUNDS,(unsigned)WARMUP_ROUNDS,(unsigned)N_SAMPLES);
    xil_printf("[INFO] timer=Zynq Cortex-A9 GT/PMU hardware counters (auto detect)\r\n");
    timer_kind = PerfTimer_Select(&gt_ctl_before, &gt_ctl_after,
                                 &gt_before, &gt_after, &pmu_before, &pmu_after);
    xil_printf("[DIAG] GT ctrl before=%08x after=%08x\r\n",
               (unsigned)gt_ctl_before, (unsigned)gt_ctl_after);
    xil_printf("[DIAG] GT counter before=%08x:%08x after=%08x:%08x\r\n",
               (unsigned)(gt_before >> 32), (unsigned)gt_before,
               (unsigned)(gt_after >> 32), (unsigned)gt_after);
    xil_printf("[DIAG] PMU CCNT before=%08x after=%08x\r\n",
               (unsigned)pmu_before, (unsigned)pmu_after);
    if (timer_kind == PERF_SOURCE_GLOBAL)
        xil_printf("[INFO] timer_source=GLOBAL_TIMER (64-bit, CPU/2)\r\n");
    else if (timer_kind == PERF_SOURCE_PMU)
        xil_printf("[INFO] timer_source=PMU_CCNT_FALLBACK (CPU cycles)\r\n");
    else
        return fail("neither Global Timer nor PMU cycle counter advances");
#if PERF_HAVE_TIMER_FREQ
    xil_printf("[INFO] PS_CPU_HZ=%u timer_ticks_per_second=%u\r\n",
               (unsigned)PERF_CPU_CLOCK_HZ, (unsigned)PERF_TICKS_PER_SEC);
#else
    xil_printf("[INFO] timer frequency=NOT_CALIBRATED (CPU Hz required for MB/s)\r\n");
#endif

    cfg=XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (!cfg || XAxiDma_CfgInitialize(&Dma,cfg)!=XST_SUCCESS || XAxiDma_HasSg(&Dma))
        return fail("DMA init failed or Scatter-Gather mode enabled");
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    if (configure_time()!=XST_SUCCESS || configure_engine()!=XST_SUCCESS)
        return XST_FAILURE;

    cwr(C_CONTROL,1U);
    usleep(10000U);  
    if (!(crd(C_STATUS)&(1U<<3))) return fail("TX not enabled");

    for (round=0U;round<WARMUP_ROUNDS;++round) {
        prepare_data(0x1000U+round);
        if (transfer_one_packet(&tx_elapsed)!=XST_SUCCESS ||
            check_packet(0x1000U+round)!=XST_SUCCESS)
            return XST_FAILURE;
    }
    xil_printf("[PASS] warmup %u packets\r\n",(unsigned)WARMUP_ROUNDS);

    begin = PerfTimer_ReadTicks();
    for (round=0U;round<PERF_ROUNDS;++round) {
        prepare_data(round);
        if (transfer_one_packet(&tx_elapsed)!=XST_SUCCESS ||
            check_packet(round)!=XST_SUCCESS) return XST_FAILURE;
        transaction_ticks+=(u64)tx_elapsed;
        ++done;
        correct+=N_SAMPLES;
    }
    finish = PerfTimer_ReadTicks();
    if (finish<=begin) return fail("selected hardware timer did not advance");
    wall_ticks=(u64)(finish-begin);

    xil_printf("[RESULT] dma_rounds=%u verified_iq_samples=%u iq_mismatches=0\r\n",
               (unsigned)done,(unsigned)correct);
    xil_printf("[NOTE] protocol_error_events=NOT_MEASURED\r\n");
    xil_printf("[RESULT] total_wall_ticks_hi=%u lo=%u\r\n",
               (unsigned)(wall_ticks>>32),(unsigned)wall_ticks);
    xil_printf("[RESULT] summed_dma_ticks_hi=%u lo=%u\r\n",
               (unsigned)(transaction_ticks>>32),(unsigned)transaction_ticks);
    xil_printf("[RESULT] iq_payload_bytes=%u\r\n", (unsigned)measured_bytes);
#if PERF_HAVE_TIMER_FREQ
    print_fixed3("[RESULT] board_system_throughput_MBps=",
                 mbps_x1000(measured_bytes,wall_ticks));
    print_fixed3("[RESULT] dma_transaction_window_throughput_MBps=",
                 mbps_x1000(measured_bytes,transaction_ticks));
    xil_printf("[RESULT] window_duration_us=%u\r\n",
               (unsigned)((wall_ticks*1000000ULL)/PERF_TICKS_PER_SEC));
    xil_printf("[RESULT] summed_dma_duration_us=%u\r\n",
               (unsigned)((transaction_ticks*1000000ULL)/PERF_TICKS_PER_SEC));
#else
    xil_printf("[RESULT] board_system_throughput_MBps=NOT_CALIBRATED\r\n");
    xil_printf("[RESULT] dma_transaction_window_throughput_MBps=NOT_CALIBRATED\r\n");
    xil_printf("[RESULT] window_duration_us=NOT_CALIBRATED\r\n");
    xil_printf("[RESULT] summed_dma_duration_us=NOT_CALIBRATED\r\n");
    xil_printf("[NOTE] Supply actual PS CPU Hz from Vivado to convert raw GT/PMU ticks offline.\r\n");
#endif
    xil_printf("[NOTE] Host-driven throughput includes Simple DMA rearm / PS / DDR.\r\n");
    xil_printf("[NOTE] NOT PL-only latency or throughput; DMA windows include PS polling.\r\n");
    xil_printf("[PASS] difi_ip_perf_test: 100 packets x 256 IQ verified\r\n");
    return XST_SUCCESS;
}
