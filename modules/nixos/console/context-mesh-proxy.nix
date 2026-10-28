{ pkgs, ... }:
let
  credentialPath = "/etc/credstore.encrypted/kong-ai-operator-console";
  script = pkgs.writeText "context-mesh-proxy.py" (builtins.readFile ./context-mesh-proxy.py);
in
{
  systemd.services.context-mesh-proxy = {
    description = "Loopback Context-Mesh token proxy";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = credentialPath;
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -u ${script}";
      DynamicUser = true;
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      LoadCredentialEncrypted = "kong-ai-operator-console:${credentialPath}";
      Restart = "on-failure";
    };
  };
}
