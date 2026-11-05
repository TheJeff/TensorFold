#!/bin/bash
# probe.sh: what does #2095's wider host step cost, cold and restored, and which of its tests read tracked files?
set -u
bash tools/zig/zig_cache_contents.sh
grep -m1 'model name' /proc/cpuinfo | sed 's/^/PROBE cpu /'
nproc | sed 's/^/PROBE cores /'
go() {
  local name=$1 gate=$2 s=$(date +%s) rc
  zig build -Dfixed-cpu -Dname-tests $gate --test-timeout 20m --summary all 2>&1 | sed -E 's/ MaxRSS:[^ ]+//'
  rc=${PIPESTATUS[0]}
  echo "PROBE $name $gate exit $rc $(( $(date +%s) - s )) s"
}
edit() {
  printf '\ntest "probe edit" {\n    try @import("std").testing.expect(true);\n}\n' >> "$1"
  git diff --stat | tail -1 | sed 's/^/PROBE edit /'
}
case $1 in
  cold)
    go cold test-host
    du -sm .zig-cache | sed 's/^/PROBE cache MB /' ;;
  audit)
    sudo apt-get install -y -qq strace > /dev/null 2>&1; strace -V | head -1
    s=$(date +%s)
    strace -f --seccomp-bpf -qq -y -s 1024 -e trace=execve,execveat,openat,openat2,open,creat,clone,clone3,fork,vfork -o "$RUNNER_TEMP/trace.txt" zig build -Dfixed-cpu -Dname-tests -Drerun-tests test-host --test-timeout 20m --summary line 2>&1 | tail -40
    echo "PROBE traced exit ${PIPESTATUS[0]} $(( $(date +%s) - s )) s, trace $(du -m "$RUNNER_TEMP/trace.txt" | cut -f1) MB"
    python3 probe_audit.py "$RUNNER_TEMP/trace.txt" ;;
  same) go same "$2" ;;
  family) edit zig/src/families/qwen3/native.zig; go family "$2" ;;
  shared) edit zig/src/core/engine_api.zig; go shared "$2" ;;
esac
exit 0
