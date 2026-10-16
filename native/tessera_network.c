#include <enet/enet.h>
#include <stdint.h>
/* ENet counters include UDP datagrams, protocol headers, compression and retransmissions. */
uint32_t tessera_net_sent(const ENetHost *host) { return host ? host->totalSentData : 0; }
uint32_t tessera_net_received(const ENetHost *host) { return host ? host->totalReceivedData : 0; }
