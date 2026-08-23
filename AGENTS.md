# AGENTS

Authoritative agent-contribution guidance for this NixOS configuration repo.
Applies to every agent (Claude, Codex, etc.); `CLAUDE.md` is a symlink to this
file.

## Validation policy — cheap validation only

Nix compiles/realises and CI runs each take an hour or more. Agents must not
burn a heartbeat on them. Formatting is the only local validation you run; CI
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
takes 1h+. Push your change and hand off; never block a heartbeat on CI.

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
