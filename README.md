# actions-testcases

[![Actions suite](https://github.com/harricross/actions-testcases/actions/workflows/_scheduler.yml/badge.svg)](https://github.com/harricross/actions-testcases/actions/workflows/_scheduler.yml)

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
| `ENABLE_PAGES` | GitHub Pages deployment suite |
| `ENABLE_ATTESTATIONS` | Build provenance attestations suite |

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
completion and produces three things:

- **A committed snapshot** on a dedicated [`status` branch](../../tree/status).
  Each hour writes `status/YYYY/MM/DD/HH.json` (machine-readable) +
  `HH.md` (rendered). Daily and monthly rollup markdown files live one
  level up. The `main` branch is never touched.
- **Per-failing-suite issues** labelled `suite-failure`. One issue per
  failing workflow, deduplicated by title. Each subsequent failure adds
  a comment; when the suite recovers, the issue auto-closes with a
  recovery comment.
- **Per-suite step summaries** in the Actions UI (every workflow writes
  PASS/FAIL lines to `$GITHUB_STEP_SUMMARY`).

The badge above reflects the latest `_scheduler.yml` run conclusion.

## Contributing

Read [`AGENTS.md`](./AGENTS.md) before opening a PR. The first-party-only
rule is non-negotiable: the suite's value depends on it.
