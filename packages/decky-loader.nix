# Decky Loader — the Steam Deck plugin loader (SteamDeckHomebrew/decky-loader),
# for the console's Unifideck plugin (packages/unifideck.nix).
#
# Not in nixpkgs at the pinned rev (verified: no `decky` / `SteamDeckHomebrew`
# path or content match). Vendored from Jovian-NixOS's derivation
# (Jovian-Experiments/Jovian-NixOS, branch `development`,
# `pkgs/decky-loader/default.nix`, both hashes copied verbatim) rather than
# taken as a flake input, to avoid pulling Jovian's whole overlay for one
# package.
#
# postPatch below adds two `--replace-fail` edits to
# backend/decky_loader/helpers.py (confirmed present verbatim at v3.2.8),
# lifted from sabrsorensen/nix-dendrites'
# modules/platforms/steamdeck/_steamdeck/decky-loader/_steamdeck-decky-loader.nix:
# `get_system_pythonpaths()` shells out to a bare `python3` with an empty
# `env={}`, which fails outside a login shell with $PATH set — Nix's Python
# has no `python3` alongside it on PATH by default at the store path decky's
# subprocess call resolves against. The first edit makes that call use an
# absolute store `python3`; the second restores $PATH so that interpreter can
# still find its own stdlib/site-packages. Jovian's own systemctl
# substitutions are skipped: this derivation's service (module) puts
# `systemd` on decky-loader's PATH instead, so the bare `systemctl` calls in
# localplatformlinux.py resolve without a source patch.
#
# Pin/update path:
#   1. Diff Jovian-NixOS's `pkgs/decky-loader/default.nix` on `development`
#      against this file; if the two `--replace-fail` target strings still
#      match `backend/decky_loader/helpers.py` at the new `rev`, bump
#      `version`/`rev`/both hashes verbatim from Jovian's file.
#   2. Refresh hashes (SRI form) with `nix store prefetch-file`/`lib.fakeHash`
#      + one build, same as `packages/opengameinstaller.nix`.
{ lib
, fetchFromGitHub
, nodejs
, pnpm_11
, fetchPnpmDeps
, pnpmConfigHook
, python3
, coreutils
, psmisc
, systemd
}:
python3.pkgs.buildPythonPackage rec {
  pname = "decky-loader";
  version = "3.2.8";

  src = fetchFromGitHub {
    owner = "SteamDeckHomebrew";
    repo = "decky-loader";
    rev = "v${version}";
    hash = "sha256-Y2dMTKLXtZAyXuWhnS/jbqjCYyWvSChslt/YxIBbWXw=";
  };

  # confuses our pnpm tooling
  postPatch = ''
    rm frontend/pnpm-workspace.yaml

    substituteInPlace backend/decky_loader/helpers.py \
      --replace-fail '["python3" if localplatform.ON_LINUX else "python", "-c",' '["${python3}/bin/python3" if localplatform.ON_LINUX else "python", "-c",' \
      --replace-fail 'env={} if localplatform.ON_LINUX else None' 'env={"PATH": os.environ.get("PATH", "")} if localplatform.ON_LINUX else None'
  '';

  pnpmDeps = fetchPnpmDeps {
    fetcherVersion = 4;
    inherit pname version src;

    # copy here because of sourceRoot
    postPatch = ''
      rm pnpm-workspace.yaml
    '';

    pnpm = pnpm_11;
    sourceRoot = "${src.name}/frontend";
    hash = "sha256-OHimg85kcjk+Tq1Yv8TA9CfPDVzxdgPpzTi2mxyPs4s=";
  };

  pyproject = true;

  pnpmRoot = "frontend";

  nativeBuildInputs = [
    nodejs
    pnpm_11
    pnpmConfigHook
  ];

  preBuild = ''
    cd frontend
    pnpm build
    cd ../backend
  '';

  build-system = with python3.pkgs; [
    poetry-core
    poetry-dynamic-versioning
  ];

  dependencies = with python3.pkgs; [
    aiohttp
    aiohttp-cors
    aiohttp-jinja2
    certifi
    multidict
    packaging
    setproctitle
    watchdog
  ];

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ coreutils psmisc systemd ]}"
  ];

  pythonRelaxDeps = [
    "aiohttp-cors"
    "packaging"
    "watchdog"
  ];

  passthru.python = python3;

  meta = with lib; {
    description = "A plugin loader for the Steam Deck";
    homepage = "https://github.com/SteamDeckHomebrew/decky-loader";
    platforms = platforms.linux;
    license = licenses.gpl2Only;
  };
}
