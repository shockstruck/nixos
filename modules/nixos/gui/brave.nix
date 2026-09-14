{ ... }:
{
  # Brave managed policy (system layer). Home layer (extension + module
  # enable) is modules/home/brave.nix.
  #
  # The default search provider is set here rather than left to Brave's own
  # default because a managed policy is the only way to lock it on every
  # build; users can't change it from brave://settings. The Bitwarden toolbar
  # pin rides on top of the extension Home Manager installs — this policy
  # only forces its pin state, not its presence.
  environment.etc."brave/policies/managed/policies.json".text = builtins.toJSON {
    HomepageLocation = "https://portal.panic.ac";
    ShowHomeButton = true;
    HomepageIsNewTabPage = false;
    PasswordManagerEnabled = false;
    ShowFullUrlsInAddressBar = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "Brave";
    DefaultSearchProviderSearchURL = "https://search.brave.com/search?q={searchTerms}&source=desktop";
    DefaultSearchProviderSuggestURL = "https://search.brave.com/api/suggest?q={searchTerms}&rich=true&rich_verticals=true&source=desktop";
    DefaultSearchProviderIconURL = "https://cdn.search.brave.com/serp/favicon.ico";
    DefaultSearchProviderEncodings = [ "UTF-8" ];
    ExtensionSettings = {
      nngceckbapebfimnlniiiahkandclblb = {
        toolbar_pin = "force_pinned";
      };
    };
  };
}
