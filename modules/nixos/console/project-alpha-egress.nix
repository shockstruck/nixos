# Console guest egress gateway, disabled by default. With `enable = false`
# nothing here is instantiated: no user, group, unit, socket or namespace
# exists, and the runner's `Requires=` on the gateway socket fails only when
# the runner itself is enabled.
#
# The gateway gives the disposable Project Alpha CI guest no route. `passt`
# presents one dummy interface in a private namespace whose only address is
# 198.18.0.1/30. A DNS sinkhole answers listed names with that address, and an
# HAProxy SNI relay accepts only a listed TLS server name, resolves it itself,
# rejects denied addresses, and dials the resolved IPv4 address on 443. The
# guest never sees a host, LAN, control-plane or metadata address.
#
# Layers:
#
#   * `-netns` is the only unit with a capability (`CAP_NET_ADMIN`); it runs in
#     a private network namespace and refuses before any change unless the
#     namespace looks empty.
#   * `-dns` and `-relay` run as their own unprivileged users with no
#     capabilities. Their sockets join the namespace; the DNS service runs in
#     its own empty namespace and takes the descriptors.
#   * The gateway socket is an AF_UNIX stream socket, root-only, one connection
#     at a time. Each instance runs `passt` in the namespace as its own
#     unprivileged user.
#
# The allow list, deny lists and HAProxy configuration are static files beside
# this module, so the test file reads exactly what runs. The only values Nix
# adds to the unit bodies are the `Exec*=` lines, the gateway's `ListenStream`
# (from the runner's `egressSocket`, so no socket path is committed here) and
# the relay's `IPAddressDeny=`, rendered from the same two deny lists HAProxy
# reads. No unit here starts by default.
{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.project-alpha-console-egress;
  runner = config.services.project-alpha-console-runner;

  assets = ./project-alpha-egress;
  units = builtins.fromJSON (builtins.readFile ./project-alpha-egress/units.json);

  # One list file feeds both HAProxy (`-m ip -f`) and systemd's
  # `IPAddressDeny=`; comments and blank lines are dropped here, not there.
  readList = file:
    let
      strip = line:
        lib.removeSuffix "\r" (builtins.head (lib.splitString "#" line));
      entries = map strip (lib.splitString "\n" (builtins.readFile file));
    in
    builtins.filter (entry: entry != "") entries;

  denyAddresses =
    readList (assets + "/deny-ipv4.list")
    ++ readList (assets + "/deny-ipv6.list");

  socketDir = builtins.dirOf runner.egressSocket;

  egressUsers = [
    "project-alpha-egress-passt"
    "project-alpha-egress-dns"
    "project-alpha-egress-relay"
    "project-alpha-egress-netns"
    "project-alpha-egress-overlap"
  ];

  mkService = name: description: extraConfig: {
    inherit description;
    unitConfig = units.${name}.unitConfig or { };
    serviceConfig = (units.${name}.serviceConfig or { }) // extraConfig;
  };

  mkSocket = name: description: extraConfig: {
    inherit description;
    unitConfig = units.${name}.unitConfig or { };
    socketConfig = (units.${name}.socketConfig or { }) // extraConfig;
  };

  # The namespace script is static so the test reads exactly what runs; the
  # wrapper only supplies `ip`, `nft` and the text tools on PATH. `$0` inside
  # the script is still its store path, so `namespace.nft` resolves beside it.
  netnsSetup = pkgs.writeShellApplication {
    name = "project-alpha-egress-netns-setup";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      iproute2
      nftables
    ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${assets}/netns-setup.sh
    '';
  };
in
{
  options.services.project-alpha-console-egress = {
    enable = lib.mkEnableOption "the isolated egress gateway for the disabled Project Alpha console CI guest";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "/run/[^/]+/[^/]+" runner.egressSocket != null;
        message = ''
          services.project-alpha-console-runner.egressSocket must name one
          socket file directly inside one /run directory, so the gateway can
          create that directory 0700 root:root.
        '';
      }
    ];

    users.groups = lib.genAttrs egressUsers (_: { });
    users.users = lib.genAttrs egressUsers (name: {
      isSystemUser = true;
      group = name;
    });

    # Belt and braces beside the gateway socket's DirectoryMode=; both name the
    # same run directory and neither writes a socket path into the repository.
    systemd.tmpfiles.rules = [
      "d ${socketDir} 0700 root root -"
    ];

    systemd.services.project-alpha-egress-overlap = mkService
      "project-alpha-egress-overlap.service"
      "Project Alpha console egress: host route overlap check"
      {
        ExecStart = "${pkgs.python3}/bin/python3 ${assets}/overlap.py";
      };

    systemd.services.project-alpha-egress-netns = mkService
      "project-alpha-egress-netns.service"
      "Project Alpha console egress: private network namespace"
      {
        ExecStart = "${netnsSetup}/bin/project-alpha-egress-netns-setup";
      };

    systemd.sockets.project-alpha-egress-dns = mkSocket
      "project-alpha-egress-dns.socket"
      "Project Alpha console egress: DNS socket"
      { };

    systemd.services.project-alpha-egress-dns = mkService
      "project-alpha-egress-dns.service"
      "Project Alpha console egress: DNS sinkhole"
      {
        ExecStart = "${pkgs.python3}/bin/python3 ${assets}/dns.py";
      };

    systemd.sockets.project-alpha-egress-relay = mkSocket
      "project-alpha-egress-relay.socket"
      "Project Alpha console egress: TLS SNI relay socket"
      { };

    systemd.services.project-alpha-egress-relay = mkService
      "project-alpha-egress-relay.service"
      "Project Alpha console egress: TLS SNI relay"
      {
        # A3: the cgroup filter has no effect when eBPF is unavailable, so the
        # unit proves EPERM before HAProxy starts. ExecStartPost keeps an
        # immediate HAProxy exit inside the start job instead of leaving a
        # socket that accepts and then closes.
        ExecStartPre = "${pkgs.python3}/bin/python3 ${assets}/deny_probe.py";
        ExecStart = "${pkgs.haproxy}/bin/haproxy -db -f ${assets}/haproxy.cfg";
        ExecStartPost = "${pkgs.coreutils}/bin/sleep 1";
        IPAddressDeny = denyAddresses;
      };

    systemd.sockets.project-alpha-egress = mkSocket
      "project-alpha-egress.socket"
      "Project Alpha console egress: gateway socket"
      {
        ListenStream = runner.egressSocket;
      };

    systemd.services."project-alpha-egress@" = mkService
      "project-alpha-egress@.service"
      "Project Alpha console egress: gateway instance"
      {
        ExecStart = "${pkgs.passt}/bin/passt ${lib.escapeShellArgs units.passtArgs}";
      };
  };
}
