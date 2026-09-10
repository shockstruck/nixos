{ ... }:
{
  # Brave managed policy (system layer). Home layer (extension + module
  # enable) is modules/home/brave.nix.
  environment.etc."brave/policies/managed/policies.json".text = builtins.toJSON {
    HomepageLocation = "https://portal.panic.ac";
    ShowHomeButton = true;
    PasswordManagerEnabled = false;
    ShowFullUrlsInAddressBar = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
  };
}
