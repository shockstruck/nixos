#!/usr/bin/env bash
# PreToolUse(Bash): block Git commands that bypass review gates or destroy work.
# Never bypass hooks, force-push, amend someone else's work, or revert unrelated
# changes. Wrappers (`bash -c`, `eval`, `xargs`, `&&` chains) are inspected
# through lib/shell_command.py, the same walker block-runtime.sh uses.
#
# Template file: identical in every repository that adopts repo-policy. Change
# it in shockstruck/agent-platform, not here.
set -euo pipefail

if ! HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"; then
  echo "[block-git-unsafe] hook library is missing; refusing to allow the command" >&2
  exit 2
fi
export HOOK_LIB_DIR

CLAUDE_HOOK_PAYLOAD="$(cat)"

set +e
python3 - 3<<<"${CLAUDE_HOOK_PAYLOAD}" <<'PYEOF'
import json
import os
import sys

sys.path.insert(0, os.environ["HOOK_LIB_DIR"])

from git_command import invocations, parse  # noqa: E402
from shell_command import Denial  # noqa: E402

PROTECTED_BRANCHES = {"main", "master", "origin/main"}


def deny(message: str) -> None:
    sys.stderr.write(f"[block-git-unsafe] {message}\n")
    sys.exit(2)


try:
    payload = json.load(os.fdopen(3))
except (json.JSONDecodeError, OSError):
    deny("hook input was not valid JSON; refusing to skip the Git safety check")

tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    deny("hook tool_input was not an object; refusing to skip the Git safety check")
cmd = tool_input.get("command") or ""
if not isinstance(cmd, str):
    deny("Bash command was not text")
if not cmd.strip():
    sys.exit(0)


def check(name: str, arguments: list[str]) -> None:
    if name == "commit":
        flags, longs, _ = parse(
            arguments,
            "mFCct",
            {
                "--author",
                "--cleanup",
                "--date",
                "--file",
                "--fixup",
                "--message",
                "--pathspec-from-file",
                "--reedit-message",
                "--reuse-message",
                "--squash",
                "--template",
                "--trailer",
            },
        )
        if "--no-verify" in longs or "n" in flags:
            deny(
                "`git commit --no-verify` bypasses the pre-commit gate. Fix what the hook "
                "reports instead of skipping it."
            )
        return

    if name == "push":
        flags, longs, operands = parse(
            arguments,
            "o",
            {"--exec", "--push-option", "--receive-pack", "--repo"},
        )
        if "--force" in longs or "--force-with-lease" in longs or "f" in flags:
            deny(
                "force-pushing rewrites published history. Fetch the default branch, integrate "
                "without force, then push."
            )
        if "--mirror" in longs:
            deny(
                "`git push --mirror` replaces every ref on the remote with this checkout's set, "
                "deleting the ones it does not have. Push the branch you mean, by name."
            )
        if "--delete" in longs or "d" in flags:
            deny(
                "`git push --delete` removes a branch or tag from the remote, and with it the "
                "review history that points at it. Ask the repository owner before deleting a "
                "published ref."
            )
        if any(operand.startswith(":") for operand in operands):
            deny(
                "an empty-source refspec (`:ref`) deletes that ref on the remote. Name the source "
                "and destination explicitly, as in `HEAD:main`."
            )
        return

    if name == "clean":
        flags, longs, _ = parse(arguments, "e", {"--exclude"})
        if "f" in flags or "--force" in longs:
            deny(
                "`git clean -f` deletes untracked files outright, including work this session has "
                "not committed. List them with `git clean -n`, then remove the specific paths."
            )
        return

    if name == "worktree":
        flags, longs, operands = parse(arguments, "b", {"--reason"})
        action = operands[0] if operands else ""
        if action == "remove" and ("f" in flags or "--force" in longs):
            deny(
                "`git worktree remove --force` discards a worktree that still holds uncommitted "
                "changes, and another session may own it. Commit or move that work first."
            )
        return

    if name == "update-ref":
        flags, longs, _ = parse(arguments, "m", {"--reason"})
        if "d" in flags or "--delete" in longs:
            deny(
                "`git update-ref -d` deletes a ref with no reflog entry to recover it from. "
                "Delete a branch with `git branch -d`, which leaves one."
            )
        return

    if name in ("filter-branch", "filter-repo"):
        deny(
            f"`git {name}` rewrites every commit in the history and breaks every published ref "
            "and review link. Never force-push or rewrite published history."
        )

    if name == "reset":
        _, longs, _ = parse(arguments)
        if "--hard" in longs:
            deny(
                "`git reset --hard` discards uncommitted work with no recovery path. Restore the "
                "specific path, or commit the work first and reset to that commit."
            )
        return

    if name == "stash":
        _, _, operands = parse(arguments, "m", {"--message"})
        action = operands[0] if operands else ""
        if not action:
            deny(
                "bare `git stash` shares one stash stack with every other worktree and session on "
                "this agent home. Use `git stash push -u -m <unique-tag>`, or a temporary WIP commit."
            )
        if action == "pop":
            deny(
                "`git stash pop` can pop another session's entry from the shared stash stack. "
                "Find your entry by tag and use `git stash apply <sha>`, then drop it."
            )
        return

    if name in ("checkout", "restore"):
        value_letters = "bB" if name == "checkout" else "s"
        _, _, operands = parse(arguments, value_letters, {"--orphan", "--source", "--track"})
        if "." in operands:
            deny(
                f"`git {name} .` discards every uncommitted change in the worktree. Restore the "
                "specific path you meant instead."
            )
        return

    if name == "branch":
        flags, longs, operands = parse(arguments, "uUt", {"--contains", "--set-upstream-to", "--sort"})
        forced = "D" in flags or (
            ("d" in flags or "--delete" in longs) and ("f" in flags or "--force" in longs)
        )
        if forced and PROTECTED_BRANCHES.intersection(operands):
            deny(
                "force-deleting the mainline branch destroys the only local copy of reviewed work. "
                "Delete the topic branch instead."
            )
        return


try:
    for invocation in invocations(cmd):
        check(invocation.subcommand, invocation.arguments)
except Denial as denial:
    deny(denial.message)

sys.exit(0)
PYEOF
status=$?
set -e
if [[ ${status} -ne 0 && ${status} -ne 2 ]]; then
  echo "[block-git-unsafe] internal hook failure; refusing to allow the command" >&2
  exit 2
fi
exit "${status}"
