{ lib
, stdenvNoCC
, fetchFromGitHub
, sassc
, glib
, libxml2
, gtk3
, getent
, which
  # Founder-palette tint (SHOA-1094): accent + dark surface colors are single
  # sass variables in the pinned source, so the theme can be tinted at build
  # time with NO new assets. Defaults are the vanilla vinceliuice values, so
  # the package alone still builds vanilla.
, tint ? {
    accent = "#0088FF";
    onAccent = "#ffffff";
    base = "#242424";
    bg = "#333333";
    text = "#dadada";
    fg = "#dedede";
  }
}:

stdenvNoCC.mkDerivation {
  pname = "mactahoe-gtk-theme";
  version = "2026-08-08";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "MacTahoe-gtk-theme";
    rev = "2026-08-08";
    hash = "sha256-UEJZFXCVox3KCTZqSeOILumKCbUIeDTzcbLjimtotEI=";
  };

  nativeBuildInputs = [ sassc glib libxml2 gtk3 getent which ];

  dontBuild = true;
  dontFixup = true;

  postPatch = ''
    substituteInPlace libs/lib-core.sh \
      --replace-fail 'MY_HOME=$(getent passwd "''${MY_USERNAME}" | cut -d: -f6)' 'MY_HOME="$HOME"' \
      --replace-fail 'SUDO_BIN="$(which sudo)"' 'SUDO_BIN=""' \
      --replace-fail 'if [[ ! -w "/root" ]]; then' 'if false; then'

    # Founder-palette tint (SHOA-1094): accent + dark surface colors are
    # single sass variables in the pinned source — no new assets needed.
    substituteInPlace src/sass/_colors-palette.scss \
      --replace-fail '$theme_color_default: #0088FF;' '$theme_color_default: ${tint.accent};'

    substituteInPlace src/sass/_colors.scss \
      --replace-fail '$base_color:                        if($variant == 'light', #ffffff, if($darker == 'true', #1f1f1f, #242424));' '$base_color:                        if($variant == 'light', #ffffff, ${tint.base});' \
      --replace-fail '$text_color:                        if($variant == 'light', #363636, #dadada);' '$text_color:                        if($variant == 'light', #363636, ${tint.text});' \
      --replace-fail '$bg_color:                          if($variant == 'light', #f5f5f5, if($darker == 'true', #282828, #333333));' '$bg_color:                          if($variant == 'light', #f5f5f5, ${tint.bg});' \
      --replace-fail '$fg_color:                          if($variant == 'light', #242424, #dedede);' '$fg_color:                          if($variant == 'light', #242424, ${tint.fg});' \
      --replace-fail '$selected_fg_color:                 $light_fg_color;' '$selected_fg_color:                 ${tint.onAccent};'
    patchShebangs install.sh libs/lib-install.sh libs/lib-core.sh
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/themes
    HOME=$TMPDIR ./install.sh --dest $out/share/themes --silent-mode -c dark -o normal
    runHook postInstall
  '';

  meta = with lib; {
    description = "MacOS Tahoe-like GTK theme (dark variant), founder-palette tinted at build time via sass variables (SHOA-1094)";
    homepage = "https://github.com/vinceliuice/MacTahoe-gtk-theme";
    license = licenses.gpl3Only;
    platforms = platforms.unix;
  };
}
