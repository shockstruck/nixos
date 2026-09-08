#!/usr/bin/env bash
# PreToolUse(Bash): gate `git commit` and `git push` on what the session already ran.
# Commit is gated on this repository's validation having run after the last
# write; push is gated on a `git fetch` or `git pull` since the last push. Both
# gates read the session transcript through lib/transcript.py; an unreadable
# transcript is a block, because it cannot show the gate was met.
#
# Which commands count as validation is `validation.commandPattern` in
# .claude/hooks/policy.json, this repository's slot; an empty pattern turns the
# commit gate off and leaves the push gate in force.
#
# Template file: identical in every repository that adopts repo-policy. Change
# it in shockstruck/agent-platform, not here.
set -euo pipefail

if ! HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"; then
  echo "[require-validation-before-git] hook library is missing; refusing to allow the command" >&2
  exit 2
fi
export HOOK_LIB_DIR

CLAUDE_HOOK_PAYLOAD="$(cat)"

set +e
python3 - 3<<<"${CLAUDE_HOOK_PAYLOAD}" <<'PYEOF'
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ["HOOK_LIB_DIR"])

from git_command import invocations  # noqa: E402
from repo_policy import PolicyError, load  # noqa: E402
from shell_command import Denial  # noqa: E402
from transcript import TranscriptError, last_index, read_tool_uses, writes_under  # noqa: E402


def deny(message: str) -> None:
    sys.stderr.write(f"[require-validation-before-git] {message}\n")
    sys.exit(2)


try:
    policy = load()
except PolicyError as exc:
    deny(f"{exc}; refusing to skip the validation gate")

VALIDATION_COMMAND = policy.validation_pattern
VALIDATION_HINT = policy.validation_hint.strip() or "this repository's validation commands"

try:
    payload = json.load(os.fdopen(3))
except (json.JSONDecodeError, OSError):
    deny("hook input was not valid JSON; refusing to skip the validation gate")

tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    deny("hook tool_input was not an object; refusing to skip the validation gate")
cmd = tool_input.get("command") or ""
if not isinstance(cmd, str):
    deny("Bash command was not text")
if not cmd.strip():
    sys.exit(0)

try:
    current = invocations(cmd)
except Denial as denial:
    deny(denial.message)

gates = {invocation.subcommand for invocation in current}.intersection({"commit", "push"})
if VALIDATION_COMMAND is None:
    gates.discard("commit")
if not gates:
    sys.exit(0)

# A chained command carries its own evidence: `<validation> && git commit`, or
# `git fetch origin && git push HEAD:main`.
if "commit" in gates and VALIDATION_COMMAND.search(cmd):
    gates.discard("commit")
if "push" in gates:
    order = [invocation.subcommand for invocation in current]
    if any(name in ("fetch", "pull") for name in order[: order.index("push")]):
        gates.discard("push")
if not gates:
    sys.exit(0)

project_root = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")).resolve()
missing = "a validation run" if "commit" in gates else "a `git fetch`"
try:
    uses = read_tool_uses(payload.get("transcript_path"))
except TranscriptError as exc:
    deny(
        f"{exc}. Without the session history this hook cannot show that {missing} preceded "
        f"`git {sorted(gates)[0]}`; run {VALIDATION_HINT} and retry in a session with a readable "
        "transcript."
    )

# The pending call is already in the transcript. Drop its last occurrence so the
# gate is measured against what ran before it, and no earlier one is lost.
pending = last_index(uses, lambda use: use.name == "Bash" and use.input.get("command") == cmd)
if pending >= 0:
    uses = uses[:pending] + uses[pending + 1 :]


def is_validation(use) -> bool:
    return (
        use.name == "Bash"
        and isinstance(use.input.get("command"), str)
        and VALIDATION_COMMAND.search(use.input["command"]) is not None
    )


def runs_git(use, *names: str) -> bool:
    if use.name != "Bash" or not isinstance(use.input.get("command"), str):
        return False
    return any(
        invocation.subcommand in names
        for invocation in invocations(use.input["command"], strict=False)
    )


if "commit" in gates:
    wrote = writes_under(project_root)
    write_at = last_index(uses, wrote)
    if write_at >= 0 and last_index(uses, is_validation, write_at) < 0:
        written = uses[write_at].input.get("file_path") or uses[write_at].input.get("notebook_path")
        deny(
            f"`git commit` is gated: `{written}` was written after the last validation run in this "
            f"session. Run {VALIDATION_HINT} for the changed surface, then commit."
        )

if "push" in gates:
    push_at = last_index(uses, lambda use: runs_git(use, "push"))
    if last_index(uses, lambda use: runs_git(use, "fetch", "pull"), max(push_at, 0)) < 0:
        since = "since the last `git push`" if push_at >= 0 else "in this session"
        deny(
            f"`git push` is gated: no `git fetch` or `git pull` {since}. Fetch the default branch, "
            "integrate without force, rerun affected validation if the base moved, then push."
        )

sys.exit(0)
PYEOF
status=$?
set -e
if [[ ${status} -ne 0 && ${status} -ne 2 ]]; then
  echo "[require-validation-before-git] internal hook failure; refusing to allow the command" >&2
  exit 2
fi
exit "${status}"
