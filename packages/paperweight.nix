{
  appimageTools,
  fetchurl,
  lib,
  makeWrapper,
}:
let
  pname = "paperweight";
  version = "0.5.0";

  src = fetchurl {
    url = "https://github.com/wslyvh/paperweight/releases/download/v${version}/Paperweight-${version}.AppImage";
    hash = "sha256-oURDW3fSgwHnwQDzhlO3hHMvx94ooXjYqgl5sqwku38=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    install -Dm 644 ${appimageContents}/paperweight.desktop $out/share/applications/paperweight.desktop
    install -Dm 644 ${appimageContents}/paperweight.png $out/share/icons/hicolor/512x512/apps/paperweight.png
    substituteInPlace $out/share/applications/paperweight.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=paperweight %U'
    wrapProgram "$out/bin/paperweight" --add-flags "--no-sandbox"
  '';

  meta = {
    description = "Local-first tool for managing your digital footprint";
    homepage = "https://www.paperweight.email";
    changelog = "https://github.com/wslyvh/paperweight/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "paperweight";
    platforms = [ "x86_64-linux" ];
  };
}
