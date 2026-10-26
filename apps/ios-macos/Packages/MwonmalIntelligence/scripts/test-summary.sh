#!/usr/bin/env bash
# swift test 를 돌리고 통과·실패·건너뜀 수를 한 줄로 보고한다. 건너뜀은 절대 조용히 넘기지 않는다.
#   REQUIRE_FM=1 scripts/test-summary.sh   # FM 실기 Mac(야간): FM 스모크가 건너뛰어지면 실패
set -uo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp); swift test 2>&1 | tee "$log" >/dev/null; rc=${PIPESTATUS[0]}
passed=$(grep -cE '^.{1,3}Test .* passed after' "$log")
failed=$(grep -cE '^.{1,3}Test .* failed after' "$log")
skipped=$(grep -cE '^.{1,3}Test .* skipped' "$log")
echo "mwintel-tests passed=$passed failed=$failed skipped=$skipped rc=$rc"
grep -E 'skipped:' "$log" | sed 's/^/  SKIP /'
if [[ "${REQUIRE_FM:-0}" == "1" && "$skipped" -gt 0 ]]; then echo "REQUIRE_FM=1 인데 건너뛴 테스트가 있다"; exit 3; fi
rm -f "$log"; exit "$rc"
