# Copilot instructions — actions-testcases

This repo is a forkable GitHub Actions stability test suite. An hourly
`_scheduler.yml` invokes ~30 feature-area sub-workflows; `_aggregate.yml`
collects results, computes deterministic metrics with `jq`, and renders a
self-contained Pages dashboard. **Read `AGENTS.md` first** — it is the
authoritative spec; this file is a distilled cheat-sheet.

## Hard rules

1. **First-party actions only.** Every `uses:` must be `./` (local),
   `actions/*`, or `github/*`. No third-party actions, ever.
2. **Pin first-party actions to a major version** (`@v4`, not `@main`).
3. **Fork-and-go.** Anything that needs configuration must be optional
   and gated by a `vars.*` check. The default fork must work with zero
   setup.
4. **No external network I/O.** No `curl example.com`, no `npm install`
   from a public registry inside a suite. Use `gh` and the runner image.
5. **Tests must assert.** Every job ends with an explicit
   PASS/FAIL line and exits non-zero on failure. "It ran" is not a pass.
6. **One workflow per feature area.** Don't pile features into one file.

## Layout

```
.github/
  workflows/
    _scheduler.yml        # hourly orchestrator (workflow_call/dispatch)
    _aggregate.yml        # workflow_run on _scheduler → metrics + dashboard + issues
    _self-test.yml        # static contract tests (push to workflows/scripts/tests)
    _issue-lifecycle-test.yml  # weekly gh issue API probe
    pages-deploy.yml      # CONSUMER probe (not a deployer; aggregator deploys)
    <feature>.yml         # one suite per feature (cache, matrix, oidc, ...)
  actions/<name>/action.yml  # local composite/docker/JS actions
  scripts/
    metrics.jq            # SINGLE source of truth for metrics
    highlights.jq         # markdown highlights renderer
    check-contracts.sh    # extracted self-test contract logic
tests/
  run-metrics-tests.sh    # 39+ assertions on metrics.jq output
  run-negative-tests.sh   # mutation harness: proves checkers catch breakage
  fixtures/snapshots/0[1-5].json  # hand-crafted hourly fixtures
docs/
  FEATURE-MATRIX.md       # what each suite tests
  ENTERPRISE-SETUP.md     # gated suites + required vars
```

## Conventions

- `kebab-case.yml` filenames; `_` prefix for orchestration.
- `snake_case` job IDs, descriptive names.
- `defaults.run.shell: bash` everywhere (bash is on the Windows image).
- `set -euo pipefail` at the top of every multi-line `run:` block.
- Minimal `permissions:` per workflow; default `contents: read`.
- `timeout-minutes:` on **every** job (default 10).
- `concurrency:` on suites that mutate shared state (issues, branches).

## When adding a new test workflow

Follow **AGENTS.md → "How to add a new test workflow"** — all 8 steps.
The easy ones to forget:

- **Step 4:** add a row to `docs/FEATURE-MATRIX.md`.
- **Step 5:** wire into `_scheduler.yml` (or add to the exempt set in
  `.github/scripts/check-contracts.sh` if it's a standalone probe).
- **Step 8:** add a contracts-table row in `check-contracts.sh` —
  the substring(s) that prove the suite still tests its declared
  feature. Without this, a "fix" can silently delete the assertion.

## Before pushing any change

1. `actionlint .github/workflows/*.yml` — must be clean.
2. `bash tests/run-metrics-tests.sh` — must be green if you touched
   `metrics.jq`, `highlights.jq`, or any fixture under
   `tests/fixtures/`.
3. `bash tests/run-negative-tests.sh` — must be green if you touched
   `check-contracts.sh`, `metrics.jq`, or the negative harness.
4. The push will trigger `_self-test.yml` — watch it.

## Don'ts

- Don't introduce a third-party action "just this once."
- Don't inline a copy of `metrics.jq` / `highlights.jq` into a
  workflow — both must `jq -f "$GITHUB_WORKSPACE/.github/scripts/*.jq"`
  so the regression test guards production code.
- Don't add a CI job that runs the full suite on PR — it's already
  self-scheduled hourly.
- Don't turn `pages-deploy.yml` back into a deployer. There's only
  one Pages deployment per repo and the aggregator owns it.
- Don't use `${{ ... }}` to interpolate untrusted input into `run:`
  blocks. Pass via `env:` and reference `$VAR`.
- Don't force-push `main`. The status branch is force-pushed on
  purpose; `main` is not.

## jq gotchas (bitten us before)

- `def name: body;` must be at the **top** of the program. Mid-pipeline
  `| def ...` is a syntax error.
- Inside `map(group_by(...))`, `.` is an *array*, not a record. Use
  explicit `{workflow: $latest.workflow, ...}`, not `{workflow}` shorthand.
- `jq -n` makes input `null` — `.[]` on `null` blows up. Use a real
  fixture for syntax checks.

## Co-author trailer

All commits authored with Copilot help must include:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
