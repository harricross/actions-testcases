# actions-testcases

[![Actions suite](https://github.com/harricross/actions-testcases/actions/workflows/_scheduler.yml/badge.svg)](https://github.com/harricross/actions-testcases/actions/workflows/_scheduler.yml)
[![Aggregator](https://github.com/harricross/actions-testcases/actions/workflows/_aggregate.yml/badge.svg)](https://github.com/harricross/actions-testcases/actions/workflows/_aggregate.yml)

> 🔗 **[Live dashboard](https://harricross.github.io/actions-testcases/)** ·
> 📊 **[Latest highlights](https://github.com/harricross/actions-testcases/blob/status/status/README.md)** ·
> 🗂️ **[Status branch](https://github.com/harricross/actions-testcases/tree/status)** ·
> 📁 **[Hourly snapshots](https://github.com/harricross/actions-testcases/tree/status/status)** ·
> 🐛 **[Failing suites](https://github.com/harricross/actions-testcases/issues?q=is%3Aissue+is%3Aopen+label%3Asuite-failure)**

Hourly, **fork-and-go** smoke suite that exercises every shippable GitHub
Actions feature. Designed to run unmodified inside a GitHub Enterprise (GHES
or GHEC-EMU) tenancy so platform owners can detect regressions before users do.

> **First-party only.** Workflows here use **only** `actions/*` and `github/*`
> actions plus shell + `gh` CLI. No Marketplace dependencies, ever. See
> [`AGENTS.md`](./AGENTS.md) for the rationale and the rule for future
> contributors / LLM sessions.

## What it tests

A top-level `_scheduler.yml` workflow runs every hour and orchestrates ~30
sub-workflows, each focused on one Actions capability. A separate
`_aggregate.yml` workflow rolls the results up into a single tracking issue
(`actions-suite: status`) and the badge above.

See [`docs/FEATURE-MATRIX.md`](./docs/FEATURE-MATRIX.md) for the full
feature → workflow mapping.

Highlights:

- Every trigger type — `schedule`, `workflow_dispatch`, `workflow_call`,
  `workflow_run`, `repository_dispatch`, `push`, `pull_request`, `issues`,
  `issue_comment`, `label`.
- Hosted runners — Ubuntu, Windows, macOS, larger runners.
- Self-hosted runners — classic and **Actions Runner Controller (ARC)**.
- Container jobs and service containers.
- Matrix strategies — `include`/`exclude`, dynamic, fail-fast, output
  aggregation, matrix-over-reusable-workflow.
- Reusable workflows, composite actions, Dockerfile actions, JavaScript
  actions (all local — no Marketplace).
- Permissions, OIDC token issuance, environments and approvals.
- Artifacts (v4), cache, workflow commands, step summaries, annotations.
- Cross-OS coverage where the OS matters (paths, shells, line endings).

## Fork and run

1. Fork this repo into your enterprise.
2. Enable Actions in **Settings → Actions → General** (Allow all actions
   created by GitHub is sufficient — no Marketplace required).
3. The hourly schedule starts on its own. To run immediately:
   `gh workflow run _scheduler.yml`.
4. Watch the [tracking issue](../../issues?q=is%3Aissue+%22actions-suite%3A+status%22)
   the aggregator opens after the first run.

### Optional: enable gated suites

Suites that need enterprise-only infrastructure are skipped unless the
matching repo **variable** is set (Settings → Secrets and variables →
Actions → Variables). All variables are documented in
[`docs/ENTERPRISE-SETUP.md`](./docs/ENTERPRISE-SETUP.md).

| Variable | Enables |
|---|---|
| `SELF_HOSTED_LABEL` | Classic self-hosted runner suite |
| `ARC_RUNNER_LABEL` | Actions Runner Controller suite |
| `LARGER_RUNNER_LABEL` | Larger hosted runner suite |
| `APPROVAL_ENVIRONMENT` | Environments + approvals suite |
| `ENABLE_ATTESTATIONS` | Build provenance attestations suite |

> GitHub Pages is now used for the **live dashboard** (deployed every
> hour by `_aggregate.yml`). Enable it once at
> *Settings → Pages → Source: GitHub Actions*. The `pages-deploy.yml`
> suite then probes the published dashboard URL on every run.

## Repository layout

```
.github/
  workflows/        # one workflow per feature area + _scheduler + _aggregate
  actions/          # local composite / docker / javascript action under test
  ISSUE_TEMPLATE/   # used by triggers-events.yml
docs/
  FEATURE-MATRIX.md     # feature → workflow mapping
  ENTERPRISE-SETUP.md   # variables / secrets to enable gated suites
AGENTS.md           # contributor + LLM-session notes (READ THIS FIRST)
```

## Reading the results

The aggregator workflow (`_aggregate.yml`) runs after every `_scheduler.yml`
completion and produces four things:

- **A live HTML dashboard** at
  [`harricross.github.io/actions-testcases`](https://harricross.github.io/actions-testcases/),
  re-rendered every hour. Per-suite uptime (24h / 7d / 30d), current
  streak, flake count, and MTTR — sortable, with deep links to the
  failing run. Single self-contained page, no external JS.
- **Highlights** computed deterministically from the snapshot history:
  new failures, recoveries, long red streaks, flakiest suites, lowest
  uptime. Surfaced at the top of [`status/README.md`](https://github.com/harricross/actions-testcases/blob/status/status/README.md),
  in every aggregator run summary, and as an "Highlights" section in the
  hourly snapshot.
- **A committed snapshot** on a dedicated [`status` branch](../../tree/status).
  Each hour writes `status/YYYY/MM/DD/HH.json` (machine-readable) +
  `HH.md` (rendered). Daily and monthly rollup markdown files live one
  level up. `status/metrics.json` always holds the latest derived
  metrics. The `main` branch is never touched.
- **Per-failing-suite issues** labelled `suite-failure`. One issue per
  failing workflow, deduplicated by title. Each subsequent failure adds
  a comment; when the suite recovers, the issue auto-closes with a
  recovery comment.

The badges above reflect the latest scheduler and aggregator run
conclusions. The dashboard is also the source of truth for "is the
suite happy right now?"

## Contributing

Read [`AGENTS.md`](./AGENTS.md) before opening a PR. The first-party-only
rule is non-negotiable: the suite's value depends on it.
