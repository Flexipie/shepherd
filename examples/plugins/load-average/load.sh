#!/bin/sh
# The Mac's load average as a gadget card: a meter per interval, full at one process per core.
cores=$(sysctl -n hw.ncpu)
set -- $(sysctl -n vm.loadavg | tr -d '{}')
awk -v cores="$cores" -v one="$1" -v five="$2" -v fifteen="$3" 'BEGIN {
  printf "{\"title\": \"Load average\", \"detail\": \"%d cores\", \"meters\": [", cores
  printf "{\"label\": \"1 min\", \"fraction\": %.3f, \"text\": \"%s\"}, ", one / cores, one
  printf "{\"label\": \"5 min\", \"fraction\": %.3f, \"text\": \"%s\"}, ", five / cores, five
  printf "{\"label\": \"15 min\", \"fraction\": %.3f, \"text\": \"%s\"}]}\n", fifteen / cores, fifteen
}'
