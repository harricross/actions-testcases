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
  3. Opens a `suite-failure`-labelled issue per failing suite (deduped
     by title), comments on repeats, and auto-closes issues whose
     suite has recovered.

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
