# AGENTS.md — notes for contributors and LLM sessions

Read this **before** modifying anything in this repository. It encodes
invariants that aren't obvious from the workflow files alone, and that, if
broken, silently destroy the suite's value.

## What this repo is

A fork-and-go smoke suite that runs hourly and proves every shippable GitHub
Actions feature still works. It is operated by GitHub Enterprise platform
owners. **It is not a CI pipeline for an application.** Every change should
be evaluated against the question: "does this make the suite a more reliable
detector of Actions regressions?"

## Hard rules (do not break)

### 1. First-party actions only

Allowed `uses:` references:

- `actions/*` — e.g. `actions/checkout`, `actions/upload-artifact`,
  `actions/download-artifact`, `actions/cache`, `actions/setup-*`,
  `actions/github-script`, `actions/attest-build-provenance`,
  `actions/configure-pages`, `actions/deploy-pages`, `actions/upload-pages-artifact`.
- `github/*` — e.g. `github/codeql-action/*`.
- `./.github/actions/*` — local actions defined in this repo.
- `./.github/workflows/*.yml` — local reusable workflows in this repo.

Anything else (including very popular Marketplace actions) is **forbidden**.
Rationale: if a Marketplace action breaks, that's not an Actions platform
regression, but the suite would page the platform team anyway. Use shell +
`gh` CLI. Both ship on every hosted runner image.

If you genuinely need behaviour that only exists in a third-party action,
write a local composite/JS action under `.github/actions/` and vendor it.

### 2. Pin first-party actions to a major version

Use `actions/checkout@v4`, not `@main` and not `@<sha>`. Major-version pins
are the documented stable channel for first-party actions and are what real
enterprise customers use; pinning to a SHA hides upstream breakage that the
suite is supposed to surface.

### 3. Fork-and-go must keep working

A fresh fork with **no secrets and no variables set** must produce a green
`_scheduler.yml` run within an hour. Every gated suite must:

- Read its gate from a repo **variable** (`vars.*`), not a secret.
- Skip cleanly with a clear `$GITHUB_STEP_SUMMARY` line when the gate is
  unset (`if: vars.X != ''` on the job, not on individual steps).
- Never fail the suite because a gate is unset.

### 4. No external network I/O

Workflows may talk to `github.com` / the GHES host (via `gh` and
`actions/*`). They must not `curl` random URLs, `pip install`, `npm install`,
or `apt install` at runtime. If a suite needs a tool, it must already be on
the runner image. JS actions vendor their `node_modules`; Docker actions
build from a pinned base image with no apt/yum at run time.

### 5. Test must assert, not just run

Every workflow ends with at least one assertion that prints `PASS:` or
`FAIL:` lines to `$GITHUB_STEP_SUMMARY` and exits non-zero on failure. A
green run that doesn't actually check anything is worse than no test —
the aggregator will report it as healthy.

### 6. One workflow per feature area

Don't merge unrelated tests into one workflow file. The aggregator reports
results per workflow; a fat workflow loses the "what broke" signal.

## Architecture

```
                          schedule (cron 0 * * * *)
                                    |
                                    v
                           _scheduler.yml  ────────────────┐
                           /        |        \             │
                  workflow_call  gh wf run  repo_dispatch  │
                       │             │            │        │
                  most suites   triggers-manual triggers-events
                                                           │
                              workflow_run: completed      │
                                    │  <─────────────────  ┘
                                    v
                            _aggregate.yml
                              │       │
                       commit to     open / close
                       `status`      `suite-failure`
                       branch        issues
```

- Suites that can be invoked via `workflow_call` are called directly with
  `secrets: inherit` from the scheduler. This is the preferred path —
  results show up as nested jobs of the scheduler run.
- `triggers-manual.yml` must be invoked via `gh workflow run` because
  `workflow_dispatch` cannot be triggered by `workflow_call`.
- `triggers-events.yml` is fired via `repository_dispatch` from the
  scheduler.
- `triggers-push.yml` is fired by the scheduler creating a short-lived
  branch via `gh api` and deleting it after.
- `triggers-workflow-run.yml` chains on completion of `reusable-caller.yml`,
  not the scheduler — that's the whole point.
- `_aggregate.yml` is `on: workflow_run` for `_scheduler.yml`. It:
  1. Calls `gh run list --json` once per suite to get the latest
     conclusion, builds `snapshot.json` + `snapshot.md`.
  2. Force-pushes the snapshot + daily/monthly rollups to a dedicated
     `status` orphan branch (no `main` pollution).
  3. **Computes deterministic metrics with `jq`** by slurping every
     historical `status/**/HH.json` snapshot: per-suite uptime
     (24h / 7d / 30d), current streak, flake count (success↔failure
     transitions), MTTR over 7d, plus highlight arrays (new failures,
     recoveries, long red ≥3h, top-5 flakiest, lowest uptime). Output
     is `status/metrics.json` + a rendered `status/highlights.md`.
     **No LLM, no external network, no third-party action.**
  4. **Renders a self-contained `dashboard.html`** with the metrics
     inlined as JSON. Vanilla CSS (light + dark via
     `prefers-color-scheme`), small inline JS for table sort. No
     `fetch()`, no CDN — the page must work offline if saved.
     Deployed every hour to GitHub Pages by a separate
     `deploy_dashboard` job (split because `actions/deploy-pages@v4`
     requires its own `environment:` block).
  5. Opens a `suite-failure`-labelled issue per failing suite (deduped
     by title), comments on repeats, and auto-closes issues whose
     suite has recovered.
- `pages-deploy.yml` is a **consumer probe**, not a deployer — the
  deploy side is exercised every hour by `_aggregate.yml`. The probe
  fetches the published Pages URL via `curl` and asserts the dashboard
  body contains the expected title and `metrics.json` link. Skips
  cleanly on first run before any dashboard exists. There can only be
  one Pages deployment per repo, so the inversion is mandatory — do
  not turn this back into a deployer.

## Conventions

- **Filenames:** `kebab-case.yml`. Top-level orchestration files are
  prefixed with `_` (`_scheduler.yml`, `_aggregate.yml`).
- **Job IDs:** `snake_case`, descriptive (`assert_oidc_claims`, not `job1`).
- **Step names:** Imperative sentence case (`Request OIDC token`, not
  `oidc`). Step names appear in logs and in failure annotations.
- **Shell:** Default to `bash` everywhere via `defaults.run.shell: bash`.
  Bash is on the Windows runner image. Use `pwsh`/`cmd` only when
  Windows-specific behaviour is the point.
- **Strict mode:** Every bash step starts with `set -euo pipefail` (the
  default shell already does this when `defaults.run.shell: bash` is set,
  but be explicit in `run:` blocks that span many lines).
- **Permissions:** Each workflow declares the minimum `permissions:` it
  needs at the workflow or job level. Default to `contents: read`.
- **Concurrency:** Suites that mutate shared state (issues, branches) use
  `concurrency:` to avoid stepping on parallel runs.
- **Timeouts:** Every job sets `timeout-minutes:` (default 10). Hung jobs
  burn enterprise minutes.
- **Outputs:** Suites under test report a single `result` step output
  (`pass` / `fail`) so the aggregator can read them uniformly.

## How to add a new test workflow

1. Add the workflow file under `.github/workflows/` following naming and
   conventions above.
2. Make it callable: include `on: { workflow_call: {}, workflow_dispatch: {} }`
   so the scheduler can invoke it via `uses:` and a human can run it
   manually.
3. End every job with a PASS/FAIL summary line and a non-zero exit on
   failure.
4. Add a row to `docs/FEATURE-MATRIX.md`.
5. Add a `uses: ./.github/workflows/your-file.yml` job to `_scheduler.yml`
   (with `secrets: inherit` if it needs any).
6. If the suite is gated, add the variable to `docs/ENTERPRISE-SETUP.md`
   and the README's gated-suites table.
7. If it's gated, also gate the scheduler job: `if: vars.YOUR_GATE != ''`.
8. **Add a row to the contracts table in `.github/workflows/_self-test.yml`**
   asserting the substring(s) that prove the suite tests its declared
   feature (e.g. for a new caching test, assert it contains
   `actions/cache@`). The contracts are the line of defence against a
   "fix" that silently removes the assertion logic.

## Self-tests

Static contract tests live in `.github/workflows/_self-test.yml` and run
on every push that touches `.github/workflows/**`, `.github/scripts/**`,
or `tests/**`. They assert:

- **First-party-only invariant.** Every `uses:` is `./`, `actions/*`,
  or `github/*`. Catches drift away from the rule the moment it lands.
- **`timeout-minutes` set on every workflow.** Hung jobs burn
  enterprise minutes; the scheduler can't cancel them in time.
- **No orphan suites.** Every workflow under `.github/workflows/` is
  either called from `_scheduler.yml` or in the documented exempt set
  (orchestration, callees, trigger-only probes).
- **Per-suite feature-token contracts.** Each suite must contain the
  substring(s) that prove it tests what it claims to test (e.g.
  `cache.yml` must reference `actions/cache@` and `restore-keys`).
- **Local action.yml contracts.** The composite/docker/JS action suites
  delegate to local actions under `.github/actions/<name>/action.yml` —
  those are where `using:` lives, so we contract them there.
- **`metrics.jq` and `highlights.jq` are syntactically valid jq** and
  run cleanly against a real fixture snapshot.
- **Metrics regression test.** `tests/run-metrics-tests.sh` runs
  `metrics.jq` against `tests/fixtures/snapshots/*.json` (5 hourly
  fixtures designed to exercise every code path: stable green, stable
  red ≥3h, flapper, new-failure, and recovery) and asserts 39
  specific values in the output. Catches any regression in uptime,
  streak, flake, MTTR, or highlights logic.

`metrics.jq` and `highlights.jq` live in `.github/scripts/` so the
aggregator and the test share one source of truth — there is no
inline copy in `_aggregate.yml`.

### `_issue-lifecycle-test.yml` — issue API probe

A standalone probe that runs **weekly (Mon 06:00 UTC)** and on manual
dispatch. It exercises the exact `gh` surface `_aggregate.yml` relies on
to manage `suite-failure` issues: open → read → comment → list comments
→ close `--reason completed` → re-read. Each phase prints a `PASS:` /
`FAIL:` line and the workflow exits non-zero if any phase fails.

- **What it proves:** `GITHUB_TOKEN` still has `issues: write`;
  `gh issue create/comment/close` and `gh api repos/:o/:r/issues/...`
  still behave as the aggregator expects. A green run means the next
  hourly rollup can still open and close failure issues.
- **Why it's not in `_scheduler.yml`:** it's its own probe with its own
  trigger and label namespace (`selftest-lifecycle`). Wiring it into
  the hourly rollup would let a token regression here mask every other
  suite's status. It is therefore listed in the Test 3 exempt set in
  `_self-test.yml` (carried in `.github/scripts/check-contracts.sh`).
- **Reading a red weekly run:** check the failing `PASS/FAIL` line in
  the job summary. Most likely cause is a permissions regression
  (token can no longer write issues) or a `gh` CLI behaviour change on
  the runner image. The cleanup `trap` closes the probe issue even on
  failure, so a red run should not leave open `selftest-lifecycle`
  issues — if it does, that itself is a finding worth investigating.

## How to debug a failing suite

1. Open the `suite-failure`-labelled issue for the broken workflow → the
   most recent comment links to the failing run.
2. Cross-reference with the latest snapshot on the `status` branch
   (`status/YYYY/MM/DD/HH.md`) for the surrounding context (which other
   suites failed at the same hour).
3. The job summary at the top of the run lists every assertion. Look for
   `FAIL:` lines.
4. If the failure is environmental (rate limit, transient 5xx from the API),
   re-run the failed jobs only. The aggregator will pick up the new
   conclusion on its next pass and auto-close the issue.
5. If the failure is real, write the fix as a workflow change. The auto-
   managed issue closes itself on recovery; no manual close needed.

## Notes for LLM sessions

- The session-state plan lives in
  `~/.copilot/session-state/<id>/plan.md` and a SQL `todos` table. Both
  are kept in sync. Update both when you change scope.
- When you add or modify a workflow, **lint it locally** if `actionlint`
  is available (it isn't required to ship, but it catches typos):
  `actionlint .github/workflows/*.yml`.
- Don't add a CI job that runs the full suite on PR — it would consume
  enterprise minutes and the suite is already self-scheduled. PR
  validation should be limited to actionlint + a dry-run of the
  scheduler with `--dry-run` flags.
- Don't introduce shared helper composite actions just to DRY up
  assertions. Inline `bash` is more debuggable; the suite is small.
- If you find yourself wanting to add a third-party action "just this
  once", stop. Either write a local action or use `gh` + shell. There
  are zero exceptions to rule #1.
