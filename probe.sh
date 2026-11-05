#!/bin/bash
# probe.sh: with the restat tool, what does a pull request's zig job cost on each platform, by what its diff changed?
set -u
grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/^/PROBE cpu /'
[ -n "${PROCESSOR_IDENTIFIER:-}" ] && echo "PROBE cpu $PROCESSOR_IDENTIFIER"
if [ "$RUNNER_OS" = Windows ]; then GATES="test test-golden fuzz-cortheon"; else GATES="test test-kernel-contract test-golden test-server-security test-pull-security fuzz-cortheon"; fi
restat() {
  local s=$(date +%s) rc
  zig run -OReleaseFast -mcpu=baseline tools/zig/zig_cache_restat.zig -- .zig-cache "$(dirname "$(command -v zig)")/lib"
  rc=$?
  echo "PROBE restat exit $rc $(( $(date +%s) - s )) s"
}
go() {
  local name=$1 s=$(date +%s) rc
  zig build -Dfixed-cpu -Dname-tests $GATES --test-timeout 10m --summary all 2>&1 | sed -E 's/ MaxRSS:[^ ]+//'
  rc=${PIPESTATUS[0]}
  echo "PROBE $name exit $rc $(( $(date +%s) - s )) s"
}
edit() {
  printf '\ntest "probe edit" {\n    try @import("std").testing.expect(true);\n}\n' >> "$1"
  git diff --stat | tail -1 | sed 's/^/PROBE edit /'
}
case $1 in
  cold) restat; go cold; du -sm .zig-cache | sed 's/^/PROBE cache MB /' ;;
  same) restat; go same ;;
  family) edit zig/src/families/qwen3/native.zig; restat; go family ;;
  shared) edit zig/src/core/engine_api.zig; restat; go shared ;;
esac
exit 0
