#!/bin/bash

# Set to 1 to disable offloads (more accurate packet captures and maybe simulations).
NS_DISABLE_OFFLOADS=1

. "$(dirname "$0")"/config.sh

# Sets up namespace.
#
# Parameters:
# <mode:right/bridge/left> <namespace name> <description> <mode dependent params>
#    right params: <ip> <left namespace>
#    bridge params: <left namespace>
#    left params: <ip>
ns() {
	local mode="$1"; shift
	local name="$1"; shift
	local desc="$1"; shift

	echo -e "\n----- $mode $name ($desc):\n"

	ip netns add $name

    disable_offloads() {
        local iface="$1"
        if [ "$NS_DISABLE_OFFLOADS" = "1" ]; then
            nx ethtool -K $iface \
                rx off tx off sg off tso off ufo off gso off gro off rxvlan off txvlan off
        fi
    }

    nx() {
        nsx $name $*
    }

	case $mode in
	right)
		local ip="$1"; shift
		local leftns="$1"; shift
		ip link add dev ${name}.l type veth peer name ${leftns}.r
		ip link set dev ${name}.l netns $name
		nx ip addr add $ip dev ${name}.l
		nx ip link set ${name}.l up
        disable_offloads ${name}.l
		;;
	bridge)
		local leftns="$1"; shift
		ip link set dev ${name}.r netns $name
		nx ip link set ${name}.r up
        disable_offloads ${name}.r
		ip link add dev ${name}.l type veth peer name ${leftns}.r
		ip link set dev ${name}.l netns $name
		nx ip link set ${name}.l up
        disable_offloads ${name}.l
		nx ip link add name ${name}.b type bridge
		nx ip link set dev ${name}.r master ${name}.b
		nx ip link set dev ${name}.l master ${name}.b
		nx ip link set dev ${name}.b up
		;;
	left)
		local ip="$1"; shift
		ip link set dev ${name}.r netns $name
		nx ip addr add $ip dev ${name}.r
		nx ip link set ${name}.r up
        disable_offloads ${name}.r
		;;
	*)
		echo "invalid namespace mode: $mode"
		exit 1
		;;
	esac

	nx ip addr
}

# Executes command in namespace (helper).
nsx() {
    local ns="$1"; shift
    ip netns exec $ns $*
}

# Deletes namespaces.
nsd() {
    for ns in "$@"; do
        ip netns del $ns
        echo "Deleted namespace $ns."
    done
}
