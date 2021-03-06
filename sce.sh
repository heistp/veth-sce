#!/bin/bash

# namespaces:
# lep- left endpoint
# mid- middle box
# rep- right endpoint
#
# namespace topology:
# lep <-> mid <-> rep
#
# interface topology:
# lep.r <-> mid.l : mid.r <-> rep.l

. "$(dirname "$0")"/veth.sh
. "$(dirname "$0")"/config.sh

analyze() {
	local dir="${1:-\".\"}"

	analyze_dir() {
		local direction="$1"

		count() {
			local filter="$1"
			local pf
			sense() {
				[ "$direction" = "right" ] && echo "dst"
				[ "$direction" = "left" ] && echo "src"
			}
			filter() {
				[ "$filter" != "" ] && echo "and $filter"
			}
			wc -l < <(tcpdump -q -n -r $dir/$direction.pcap $(sense) port 5201 $(filter) 2>/dev/null)
			if (( $? != 0 )); then
				echo "* tcpdump return code: $?"
			fi
		}
	
		echo "ECT(0) $direction: $(count "ip[1]&0x03 == 0x2")"
		echo "ECT(1) (SCE) $direction: $(count "ip[1]&0x03 == 0x1")"
		echo "CE $direction: $(count "ip[1]&0x03 == 0x03")"
		echo "ECE $direction: $(count "tcp[13]&64 != 0")"
		echo "CWR $direction: $(count "tcp[13]&128 != 0")"
		echo "NS (ESCE) $direction: $(count "tcp[12]&1 != 0")"
		echo "ACK $direction: $(count "tcp[13]&16 != 0")"
		echo "PSH $direction: $(count "tcp[13]&8 != 0")"
		echo "Total $direction: $(count "")"
	}

	echo "mid.r cake stats:"
	nsx mid tc -s -d qdisc show dev mid.r
	echo "mid.l cake stats:"
	nsx mid tc -s -d qdisc show dev mid.l

	echo "Packet counts:"
	echo "--------------"
	echo
	analyze_dir right
	echo
	analyze_dir left
}

# Sets up namespaces, netem and ecn.
start() {
	left_netem="${1:-$LEFT_NETEM}"
	left_leaf="${2:-$LEFT_LEAF}"
	right_netem="${3:-$RIGHT_NETEM}"
	right_leaf="${4:-$RIGHT_LEAF}"

	# set up endpoints and middlebox
	ns right rep "right endpoint" $RIGHT_IP/24 mid
	ns bridge mid "middle box" lep
	ns left lep "left endpoint" $LEFT_IP/24

	# set up left interface
	if [[ $left_leaf == cake* ]]; then
		nsx mid tc qdisc add dev mid.l root $left_leaf
	else
		nsx mid tc qdisc add dev mid.l root handle 1: htb default 1
		nsx mid tc class add dev mid.l parent 1: classid 1:1 htb $LEFT_HTB
		nsx mid tc qdisc add dev mid.l parent 1:1 $left_leaf
	fi
	if [ "$left_netem" != "" ]; then
		modprobe ifb
		nsx mid ip link add dev imid.l type ifb
		nsx mid tc qdisc add dev imid.l root handle 1: netem $left_netem

		nsx mid tc qdisc add dev mid.l handle ffff: ingress
		nsx mid ip link set imid.l up
		nsx mid tc filter add dev mid.l parent ffff: protocol all prio 10 u32 match u32 0 0 \
			flowid 1:1 action mirred egress redirect dev imid.l
	fi
	nsx lep sysctl -w net.ipv4.tcp_ecn=$LEFT_ECN
	nsx lep sysctl -w net.ipv4.tcp_sce=$LEFT_SCE

	# set up right interface
	if [[ $right_leaf == cake* ]]; then
		nsx mid tc qdisc add dev mid.r root $right_leaf
	else
		nsx mid tc qdisc add dev mid.r root handle 1: htb default 1
		nsx mid tc class add dev mid.r parent 1: classid 1:1 htb $RIGHT_HTB
		nsx mid tc qdisc add dev mid.r parent 1:1 $right_leaf
	fi
	if [ "$right_netem" != "" ]; then
		modprobe ifb
		nsx mid ip link add dev imid.r type ifb
		nsx mid tc qdisc add dev imid.r root handle 1: netem $right_netem

		nsx mid tc qdisc add dev mid.r handle ffff: ingress
		nsx mid ip link set imid.r up
		nsx mid tc filter add dev mid.r parent ffff: protocol all prio 10 u32 match u32 0 0 \
			flowid 1:1 action mirred egress redirect dev imid.r
	fi
	nsx rep sysctl -w net.ipv4.tcp_ecn=$RIGHT_ECN
	nsx rep sysctl -w net.ipv4.tcp_sce=$RIGHT_SCE

	echo
	nsx lep ping -c 3 -i 0.1 $RIGHT_IP
}

stop() {
	nsd lep mid rep
}

restart() {
    stop
    start "$@"
}

run() {
	iperf3_params="${1:-$IPERF3_PARAMS}"
	left_pcap="${2:-"left.pcap"}"
	right_pcap="${3:-"right.pcap"}"
	clean=0

	cleanup() {
		if (( $clean == 0 )); then
			sleep 0.2
			pkill tcpdump
			pkill iperf3
			sleep 0.2
		else
			clean=1
		fi
    }

    trap cleanup EXIT
    
	nsx lep tcpdump -i lep.r -s $SNAPLEN -w "${left_pcap}" port 5201 &>/dev/null &
	nsx rep tcpdump -i rep.l -s $SNAPLEN -w "${right_pcap}" port 5201 &>/dev/null &
	sleep 1

	nsx rep iperf3 -s &>/dev/null &
	sleep 1
	nsx lep iperf3 -c $RIGHT_IP $iperf3_params 2>&1

	echo
	echo "Right queue stats:"
	echo "------------------"
	echo
	nsx mid tc -s qdisc show dev mid.r
	echo
	echo "Left queue stats:"
	echo "-----------------"
	echo
	nsx mid tc -s qdisc show dev mid.l
	echo
	cleanup
}

for arg in "$@"; do
    eval "$arg"
done
