#!/bin/bash

# iperf3 client params
IPERF3_PORT=5201
#IPERF3_PARAMS="-p $IPERF3_PORT -C dctcp-sce -t 30s"
IPERF3_PARAMS="-p $IPERF3_PORT -t 30s"

# left endpoint
LEFT_NETEM="delay 40ms limit 1000000"
# use LEFT_HTB and LEFT_LEAF for fq_codel_fast or just LEFT_LEAF for Cake
#LEFT_HTB="rate 10mbit ceil 10mbit"
#LEFT_LEAF="fq_codel ce_threshold 2.5ms"
LEFT_LEAF="cake besteffort bandwidth 10mbit sce"
LEFT_IP=10.12.0.1
LEFT_ECN=1
LEFT_SCE=1

# right endpoint
RIGHT_NETEM="delay 40ms limit 1000000"
# use RIGHT_HTB and RIGHT_LEAF for fq_codel_fast or just RIGHT_LEAF for Cake
#RIGHT_HTB="rate 10mbit ceil 10mbit"
#RIGHT_LEAF="fq_codel ce_threshold 2.5ms"
RIGHT_LEAF="cake besteffort bandwidth 10mbit sce"
RIGHT_IP=10.12.0.2
RIGHT_ECN=1
RIGHT_SCE=1

# disable offloads (more accurate packet caps and maybe simulations)
NS_DISABLE_OFFLOADS=1

# tcpdump snap length
SNAPLEN=94
