#!/usr/bin/env bash
# PreToolUse(Bash): block the `nix` and `just` subcommands that realise a
# derivation, enter a dev shell or activate the configuration.
#
# AGENTS.md states the rule: an evaluation, build or activation here takes an
# hour or more, CI and the human own that gate, and an agent must never burn a
# run on one. Until now that rule was prose. `nix fmt` — the permitted ceiling —
# stays open, as do the read-only flake queries an agent genuinely needs.
#
# Repository-specific: the template's block-runtime.sh denies whole
# executables, and `nix` is not one this repository can lose. The wrapper
# unwrapping comes from the template's lib/shell_command.py, so `bash -c`,
# `xargs` and clause chains are inspected the same way every other Bash hook
# inspects them.
set -euo pipefail

if ! HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"; then
  echo "[block-nix-realise] hook library is missing; refusing to allow the command" >&2
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

from shell_command import Denial, walk  # noqa: E402

GATE = (
    "AGENTS.md: an evaluation, build or activation here takes an hour or more, and CI plus the "
    "human own that gate. Change the source, run `nix fmt -- --check <paths>`, and hand off. If a "
    "change genuinely needs a real build to be safe, say so in the handoff and let CI run it."
)

# `nix <subcommand>` forms that realise a derivation or change the running system.
NIX = {
    "build": "`nix build` realises a derivation.",
    "run": "`nix run` activates the configuration through nixos-unified.",
    "develop": "`nix develop` builds the whole dev shell closure.",
    "shell": "`nix shell` realises every package it names.",
    "profile": "`nix profile` installs into the user profile, changing the running workstation.",
    "repl": "`nix repl` evaluates interactively and can realise a derivation with no record of it.",
}
# `nix flake <action>` forms. `show`, `metadata` and `archive --json` stay open.
NIX_FLAKE = {
    "check": "`nix flake check` builds every check output.",
    "update": "`nix flake update` rewrites flake.lock, and every later evaluation rebuilds.",
}
# `just` recipes that wrap the above.
JUST = {
    "run": "`just run` is `nix run`.",
    "check": "`just check` is `nix flake check`.",
    "update": "`just update` is `nix flake update`.",
    "dev": "`just dev` is `nix develop`.",
}
# `nix eval` is cheap unless it is asked for a derivation path.
EVAL_MARKERS = ("toplevel", "drvPath", "outPath")


def deny(message: str) -> None:
    sys.stderr.write(f"[block-nix-realise] {message}\n")
    sys.exit(2)


try:
    payload = json.load(os.fdopen(3))
except (json.JSONDecodeError, OSError):
    deny("hook input was not valid JSON; refusing to skip the build check")

tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    deny("hook tool_input was not an object; refusing to skip the build check")
cmd = tool_input.get("command") or ""
if not isinstance(cmd, str):
    deny("Bash command was not text")
if not cmd.strip():
    sys.exit(0)


def operands(arguments: list[str]) -> list[str]:
    return [token for token in arguments if not token.startswith("-")]


def visit(executable: str, arguments: list[str]) -> None:
    words = operands(arguments)
    first = words[0] if words else ""
    second = words[1] if len(words) > 1 else ""

    if executable == "nix":
        if first in NIX:
            raise Denial(f"{NIX[first]} {GATE}")
        if first == "flake" and second in NIX_FLAKE:
            raise Denial(f"{NIX_FLAKE[second]} {GATE}")
        if first == "eval" and any(marker in " ".join(arguments) for marker in EVAL_MARKERS):
            raise Denial(
                "`nix eval` of a `toplevel`, `drvPath` or `outPath` evaluates the whole "
                f"configuration. {GATE}"
            )
        return

    if executable == "nixos-rebuild":
        raise Denial(f"`nixos-rebuild` builds or activates the running system. {GATE}")

    if executable == "just" and first in JUST:
        raise Denial(f"{JUST[first]} {GATE}")


try:
    walk(cmd, visit)
except Denial as denial:
    deny(denial.message)

sys.exit(0)
PYEOF
status=$?
set -e
if [[ ${status} -ne 0 && ${status} -ne 2 ]]; then
  echo "[block-nix-realise] internal hook failure; refusing to allow the command" >&2
  exit 2
fi
exit "${status}"
