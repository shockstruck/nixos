{ lib
, stdenvNoCC
, makeWrapper
, jq
, niri
}:
stdenvNoCC.mkDerivation {
  pname = "niri-ror";
  version = "0-unstable-2026-01-08";

  # Repo-owned copy of https://github.com/boomskats/niri-ror (commit
  # 60fbab405120b2b6d2c54672e7ea74232df52dd7). Vendored verbatim rather than
  # fetched at build time — the upstream project has no releases/tags and is
  # a handful of small, auditable files, so pinning a copy in-tree avoids an
  # extra network fetch + hash pin for something this size. Update by
  # re-copying ror.sh/ws.jq/lib/*.jq from a newer upstream commit and bumping
  # `version` above.
  src = ./niri-ror/src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  doCheck = false;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    # ror.sh resolves sibling files (`lib/`, `ws.jq`) relative to its own
    # directory at runtime (`script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"`),
    # so they're installed alongside the renamed entrypoint under $out/bin
    # rather than into a separate libexec/share directory.
    install -Dm755 ror.sh "$out/bin/niri-ror"
    install -Dm644 ws.jq "$out/bin/ws.jq"
    install -Dm644 lib/filters.jq "$out/bin/lib/filters.jq"
    install -Dm644 lib/operators.jq "$out/bin/lib/operators.jq"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/niri-ror" \
      --prefix PATH : ${lib.makeBinPath [ jq niri ]}
  '';

  meta = {
    description = "Run-or-raise (ROR) helper script for the niri Wayland compositor";
    homepage = "https://github.com/boomskats/niri-ror";
    # Upstream carries no LICENSE file as of the vendored commit; leaving
    # `meta.license` unset rather than guessing.
    mainProgram = "niri-ror";
    platforms = lib.platforms.linux;
  };
}
