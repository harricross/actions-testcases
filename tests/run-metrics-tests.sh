#!/usr/bin/env bash
# Regression test for .github/scripts/metrics.jq.
#
# Runs the script against tests/fixtures/snapshots/*.json with a fixed
# "now" timestamp and asserts specific values for each synthetic suite,
# covering every code path in the highlights output:
#
#   stable_green   — 5 success           → uptime=100, no flips, no flakes
#   stable_red     — 5 failure           → long_red highlight, low uptime
#   flapper        — s,f,s,f,s           → recovery highlight, flakiest top, MTTR=3600
#   new_failure_case — s,s,s,s,f         → new_failures highlight, streak=1 fail
#   recovery_case  — f,f,f,f,s           → recovery highlight, MTTR=14400
#
# Run locally:  bash tests/run-metrics-tests.sh
# Run in CI :  triggered by .github/workflows/_self-test.yml
set -euo pipefail

cd "$(dirname "$0")/.."

NOW="2026-01-01T05:00:00Z"
fixtures=( tests/fixtures/snapshots/*.json )

out=$(jq -s --arg now "$NOW" -f .github/scripts/metrics.jq "${fixtures[@]}")

fail=0
pass=0

assert() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass+1))
    printf '  ✅ %s\n' "$name"
  else
    fail=$((fail+1))
    printf '  ❌ %s — expected: %s   got: %s\n' "$name" "$expected" "$actual"
  fi
}

field() {
  jq -r --arg label "$1" ".suites[] | select(.label==\$label) | $2" <<<"$out"
}

count() {
  jq -r ".highlights.$1 | length" <<<"$out"
}

has_label() {
  jq -e --arg label "$2" ".highlights.$1[] | select(.label==\$label)" <<<"$out" >/dev/null \
    && echo true || echo false
}

echo "── stable_green (always success) ──"
assert "uptime_24h"   "100"     "$(field stable_green .uptime_24h)"
assert "streak_count" "5"       "$(field stable_green .streak_count)"
assert "streak_state" "success" "$(field stable_green .streak_state)"
assert "flakes_7d"    "0"       "$(field stable_green .flakes_7d)"
assert "flipped"      "false"   "$(field stable_green .flipped)"
assert "mttr null"    "null"    "$(field stable_green .mttr_7d_seconds)"

echo "── stable_red (always failure) ──"
assert "uptime_24h"   "0"       "$(field stable_red .uptime_24h)"
assert "streak_count" "5"       "$(field stable_red .streak_count)"
assert "streak_state" "failure" "$(field stable_red .streak_state)"
assert "flakes_7d"    "0"       "$(field stable_red .flakes_7d)"
assert "in long_red"  "true"    "$(has_label long_red stable_red)"

echo "── flapper (s,f,s,f,s) ──"
assert "uptime_24h"   "60"      "$(field flapper .uptime_24h)"
assert "streak_count" "1"       "$(field flapper .streak_count)"
assert "streak_state" "success" "$(field flapper .streak_state)"
assert "flakes_7d"    "4"       "$(field flapper .flakes_7d)"
assert "flipped"      "true"    "$(field flapper .flipped)"
assert "mttr 3600"    "3600"    "$(field flapper .mttr_7d_seconds)"
assert "in recoveries" "true"   "$(has_label recoveries flapper)"
assert "in flakiest"   "true"   "$(has_label flakiest flapper)"

echo "── new_failure_case (s,s,s,s,f) ──"
assert "uptime_24h"   "80"      "$(field new_failure_case .uptime_24h)"
assert "streak_count" "1"       "$(field new_failure_case .streak_count)"
assert "streak_state" "failure" "$(field new_failure_case .streak_state)"
assert "flipped"      "true"    "$(field new_failure_case .flipped)"
assert "in new_failures" "true" "$(has_label new_failures new_failure_case)"

echo "── recovery_case (f,f,f,f,s) ──"
assert "uptime_24h"   "20"       "$(field recovery_case .uptime_24h)"
assert "streak_count" "1"        "$(field recovery_case .streak_count)"
assert "streak_state" "success"  "$(field recovery_case .streak_state)"
assert "flipped"      "true"     "$(field recovery_case .flipped)"
assert "mttr 14400"   "14400"    "$(field recovery_case .mttr_7d_seconds)"
assert "in recoveries" "true"    "$(has_label recoveries recovery_case)"

echo "── highlight cardinalities ──"
assert "new_failures count"   "1" "$(count new_failures)"
assert "recoveries count"     "2" "$(count recoveries)"
assert "long_red count"       "1" "$(count long_red)"
assert "flakiest length ≤ 5"  "true" "$([ "$(count flakiest)" -le 5 ] && echo true || echo false)"

echo "── highlight ordering (flakiest sorted desc) ──"
top=$(jq -r '.highlights.flakiest[0].label' <<<"$out")
assert "flakiest top is flapper" "flapper" "$top"

echo "── low_uptime sorted ascending ──"
first_low=$(jq -r '.highlights.low_uptime[0].label' <<<"$out")
assert "low_uptime first is stable_red" "stable_red" "$first_low"

echo "── highlights.jq renders without error ──"
md=$(jq -r -f .github/scripts/highlights.jq <<<"$out")
echo "$md" | grep -q "## 🆕 New failures this hour" \
  && pass=$((pass+1)) && echo "  ✅ markdown contains new failures section" \
  || { fail=$((fail+1)); echo "  ❌ missing new failures section"; }
echo "$md" | grep -q "## ✅ Recoveries this hour" \
  && pass=$((pass+1)) && echo "  ✅ markdown contains recoveries section" \
  || { fail=$((fail+1)); echo "  ❌ missing recoveries section"; }
echo "$md" | grep -q "## 🔥 Currently failing for ≥ 3 hours" \
  && pass=$((pass+1)) && echo "  ✅ markdown contains long_red section" \
  || { fail=$((fail+1)); echo "  ❌ missing long_red section"; }

echo
echo "─────────────────────────────────"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
