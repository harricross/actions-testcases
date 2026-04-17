# Enterprise setup

The default fork runs the entire suite **without any configuration** on the
hosted runner pool. Suites that depend on enterprise-only infrastructure are
skipped until you opt them in via repo **variables** (Settings → Secrets and
variables → Actions → Variables).

Variables are used (not secrets) deliberately: nothing here is sensitive,
and variables show up in the Actions UI which makes it easy to see what's
enabled.

## Variables

| Variable | Example value | Enables |
|---|---|---|
| `SELF_HOSTED_LABEL` | `linux-x64-shared` | Classic self-hosted runner suite (`runners-self-hosted.yml`). The label must be present on at least one runner in the org or repo. |
| `ARC_RUNNER_LABEL` | `arc-runner-set` | Actions Runner Controller suite (`runners-arc.yml`). The label must match an `AutoscalingRunnerSet` (gha-runner-scale-set) deployed in your cluster. |
| `LARGER_RUNNER_LABEL` | `ubuntu-latest-4-cores` | Larger hosted runner suite (`runners-larger.yml`). Must match a runner group your org has provisioned. |
| `APPROVAL_ENVIRONMENT` | `production-test` | Environments-and-approvals suite (`environments-approval.yml`). Create an environment with this name; optional reviewer rules are detected at runtime. |
| `ENABLE_PAGES` | `true` | GitHub Pages deploy suite (`pages-deploy.yml`). Requires Pages to be enabled for the repo (Settings → Pages → Source: GitHub Actions). |
| `ENABLE_ATTESTATIONS` | `true` | Build provenance attestations (`artifacts-attestations.yml`). Requires GHES 3.13+ or GHEC. |

## Secrets

The core suite needs **no secrets**. The workflows use the
auto-provisioned `GITHUB_TOKEN`, which is sufficient for issues, comments,
labels, branches, dispatches, OIDC token requests, and Pages deploys.

If you want the tracking issue and badge to live in a different repository,
add a fine-grained PAT with `issues:write` to the repo as the secret
`STATUS_REPO_TOKEN` and set the variable `STATUS_REPO` to `owner/repo`.
The aggregator will use those when present and fall back to the local repo
otherwise.

## ARC quick-start

If you don't already have ARC, the minimum to wire up `runners-arc.yml` is:

1. Install `gha-runner-scale-set-controller` Helm chart in your cluster.
2. Install a `gha-runner-scale-set` Helm release scoped to this repo (or
   the org), giving the runner-set a memorable name. The release name
   becomes the label workflows use.
3. Set `ARC_RUNNER_LABEL` in this repo's variables to that release name.

Detailed steps are in the [ARC docs](https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller).

## Self-hosted runner expectations

`runners-self-hosted.yml` only runs `bash`, `git`, and `gh`. It does **not**
install anything. If your self-hosted image lacks `gh`, the suite will
report a real failure (which is the correct behaviour — your image is
out of spec for hosting Actions workflows).

## What happens after you set a variable

The next scheduler run (top of the hour, or `gh workflow run _scheduler.yml`)
will pick up the gate change and start running the newly-enabled suite.
The aggregator will add it to the tracking issue's table on the run after
that.

## Disabling a suite again

Delete the variable. The suite will revert to skipping with a "gate not
set" summary line; the aggregator will mark it `skipped` (not failed).
