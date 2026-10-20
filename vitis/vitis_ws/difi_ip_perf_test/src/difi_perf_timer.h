/*
 * Zynq-7000 Cortex-A9 baremetal diagnostic/fallback timer, v5.
 * GT: 64-bit SCU global timer at 0xF8F00200, CPU/2 if prescaler=0.
 * PMU: 32-bit per-core cycle counter via CP15 c9, CPU cycles if D=0.
 * No dependency on xtime_l.h or XPAR_CPU_* clock macros.
 * Read GLOBAL TIMER only when it passes the monotonicity test.
 * PMU is a fallback if it passes its own monotonicity test.
 * Use only on Cortex-A9 privileged baremetal, not Linux userspace.
 */
#ifndef DIFI_PERF_TIMER_H
#define DIFI_PERF_TIMER_H
#include "xparameters.h"
#include "xil_types.h"
#include "xil_io.h"
#include "sleep.h"

#if defined(PERF_CPU_CLOCK_HZ)
# if (PERF_CPU_CLOCK_HZ < 1000000U)
#  error "PERF_CPU_CLOCK_HZ must match actual PS CPU frequency, not PL FCLK"
# endif
# define PERF_HAVE_TIMER_FREQ 1
#else
# define PERF_HAVE_TIMER_FREQ 0
#endif

#define PERF_GLOBAL_TIMER_BASE 0xF8F00200U
#define PERF_GTC_LO_OFFSET 0x00U
#define PERF_GTC_HI_OFFSET 0x04U
#define PERF_GTC_CTRL_OFFSET 0x08U
#define PERF_SOURCE_NONE 0U
#define PERF_SOURCE_GLOBAL 1U
#define PERF_SOURCE_PMU 2U

static u32 perf_timer_source = PERF_SOURCE_NONE;
static u32 perf_pmu_prev;
static u64 perf_pmu_accum;

static inline u64 PerfTimer_ReadGlobal(void)
{
    u32 high0, low, high1;
    do {
        high0 = Xil_In32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_HI_OFFSET);
        low = Xil_In32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_LO_OFFSET);
        high1 = Xil_In32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_HI_OFFSET);
    } while (high0 != high1);
    return ((u64)high0 << 32) | (u64)low;
}

static inline u32 PerfTimer_ReadPMU32(void)
{
    u32 v;
    __asm__ __volatile__("mrc p15, 0, %0, c9, c13, 0" : "=r" (v));
    return v;
}

static inline void PerfTimer_EnablePMU(void)
{
    u32 pmcr;
    u32 enable = 0x80000000U;
    __asm__ __volatile__("mrc p15, 0, %0, c9, c12, 0" : "=r" (pmcr));
    /* E=1, D=0 (no divide-by-64), C=1 (reset cycle counter). */
    pmcr = (pmcr | 0x00000005U) & ~0x00000008U;
    __asm__ __volatile__("mcr p15, 0, %0, c9, c12, 0" :: "r" (pmcr) : "memory");
    __asm__ __volatile__("mcr p15, 0, %0, c9, c12, 1" :: "r" (enable) : "memory");
    __asm__ __volatile__("isb" ::: "memory");
}

/* Non-destructive GT enable; don't reset counters used by other software. */
static inline void PerfTimer_EnableGlobal(void)
{
    u32 ctrl = Xil_In32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_CTRL_OFFSET);
    if (!(ctrl & 1U))
        Xil_Out32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_CTRL_OFFSET, ctrl | 1U);
}

/*
 * Select the actual counting timer; caller prints diagnostic output.
 * Input args report raw GT control and counter values before/after delay.
 * PMU must run on same physical CPU core throughout the benchmark.
 */
static inline u32 PerfTimer_Select(
    u32 *ctrl_before, u32 *ctrl_after, u64 *gt_before, u64 *gt_after,
    u32 *pmu_before, u32 *pmu_after)
{
    *ctrl_before = Xil_In32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_CTRL_OFFSET);
    *gt_before = PerfTimer_ReadGlobal();
    PerfTimer_EnableGlobal();
    *ctrl_after = Xil_In32(PERF_GLOBAL_TIMER_BASE + PERF_GTC_CTRL_OFFSET);
    PerfTimer_EnablePMU();
    *pmu_before = PerfTimer_ReadPMU32();
    usleep(1000U);
    *gt_after = PerfTimer_ReadGlobal();
    *pmu_after = PerfTimer_ReadPMU32();

    /* GT prescaler==0 required for CPU/2 frequency scaling. */
    if ((*ctrl_after & 1U) &&
        ((*ctrl_after & 0x0000FF00U) == 0U) &&
        (*gt_after > *gt_before)) {
        perf_timer_source = PERF_SOURCE_GLOBAL;
    } else if ((u32)(*pmu_after - *pmu_before) != 0U) {
        perf_timer_source = PERF_SOURCE_PMU;
        perf_pmu_prev = *pmu_after;
        perf_pmu_accum = 0ULL;
    } else {
        perf_timer_source = PERF_SOURCE_NONE;
    }
    return perf_timer_source;
}

static inline u64 PerfTimer_ReadTicks(void)
{
    if (perf_timer_source == PERF_SOURCE_GLOBAL)
        return PerfTimer_ReadGlobal();
    if (perf_timer_source == PERF_SOURCE_PMU) {
        u32 now = PerfTimer_ReadPMU32();
        /* modulo-2^32 delta permits one wrap between consecutive reads. */
        perf_pmu_accum += (u32)(now - perf_pmu_prev);
        perf_pmu_prev = now;
        return perf_pmu_accum;
    }
    return 0ULL;
}

#if PERF_HAVE_TIMER_FREQ
/* GT counts at CPU/2, PMU counts at CPU/1. */
#define PERF_TICKS_PER_SEC ((u64)(PERF_CPU_CLOCK_HZ) / \
    ((perf_timer_source == PERF_SOURCE_GLOBAL) ? 2ULL : 1ULL))
#endif

#endif /* DIFI_PERF_TIMER_H */
