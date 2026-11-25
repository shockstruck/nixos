# shellcheck shell=bash

# Runs before the first job step. The runner supplies its own GITHUB_* context,
# not a workflow's `env:`, so a job in any other repository or on any other
# server must not continue: print one fixed line and terminate every process
# this user can signal. Linux does not signal the calling process, so the
# fallback exit below runs even when the signal is refused.
if [ "${GITHUB_REPOSITORY_ID:-}" = "1207177553" ] && [ "${GITHUB_SERVER_URL:-}" = "https://github.com" ]; then
  exit 0
fi

printf '%s\n' "Project Alpha runner job started outside the pinned repository" >&2
builtin kill -KILL -1 || true
exit 1
