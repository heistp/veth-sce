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
	analyze_dir() {
		local dir="$1"

		count() {
			local filter="$1"
			local pf
			sense() {
				[ "$dir" = "right" ] && echo "dst"
				[ "$dir" = "left" ] && echo "src"
			}
			filter() {
				[ "$filter" != "" ] && echo "and $filter"
			}
			wc -l < <(tcpdump -q -n -r $dir.pcap $(sense) port $IPERF3_PORT $(filter) 2>/dev/null)
			if (( $? != 0 )); then
				echo "* tcpdump return code: $?"
			fi
		}
	
		echo "ECT(0) $dir: $(count "ip[1]&0x03 == 0x2")"
		echo "ECT(1)/SCE $dir: $(count "ip[1]&0x03 == 0x1")"
		echo "CE $dir: $(count "ip[1]&0x03 == 0x03")"
		echo "ECE $dir: $(count "tcp[13]&64 != 0")"
		echo "CWR $dir: $(count "tcp[13]&128 != 0")"
		echo "NS $dir: $(count "tcp[12]&1 != 0")"
		echo "PSH $dir: $(count "tcp[13]&8 != 0")"
		echo "Total $dir: $(count "")"
	}

	echo "Packet counts:"
	echo "--------------"
	echo
	analyze_dir right
	echo
	analyze_dir left
}

# Sets up namespaces, netem and ecn.
start() {
	# set up endpoints and middlebox
	ns right rep "right endpoint" $RIGHT_IP/24 mid
	ns bridge mid "middle box" lep
	ns left lep "left endpoint" $LEFT_IP/24

	# set up left interface
	if [[ $LEFT_LEAF == cake* ]]; then
		nsx mid tc qdisc add dev mid.l root $LEFT_LEAF
	else
		nsx mid tc qdisc add dev mid.l root handle 1: htb default 1
		nsx mid tc class add dev mid.l parent 1: classid 1:1 htb $LEFT_HTB
		nsx mid tc qdisc add dev mid.l parent 1:1 $LEFT_LEAF
	fi
	if [ "$LEFT_NETEM" != "" ]; then
		modprobe ifb
		nsx mid ip link add dev imid.l type ifb
		nsx mid tc qdisc add dev imid.l root handle 1: netem $LEFT_NETEM

		nsx mid tc qdisc add dev mid.l handle ffff: ingress
		nsx mid ip link set imid.l up
		nsx mid tc filter add dev mid.l parent ffff: protocol all prio 10 u32 match u32 0 0 \
			flowid 1:1 action mirred egress redirect dev imid.l
	fi
	nsx lep sysctl -w net.ipv4.tcp_ecn=$LEFT_ECN
	nsx lep sysctl -w net.ipv4.tcp_sce=$LEFT_SCE

	# set up right interface
	if [[ $RIGHT_LEAF == cake* ]]; then
		nsx mid tc qdisc add dev mid.r root $RIGHT_LEAF
	else
		nsx mid tc qdisc add dev mid.r root handle 1: htb default 1
		nsx mid tc class add dev mid.r parent 1: classid 1:1 htb $RIGHT_HTB
		nsx mid tc qdisc add dev mid.r parent 1:1 $RIGHT_LEAF
	fi
	if [ "$RIGHT_NETEM" != "" ]; then
		modprobe ifb
		nsx mid ip link add dev imid.r type ifb
		nsx mid tc qdisc add dev imid.r root handle 1: netem $RIGHT_NETEM

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
    start $*
}

run() {
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
    
	nsx rep tcpdump -i rep.l -s $SNAPLEN -w right.pcap port 5201 &>/dev/null &
	nsx lep tcpdump -i lep.r -s $SNAPLEN -w left.pcap port 5201 &>/dev/null &
	sleep 1

	nsx rep iperf3 -s &>/dev/null &
	sleep 1
	nsx lep iperf3 -c $RIGHT_IP $IPERF3_PARAMS 2>&1

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
