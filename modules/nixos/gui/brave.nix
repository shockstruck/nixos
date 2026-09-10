{ ... }:
{
  # Brave managed policy (system layer). Home layer (extension + module
  # enable) is modules/home/brave.nix. Keys confirmed against brave-core /
  # upstream Chromium policy_templates (see PR body); ShowFullUrlsInAddressBar
  # is Chromium's, the rest are Brave-specific or Chromium-inherited.
  environment.etc."brave/policies/managed/policies.json".text = builtins.toJSON {
    HomepageLocation = "https://portal.panic.ac";
    ShowHomeButton = true;
    PasswordManagerEnabled = false;
    ShowFullUrlsInAddressBar = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
  };
}
