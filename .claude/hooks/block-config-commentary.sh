#!/usr/bin/env bash
# PreToolUse(Write|Edit): keep change rationale and task identifiers out of the
# files this repository guards. Blocks only what the edit ADDS: a new
# non-directive `#` comment under `comments.paths`, or a new task identifier
# under `taskIdentifiers.paths`. Pre-existing lines never trip the hook.
#
# Both path lists are this repository's slots in .claude/hooks/policy.json; the
# rule itself lives in lib/config_commentary.py.
#
# Template file: identical in every repository that adopts repo-policy. Change
# it in shockstruck/agent-platform, not here.
set -euo pipefail

if ! HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"; then
  echo "[block-config-commentary BLOCK] hook library is missing; refusing to allow the write" >&2
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

from config_commentary import in_scope, violations  # noqa: E402
from repo_policy import PolicyError, load  # noqa: E402

DEFAULT_GUIDANCE = (
    "Change rationale belongs in the pull request body, not in a guarded file, and task "
    "identifiers never enter the repository."
)


def deny(message: str) -> None:
    sys.stderr.write(f"[block-config-commentary BLOCK] {message}\n")
    sys.exit(2)


try:
    policy = load()
except PolicyError as exc:
    deny(f"{exc}; refusing to skip the commentary check")

try:
    payload = json.load(os.fdopen(3))
except (json.JSONDecodeError, OSError):
    deny("hook input was not valid JSON; refusing to skip the commentary check")

tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    deny("hook tool_input was not an object; refusing to skip the commentary check")

raw_path = tool_input.get("file_path") or ""
if not isinstance(raw_path, str) or not raw_path:
    sys.exit(0)

project_root = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")).resolve()
path = Path(raw_path)
if not path.is_absolute():
    path = project_root / path
path = path.resolve()
try:
    relative = path.relative_to(project_root).as_posix()
except ValueError:
    sys.exit(0)
if not in_scope(relative, policy):
    sys.exit(0)

try:
    existing = path.read_text(encoding="utf-8")
except FileNotFoundError:
    existing = ""
except (OSError, UnicodeError) as exc:
    deny(f"cannot read {relative} to compare the proposed edit: {exc}")

tool_name = payload.get("tool_name") or ""
if tool_name == "Write":
    candidate = tool_input.get("content") or ""
elif tool_name == "Edit":
    old = tool_input.get("old_string") or ""
    new = tool_input.get("new_string") or ""
    if old and old in existing:
        candidate = (
            existing.replace(old, new)
            if tool_input.get("replace_all")
            else existing.replace(old, new, 1)
        )
    else:
        deny(f"cannot reconstruct the proposed edit for {relative}; use a full, reviewable edit")
else:
    deny(f"unsupported tool `{tool_name}` for the commentary check")

if not isinstance(candidate, str):
    deny("proposed file content was not text")

found = violations(relative, existing, candidate, policy)
if found:
    for violation in found[:20]:
        sys.stderr.write(f"[block-config-commentary BLOCK] {relative}: {violation}\n")
    if len(found) > 20:
        sys.stderr.write(
            f"[block-config-commentary BLOCK] {relative}: and {len(found) - 20} more\n"
        )
    guidance = policy.comment_guidance.strip() or DEFAULT_GUIDANCE
    allowed = ", ".join(f"`# {prefix}`" for prefix in policy.comment_directives)
    if allowed:
        guidance = f"{guidance} Only the {allowed} directives may be added here."
    sys.stderr.write(f"[block-config-commentary BLOCK] {guidance}\n")
    sys.exit(2)

sys.exit(0)
PYEOF
status=$?
set -e
if [[ ${status} -ne 0 && ${status} -ne 2 ]]; then
  echo "[block-config-commentary BLOCK] internal hook failure; refusing to allow the write" >&2
  exit 2
fi
exit "${status}"
