#!/bin/bash

run() {
	local cc=$1
	local bandwidth=$2
	local delay=$3
	local netem="delay $delay limit 1000000"
	local cake="cake besteffort sce bandwidth $bandwidth"
	local outdir="${cc}_${delay}_${bandwidth}"
	local iperf3_params="-C $cc -t 30s"

	echo "CC: $cc bandwidth: $bandwidth delay: $delay"
	mkdir $outdir
	./sce.sh "restart \"$netem\" \"$cake\" \"$netem\" \"$cake\"" \
		"run \"$iperf3_params\" $outdir/left.pcap $outdir/right.pcap"
	./sce.sh "analyze $outdir" > $outdir/analysis.txt
	cd $outdir
	cctrace right.pcap
	tcptrace -G right.pcap
	cd ..
}

bytes_rtt() {
	local cc=$1
	local bandwidth=$2
	local delay=$3
	local outdir="${cc}_${delay}_${bandwidth}"
	read a bytes <<< $(grep -m 1 "^  bytes" $outdir/analysis.txt)
	local tcp_rtt=$(tshark -Y "tcp.stream==1" -r $outdir/left.pcap -Tfields -e "tcp.analysis.ack_rtt" | grep . | awk '{ sum += $1; n++ } END { if (n > 0) printf "%f\n", sum / n; }')
	echo $cc,$delay,$bandwidth,$bytes,$tcp_rtt
}

func=${1:-run}
for bandwidth in 1Mbit 10Mbit 100Mbit; do
	for delay in 10ms 20ms 40ms 80ms 160ms; do
		for cc in cubic dctcp dctcp-sce; do
			$func $cc $bandwidth $delay
		done
	done
done
