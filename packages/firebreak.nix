{ lib
, python3Packages
, fetchPypi
, android-tools
}:
python3Packages.buildPythonApplication rec {
  pname = "firebreak";
  version = "1.3.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-6dS2oikHw2Obu8LAKi3UZJebfsR9nXCsVOW02slZl14=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    pyserial
    pyusb
  ];

  # firebreak pins exact versions; nixpkgs carries its own. The update checker
  # is optional (its import is wrapped in contextlib.suppress) and the wrapper
  # passes --no-update-check, so it is left out.
  pythonRemoveDeps = [ "update-checker" ];

  # The emOS child process is re-exec'd with PYTHONPATH=child_path(), which
  # assumes a flat source tree. In the Nix store the dependencies live on
  # sys.path instead, so hand the child the whole path.
  postPatch = ''
    substituteInPlace firebreak/host.py \
      --replace-fail 'return str(pathlib.Path(__file__).resolve().parents[1])' 'return os.pathsep.join(sys.path)'
  '';

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ android-tools ]}"
    "--add-flags --no-update-check"
  ];

  meta = {
    description = "Root an Echo Dot or Echo, or return it to stock";
    homepage = "https://github.com/bboe/firebreak";
    license = lib.licenses.bsd2;
    mainProgram = "firebreak";
    platforms = lib.platforms.linux;
  };
}
