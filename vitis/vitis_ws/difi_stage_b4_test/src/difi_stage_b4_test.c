/* Stage B4: set UTC over UART and check periodic packets. */
#include <stddef.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xgpio.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"
#include "difi_board_addresses.h"
#include "difi_time_regmap.h"

extern char inbyte(void);

#if defined(SDT)
#define DMA_IDENTIFIER   XPAR_XAXIDMA_0_BASEADDR
#define GPIO_IDENTIFIER  XPAR_XGPIO_0_BASEADDR
#else
#define DMA_IDENTIFIER   XPAR_AXIDMA_0_DEVICE_ID
#define GPIO_IDENTIFIER  XPAR_GPIO_0_DEVICE_ID
#endif

#define R_CONTROL       0x00U
#define R_COMMAND       0x04U
#define R_STATUS        0x08U
#define R_COMMIT_ERROR  0x0CU
#define R_DATA_SID      0x10U
#define R_VER_SID       0x14U
#define R_SAMPLES       0x18U
#define R_FS            0x1CU
#define R_BW            0x20U
#define R_RF_LO         0x24U
#define R_RF_HI         0x28U
#define R_CTX_PERIOD    0x2CU
#define R_VER_PERIOD    0x30U
#define R_RX_FILTER     0x34U
#define R_RX_DATA_SID   0x38U
#define R_RX_VER_SID    0x3CU
#define R_ACT_DATA_SID  0x40U
#define R_ACT_VER_SID   0x44U
#define R_ACT_SAMPLES   0x48U
#define R_ACT_FS        0x4CU
#define R_ACT_BW        0x50U
#define R_ACT_RF_LO     0x54U
#define R_ACT_RF_HI     0x58U
#define R_ACT_CTX_PERIOD 0x5CU
#define R_ACT_VER_PERIOD 0x60U

#define SAMPLES         256U
#define DATA_SID        0x10203040U
#define VERSION_SID     0x55667788U
#define SAMPLE_RATE_HZ  2000000U
#define BANDWIDTH_HZ    1500000U
#define RF_FREQ_HZ      915000000U
#define CTX_PERIOD_MS   2000U
#define VER_PERIOD_MS   3000U
#define TIMEOUT_MS      10000U
#define DMA_SPIN_LIMIT  100000000U

#define PG_MAGIC       0U
#define PG_DATA_CNT    1U
#define PG_CTX_CNT     2U
#define PG_VER_CNT     3U
#define PG_E_DISP      4U
#define PG_E_DATA      5U
#define PG_E_CTX       6U
#define PG_E_VER       7U
#define PG_LAST_ERR    8U
#define PG_DATA_SID    9U
#define PG_DATA_SZQ   10U
#define PG_DATA_SEC   11U
#define PG_DATA_PSH   12U
#define PG_DATA_PSL   13U
#define PG_CTX_SID    14U
#define PG_CTX_SQC    15U
#define PG_CTX_BW     16U
#define PG_CTX_RFHI   17U
#define PG_CTX_RFLO   18U
#define PG_CTX_FS     19U
#define PG_CTX_SEC    20U
#define PG_CTX_PSH    21U
#define PG_CTX_PSL    22U
#define PG_VER_SID    23U
#define PG_VER_SQC    24U
#define PG_VER_INFO   25U
#define PG_VER_SEC    26U
#define PG_VER_PSH    27U
#define PG_VER_PSL    28U
#define PG_TX_PKTS    29U
#define PG_TX_BEATS   30U

static XAxiDma Dma;
static XGpio Gpio;
static u32 TxIQ[SAMPLES] __attribute__((aligned(64)));
static u32 RxIQ[SAMPLES] __attribute__((aligned(64)));

static void ctrl_wr(u32 off, u32 val) { Xil_Out32((UINTPTR)DIFI_CTRL_BASE + off, val); }
static u32 ctrl_rd(u32 off) { return Xil_In32((UINTPTR)DIFI_CTRL_BASE + off); }
static void time_wr(u32 off, u32 val) { Xil_Out32((UINTPTR)DIFI_TIME_BASE + off, val); }
static u32 time_rd(u32 off) { return Xil_In32((UINTPTR)DIFI_TIME_BASE + off); }
static u32 mon(u32 p) {
    XGpio_DiscreteWrite(&Gpio, 1U, p & 31U);
    (void)XGpio_DiscreteRead(&Gpio, 1U); // Wait for the selected read page to take effect.
    return XGpio_DiscreteRead(&Gpio, 2U);
}
static int fail(const char *why) {
    xil_printf("[FAIL] %s\r\n", why);
    return XST_FAILURE;
}
static int check_u32(const char *what, u32 got, u32 want) {
    if (got == want) return XST_SUCCESS;
    xil_printf("[FAIL] %s: got=0x%08x expected=0x%08x\r\n",
               what, (unsigned)got, (unsigned)want);
    return XST_FAILURE;
}
static int await_count(u32 pg, u32 minimum, u32 timeout_ms) {
    u32 t;
    for (t = 0; t < timeout_ms; ++t) {
        if (mon(pg) >= minimum) return XST_SUCCESS;
        usleep(1000);
    }
    xil_printf("[FAIL] page %u count %u < %u\r\n", (unsigned)pg,
               (unsigned)mon(pg), (unsigned)minimum);
    return XST_FAILURE;
}
static int no_errors(void) {
    if (mon(PG_E_DISP) || mon(PG_E_DATA) ||
        mon(PG_E_CTX) || mon(PG_E_VER)) {
        xil_printf("[FAIL] RX errors = %u/%u/%u/%u, last=0x%08x\r\n",
            (unsigned)mon(PG_E_DISP), (unsigned)mon(PG_E_DATA),
            (unsigned)mon(PG_E_CTX), (unsigned)mon(PG_E_VER),
            (unsigned)mon(PG_LAST_ERR));
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

/* UART format: UTC <seconds> <nanoseconds within the second>. Wait for input with blocking reads. */
static int parse_decimal(const char **p, u32 *out) {
    u64 v = 0ULL;
    int found = 0;
    while (**p == ' ' || **p == '\t') ++(*p);
    while (**p >= '0' && **p <= '9') {
        found = 1;
        v = v * 10ULL + (u32)(**p - '0');
        if (v > 0xFFFFFFFFULL) return XST_FAILURE;
        ++(*p);
    }
    if (!found) return XST_FAILURE;
    *out = (u32)v;
    return XST_SUCCESS;
}
static int parse_utc(const char *line, u32 *sec, u32 *ns) {
    const char *p = line;
    if (p[0]!='U'||p[1]!='T'||p[2]!='C'||p[3]!=' ') return XST_FAILURE;
    p += 4;
    if (parse_decimal(&p,sec) != XST_SUCCESS) return XST_FAILURE;
    if (parse_decimal(&p,ns) != XST_SUCCESS) return XST_FAILURE;
    while (*p == ' ' || *p == '\t') ++p;
    if (*p != '\0' || *ns >= 1000000000U) return XST_FAILURE;
    return XST_SUCCESS;
}

static void uart_getline(char *buf, unsigned cap) {
    unsigned n = 0U;
    static int skip_lf_after_cr = 0;
    char c;

    if (cap == 0U) return;

    for (;;) {
        c = inbyte();

        if (skip_lf_after_cr) {
            skip_lf_after_cr = 0;
            if (c == '\n') continue;
        }

        if (c == '\r' || c == '\n') {
            buf[n] = '\0';
            xil_printf("\r\n");
            if (c == '\r') skip_lf_after_cr = 1;
            return;
        }

        if (c == '\b' || c == 127) {
            if (n > 0U) {
                --n;
                xil_printf("\b \b");
            }
            continue;
        }

        if ((unsigned char)c < 32U && c != '\t') continue;

        if (n + 1U < cap) {
            buf[n++] = c;
            xil_printf("%c", (int)c);
        }
    }
}
static int configure_utc_from_uart(u32 *base_sec) {
    char line[80];
    u32 sec=0U,ns=0U, status;
    u64 ps;
    if (time_rd(DIFI_TIME_STATUS_OFFSET) & DIFI_TIME_STATUS_VALID)
        return fail("unexpected TIME_VALID before initialization; reprogram PL");
    if (ctrl_rd(R_STATUS) & (1U<<4))
        return fail("unexpected CTRL TIME_VALID before initialization");
    xil_printf("[PASS] reset: TIME_VALID=0 on both AXI slaves\r\n");
    for (;;) {
        xil_printf("[WAIT_UTC] Send: UTC <UNIX_SEC> <NANOSECOND_0_TO_999999999>\r\n");
        uart_getline(line, sizeof(line));
        if (parse_utc(line,&sec,&ns) == XST_SUCCESS) break;
        xil_printf("[WARN] Invalid UTC line; retry\r\n");
    }
    ps = (u64)ns * 1000ULL;
    
    time_wr(DIFI_TIME_SEC_OFFSET, sec);
    time_wr(DIFI_TIME_PS_LO_OFFSET, (u32)ps);
    time_wr(DIFI_TIME_PS_HI_OFFSET, (u32)(ps >> 32));
    if (check_u32("TIME_SEC shadow",time_rd(DIFI_TIME_SEC_OFFSET),sec) ||
        check_u32("TIME_PS_LO shadow",time_rd(DIFI_TIME_PS_LO_OFFSET),(u32)ps) ||
        check_u32("TIME_PS_HI shadow",time_rd(DIFI_TIME_PS_HI_OFFSET),(u32)(ps>>32)))
        return XST_FAILURE;
    time_wr(DIFI_TIME_CMD_OFFSET, DIFI_TIME_CMD_LOAD);
    
    {
        u32 k;
        for (k=0U;k<50000U;++k) {
            status=time_rd(DIFI_TIME_STATUS_OFFSET);
            if (status & DIFI_TIME_STATUS_ERROR)
                return fail("TIME_STATUS rejected valid UTC");
            if (status & DIFI_TIME_STATUS_VALID) break;
        }
        if (k == 50000U) return fail("time_load not observed");
    }
    if (!(ctrl_rd(R_STATUS) & (1U<<4)))
        return fail("Time Source valid not propagated to Engine STATUS[4]");
    *base_sec=sec;
    xil_printf("[PASS] PS UART UTC -> AXI4-Lite -> Time Source, sec=%u ns=%u\r\n",
               (unsigned)sec,(unsigned)ns);
    return XST_SUCCESS;
}

static int configure_protocol(void) {
    u32 i, st;
    ctrl_wr(R_CONTROL,0U);
    ctrl_wr(R_DATA_SID,DATA_SID);
    ctrl_wr(R_VER_SID,VERSION_SID);
    ctrl_wr(R_SAMPLES,SAMPLES);
    ctrl_wr(R_FS,SAMPLE_RATE_HZ);
    ctrl_wr(R_BW,BANDWIDTH_HZ);
    ctrl_wr(R_RF_LO,RF_FREQ_HZ);
    ctrl_wr(R_RF_HI,0U);
    ctrl_wr(R_CTX_PERIOD,CTX_PERIOD_MS);
    ctrl_wr(R_VER_PERIOD,VER_PERIOD_MS);
    ctrl_wr(R_RX_DATA_SID,DATA_SID);
    ctrl_wr(R_RX_VER_SID,VERSION_SID);
    ctrl_wr(R_RX_FILTER,3U);
    ctrl_wr(R_COMMAND,1U);
    for (i=0;i<100000U;++i)
        if (!(ctrl_rd(R_STATUS)&1U)) break;
    st=ctrl_rd(R_STATUS);
    if (i==100000U || (st & (1U|32U)) || ctrl_rd(R_COMMIT_ERROR))
        return fail("cfg_regs commit timeout/invalid");
    if (check_u32("active SID",ctrl_rd(R_ACT_DATA_SID),DATA_SID) ||
        check_u32("active Version SID",ctrl_rd(R_ACT_VER_SID),VERSION_SID) ||
        check_u32("active N",ctrl_rd(R_ACT_SAMPLES),SAMPLES) ||
        check_u32("active Fs",ctrl_rd(R_ACT_FS),SAMPLE_RATE_HZ) ||
        check_u32("active BW",ctrl_rd(R_ACT_BW),BANDWIDTH_HZ) ||
        check_u32("active RF LO",ctrl_rd(R_ACT_RF_LO),RF_FREQ_HZ) ||
        check_u32("active RF HI",ctrl_rd(R_ACT_RF_HI),0U) ||
        check_u32("active Context period",ctrl_rd(R_ACT_CTX_PERIOD),CTX_PERIOD_MS) ||
        check_u32("active Version period",ctrl_rd(R_ACT_VER_PERIOD),VER_PERIOD_MS))
        return XST_FAILURE;
    xil_printf("[PASS] Config Shadow -> Commit -> Active; periods=%u/%u ms\r\n",
        (unsigned)CTX_PERIOD_MS,(unsigned)VER_PERIOD_MS);
    return XST_SUCCESS;
}

static u32 dma_status(int direction) {
    UINTPTR offset=(direction==XAXIDMA_DEVICE_TO_DMA)?
            (UINTPTR)XAXIDMA_RX_OFFSET:(UINTPTR)XAXIDMA_TX_OFFSET;
    return XAxiDma_ReadReg(Dma.RegBase+offset,XAXIDMA_SR_OFFSET);
}
static int dma_wait(int direction, const char *label) {
    u32 i;
    for (i=0U;i<DMA_SPIN_LIMIT;++i) {
        u32 status=dma_status(direction);
        if (status & XAXIDMA_ERR_ALL_MASK) {
            xil_printf("[FAIL] DMA %s error SR=0x%08x\r\n",label,(unsigned)status);
            return XST_FAILURE;
        }
        if (!XAxiDma_Busy(&Dma,direction)) return XST_SUCCESS;
    }
    xil_printf("[FAIL] DMA %s timeout SR=0x%08x\r\n",label,(unsigned)dma_status(direction));
    return XST_FAILURE;
}
static void init_iq(u32 round) {
    u32 i;
    for (i=0U;i<SAMPLES;++i) {
        u32 in=(0x1000U+i+0x0200U*round)&0xFFFFU;
        u32 qn=(0xA000U+3U*i+0x0011U*round)&0xFFFFU;
        TxIQ[i]=(in<<16)|qn;
        RxIQ[i]=0xDEADBEEFU;
    }
    Xil_DCacheFlushRange((INTPTR)TxIQ,(u32)sizeof(TxIQ));
    Xil_DCacheFlushRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
    Xil_DCacheInvalidateRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
}
static int loopback_round(u32 round, u32 base_sec) {
    u32 i;
    init_iq(round);
    if (XAxiDma_SimpleTransfer(&Dma,(UINTPTR)RxIQ,sizeof(RxIQ),XAXIDMA_DEVICE_TO_DMA)!=XST_SUCCESS)
        return fail("arm S2MM");
    if (XAxiDma_SimpleTransfer(&Dma,(UINTPTR)TxIQ,sizeof(TxIQ),XAXIDMA_DMA_TO_DEVICE)!=XST_SUCCESS)
        return fail("start MM2S");
    if (dma_wait(XAXIDMA_DMA_TO_DEVICE,"MM2S") ||
        dma_wait(XAXIDMA_DEVICE_TO_DMA,"S2MM") ||
        await_count(PG_DATA_CNT,round+1U,TIMEOUT_MS))
        return XST_FAILURE;
    Xil_DCacheInvalidateRange((INTPTR)RxIQ,(u32)sizeof(RxIQ));
    for (i=0U;i<SAMPLES;++i)
        if (RxIQ[i] != TxIQ[i]) {
            xil_printf("[FAIL] IQ[%u] sent=%08x received=%08x\r\n",
                (unsigned)i,(unsigned)TxIQ[i],(unsigned)RxIQ[i]);
            return XST_FAILURE;
        }
    if (check_u32("RX Data SID",mon(PG_DATA_SID),DATA_SID) ||
        check_u32("Data count/seq",mon(PG_DATA_SZQ),(SAMPLES<<4)|(round&15U)))
        return XST_FAILURE;
    if (mon(PG_DATA_SEC) < base_sec)
        return fail("Data timestamp less than UTC initialized seconds");
    if (no_errors()) return XST_FAILURE;
    xil_printf("[PASS] Data round %u: 256/256 IQ; sec=%u ps_hi=%08x ps_lo=%08x\r\n",
        (unsigned)round,(unsigned)mon(PG_DATA_SEC),
        (unsigned)mon(PG_DATA_PSH),(unsigned)mon(PG_DATA_PSL));
    return XST_SUCCESS;
}
static int timestamp_after(u32 new_sec,u32 new_hi,u32 new_lo,
                           u32 old_sec,u32 old_hi,u32 old_lo) {
    if(new_sec != old_sec) return new_sec > old_sec;
    if(new_hi != old_hi) return new_hi > old_hi;
    return new_lo > old_lo;
}
static void report_status(void) {
    xil_printf("[MON] DATA=%u CTX=%u VER=%u TX_PKTS=%u BEATS=%u\r\n",
        (unsigned)mon(PG_DATA_CNT),(unsigned)mon(PG_CTX_CNT),
        (unsigned)mon(PG_VER_CNT),(unsigned)mon(PG_TX_PKTS),
        (unsigned)mon(PG_TX_BEATS));
    xil_printf("[MON] ERR dispatch/data/ctx/ver=%u/%u/%u/%u; last=%08x\r\n",
        (unsigned)mon(PG_E_DISP),(unsigned)mon(PG_E_DATA),
        (unsigned)mon(PG_E_CTX),(unsigned)mon(PG_E_VER),(unsigned)mon(PG_LAST_ERR));
    xil_printf("[MON] AXI CTRL status=%08x TIME status=%08x\r\n",
        (unsigned)ctrl_rd(R_STATUS),(unsigned)time_rd(DIFI_TIME_STATUS_OFFSET));
}

int main(void) {
    XAxiDma_Config *dma_cfg;
    u32 utc_sec=0U,ctx0_sec,ctx0_hi,ctx0_lo,ver0_sec,ver0_hi,ver0_lo;
    u32 i;
    xil_printf("\r\n======================================\r\n");
    xil_printf(" DIFI FULL INTEGRATED BOARD TEST\r\n");
    xil_printf("======================================\r\n");
    xil_printf("[INFO] CTRL_BASE=%08x TIME_BASE=%08x\r\n",
        (unsigned)DIFI_CTRL_BASE,(unsigned)DIFI_TIME_BASE);
    dma_cfg=XAxiDma_LookupConfig(DMA_IDENTIFIER);
    if (!dma_cfg || XAxiDma_CfgInitialize(&Dma,dma_cfg)!=XST_SUCCESS || XAxiDma_HasSg(&Dma))
        return fail("DMA init failed / SG enabled (requires Simple mode)");
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&Dma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    if (XGpio_Initialize(&Gpio,GPIO_IDENTIFIER)!=XST_SUCCESS)
        return fail("AXI GPIO initialization failed");
    XGpio_SetDataDirection(&Gpio,1U,0U);          
    XGpio_SetDataDirection(&Gpio,2U,0xFFFFFFFFU); 
    ctrl_wr(R_CONTROL,0U);
    if (check_u32("board ID",mon(PG_MAGIC),0xD1F10001U) ||
        check_u32("board tail ID",mon(31U),0xD1F1F01FU))
        return fail("wrong bitstream, GPIO wiring, or AXI GPIO base");
    for(i=1U;i<=7U;++i)
        if(mon(i)!=0U) return fail("PL counters not reset: reprogram bitstream");
    if(mon(PG_TX_PKTS)!=0U || mon(PG_TX_BEATS)!=0U)
        return fail("TX monitor counters not reset");
    xil_printf("[PASS] board ID and all monitor reset counters\r\n");

    // The PC supplies real UTC over UART.
    if (configure_utc_from_uart(&utc_sec)) return XST_FAILURE;
    if (configure_protocol()) return XST_FAILURE;
    ctrl_wr(R_CONTROL,1U);
    if (await_count(PG_VER_CNT,1U,TIMEOUT_MS) ||
        await_count(PG_CTX_CNT,1U,TIMEOUT_MS)) return XST_FAILURE;
    if (check_u32("startup Version SID",mon(PG_VER_SID),VERSION_SID) ||
        check_u32("startup Context SID",mon(PG_CTX_SID),DATA_SID) ||
        check_u32("startup Version changed",mon(PG_VER_SQC),0x10U) ||
        check_u32("startup Context changed",mon(PG_CTX_SQC),0x10U) ||
        check_u32("startup Context BW",mon(PG_CTX_BW),BANDWIDTH_HZ) ||
        check_u32("startup Context Fs",mon(PG_CTX_FS),SAMPLE_RATE_HZ) ||
        check_u32("startup Context RF Lo",mon(PG_CTX_RFLO),RF_FREQ_HZ) ||
        check_u32("startup Context RF Hi",mon(PG_CTX_RFHI),0U))
        return XST_FAILURE;
    ctx0_sec=mon(PG_CTX_SEC); ctx0_hi=mon(PG_CTX_PSH);ctx0_lo=mon(PG_CTX_PSL);
    ver0_sec=mon(PG_VER_SEC); ver0_hi=mon(PG_VER_PSH);ver0_lo=mon(PG_VER_PSL);
    if(ctx0_sec<utc_sec || ver0_sec<utc_sec)
        return fail("startup timestamp predates PS UTC load");
    if(no_errors()) return XST_FAILURE;
    xil_printf("[PASS] startup Version -> changed Context; timestamps live\r\n");

    if (loopback_round(0U,utc_sec) || loopback_round(1U,utc_sec))
        return XST_FAILURE;

    // Receive at least 2 packets of each type to confirm periodic packets follow startup.
    
    xil_printf("[WAIT] Observe periodic Context=%ums Version=%ums ...\r\n",
       (unsigned)CTX_PERIOD_MS,(unsigned)VER_PERIOD_MS);
    if (await_count(PG_CTX_CNT,2U,TIMEOUT_MS) ||
        await_count(PG_VER_CNT,2U,TIMEOUT_MS)) return XST_FAILURE;
    if (mon(PG_CTX_SQC) & 0x10U) return fail("periodic Context changed bit not zero");
    if (mon(PG_VER_SQC) & 0x10U) return fail("periodic Version changed bit not zero");
    if (!timestamp_after(mon(PG_CTX_SEC),mon(PG_CTX_PSH),mon(PG_CTX_PSL),
                         ctx0_sec,ctx0_hi,ctx0_lo))
        return fail("periodic Context timestamp not increasing");
    if (!timestamp_after(mon(PG_VER_SEC),mon(PG_VER_PSH),mon(PG_VER_PSL),
                         ver0_sec,ver0_hi,ver0_lo))
        return fail("periodic Version timestamp not increasing");
    if (mon(PG_TX_PKTS) < mon(PG_DATA_CNT)+mon(PG_CTX_CNT)+mon(PG_VER_CNT))
        return fail("TX packet accounting lower than RX packet counts");
    if (no_errors()) return XST_FAILURE;
    xil_printf("[PASS] periodic Context/Version: seq advances, changed=0, time increases\r\n");
    report_status();
    xil_printf("\r\n[ALL INTEGRATED BOARD TESTS PASSED]\r\n");
    xil_printf("[NOTE] UTC is PC-supplied; no PPS/PTP/NTP precision claim.\r\n");
    return XST_SUCCESS;
}
