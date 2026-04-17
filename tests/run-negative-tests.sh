#!/usr/bin/env bash
# Negative-test harness for the self-test contracts and the metrics
# regression test.
#
# A green self-test run only proves that the checkers are silent today,
# not that they would catch a real regression. This harness deliberately
# breaks the suite in a number of well-defined ways and asserts that the
# corresponding checker DETECTS the breakage (i.e. exits non-zero).
#
# Each mutation:
#   1. Materialises a clean copy of the repo into a fresh tmp workdir
#      (mktemp -d). Tracked sources are NEVER modified in place.
#   2. Applies one specific mutation inside the copy.
#   3. Runs the relevant checker against the copy.
#   4. Asserts the checker exited non-zero (i.e. caught the breakage).
#   5. Cleans up via trap.
#
# Run locally:  bash tests/run-negative-tests.sh
# Run in CI :   triggered from .github/workflows/_self-test.yml after the
#               metrics regression run.
#
# To add a new mutation, append a `mutation` function below following the
# existing pattern, then call it from `main` and bump the expected count.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

# Single tmp workdir for all mutations; per-mutation subdirs underneath.
ROOT_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t neg)"
trap 'rm -rf "$ROOT_TMP"' EXIT

pass=0
fail=0

# Materialise a fresh copy of the repo (excluding .git) into a tmp dir
# named after the mutation. Echoes the dir to stdout.
make_copy() {
  local name="$1"
  local dest="$ROOT_TMP/$name"
  mkdir -p "$dest"
  # Use tar pipe instead of cp -r to honour the .git exclusion cleanly
  # and preserve permissions.
  ( cd "$REPO_ROOT" && tar --exclude='.git' --exclude='.contracts-work' \
      --exclude='node_modules' -cf - . ) | ( cd "$dest" && tar -xf - )
  echo "$dest"
}

# assert_fails <mutation-name> <command...>
# Runs the command with stdout/stderr captured and asserts non-zero exit.
assert_fails() {
  local name="$1"; shift
  local log
  log="$ROOT_TMP/${name}.log"
  if "$@" >"$log" 2>&1; then
    fail=$((fail+1))
    printf '  ❌ FAIL %s — checker returned success on a broken tree\n' "$name"
    printf '     (last 5 lines of checker output:)\n'
    tail -n 5 "$log" | sed 's/^/       /'
    return 1
  else
    pass=$((pass+1))
    printf '  ✅ PASS %s — checker correctly detected breakage\n' "$name"
    return 0
  fi
}

# ---------------------------------------------------------------
# Mutation (a): metrics value drift.
# Flip a conclusion in 05.json (the "now" snapshot) and assert the
# regression test catches it.
# ---------------------------------------------------------------
mutation_metrics_drift() {
  local copy
  copy="$(make_copy metrics-drift)"
  # Flip stable_green's conclusion in the latest snapshot from success
  # to failure. This breaks uptime_24h, streak, mttr and several
  # highlight assertions at once.
  sed -i.bak 's/"label":"stable_green","conclusion":"success"/"label":"stable_green","conclusion":"failure"/' \
    "$copy/tests/fixtures/snapshots/05.json"
  rm -f "$copy/tests/fixtures/snapshots/05.json.bak"
  assert_fails "metrics-value-drift" bash "$copy/tests/run-metrics-tests.sh"
}

# ---------------------------------------------------------------
# Mutation (b): missing feature token.
# Strip `actions/cache@` from cache.yml and assert the per-suite
# feature-token contract catches it.
# ---------------------------------------------------------------
mutation_missing_feature_token() {
  local copy
  copy="$(make_copy missing-feature-token)"
  # Replace `actions/cache@` references with a plausible-looking
  # decoy so the workflow still parses but the contract token is gone.
  sed -i.bak 's|actions/cache@|actions/checkout@|g' \
    "$copy/.github/workflows/cache.yml"
  rm -f "$copy/.github/workflows/cache.yml.bak"
  assert_fails "missing-feature-token (cache.yml)" \
    bash "$copy/.github/scripts/check-contracts.sh" "$copy"
}

# ---------------------------------------------------------------
# Mutation (c): missing timeout-minutes.
# Strip every `timeout-minutes:` line from cache.yml and assert the
# timeout check catches it.
# ---------------------------------------------------------------
mutation_missing_timeout() {
  local copy
  copy="$(make_copy missing-timeout)"
  sed -i.bak '/timeout-minutes:/d' "$copy/.github/workflows/cache.yml"
  rm -f "$copy/.github/workflows/cache.yml.bak"
  assert_fails "missing-timeout-minutes (cache.yml)" \
    bash "$copy/.github/scripts/check-contracts.sh" "$copy"
}

# ---------------------------------------------------------------
# Mutation (d): non-first-party uses.
# Inject a fake third-party action reference into cache.yml and assert
# the first-party-only invariant catches it.
# ---------------------------------------------------------------
mutation_non_first_party() {
  local copy
  copy="$(make_copy non-first-party)"
  # Append a step with a third-party `uses:` to a known-existing job.
  # Inserted as a top-level YAML comment-then-step so the file remains
  # syntactically valid for grep purposes (the contract is a textual
  # check, not a YAML parse).
  printf '\n# negative-test injection\n      - uses: some-org/evil-action@v1\n' \
    >> "$copy/.github/workflows/cache.yml"
  assert_fails "non-first-party-uses (cache.yml)" \
    bash "$copy/.github/scripts/check-contracts.sh" "$copy"
}

# ---------------------------------------------------------------
# Mutation (e): orphan suite.
# Drop a fake workflow file that is neither referenced by
# _scheduler.yml nor in the exempt set, and assert the orphan check
# catches it.
# ---------------------------------------------------------------
mutation_orphan_suite() {
  local copy
  copy="$(make_copy orphan-suite)"
  cat >"$copy/.github/workflows/orphan-test.yml" <<'YAML'
name: orphan-test
on: { workflow_dispatch: {} }
jobs:
  noop:
    runs-on: ubuntu-latest
    timeout-minutes: 1
    steps:
      - run: echo "I am an orphan"
YAML
  assert_fails "orphan-suite" \
    bash "$copy/.github/scripts/check-contracts.sh" "$copy"
}

# ---------------------------------------------------------------
# Mutation (f): highlights ordering.
# Mutate metrics.jq to reverse the flakiest sort order, then re-run
# the metrics regression test and assert it catches the ordering
# regression (the "flakiest top is flapper" assertion).
# ---------------------------------------------------------------
mutation_highlights_ordering() {
  local copy
  copy="$(make_copy highlights-ordering)"
  # Flip the descending flakes sort to ascending. The fixtures are
  # designed so flapper has the highest flakes_7d; reversing puts a
  # zero-flake suite at the top, breaking the regression assertion.
  if ! grep -q 'sort_by(-.flakes)' "$copy/.github/scripts/metrics.jq"; then
    printf '  ⚠️  skip highlights-ordering — sort_by(-.flakes) not found in metrics.jq\n'
    fail=$((fail+1))
    return
  fi
  sed -i.bak 's|sort_by(-.flakes)|sort_by(.flakes)|' \
    "$copy/.github/scripts/metrics.jq"
  rm -f "$copy/.github/scripts/metrics.jq.bak"
  assert_fails "highlights-ordering (flakiest reversed)" \
    bash "$copy/tests/run-metrics-tests.sh"
}

main() {
  echo "── Negative-test harness ─────────────────────"
  echo "Workdir: $ROOT_TMP"
  echo

  mutation_metrics_drift       || true
  mutation_missing_feature_token || true
  mutation_missing_timeout     || true
  mutation_non_first_party     || true
  mutation_orphan_suite        || true
  mutation_highlights_ordering || true

  echo
  echo "─────────────────────────────────────────────"
  printf '%d mutations detected, %d missed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

main "$@"
