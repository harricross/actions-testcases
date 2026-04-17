#!/bin/sh
set -eu

who="${1:-world}"
greeting="hello ${who} from docker action"
echo "${greeting}"

# Workflow command form: write to GITHUB_OUTPUT (mounted into the container).
if [ -n "${GITHUB_OUTPUT:-}" ] && [ -w "${GITHUB_OUTPUT}" ]; then
  printf 'greeting=%s\n' "${greeting}" >> "${GITHUB_OUTPUT}"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -w "${GITHUB_STEP_SUMMARY}" ]; then
  printf '## docker-smoke\n%s\n' "${greeting}" >> "${GITHUB_STEP_SUMMARY}"
fi
