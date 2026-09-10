# AGENTS

Authoritative agent-contribution guidance for this NixOS configuration repo.
Applies to every agent (Claude, Codex, etc.); `CLAUDE.md` is a symlink to this
file.

## Validation policy — cheap validation only

Nix compiles/realises and CI runs each take an hour or more. Agents must not
burn a run on them. Formatting is the only local validation you run; CI
and the human are the compile/build/activation gate.

### Prohibited during iteration

Do not run any command that triggers a full evaluation, derivation build, or
activation — each takes 1h+:

- `nix run` (and `just run`) — activates the configuration via nixos-unified
- `nixos-rebuild switch|build|test|dry-build|boot`
- `nix build` / `nix build .#…`
- `home-manager switch|build`
- `nix flake check` (and `just check`)
- `nix eval` of a configuration `toplevel` / `drvPath`
- `nix develop`, `nix flake update` (and `just update`) as a "verify" step
- any other command that realises a derivation

Do not wait for or poll CI to go green before proceeding or handing off. CI also
takes 1h+. Push your change and hand off; never block a run on CI.

### Permitted validation — the ceiling

- `nix fmt` — the flake's configured formatter (`nixpkgs-fmt`); `just lint` runs
  the same thing. Use `nix fmt -- --check <paths>` to check without writing,
  mirroring the CI formatting step.
- Pure formatting/lint and markdown edits need no build at all.

### Who owns the build gate

CI (`.github/workflows/ci.yaml`) and the human perform the eval, build, and
activation. Agents rely on `nix fmt` plus careful review of the diff — never on a
local build. If you believe a change genuinely needs a real build to be safe, say
so in your handoff and let CI/the human run it; do not run it yourself.

## Agent policy: what is enforced, and where it comes from

`.claude/` comes from the shared template in `shockstruck/agent-platform`, `repo-policy/template/`.
The hook scripts and `.claude/hooks/lib/` are byte-identical to it and a weekly drift check reports
any local edit. Everything this repository tunes lives in `.claude/hooks/policy.json` — change the
template, not the copy.

The "cheap validation only" rule above is no longer only prose:

| Hook | Denies |
|---|---|
| `block-nix-realise.sh` | `nix build/run/develop/shell/profile/repl`, `nix flake check/update`, `nix eval` of a `toplevel`/`drvPath`/`outPath`, `nixos-rebuild`, `just run/check/update/dev` |
| `block-runtime.sh` | `nixos-rebuild`, `nixos-install`, `home-manager`, `disko`, and the cluster CLIs, per `policy.json` |
| `block-git-unsafe.sh` | force-push, `--no-verify`, `reset --hard`, `clean -f`, ref deletion, history rewrites |
| `block-gh-unsafe.sh` | `gh api -X <write>`, `gh secret set`, `gh workflow run`, `gh pr merge --admin`, `gh repo delete` |
| `require-validation-before-git.sh` | `git commit` with no `nix fmt` / `just lint` / `bash -n install.sh` since the last write; `git push` with no `git fetch` since the last push |
| `block-config-commentary.sh` | a write that adds a Multica task identifier to a committed file |
| `probity.sh` | a commit whose session writes bundle unrelated work (AI-judged) |

`nix fmt`, `just lint`, `nix flake show`, `nix flake metadata`, `nix-instantiate --parse` and a
plain `nix eval` of a cheap attribute all stay open. The same commands are also in
`permissions.deny`, so a blocked build never starts even if a hook is bypassed.

**No gate waits for a person.** Every hook allows or denies on automated criteria and says why.
There is no `permissions.ask` and no approval token: an unattended run has no one to answer a
prompt. If a check is wrong, change it in a pull request and say why.

Run `python3 scripts/test-agent-hooks.py` after any change under `.claude/` — it is cheap and
realises nothing.
