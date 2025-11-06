#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#include <rte_common.h>
#include <rte_eal.h>
#include <rte_lcore.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>
#include <rte_log.h>
#include <rte_ether.h>
#include <rte_flow.h>

#define BURST_SIZE       32
#define MBUF_CACHE_SIZE  250
#define RX_QUEUE_ID 0
#define TX_QUEUE_ID 0

static volatile bool force_quit = false;

/* Signal handler for Ctrl+C and SIGTERM */
static void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        printf("\nSignal %d received, preparing to exit...\n", sig);
        force_quit = true;
    }
}

/* Worker: swaps MAC and forwards */
static int
lcore_forward_mac_swap(void *arg)
{
    uint16_t port_id = (uint16_t)(uintptr_t)arg;
    struct rte_mbuf *bufs[BURST_SIZE];
    struct rte_mbuf *m = NULL;
    struct rte_ether_hdr *eth = NULL;
    struct rte_ether_addr tmp;
    uint16_t nb_rx, nb_tx;
    uint16_t i;

    RTE_LOG(INFO, USER1, "Worker lcore %u: started for port %u queue %u\n",
            rte_lcore_id(), port_id, RX_QUEUE_ID);

    while (!force_quit) {
        nb_rx = rte_eth_rx_burst(port_id, RX_QUEUE_ID, bufs, BURST_SIZE);
        if (nb_rx == 0)
            continue;

        for (i = 0; i < nb_rx; i++) {
            m = bufs[i];
            eth = rte_pktmbuf_mtod(m, struct rte_ether_hdr *);
            rte_ether_addr_copy(&eth->src_addr, &tmp);
            rte_ether_addr_copy(&eth->dst_addr, &eth->src_addr);
            rte_ether_addr_copy(&tmp, &eth->dst_addr);
        }

        nb_tx = rte_eth_tx_burst(port_id, TX_QUEUE_ID, bufs, nb_rx);
        if (nb_tx < nb_rx) {
            for (i = nb_tx; i < nb_rx; i++)
                rte_pktmbuf_free(bufs[i]);
        }
    }
    return 0;
}

/* RAW flow for all traffic */
static int
setup_rte_flow(uint16_t port_id)
{

    struct rte_flow_item_raw raw_spec;
    struct rte_flow_item_raw raw_mask;
    struct rte_flow_attr attr;
    struct rte_flow_item pattern[2];
    struct rte_flow_action action[2];
    struct rte_flow_action_queue queue = { .index = RX_QUEUE_ID };
    struct rte_flow_error error;
    struct rte_flow *flow;
    struct rte_flow_action_port_id port_id_action;

    /* Match in RX */
    memset(&attr, 0, sizeof(attr));
    attr.ingress = 1;

    /* RAW: search for 0xFD in byte 23 */
    memset(&raw_spec, 0, sizeof(raw_spec));
    raw_spec.pattern  = (const uint8_t*)"fd";
    raw_spec.length   = strlen((const char*)raw_spec.pattern);     /* 1 byte */
    raw_spec.offset   = 23;    /* Protocol position in IPv4 header */
    raw_spec.relative = 0;     /* start from byte 0*/
    
    memset(&raw_mask, 0, sizeof(raw_spec));
    raw_mask.pattern = (const uint8_t*)"ff";
    raw_mask.length = strlen((const char*)raw_mask.pattern);
    raw_mask.relative = 0;
    raw_mask.search = 0;
    raw_mask.offset = 23;   

    memset(pattern, 0, sizeof(pattern));
    pattern[0].type = RTE_FLOW_ITEM_TYPE_RAW;
    pattern[0].spec = &raw_spec;
    pattern[0].mask = &raw_mask;
    pattern[1].type = RTE_FLOW_ITEM_TYPE_END;

    memset(&port_id_action, 0, sizeof(port_id_action));
    port_id_action.id = port_id;

    /* Action: send to port_id */
    memset(action, 0, sizeof(action));
    action[0].type = RTE_FLOW_ACTION_TYPE_PORT_ID;
    action[0].conf = &port_id_action;
    action[1].type = RTE_FLOW_ACTION_TYPE_END;

    /* Create flow */
    flow = rte_flow_create(port_id, &attr, pattern, action, &error);
    if (!flow) {
        printf("Failed to create flow: %s\n",
            error.message ? error.message : "(no message)");
        return -1;
    }

    printf("RAW flow installed: all packets redirected to queue %u\n", RX_QUEUE_ID);
    return 0;
}

int main(int argc, char **argv)
{
    int ret = rte_eal_init(argc, argv);
    if (ret < 0)
        rte_exit(EXIT_FAILURE, "EAL init failed\n");

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    uint16_t port_id = 0;
    if (rte_eth_dev_count_avail() == 0)
        rte_exit(EXIT_FAILURE, "No Ethernet ports found\n");

    struct rte_mempool *mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL",
                                                            20479,
                                                            MBUF_CACHE_SIZE,
                                                            0,
                                                            RTE_MBUF_DEFAULT_BUF_SIZE,
                                                            rte_socket_id());
    if (!mbuf_pool)
        rte_exit(EXIT_FAILURE, "Cannot create mbuf pool\n");

    struct rte_eth_conf port_conf = {0};
    port_conf.rxmode.mq_mode = RTE_ETH_MQ_RX_NONE;
    if (rte_eth_dev_configure(port_id, 1, 1, &port_conf) < 0)
        rte_exit(EXIT_FAILURE, "rte_eth_dev_configure failed\n");

    if (rte_eth_rx_queue_setup(port_id, RX_QUEUE_ID, 1024,
                               rte_eth_dev_socket_id(port_id), NULL, mbuf_pool) < 0)
        rte_exit(EXIT_FAILURE, "rte_eth_rx_queue_setup failed\n");

    if (rte_eth_tx_queue_setup(port_id, TX_QUEUE_ID, 1024,
                               rte_eth_dev_socket_id(port_id), NULL) < 0)
        rte_exit(EXIT_FAILURE, "rte_eth_tx_queue_setup failed\n");

    if (rte_eth_dev_start(port_id) < 0)
        rte_exit(EXIT_FAILURE, "rte_eth_dev_start failed\n");

    struct rte_ether_addr mac;
    rte_eth_macaddr_get(port_id, &mac);
    printf("Port %u MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
           port_id,
           mac.addr_bytes[0], mac.addr_bytes[1], mac.addr_bytes[2],
           mac.addr_bytes[3], mac.addr_bytes[4], mac.addr_bytes[5]);

    if (setup_rte_flow(port_id) < 0)
        rte_exit(EXIT_FAILURE, "Failed to setup RAW rte_flow\n");

    /* Launch a single worker and master waits */ 
    unsigned worker_lcore = rte_get_next_lcore(rte_lcore_id(), 1, 0);
    if (worker_lcore == RTE_MAX_LCORE)
        lcore_forward_mac_swap((void *)(uintptr_t)port_id);
    else
        rte_eal_remote_launch(lcore_forward_mac_swap, (void *)(uintptr_t)port_id, worker_lcore);

    rte_eal_mp_wait_lcore();

    rte_eth_dev_stop(port_id);
    rte_eth_dev_close(port_id);
    rte_eal_cleanup();
    RTE_LOG(INFO, USER1,"Bye!\n");
    return 0;
}
