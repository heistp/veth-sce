# veth-sce

These scripts run an iperf3 test with basic SCE analysis using network namespaces.

### Prerequisites:
- SCE capable Cake or htb+fq_codel_fast
- Linux kernel with IFB, VETH, HTB, NETEM and INGRESS support, as well as TC and
  a number of packet classifiers
- tc-adv
- iperf3
- tcpdump
- iproute2

### Quick start (run as root):

```
# sets up namespaces, runs test and counts packets
./sce.sh start run analyze
```

### Notes:
- Modify `config.sh` in case anything needs to be changed (defaults should work)
- Commands (run as root):
	```
	./sce.sh start    # set up namespaces and qdiscs
	./sce.sh run      # run test and show packet counts
	./sce.sh analyze  # show packet counts
	./sce.sh stop     # delete namespaces
	./sce.sh restart  # stop and start
	```
- Multiple commands may be strung together, e.g.: `./sce.sh restart run analyze`
