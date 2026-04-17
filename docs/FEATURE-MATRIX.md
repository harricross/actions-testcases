# Feature matrix

Every shippable GitHub Actions capability mapped to the workflow that
exercises it. If a row is missing, the suite has a gap — open a PR.

| # | Feature area | Workflow | Gated by |
|---|---|---|---|
| 1 | Schedule trigger (cron) | `_scheduler.yml` | — |
| 2 | `workflow_dispatch` w/ all input types | `triggers-manual.yml` | — |
| 3 | `workflow_call` (reusable workflow) | `triggers-workflow-call.yml` + `reusable-caller.yml` | — |
| 4 | `workflow_run` chained trigger | `triggers-workflow-run.yml` | — |
| 5 | `push` + `pull_request` + branch & path filters | `triggers-push.yml` | — |
| 6 | `issues`, `issue_comment`, `label`, `repository_dispatch` | `triggers-events.yml` | — |
| 7 | Ubuntu / Windows / macOS hosted runners + shells | `runners-os-matrix.yml` | — |
| 8 | Classic self-hosted runner | `runners-self-hosted.yml` | `vars.SELF_HOSTED_LABEL` |
| 9 | Actions Runner Controller (ARC) | `runners-arc.yml` | `vars.ARC_RUNNER_LABEL` |
| 10 | Larger hosted runners | `runners-larger.yml` | `vars.LARGER_RUNNER_LABEL` |
| 11 | `container:` job + `services:` containers | `runners-container.yml` | — |
| 12 | Matrix strategies (incl./excl., dynamic, reusable, output aggregation, fail-fast) | `matrix-strategies.yml` | — |
| 13 | Expressions + every context | `expressions-contexts.yml` | — |
| 14 | `needs` DAG, outputs, `if`, `continue-on-error`, `timeout-minutes` | `job-orchestration.yml` | — |
| 15 | `concurrency` group + cancel-in-progress | `concurrency.yml` | — |
| 16 | `permissions:` / `GITHUB_TOKEN` scopes | `permissions-token.yml` | — |
| 17 | Repo + environment-scoped secrets/vars + masking | `secrets-and-vars.yml` | — |
| 18 | Environments + approvals | `environments-approval.yml` | `vars.APPROVAL_ENVIRONMENT` |
| 19 | OIDC token issuance + claim assertions | `oidc-cloud.yml` | — |
| 20 | `actions/upload-artifact` + `actions/download-artifact` (v4) | `artifacts.yml` | — |
| 21 | `actions/cache` save / restore / restore-keys | `cache.yml` | — |
| 22 | Workflow commands (`::notice`, `::group`, masking, env, path, output) | `workflow-commands.yml` | — |
| 23 | `$GITHUB_STEP_SUMMARY` + file annotations | `step-summary-annotations.yml` | — |
| 24 | Local composite action | `composite-action-test.yml` | — |
| 25 | Local Dockerfile action | `docker-action-test.yml` | — |
| 26 | Local JavaScript action | `javascript-action-test.yml` | — |
| 27 | Build provenance attestations | `artifacts-attestations.yml` | `vars.ENABLE_ATTESTATIONS` |
| 28 | Dependency submission API | `dependency-graph.yml` | — |
| 29 | GitHub Pages deploy | `pages-deploy.yml` | `vars.ENABLE_PAGES` |
| 30 | Aggregation + badge + tracking issue | `_aggregate.yml` | — |

## Cross-OS coverage

These workflows run as a matrix over `[ubuntu-latest, windows-latest, macos-latest]`:

- `artifacts.yml`
- `cache.yml`
- `workflow-commands.yml`
- `step-summary-annotations.yml`
- `expressions-contexts.yml`
- `composite-action-test.yml`
- `javascript-action-test.yml`
- `concurrency.yml`

Linux-only by hosted-runner platform constraint:

- `runners-container.yml` (services / container jobs)
- `docker-action-test.yml` (Dockerfile actions)
