#!/usr/bin/env python3
"""Behavioural tests for this repository's agent safety hooks.

The generic half of this file is template scaffolding: it exercises every hook
in `repo-policy` against *this* repository's `.claude/hooks/policy.json`, so the
suite is meaningful without being rewritten. Add repository-specific tests below
the marker at the end and register them in `main`.

Run it before committing a hook or policy change:

    python3 scripts/test-agent-hooks.py

Exit 0 means every case held. Any failure raises `AssertionError` naming the
hook, the payload and what came back.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / ".claude" / "hooks"
LIB = HOOKS / "lib"
TESTS = 0
SKIPPED: list[str] = []

sys.path.insert(0, str(LIB))

from repo_policy import Policy, PolicyError, load  # noqa: E402


# --------------------------------------------------------------------------
# Harness
# --------------------------------------------------------------------------


def run_hook(
    hook: str,
    payload: dict[str, object] | str,
    expected: int,
    *messages: str,
    hooks_dir: Path = HOOKS,
    project_dir: Path = ROOT,
    silent: bool = False,
) -> None:
    global TESTS
    hook_input = payload if isinstance(payload, str) else json.dumps(payload)
    env = {**os.environ, "CLAUDE_PROJECT_DIR": str(project_dir)}
    env.pop("MULTICA_POLICY_DIR", None)
    result = subprocess.run(
        [str(hooks_dir / hook)],
        input=hook_input,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )
    if result.returncode != expected:
        raise AssertionError(
            f"{hook}: expected exit {expected}, got {result.returncode}\n"
            f"payload: {hook_input[:400]}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    for message in messages:
        if message not in result.stderr:
            raise AssertionError(f"{hook}: missing {message!r} in stderr:\n{result.stderr}")
    if silent and result.stderr.strip():
        raise AssertionError(f"{hook}: expected no advisory, got:\n{result.stderr}")
    TESTS += 1


def bash(command: str) -> dict[str, object]:
    return {"tool_name": "Bash", "tool_input": {"command": command}}


def write(path: Path, content: str) -> dict[str, object]:
    return {"tool_name": "Write", "tool_input": {"file_path": str(path), "content": content}}


def tracked_files() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    return [entry for entry in out.split("\0") if entry]


def transcript(directory: Path, *entries: dict[str, object]) -> str:
    path = directory / "transcript.jsonl"
    path.write_text(
        "".join(f"{json.dumps(entry)}\n" for entry in entries),
        encoding="utf-8",
    )
    return str(path)


def assistant(*tool_uses: tuple[str, dict[str, object]]) -> dict[str, object]:
    return {
        "type": "assistant",
        "message": {
            "content": [
                {"type": "tool_use", "name": name, "input": tool_input}
                for name, tool_input in tool_uses
            ]
        },
    }


# --------------------------------------------------------------------------
# Generic cases — every repository that adopts repo-policy runs these
# --------------------------------------------------------------------------


def test_policy_loads() -> Policy:
    global TESTS
    policy = load(HOOKS)
    assert policy.repository.strip(), "policy.json `repository` is still the placeholder or empty"
    assert not policy.repository.startswith("REPLACE ME"), "policy.json `repository` is unfilled"
    TESTS += 1
    return policy


def test_policy_fails_closed() -> None:
    """A hook whose policy is missing or malformed denies rather than allows."""
    with tempfile.TemporaryDirectory() as raw:
        broken = Path(raw) / "hooks"
        shutil.copytree(HOOKS, broken)
        (broken / "policy.json").write_text("{ not json", encoding="utf-8")
        run_hook("block-runtime.sh", bash("echo hi"), 2, "not valid JSON", hooks_dir=broken)
        (broken / "policy.json").unlink()
        run_hook("block-runtime.sh", bash("echo hi"), 2, "policy.json", hooks_dir=broken)
        run_hook(
            "block-config-commentary.sh",
            write(ROOT / "README.md", "text\n"),
            2,
            "policy.json",
            hooks_dir=broken,
        )


def test_block_runtime(policy: Policy) -> None:
    run_hook("block-runtime.sh", bash("git status"), 0, silent=True)
    run_hook("block-runtime.sh", bash(""), 0, silent=True)
    run_hook("block-runtime.sh", "not json", 2, "not valid JSON")
    if not policy.blocked_commands:
        SKIPPED.append("block-runtime: policy.json blocks no executables")
        return
    for name in policy.blocked_commands:
        run_hook("block-runtime.sh", bash(f"{name} --help"), 2, name)
        run_hook("block-runtime.sh", bash(f"/usr/bin/{name} --help"), 2, name)
        run_hook("block-runtime.sh", bash(f"bash -lc '{name} --help'"), 2, name)
        run_hook("block-runtime.sh", bash(f"true && {name} --help"), 2, name)
        # A heredoc body is data, not code.
        run_hook("block-runtime.sh", bash(f"cat > n.md <<'EOF'\ndo not run {name}\nEOF"), 0)


def test_block_git_unsafe() -> None:
    run_hook("block-git-unsafe.sh", bash("git status --short"), 0, silent=True)
    run_hook("block-git-unsafe.sh", bash("git commit -m 'fix'"), 0, silent=True)
    run_hook("block-git-unsafe.sh", bash("git commit --no-verify -m 'fix'"), 2, "--no-verify")
    run_hook("block-git-unsafe.sh", bash("git commit -n -m 'fix'"), 2, "--no-verify")
    run_hook("block-git-unsafe.sh", bash("git push --force origin HEAD"), 2, "force-pushing")
    run_hook("block-git-unsafe.sh", bash("git push --force-with-lease"), 2, "force-pushing")
    run_hook("block-git-unsafe.sh", bash("git push origin :main"), 2, "deletes that ref")
    run_hook("block-git-unsafe.sh", bash("git reset --hard HEAD~1"), 2, "discards uncommitted work")
    run_hook("block-git-unsafe.sh", bash("git clean -fd"), 2, "deletes untracked files")
    run_hook("block-git-unsafe.sh", bash("git stash"), 2, "one stash stack")
    run_hook("block-git-unsafe.sh", bash("git stash pop"), 2, "another session's entry")
    run_hook("block-git-unsafe.sh", bash("git checkout ."), 2, "discards every uncommitted change")
    run_hook("block-git-unsafe.sh", bash("git filter-branch --all"), 2, "rewrites every commit")
    run_hook("block-git-unsafe.sh", bash("bash -c 'git push --force'"), 2, "force-pushing")


def test_block_gh_unsafe() -> None:
    run_hook("block-gh-unsafe.sh", bash("gh pr list"), 0, silent=True)
    run_hook("block-gh-unsafe.sh", bash("gh api repos/shockstruck/x"), 0, silent=True)
    run_hook("block-gh-unsafe.sh", bash("gh auth status"), 0, silent=True)
    run_hook("block-gh-unsafe.sh", bash("gh api -X DELETE repos/shockstruck/x"), 2, "mutates GitHub")
    run_hook("block-gh-unsafe.sh", bash("gh api -X PATCH repos/shockstruck/x"), 2, "mutates GitHub")
    run_hook("block-gh-unsafe.sh", bash("gh secret set FOO"), 2, "Actions secrets")
    run_hook("block-gh-unsafe.sh", bash("gh repo delete shockstruck/x"), 2, "destroys the repository")
    run_hook("block-gh-unsafe.sh", bash("gh workflow run ci.yaml"), 2, "mutates CI")
    run_hook("block-gh-unsafe.sh", bash("gh pr merge 1 --admin"), 2, "branch protection")
    run_hook("block-gh-unsafe.sh", bash("gh auth token"), 2, "GitHub credentials")


def test_block_config_commentary(policy: Policy) -> None:
    files = tracked_files()
    if not files:
        SKIPPED.append("block-config-commentary: git could not list tracked files")
        return

    identifier_target = next((f for f in files if policy.checks_task_identifiers(f)), None)
    if identifier_target and policy.task_prefixes:
        path = ROOT / identifier_target
        existing = path.read_text(encoding="utf-8", errors="replace")
        run_hook("block-config-commentary.sh", write(path, existing), 0, silent=True)
        run_hook(
            "block-config-commentary.sh",
            write(path, f"{existing}\n{policy.task_prefixes[0]}-1234\n"),
            2,
            "task identifier",
        )
    else:
        SKIPPED.append("block-config-commentary: no tracked file in taskIdentifiers.paths")

    comment_target = next((f for f in files if policy.checks_comments(f)), None)
    if comment_target:
        path = ROOT / comment_target
        existing = path.read_text(encoding="utf-8", errors="replace")
        run_hook(
            "block-config-commentary.sh",
            write(path, f"{existing}\n# why this change was made\n"),
            2,
            "adds a comment",
        )
        if policy.comment_directives:
            directive = policy.comment_directives[0]
            run_hook(
                "block-config-commentary.sh",
                write(path, f"{existing}\n# {directive} allowed\n"),
                0,
                silent=True,
            )
    else:
        SKIPPED.append("block-config-commentary: no tracked file in comments.paths")

    # A path outside every guarded list is never the hook's business.
    run_hook(
        "block-config-commentary.sh",
        write(Path("/tmp/outside-the-repository.yaml"), "# a comment\n"),
        0,
        silent=True,
    )


def test_require_validation_before_git(policy: Policy) -> None:
    with tempfile.TemporaryDirectory() as raw:
        directory = Path(raw)
        target = str(ROOT / "README.md")

        # Push is gated on a fetch since the last push, in every repository.
        no_fetch = transcript(directory, assistant(("Bash", {"command": "git push HEAD:main"})))
        run_hook(
            "require-validation-before-git.sh",
            {
                "tool_name": "Bash",
                "tool_input": {"command": "git push HEAD:main"},
                "transcript_path": no_fetch,
            },
            2,
            "no `git fetch`",
        )
        fetched = transcript(
            directory,
            assistant(("Bash", {"command": "git fetch origin"})),
            assistant(("Bash", {"command": "git push HEAD:main"})),
        )
        run_hook(
            "require-validation-before-git.sh",
            {
                "tool_name": "Bash",
                "tool_input": {"command": "git push HEAD:main"},
                "transcript_path": fetched,
            },
            0,
            silent=True,
        )
        run_hook(
            "require-validation-before-git.sh",
            bash("git fetch origin && git push HEAD:main"),
            0,
            silent=True,
        )

        if policy.validation_pattern is None:
            SKIPPED.append(
                "require-validation-before-git: policy.json sets no validation.commandPattern, "
                "so the commit gate is off"
            )
            return

        sample = policy.validation_hint or ""
        command = next(
            (
                candidate
                for candidate in _validation_candidates(policy, sample)
                if policy.validation_pattern.search(candidate)
            ),
            None,
        )
        if command is None:
            raise AssertionError(
                "validation.hint names no command that validation.commandPattern matches; the "
                "denial would tell an agent to run something the gate does not recognise"
            )

        unvalidated = transcript(
            directory, assistant(("Write", {"file_path": target, "content": "x"}))
        )
        run_hook(
            "require-validation-before-git.sh",
            {
                "tool_name": "Bash",
                "tool_input": {"command": "git commit -m x"},
                "transcript_path": unvalidated,
            },
            2,
            "`git commit` is gated",
        )
        validated = transcript(
            directory,
            assistant(("Write", {"file_path": target, "content": "x"})),
            assistant(("Bash", {"command": command})),
        )
        run_hook(
            "require-validation-before-git.sh",
            {
                "tool_name": "Bash",
                "tool_input": {"command": "git commit -m x"},
                "transcript_path": validated,
            },
            0,
            silent=True,
        )
        # An unreadable transcript cannot show the gate was met, so it blocks.
        run_hook(
            "require-validation-before-git.sh",
            {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}},
            2,
            "transcript",
        )


def _validation_candidates(policy: Policy, hint: str) -> list[str]:
    """Command strings drawn from the hint, longest first, plus the raw hint."""
    words = [
        token.strip("`,.;:()")
        for token in hint.replace("`", " ` ").split()
        if token.strip("`,.;:()")
    ]
    fragments = [hint]
    for size in (4, 3, 2, 1):
        fragments.extend(
            " ".join(words[start : start + size]) for start in range(0, max(len(words) - size + 1, 0))
        )
    return [fragment for fragment in fragments if fragment]


def test_probity_fails_closed() -> None:
    """No config and no `probity` on PATH is a denial, never a silent pass."""
    with tempfile.TemporaryDirectory() as raw:
        empty = Path(raw)
        run_hook(
            "probity.sh",
            bash("echo hi"),
            2,
            "probity.config.ts",
            project_dir=empty,
        )


def test_settings_registers_every_hook() -> None:
    global TESTS
    settings = json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))
    registered = {
        Path(entry["command"].strip('"')).name
        for event in settings.get("hooks", {}).values()
        for matcher in event
        for entry in matcher.get("hooks", [])
        if isinstance(entry.get("command"), str)
    }
    required = {
        "block-runtime.sh",
        "block-git-unsafe.sh",
        "block-gh-unsafe.sh",
        "block-config-commentary.sh",
        "require-validation-before-git.sh",
        "probity.sh",
    }
    missing = required - registered
    assert not missing, f".claude/settings.json does not register: {sorted(missing)}"
    # No gate may wait for a person: an `ask` rule stalls an unattended run.
    assert "ask" not in settings.get("permissions", {}), (
        "permissions.ask stalls an unattended agent run; every gate must allow or deny on "
        "automated criteria"
    )
    TESTS += 1


# --------------------------------------------------------------------------
# Repository-specific cases — add yours below and register them in main()
# --------------------------------------------------------------------------


def test_block_nix_realise() -> None:
    """AGENTS.md's "cheap validation only" rule, enforced rather than stated."""
    # The permitted ceiling stays open.
    run_hook("block-nix-realise.sh", bash("nix fmt -- --check flake.nix"), 0, silent=True)
    run_hook("block-nix-realise.sh", bash("just lint"), 0, silent=True)
    run_hook("block-nix-realise.sh", bash("nix flake show --no-write-lock-file"), 0, silent=True)
    run_hook("block-nix-realise.sh", bash("nix flake metadata"), 0, silent=True)
    run_hook("block-nix-realise.sh", bash("bash -n install.sh"), 0, silent=True)
    run_hook("block-nix-realise.sh", bash("nix eval .#packages.x86_64-linux.default.name"), 0)

    for command, needle in (
        ("nix build .#nixosConfigurations.desktop", "`nix build`"),
        ("nix run", "`nix run`"),
        ("nix develop", "`nix develop`"),
        ("nix shell nixpkgs#jq", "`nix shell`"),
        ("nix profile install nixpkgs#jq", "`nix profile`"),
        ("nix repl", "`nix repl`"),
        ("nix flake check", "`nix flake check`"),
        ("nix flake update", "`nix flake update`"),
        ("nixos-rebuild switch --flake .#desktop", "`nixos-rebuild`"),
        ("just run", "`just run`"),
        ("just check", "`just check`"),
        ("just update", "`just update`"),
        ("just dev", "`just dev`"),
        ("nix eval .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath", "`nix eval`"),
    ):
        run_hook("block-nix-realise.sh", bash(command), 2, needle)

    # Wrappers and chains are inspected, prose is not.
    run_hook("block-nix-realise.sh", bash("bash -lc 'nix build .#x'"), 2, "`nix build`")
    run_hook("block-nix-realise.sh", bash("true && nix flake check"), 2, "`nix flake check`")
    run_hook(
        "block-nix-realise.sh",
        bash("cat > note.md <<'EOF'\nnever run nix build here\nEOF"),
        0,
        silent=True,
    )


def test_activation_is_denied_by_permission_too() -> None:
    """Two layers: the hook denies the command, the deny rule never lets it start."""
    global TESTS
    deny = set(
        json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))["permissions"][
            "deny"
        ]
    )
    for rule in (
        "Bash(nixos-rebuild *)",
        "Bash(nixos-install *)",
        "Bash(home-manager *)",
        "Bash(disko *)",
        "Bash(nix build *)",
        "Bash(nix run *)",
    ):
        assert rule in deny, f"{rule} is no longer denied"
    TESTS += 1


def main() -> int:
    try:
        policy = test_policy_loads()
    except PolicyError as exc:
        print(f"FAIL  .claude/hooks/policy.json: {exc}")
        return 1

    test_policy_fails_closed()
    test_block_runtime(policy)
    test_block_git_unsafe()
    test_block_gh_unsafe()
    test_block_config_commentary(policy)
    test_require_validation_before_git(policy)
    test_probity_fails_closed()
    test_settings_registers_every_hook()

    test_block_nix_realise()
    test_activation_is_denied_by_permission_too()

    for note in SKIPPED:
        print(f"SKIP  {note}")
    print(f"PASS  {TESTS} hook cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
