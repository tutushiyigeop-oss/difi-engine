/* UDP echo test for Zynq GEM0. */

#include "xparameters.h"
#include "xparameters_ps.h"
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

#if !NO_SYS
#error "This demo requires standalone lwIP220 RAW_API / NO_SYS=1."
#endif

#ifndef XPAR_XEMACPS_0_BASEADDR
#error "PS GEM0 is missing from xparameters.h. Enable ENET0 and re-export the XSA."
#endif

#define BOARD_IP_A      192
#define BOARD_IP_B      168
#define BOARD_IP_C      1
#define BOARD_IP_D      10
#define UDP_ECHO_PORT   4991U
#define MAX_ECHO_BYTES  1400U

#define PS_CPU_CLOCK_HZ   666666667U
#define TIMER_TICKS_PER_SEC 20U

static struct netif board_netif;
static struct udp_pcb *udp_server;
static XScuTimer scu_timer;
static volatile unsigned int ticks_50ms = 0;
static unsigned int packet_count = 0;

static void timer_irq(void *context)
{
    XScuTimer *timer = (XScuTimer *)context;
    XScuTimer_ClearInterruptStatus(timer);
    ++ticks_50ms;
}

static int init_interrupts_and_timer(void)
{
    XScuTimer_Config *timer_cfg;
    int status;

    timer_cfg = XScuTimer_LookupConfig(XPAR_SCUTIMER_BASEADDR);
    if (timer_cfg == NULL) {
        xil_printf("ERROR: SCU timer config missing\r\n");
        return XST_FAILURE;
    }

    status = XScuTimer_CfgInitialize(&scu_timer, timer_cfg,
                                     timer_cfg->BaseAddr);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: SCU timer init = %d\r\n", status);
        return XST_FAILURE;
    }

    XScuTimer_EnableAutoReload(&scu_timer);
    /* The private timer runs at half the CPU clock. */
    XScuTimer_LoadTimer(&scu_timer,
                        PS_CPU_CLOCK_HZ / (2U * TIMER_TICKS_PER_SEC));
    XScuTimer_ClearInterruptStatus(&scu_timer);

    xil_printf("SCU timer initialized\r\n");

    Xil_ExceptionInit();
    status = XScuGic_DeviceInitialize(XPAR_SCUGIC_DIST_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: GIC init = %d\r\n", status);
        return XST_FAILURE;
    }

    Xil_ExceptionRegisterHandler(
        XIL_EXCEPTION_ID_IRQ_INT,
        (Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
        (void *)XPAR_SCUGIC_CPU_BASEADDR);

    XScuGic_RegisterHandler(XPAR_SCUGIC_CPU_BASEADDR,
                            XPAR_SCUTIMER_INTR,
                            (Xil_ExceptionHandler)timer_irq,
                            (void *)&scu_timer);
    XScuGic_EnableIntr(XPAR_SCUGIC_DIST_BASEADDR,
                       XPAR_SCUTIMER_INTR);
    xil_printf("GIC initialized\r\n");
    return XST_SUCCESS;
}

static void udp_receive(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                        const ip_addr_t *remote_addr, u16_t remote_port)
{
    struct pbuf *reply;
    err_t status;
    (void)arg;

    if (p == NULL) {
        return;
    }

    ++packet_count;
    xil_printf("RX #%u: %u bytes, source port %u\r\n",
               packet_count, (unsigned int)p->tot_len,
               (unsigned int)remote_port);

    if ((p->tot_len == 0U) || (p->tot_len > MAX_ECHO_BYTES)) {
        xil_printf("DROP: unsupported payload length\r\n");
        pbuf_free(p);
        return;
    }

    reply = pbuf_alloc(PBUF_TRANSPORT, p->tot_len, PBUF_RAM);
    if (reply == NULL) {
        xil_printf("ERROR: cannot allocate TX pbuf\r\n");
        pbuf_free(p);
        return;
    }

    status = pbuf_copy(reply, p);
    if (status == ERR_OK) {
        status = udp_sendto(pcb, reply, remote_addr, remote_port);
    }

    if (status == ERR_OK) {
        xil_printf("TX echo: %u bytes\r\n", (unsigned int)reply->tot_len);
    } else {
        xil_printf("ERROR: UDP echo failed, err=%d\r\n", (int)status);
    }

    pbuf_free(reply);
    pbuf_free(p);
}

static int start_udp_server(void)
{
    err_t status;

    udp_server = udp_new();
    if (udp_server == NULL) {
        xil_printf("ERROR: udp_new failed\r\n");
        return XST_FAILURE;
    }

    status = udp_bind(udp_server, IP_ADDR_ANY, UDP_ECHO_PORT);
    if (status != ERR_OK) {
        xil_printf("ERROR: udp_bind failed, err=%d\r\n", (int)status);
        udp_remove(udp_server);
        udp_server = NULL;
        return XST_FAILURE;
    }

    udp_recv(udp_server, udp_receive, NULL);
    xil_printf("UDP Echo ready on port %u\r\n", UDP_ECHO_PORT);
    return XST_SUCCESS;
}

int main(void)
{
    ip_addr_t ip_addr, netmask, gateway;
    unsigned int last_fast, last_slow, last_arp;
    unsigned int now;
    unsigned char mac_addr[6] = {0x02, 0x0A, 0x35, 0x00, 0x01, 0x02};

    xil_printf("\r\n=== Zynq-7000 standalone UDP Echo ===\r\n");

    /* Initialize GIC before setting up network interrupts. */
    if (init_interrupts_and_timer() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    IP4_ADDR(&ip_addr, BOARD_IP_A, BOARD_IP_B, BOARD_IP_C, BOARD_IP_D);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gateway, 192, 168, 1, 1);

    lwip_init();
    if (!xemac_add(&board_netif, &ip_addr, &netmask, &gateway,
                   mac_addr, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("ERROR: xemac_add failed (check GEM0/PHY/MIO/XSA)\r\n");
        return XST_FAILURE;
    }
    netif_set_default(&board_netif);
    netif_set_up(&board_netif);

    if (start_udp_server() != XST_SUCCESS) {
        return XST_FAILURE;
    }

    /* Enable interrupts only after the network adapter and UDP are ready. */
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    XScuTimer_EnableInterrupt(&scu_timer);
    XScuTimer_Start(&scu_timer);

    xil_printf("Board IP : %u.%u.%u.%u\r\n",
               BOARD_IP_A, BOARD_IP_B, BOARD_IP_C, BOARD_IP_D);
    xil_printf("Netmask  : 255.255.255.0\r\n");
    xil_printf("MAC      : 02:0A:35:00:01:02 (demo, make unique)\r\n");
    xil_printf("Connect your PC to the board's PS Ethernet port.\r\n");

    last_fast = 0U;
    last_slow = 0U;
    last_arp  = 0U;

    for (;;) {
        
        xemacif_input(&board_netif);

        now = ticks_50ms;
        /* Run lwIP timers in the main loop. */
        if ((unsigned int)(now - last_fast) >= 5U) {
            last_fast = now;
            tcp_fasttmr();           
        }
        if ((unsigned int)(now - last_slow) >= 10U) {
            last_slow = now;
            tcp_slowtmr();           
        }
        if ((unsigned int)(now - last_arp) >= 100U) {
            last_arp = now;
            etharp_tmr();            
        }
    }
}
