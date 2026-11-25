#!/usr/bin/env python3
"""Tests for the disabled console egress gateway.

Run as `python3 modules/nixos/console/project-alpha-egress_test.py` from the
repository root, or `python3 -I` from anywhere. Standard library only: no Nix,
no root, no network and no socket is created. Each test class reads the same
static file the running unit reads, so a test cannot pass on a copy that
differs from what runs.
"""

import errno
import importlib.util
import ipaddress
import json
import re
import struct
import types
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "project-alpha-egress"
NIX_FILE = HERE / "project-alpha-egress.nix"
RUNNER_FILE = HERE / "project-alpha-runner.nix"

GATEWAY = "198.18.0.1"
CONTRACT = "198.18.0.0/30"

IPV4_ROWS = [
    ("0.0.0.0/8", "0.1.2.3"),
    ("10.0.0.0/8", "10.1.2.3"),
    ("100.64.0.0/10", "100.64.0.1"),
    ("127.0.0.0/8", "127.0.0.1"),
    ("169.254.0.0/16", "169.254.169.254"),
    ("172.16.0.0/12", "172.16.1.1"),
    ("192.0.0.0/24", "192.0.0.1"),
    ("192.0.2.0/24", "192.0.2.1"),
    ("192.88.99.0/24", "192.88.99.1"),
    ("192.168.0.0/16", "192.168.1.1"),
    ("198.18.0.0/15", "198.18.0.1"),
    ("198.51.100.0/24", "198.51.100.1"),
    ("203.0.113.0/24", "203.0.113.1"),
    ("224.0.0.0/4", "224.0.0.1"),
    ("240.0.0.0/4", "240.0.0.1"),
]

IPV6_ROWS = [
    ("::/128", "::"),
    ("::1/128", "::1"),
    ("::/0", "2001:db8::1"),
    ("fc00::/7", "fd00::1"),
    ("fd00:ec2::254", "fd00:ec2::254"),
    ("fe80::/10", "fe80::1"),
    ("ff00::/8", "ff02::1"),
]

PUBLIC_CONTROLS = [
    "1.1.1.1",
    "9.9.9.9",
    "8.8.8.8",
    "140.82.112.3",
    "151.101.1.6",
    "199.232.0.1",
]


def read(name):
    return (ASSETS / name).read_text(encoding="utf-8")


def read_list(name):
    entries = []
    for line in read(name).splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry:
            entries.append(entry)
    return entries


def load_module(name):
    spec = importlib.util.spec_from_file_location(
        "egress_" + name, ASSETS / f"{name}.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def normalize(entry):
    net = ipaddress.ip_network(entry, strict=False)
    return str(net)


def duration_millis(number, unit):
    """Convert a HAProxy time unit to milliseconds, both units exercised."""
    return number if unit == "ms" else number * 1000


class AllowListTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.allow = set(read_list("allow-exact.list"))
        cls.dns = load_module("dns")

    def test_list_shape_is_sorted_lowercase_and_exact(self):
        entries = read_list("allow-exact.list")
        self.assertEqual(entries, sorted(entries))
        self.assertEqual(len(entries), len(set(entries)))
        for entry in entries:
            self.assertEqual(entry, entry.lower())
            self.assertNotIn("*", entry)
            self.assertNotIn("#", entry)
            self.assertEqual(entry, entry.strip())

    def test_fixed_names_and_blob_count(self):
        self.assertIn("github.com", self.allow)
        self.assertIn("api.github.com", self.allow)
        self.assertIn("codeload.github.com", self.allow)
        self.assertIn("release-assets.githubusercontent.com", self.allow)
        self.assertIn("services.gradle.org", self.allow)
        self.assertIn("downloads.gradle.org", self.allow)
        self.assertIn("repo.maven.apache.org", self.allow)
        self.assertIn("plugins.gradle.org", self.allow)
        self.assertIn("plugins-artifacts.gradle.org", self.allow)
        blobs = [e for e in self.allow if e.endswith(".blob.core.windows.net")]
        self.assertEqual(len(blobs), 140)
        for blob in blobs:
            number = blob[: -len(".blob.core.windows.net")].removeprefix(
                "productionresultssa"
            )
            self.assertTrue(number.isdigit(), blob)

    def test_excluded_hosts_are_absent(self):
        for name in (
            "m2.dv8tion.net",
            "ghcr.io",
            "objects.githubusercontent.com",
            "objects-origin.githubusercontent.com",
        ):
            self.assertNotIn(name, self.allow)

    def test_dns_exact_matching_is_anchored(self):
        self.assertTrue(self.dns.name_allowed("github.com", self.allow))
        self.assertTrue(self.dns.name_allowed("GitHub.COM", self.allow))
        self.assertFalse(self.dns.name_allowed("xgithub.com", self.allow))
        self.assertFalse(
            self.dns.name_allowed("github.com.evil.example", self.allow)
        )
        self.assertFalse(self.dns.name_allowed("github.com\n", self.allow))
        self.assertFalse(self.dns.name_allowed("github.com\0evil", self.allow))
        self.assertFalse(self.dns.name_allowed("github.com.", self.allow))
        self.assertFalse(self.dns.name_allowed("", self.allow))
        self.assertFalse(self.dns.name_allowed("m2.dv8tion.net", self.allow))

    def test_dns_actions_wildcard_is_one_label(self):
        self.assertTrue(
            self.dns.name_allowed(
                "run-actions-1-azure-eastus.actions.githubusercontent.com",
                self.allow,
            )
        )
        self.assertTrue(
            self.dns.name_allowed(
                "RUN-ACTIONS-1-AZURE-EASTUS.ACTIONS.GITHUBUSERCONTENT.COM",
                self.allow,
            )
        )
        self.assertFalse(
            self.dns.name_allowed(
                "a.b.actions.githubusercontent.com", self.allow
            )
        )
        self.assertFalse(
            self.dns.name_allowed(
                "actions.githubusercontent.com", self.allow
            )
        )
        self.assertFalse(
            self.dns.name_allowed(
                "evil.actions.githubusercontent.com.evil.example", self.allow
            )
        )
        self.assertFalse(
            self.dns.name_allowed(
                "run.actions.githubusercontent.com\n", self.allow
            )
        )
        self.assertFalse(
            self.dns.name_allowed(
                "run.actions.githubusercontent.com\0evil", self.allow
            )
        )

    def test_unlisted_blob_number_fails_closed(self):
        missing = None
        for number in range(1000, 2000):
            candidate = f"productionresultssa{number}.blob.core.windows.net"
            if candidate not in self.allow:
                missing = candidate
                break
        self.assertIsNotNone(missing)
        self.assertFalse(self.dns.name_allowed(missing, self.allow))


class HaproxyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = read("haproxy.cfg")
        cls.lines = [
            " ".join(line.split()).strip()
            for line in cls.text.splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]

    def acl_regex(self, name):
        pattern = re.compile(
            r"^acl " + re.escape(name) + r" .* -m reg '([^']*)'$"
        )
        for line in self.lines:
            match = pattern.match(line)
            if match:
                return re.compile(match.group(1).replace("\\z", "\\Z"))
        self.fail(f"no regex ACL named {name}")

    def test_sni_chars_rejects_bad_shapes(self):
        regex = self.acl_regex("sni_chars")
        for name in (
            "github.com",
            "a.b-c.d",
            "x" * 253,
            # A syntactically valid but unlisted name passes the character
            # class; the exact list is what rejects it.
            "github.com.evil.example",
        ):
            self.assertIsNotNone(regex.search(name), repr(name))
        for name in (
            "",
            "x" * 254,
            " xgithub.com",
            "github.com ",
            "github.com\n",
            "\0github.com",
            "github.com\0evil",
            "github com",
            "github.com/evil",
        ):
            self.assertIsNone(regex.search(name), repr(name))

    def test_sni_actions_is_one_label(self):
        regex = self.acl_regex("sni_actions")
        positive = "run-actions-1-azure-eastus.actions.githubusercontent.com"
        self.assertIsNotNone(regex.search(positive))
        for name in (
            "a.b.actions.githubusercontent.com",
            "actions.githubusercontent.com",
            "evil.example." + positive,
            positive + ".evil.example",
            positive + "\n",
            "\0" + positive,
            # One name per dot in the ACL: an unescaped dot would let the
            # separator be any character.
            "x-actions.githubusercontent.com",
            "x.actions-githubusercontent.com",
            "x.actions.githubusercontent-com",
        ):
            self.assertIsNone(regex.search(name), repr(name))

    def test_dns_matches_the_same_edge_names(self):
        dns = load_module("dns")
        allow = dns.load_allow()
        positive = "run-actions-1-azure-eastus.actions.githubusercontent.com"
        self.assertTrue(dns.name_allowed("github.com", allow))
        self.assertTrue(dns.name_allowed(positive, allow))
        for name in (
            "xgithub.com",
            "github.com.evil.example",
            "github.com ",
            "github.com\n",
            "\0github.com",
            "github.com\0evil",
            "x-actions.githubusercontent.com",
            "x.actions-githubusercontent.com",
            "x.actions.githubusercontent-com",
            "evil.example." + positive,
            positive + ".evil.example",
            positive + "\n",
            "\0" + positive,
            "a.b.actions.githubusercontent.com",
            "actions.githubusercontent.com",
        ):
            self.assertFalse(dns.name_allowed(name, allow), repr(name))

    def test_config_is_pinned_whole(self):
        expected = [
            "global",
            "default-path config",
            "dns-accept-family ipv4",
            "maxconn 256",
            "nbthread 2",
            "httpclient.resolvers.disabled on",
            "log stderr format raw daemon",
            "resolvers upstream",
            "nameserver upstream1 1.1.1.1:53",
            "nameserver upstream2 9.9.9.9:53",
            "accepted_payload_size 1232",
            "resolve_retries 3",
            "timeout resolve 1s",
            "timeout retry 1s",
            "frontend guest",
            "mode tcp",
            "bind fd@3",
            "log global",
            'log-format "egress entry=%[var(txn.entry)] state=%ts"',
            "tcp-request inspect-delay 10s",
            r"acl sni_chars req.ssl_sni,lower -m reg '\A[a-z0-9.-]{1,253}\z'",
            "acl sni_listed req.ssl_sni,lower -m str -f allow-exact.list",
            r"acl sni_actions req.ssl_sni,lower -m reg '\A[a-z0-9-]+\.actions\.githubusercontent\.com\z'",
            "tcp-request content set-var(txn.entry) str(rejected-sni)",
            "tcp-request content reject unless { req.ssl_hello_type 1 }",
            "tcp-request content reject unless sni_chars",
            "tcp-request content reject unless sni_listed || sni_actions",
            "tcp-request content set-var(txn.entry) str(rejected-resolve)",
            "tcp-request content do-resolve(txn.dst,upstream,ipv4) req.ssl_sni,lower",
            "tcp-request content reject unless { var(txn.dst) -m found }",
            "tcp-request content reject unless { var(txn.dst) -m ip 0.0.0.0/1 128.0.0.0/1 }",
            "tcp-request content set-var(txn.entry) str(rejected-address)",
            "tcp-request content reject if { var(txn.dst) -m ip -f deny-ipv4.list }",
            "tcp-request content set-dst var(txn.dst)",
            "tcp-request content set-dst-port int(443)",
            "tcp-request content set-var(txn.entry) req.ssl_sni,lower if sni_listed",
            "tcp-request content set-var(txn.entry) str(*.actions.githubusercontent.com) if sni_actions !sni_listed",
            "tcp-request content accept if sni_listed || sni_actions",
            "tcp-request content reject",
            "timeout client 30s",
            "default_backend upstream_443",
            "backend upstream_443",
            "mode tcp",
            "timeout connect 5s",
            "timeout server 30s",
            "timeout tunnel 1h",
            "server upstream 0.0.0.0:443",
        ]
        self.assertEqual(self.lines, expected)

    def test_duration_helper_uses_both_units(self):
        self.assertEqual(duration_millis(500, "ms"), 500)
        self.assertEqual(duration_millis(10, "s"), 10000)

    def test_chars_acl_precedes_list_acl(self):
        chars = self.lines.index(
            next(line for line in self.lines if line.startswith("acl sni_chars "))
        )
        listed = self.lines.index(
            next(line for line in self.lines if line.startswith("acl sni_listed "))
        )
        self.assertLess(chars, listed)

    def test_rule_order_is_exact_and_fail_closed(self):
        expected = [
            "tcp-request content set-var(txn.entry) str(rejected-sni)",
            "tcp-request content reject unless { req.ssl_hello_type 1 }",
            "tcp-request content reject unless sni_chars",
            "tcp-request content reject unless sni_listed || sni_actions",
            "tcp-request content set-var(txn.entry) str(rejected-resolve)",
            "tcp-request content do-resolve(txn.dst,upstream,ipv4) req.ssl_sni,lower",
            "tcp-request content reject unless { var(txn.dst) -m found }",
            "tcp-request content reject unless { var(txn.dst) -m ip 0.0.0.0/1 128.0.0.0/1 }",
            "tcp-request content set-var(txn.entry) str(rejected-address)",
            "tcp-request content reject if { var(txn.dst) -m ip -f deny-ipv4.list }",
            "tcp-request content set-dst var(txn.dst)",
            "tcp-request content set-dst-port int(443)",
            "tcp-request content set-var(txn.entry) req.ssl_sni,lower if sni_listed",
            "tcp-request content set-var(txn.entry) str(*.actions.githubusercontent.com) if sni_actions !sni_listed",
            "tcp-request content accept if sni_listed || sni_actions",
            "tcp-request content reject",
        ]
        actual = [line for line in self.lines if line.startswith("tcp-request content ")]
        self.assertEqual(actual, expected)

    def test_no_early_accept_and_no_forbidden_directive(self):
        rules = [line for line in self.lines if line.startswith("tcp-request content ")]
        accepts = [i for i, line in enumerate(rules) if " accept " in f" {line} "]
        self.assertEqual(accepts, [len(rules) - 2])
        for line in rules[: len(rules) - 2]:
            self.assertNotIn(" accept", line)
        forbidden = re.compile(
            r"^(stats|peers|lua|namespace|http-request|http-response|mode\s+http)\b"
        )
        for line in self.lines:
            self.assertIsNone(forbidden.match(line), line)
        logs = [line for line in self.lines if line == "log global" or line.startswith("log ")]
        self.assertEqual(sorted(logs), ["log global", "log stderr format raw daemon"])

    def test_no_process_manager_or_master_mode(self):
        self.assertNotIn("-W", self.text)
        self.assertNotIn("-Ws", self.text)
        self.assertIn("bind fd@3", self.lines)
        self.assertIn("default-path config", self.lines)

    def test_list_match_uses_exact_strings(self):
        line = next(
            line for line in self.lines if line.startswith("acl sni_listed ")
        )
        self.assertIn("-m str -f allow-exact.list", line)

    def test_every_sni_acl_lowercases_before_matching(self):
        for name in ("sni_chars", "sni_listed", "sni_actions"):
            line = next(
                line for line in self.lines if line.startswith(f"acl {name} ")
            )
            self.assertIn("req.ssl_sni,lower", line, name)

    def test_timeout_tunnel_only_in_backend(self):
        frontend = self.text.split("frontend guest", 1)[1].split(
            "backend upstream_443", 1
        )[0]
        backend = self.text.split("backend upstream_443", 1)[1]
        self.assertNotIn("timeout tunnel", frontend)
        self.assertIn("timeout tunnel", backend)

    def test_resolve_retry_budget_stays_under_inspect_delay(self):
        def millis(pattern):
            match = re.search(pattern, self.text, re.MULTILINE)
            self.assertIsNotNone(match, pattern)
            return duration_millis(int(match.group(1)), match.group(2))

        match = re.search(r"^\s*resolve_retries (\d+)$", self.text, re.MULTILINE)
        self.assertIsNotNone(match)
        retries = int(match.group(1))
        retry = millis(r"^\s*timeout retry (\d+)(ms|s)$")
        inspect = millis(r"^\s*tcp-request inspect-delay (\d+)(ms|s)$")
        self.assertEqual(retries, 3)
        self.assertLess(retries * retry, inspect)


class DenyListTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ipv4 = [normalize(entry) for entry in read_list("deny-ipv4.list")]
        cls.ipv6 = [normalize(entry) for entry in read_list("deny-ipv6.list")]

    def test_ipv4_covers_every_contract_row(self):
        self.assertEqual(sorted(self.ipv4), sorted(normalize(r[0]) for r in IPV4_ROWS))
        networks = [ipaddress.ip_network(entry) for entry in self.ipv4]
        for row, address in IPV4_ROWS:
            self.assertIn(normalize(row), self.ipv4)
            self.assertTrue(
                any(ipaddress.ip_address(address) in net for net in networks),
                row,
            )

    def test_ipv6_covers_every_contract_row(self):
        self.assertEqual(sorted(self.ipv6), sorted(normalize(r[0]) for r in IPV6_ROWS))
        networks = [ipaddress.ip_network(entry) for entry in self.ipv6]
        for row, address in IPV6_ROWS:
            self.assertIn(normalize(row), self.ipv6)
            self.assertTrue(
                any(ipaddress.ip_address(address) in net for net in networks),
                row,
            )

    def test_ipv6_denies_the_whole_family(self):
        self.assertIn("::/0", self.ipv6)

    def test_public_controls_stay_outside_every_row(self):
        networks = [ipaddress.ip_network(entry) for entry in self.ipv4]
        for address in PUBLIC_CONTROLS:
            self.assertFalse(
                any(ipaddress.ip_address(address) in net for net in networks),
                address,
            )

    def test_contract_gateway_is_not_a_deny_row(self):
        networks = [ipaddress.ip_network(entry) for entry in self.ipv4]
        # 198.18.0.0/15 is a contract row, so the gateway address is inside
        # it; what must not happen is a deny row narrower than /15 that
        # swallows the gateway while looking like an allow.
        self.assertIn("198.18.0.0/15", self.ipv4)
        for net in networks:
            self.assertNotEqual(str(net), "198.18.0.1/32")

    def test_no_comments_leak_into_entries(self):
        for entry in read_list("deny-ipv4.list") + read_list("deny-ipv6.list"):
            self.assertNotIn("#", entry)
            ipaddress.ip_network(entry, strict=False)


class UnitsJsonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.units = json.loads(read("units.json"))

    def services(self):
        for name, unit in self.units.items():
            if name == "passtArgs":
                continue
            if "serviceConfig" in unit:
                yield name, unit

    def test_unit_set_is_exact(self):
        names = {name for name in self.units if name != "passtArgs"}
        self.assertEqual(
            names,
            {
                "project-alpha-egress-overlap.service",
                "project-alpha-egress-netns.service",
                "project-alpha-egress-dns.socket",
                "project-alpha-egress-dns.service",
                "project-alpha-egress-relay.socket",
                "project-alpha-egress-relay.service",
                "project-alpha-egress.socket",
                "project-alpha-egress@.service",
            },
        )

    def test_passt_args_are_exact(self):
        self.assertEqual(
            self.units["passtArgs"],
            [
                "--foreground",
                "--fd",
                "3",
                "--ipv4-only",
                "--interface",
                "pa-egress0",
                "--address",
                "198.18.0.2",
                "--netmask",
                "30",
                "--gateway",
                "198.18.0.1",
                "--dns",
                "198.18.0.1",
                "--search",
                "none",
                "--no-map-gw",
                "--no-icmp",
            ],
        )

    def test_users_are_five_distinct_service_accounts(self):
        users = []
        for name, unit in self.services():
            config = unit["serviceConfig"]
            self.assertEqual(config["User"], config["Group"], name)
            self.assertNotEqual(config["User"], "root", name)
            users.append(config["User"])
        self.assertEqual(len(users), len(set(users)))
        self.assertEqual(
            set(users),
            {
                "project-alpha-egress-passt",
                "project-alpha-egress-dns",
                "project-alpha-egress-relay",
                "project-alpha-egress-netns",
                "project-alpha-egress-overlap",
            },
        )

    def test_only_netns_holds_cap_net_admin(self):
        for name, unit in self.services():
            config = unit["serviceConfig"]
            if name == "project-alpha-egress-netns.service":
                self.assertEqual(config["CapabilityBoundingSet"], ["CAP_NET_ADMIN"])
                self.assertEqual(config["AmbientCapabilities"], ["CAP_NET_ADMIN"])
            else:
                self.assertEqual(config["CapabilityBoundingSet"], [""], name)
                self.assertEqual(config["AmbientCapabilities"], [""], name)
            self.assertEqual(config["NoNewPrivileges"], "yes", name)

    def test_ip_address_pairs(self):
        paired = [
            "project-alpha-egress-relay.socket",
            "project-alpha-egress-dns.socket",
            "project-alpha-egress-dns.service",
            "project-alpha-egress@.service",
        ]
        for name in paired:
            unit = self.units[name]
            config = unit.get("socketConfig") or unit["serviceConfig"]
            self.assertEqual(config["IPAddressDeny"], ["any"], name)
            self.assertEqual(config["IPAddressAllow"], [CONTRACT], name)
        for name in (
            "project-alpha-egress-netns.service",
            "project-alpha-egress-overlap.service",
        ):
            config = self.units[name]["serviceConfig"]
            self.assertEqual(config["IPAddressDeny"], ["any"], name)
            self.assertNotIn("IPAddressAllow", config, name)
        relay = self.units["project-alpha-egress-relay.service"]["serviceConfig"]
        self.assertNotIn("IPAddressAllow", relay)
        self.assertNotIn("IPAddressDeny", relay)

    def test_every_service_has_limits_and_hardening(self):
        for name, unit in self.services():
            config = unit["serviceConfig"]
            for key in (
                "MemoryMax",
                "CPUQuota",
                "TasksMax",
                "LimitNOFILE",
                "UMask",
                "Restart",
            ):
                self.assertIn(key, config, name)
            self.assertEqual(config["MemorySwapMax"], "0", name)
            self.assertEqual(config["Restart"], "no", name)
            self.assertEqual(config["UMask"], "0077", name)
            self.assertEqual(config["ProtectSystem"], "strict", name)
            for key in (
                "ProtectHome",
                "ProtectClock",
                "ProtectControlGroups",
                "ProtectHostname",
                "ProtectKernelLogs",
                "ProtectKernelModules",
                "ProtectKernelTunables",
            ):
                self.assertEqual(config[key], "yes", f"{name} {key}")
            self.assertEqual(config["SystemCallArchitectures"], "native", name)
            self.assertEqual(config["SystemCallErrorNumber"], "EPERM", name)
            self.assertIn("PrivateTmp", config, name)
            paths = config["InaccessiblePaths"]
            self.assertIn("-/etc/credstore", paths, name)
            self.assertIn("-/etc/credstore.encrypted", paths, name)
            filters = ";".join(config["SystemCallFilter"])
            self.assertIn("io_uring_setup", filters, name)
            self.assertIn("io_uring_enter", filters, name)
            self.assertIn("io_uring_register", filters, name)

    def test_relay_and_passt_hide_resolv_conf(self):
        relay = self.units["project-alpha-egress-relay.service"]["serviceConfig"]
        passt = self.units["project-alpha-egress@.service"]["serviceConfig"]
        self.assertIn("-/etc/resolv.conf", relay["InaccessiblePaths"])
        self.assertIn("-/etc/resolv.conf", passt["InaccessiblePaths"])

    def test_relay_filter_is_not_write_exec_denied(self):
        relay = self.units["project-alpha-egress-relay.service"]["serviceConfig"]
        self.assertNotIn("MemoryDenyWriteExecute", relay)
        self.assertIn("@system-service", relay["SystemCallFilter"])
        self.assertIn("~@privileged", relay["SystemCallFilter"])
        self.assertNotIn("~@resources", relay["SystemCallFilter"])

    def test_relay_family_and_namespace_restrictions(self):
        relay = self.units["project-alpha-egress-relay.service"]["serviceConfig"]
        self.assertEqual(relay["RestrictAddressFamilies"], ["AF_INET"])
        self.assertEqual(relay["RestrictNamespaces"], "yes")

    def test_dns_runs_empty_and_takes_descriptors(self):
        dns = self.units["project-alpha-egress-dns.service"]["serviceConfig"]
        self.assertEqual(dns["PrivateNetwork"], "yes")
        self.assertNotIn("JoinsNamespaceOf", dns)
        self.assertEqual(dns["RestrictAddressFamilies"], ["none"])

    def test_passt_namespace_and_family_settings(self):
        passt = self.units["project-alpha-egress@.service"]["serviceConfig"]
        self.assertEqual(passt["PrivateNetwork"], "yes")
        self.assertEqual(
            self.units["project-alpha-egress@.service"]["unitConfig"][
                "JoinsNamespaceOf"
            ],
            "project-alpha-egress-netns.service",
        )
        self.assertNotIn("JoinsNamespaceOf", passt)
        self.assertEqual(
            passt["RestrictAddressFamilies"],
            ["AF_INET", "AF_NETLINK", "AF_UNIX"],
        )
        self.assertEqual(
            passt["RestrictNamespaces"], ["user", "ipc", "mnt", "uts", "pid"]
        )
        self.assertNotIn("net", passt["RestrictNamespaces"])
        self.assertNotIn("ProcSubset", passt)
        filters = passt["SystemCallFilter"]
        self.assertIn("@mount", filters)
        self.assertIn("seccomp", filters)
        for group in (
            "~@clock",
            "~@module",
            "~@raw-io",
            "~@reboot",
            "~@swap",
            "~@obsolete",
            "~@cpu-emulation",
        ):
            self.assertIn(group, filters)
        self.assertNotIn("~@privileged", filters)

    def test_joins_namespace_only_on_sockets_and_template(self):
        present = set()
        for name, unit in self.units.items():
            if name == "passtArgs":
                continue
            for section in ("unitConfig", "serviceConfig", "socketConfig"):
                if "JoinsNamespaceOf" in unit.get(section, {}):
                    present.add(name)
        self.assertEqual(
            present,
            {
                "project-alpha-egress-dns.socket",
                "project-alpha-egress-relay.socket",
                "project-alpha-egress@.service",
            },
        )
        for name in (
            "project-alpha-egress-dns.service",
            "project-alpha-egress-relay.service",
        ):
            for section in ("unitConfig", "serviceConfig", "socketConfig"):
                self.assertNotIn(
                    "JoinsNamespaceOf", self.units[name].get(section, {}), name
                )

    def test_overlap_and_netns_run_on_the_host(self):
        overlap = self.units["project-alpha-egress-overlap.service"]["serviceConfig"]
        netns = self.units["project-alpha-egress-netns.service"]["serviceConfig"]
        self.assertNotIn("PrivateNetwork", overlap)
        self.assertEqual(netns["PrivateNetwork"], "yes")
        self.assertEqual(netns["RemainAfterExit"], "yes")
        self.assertEqual(netns["Type"], "oneshot")
        self.assertEqual(overlap["Type"], "oneshot")
        self.assertEqual(
            self.units["project-alpha-egress-netns.service"]["unitConfig"]["Requires"],
            ["project-alpha-egress-overlap.service"],
        )

    def test_every_socket_disables_default_dependencies(self):
        for name, unit in self.units.items():
            if name == "passtArgs" or "socketConfig" not in unit:
                continue
            config = unit["unitConfig"]
            self.assertEqual(config["DefaultDependencies"], "no", name)
            self.assertIn("shutdown.target", config["Conflicts"], name)
            self.assertIn("shutdown.target", config["Before"], name)
            self.assertNotIn("FreeBind", unit["socketConfig"], name)
            self.assertNotIn("FreeBind", config, name)

    def test_gateway_socket_is_root_only_and_single_connection(self):
        socket_config = self.units["project-alpha-egress.socket"]["socketConfig"]
        self.assertEqual(socket_config["SocketMode"], "0600")
        self.assertEqual(socket_config["DirectoryMode"], "0700")
        self.assertEqual(socket_config["Accept"], "yes")
        self.assertEqual(socket_config["MaxConnections"], 1)
        self.assertNotIn("ListenStream", socket_config)
        self.assertNotIn("IPAddressDeny", socket_config)
        self.assertNotIn("IPAddressAllow", socket_config)

    def test_dns_and_relay_listen_only_on_the_gateway(self):
        dns = self.units["project-alpha-egress-dns.socket"]["socketConfig"]
        relay = self.units["project-alpha-egress-relay.socket"]["socketConfig"]
        self.assertEqual(dns["ListenStream"], ["198.18.0.1:53"])
        self.assertEqual(dns["ListenDatagram"], ["198.18.0.1:53"])
        self.assertEqual(relay["ListenStream"], ["198.18.0.1:443"])
        self.assertNotIn("ListenDatagram", relay)
        for name in (
            "project-alpha-egress-dns.socket",
            "project-alpha-egress-relay.socket",
        ):
            config = self.units[name]["socketConfig"]
            self.assertEqual(config["PrivateNetwork"], "yes", name)
            self.assertEqual(
                self.units[name]["unitConfig"]["JoinsNamespaceOf"],
                "project-alpha-egress-netns.service",
                name,
            )
            self.assertNotIn("JoinsNamespaceOf", config, name)

    def test_stop_when_unneeded_exceptions(self):
        units = self.units
        for name in (
            "project-alpha-egress-netns.service",
            "project-alpha-egress-dns.socket",
            "project-alpha-egress-dns.service",
            "project-alpha-egress-relay.socket",
            "project-alpha-egress-relay.service",
            "project-alpha-egress.socket",
        ):
            self.assertEqual(units[name]["unitConfig"]["StopWhenUnneeded"], "yes", name)
        self.assertNotIn(
            "StopWhenUnneeded",
            units["project-alpha-egress-overlap.service"]["unitConfig"],
        )
        self.assertNotIn(
            "StopWhenUnneeded",
            units["project-alpha-egress@.service"]["unitConfig"],
        )

    def test_gateway_binds_to_all_three_units(self):
        expected = [
            "project-alpha-egress-netns.service",
            "project-alpha-egress-dns.service",
            "project-alpha-egress-relay.service",
        ]
        for name in (
            "project-alpha-egress.socket",
            "project-alpha-egress@.service",
        ):
            config = self.units[name]["unitConfig"]
            self.assertEqual(config["Requires"], expected, name)
            self.assertEqual(config["BindsTo"], expected, name)
            self.assertEqual(config["After"], expected, name)
        template = self.units["project-alpha-egress@.service"]["unitConfig"]
        self.assertEqual(template["CollectMode"], "inactive-or-failed")

    def test_dns_and_relay_require_their_own_socket(self):
        for name, socket_name in (
            ("project-alpha-egress-dns.service", "project-alpha-egress-dns.socket"),
            ("project-alpha-egress-relay.service", "project-alpha-egress-relay.socket"),
        ):
            config = self.units[name]["unitConfig"]
            self.assertIn("project-alpha-egress-netns.service", config["Requires"])
            self.assertIn(socket_name, config["Requires"])
            self.assertIn("project-alpha-egress-netns.service", config["BindsTo"])
            self.assertIn("project-alpha-egress-netns.service", config["After"])
            self.assertIn(socket_name, config["After"])
            self.assertNotIn(socket_name, config["BindsTo"])

    def test_nix_adds_only_exec_lines_and_relay_deny(self):
        for name, unit in self.services():
            for key in unit["serviceConfig"]:
                self.assertFalse(key.startswith("Exec"), f"{name} has {key}")

    def test_no_wanted_by_or_refuse_manual_start(self):
        text = read("units.json")
        self.assertNotIn("wantedBy", text)
        self.assertNotIn("RefuseManualStart", text)


class NetnsScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = read("netns-setup.sh")

    def test_code_lines_are_pinned_in_order(self):
        expected = [
            "set -euo pipefail",
            "fail() {",
            "printf '%s\\n' \"$*\" >&2",
            "exit 1",
            "}",
            "links_up=$(ip -o link show up | awk -F': ' '{ print $2 }' | grep -vx 'lo' || true)",
            '[ -z "$links_up" ] || fail "egress namespace guard: a non-loopback link is up"',
            "addresses=$(ip -o addr show | awk '$2 != \"lo\" { print $2 \" \" $4 }')",
            '[ -z "$addresses" ] || fail "egress namespace guard: a non-loopback address exists"',
            "ruleset=$(nft list ruleset)",
            '[ -z "$ruleset" ] || fail "egress namespace guard: the ruleset is not empty"',
            "here=$(CDPATH='' cd -- \"$(dirname -- \"$0\")\" && pwd)",
            'nft -f "$here/namespace.nft"',
            "ip link add pa-egress0 type dummy",
            "ip addr add 198.18.0.1/30 dev pa-egress0",
            "ip link set pa-egress0 up",
            'if [ -n "$(ip -4 route show default)" ] || [ -n "$(ip -6 route show default)" ]; then',
            'fail "egress namespace guard: a default route exists"',
            "fi",
        ]
        actual = [
            " ".join(line.split())
            for line in self.text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertEqual(actual, expected)


class NftTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = read("namespace.nft")

    def chain_body(self, name):
        match = re.search(
            r"chain\s+" + name + r"\s*\{(.*?)\n    \}",
            self.text,
            re.DOTALL,
        )
        self.assertIsNotNone(match, name)
        body = match.group(1)
        statements = []
        for line in body.splitlines():
            statement = line.strip()
            if statement and not statement.startswith("type filter hook"):
                statements.append(statement)
        return statements

    def test_table_and_hooks(self):
        self.assertIn("table inet project_alpha_egress", self.text)
        for hook in ("input", "output", "forward"):
            self.assertIn(f"chain {hook}", self.text)
        self.assertEqual(self.text.count("policy drop;"), 3)

    def test_input_and_output_hold_only_the_three_allowed_rules(self):
        expected = [
            "ct state established ct direction reply accept",
            "ip daddr 198.18.0.1 tcp dport { 53, 443 } accept",
            "ip daddr 198.18.0.1 udp dport 53 accept",
        ]
        self.assertEqual(self.chain_body("input"), expected)
        self.assertEqual(self.chain_body("output"), expected)

    def test_forward_is_empty_and_drops(self):
        self.assertEqual(self.chain_body("forward"), [])

    def test_no_loopback_dhcp_or_icmp_rule(self):
        code = "\n".join(
            line.split("#", 1)[0]
            for line in self.text.splitlines()
            if not line.strip().startswith("#")
        )
        for forbidden in ("iif", "dport 67", "icmp", "ip6"):
            self.assertNotIn(forbidden, code)
        self.assertIsNone(re.search(r"\blo\b", code))


class OverlapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.overlap = load_module("overlap")

    def test_contains_contained_default_and_other_table(self):
        text = json.dumps(
            [
                {"dst": "default", "gateway": "10.0.0.1"},
                {"dst": "198.18.0.0/16", "table": "main"},
                {"dst": "10.0.0.0/8", "table": "0x1BD0"},
                {"dst": "198.18.0.1/32", "table": "local"},
            ]
        )
        prefixes = self.overlap.parse_routes(text)
        self.assertEqual(
            self.overlap.overlaps(prefixes), ["198.18.0.0/16", "198.18.0.1/32"]
        )
        self.assertNotIn("default", self.overlap.overlaps(prefixes))

    def test_other_table_prefix_is_still_found(self):
        text = json.dumps([{"dst": "198.18.0.0/16", "table": "0x1BD0"}])
        self.assertEqual(
            self.overlap.overlaps(self.overlap.parse_routes(text)),
            ["198.18.0.0/16"],
        )

    def test_addresses_are_checked(self):
        text = json.dumps(
            [
                {
                    "ifname": "lo",
                    "addr_info": [{"family": "inet", "local": "127.0.0.1", "prefixlen": 8}],
                },
                {
                    "ifname": "pa0",
                    "addr_info": [{"family": "inet", "local": "198.18.0.2", "prefixlen": 30}],
                },
            ]
        )
        prefixes = self.overlap.parse_addresses(text)
        self.assertEqual(self.overlap.overlaps(prefixes), ["198.18.0.0/30"])

    def test_bad_json_and_bad_shapes_refuse(self):
        for text in ("{", "[] trailing", "null", "{}"):
            with self.assertRaises(self.overlap.ParseError):
                self.overlap.parse_routes(text)
        with self.assertRaises(self.overlap.ParseError):
            self.overlap.parse_routes(json.dumps([{"gateway": "10.0.0.1"}]))
        with self.assertRaises(self.overlap.ParseError):
            self.overlap.parse_routes(json.dumps([{"dst": "not-a-prefix"}]))
        with self.assertRaises(self.overlap.ParseError):
            self.overlap.parse_addresses(json.dumps([{"ifname": "lo"}]))

    def test_bad_ip_json_is_not_a_prefix(self):
        with self.assertRaises(self.overlap.ParseError):
            self.overlap.parse_routes("not json")

    def test_run_ip_command_failure_refuses(self):
        failed = types.SimpleNamespace(returncode=1, stdout="")
        with mock.patch.object(
            self.overlap.subprocess, "run", return_value=failed
        ):
            with self.assertRaises(self.overlap.ParseError):
                self.overlap.run_ip("-4", "-j", "addr")

    def test_main_refuses_on_parse_and_overlap(self):
        with mock.patch.object(
            self.overlap, "run_ip", side_effect=self.overlap.ParseError("bad")
        ), mock.patch("sys.stderr"):
            self.assertEqual(self.overlap.main(), 1)
        clean_routes = json.dumps([{"dst": "default"}])
        clean_addrs = json.dumps(
            [
                {
                    "ifname": "lo",
                    "addr_info": [
                        {"family": "inet", "local": "127.0.0.1", "prefixlen": 8}
                    ],
                }
            ]
        )
        replies = iter([clean_routes, clean_addrs])
        with mock.patch.object(self.overlap, "run_ip", side_effect=lambda *a: next(replies)):
            self.assertEqual(self.overlap.main(), 0)
        replies = iter(
            [json.dumps([{"dst": "198.18.0.0/16"}]), clean_addrs]
        )
        with mock.patch.object(
            self.overlap, "run_ip", side_effect=lambda *a: next(replies)
        ), mock.patch("sys.stderr"):
            self.assertEqual(self.overlap.main(), 1)


def wire_name(name):
    out = bytearray()
    for label in name.split("."):
        if not label:
            continue
        raw = label.encode("utf-8")
        out.append(len(raw))
        out.extend(raw)
    out.append(0)
    return bytes(out)


def make_query(
    name,
    qtype=1,
    qclass=1,
    qid=0x1234,
    flags=0x0100,
    qdcount=1,
    opcode=0,
    extra=b"",
):
    header_flags = (flags & ~0x7800) | ((opcode & 0xF) << 11)
    header = struct.pack(
        "!HHHHHH",
        qid,
        header_flags,
        qdcount,
        0,
        0,
        1 if extra else 0,
    )
    return header + wire_name(name) + struct.pack("!HH", qtype, qclass) + extra


def parse_response(data):
    qid, flags, qdcount, ancount, nscount, arcount = struct.unpack(
        "!HHHHHH", data[:12]
    )
    return {
        "id": qid,
        "flags": flags,
        "qr": bool(flags & 0x8000),
        "aa": bool(flags & 0x0400),
        "ra": bool(flags & 0x0080),
        "rd": bool(flags & 0x0100),
        "rcode": flags & 0x000F,
        "qdcount": qdcount,
        "ancount": ancount,
    }


class DnsWireTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dns = load_module("dns")
        cls.allow = cls.dns.load_allow()

    def answer(self, data):
        return self.dns.answer_query(data, self.allow)

    def test_listed_a_answers_gateway_with_ttl(self):
        query = make_query("github.com")
        response = self.answer(query)
        self.assertIsNotNone(response)
        parsed = parse_response(response)
        self.assertEqual(parsed["id"], 0x1234)
        self.assertTrue(parsed["qr"])
        self.assertTrue(parsed["aa"])
        self.assertTrue(parsed["ra"])
        self.assertEqual(parsed["rcode"], 0)
        self.assertEqual(parsed["qdcount"], 1)
        self.assertEqual(parsed["ancount"], 1)
        question = wire_name("github.com") + struct.pack("!HH", 1, 1)
        offset = 12 + len(question)
        self.assertEqual(response[12 : 12 + len(question)], question)
        self.assertEqual(response[offset : offset + 2], b"\xc0\x0c")
        qtype, qclass, ttl, rdlength = struct.unpack(
            "!HHIH", response[offset + 2 : offset + 12]
        )
        self.assertEqual((qtype, qclass, ttl, rdlength), (1, 1, 60, 4))
        self.assertEqual(response[offset + 12 : offset + 16], bytes([198, 18, 0, 1]))

    def test_question_bytes_are_echoed_with_case(self):
        query = make_query("GitHub.COM")
        response = self.answer(query)
        parsed = parse_response(response)
        self.assertEqual(parsed["rcode"], 0)
        self.assertEqual(parsed["ancount"], 1)
        question = wire_name("GitHub.COM") + struct.pack("!HH", 1, 1)
        self.assertEqual(response[12 : 12 + len(question)], question)

    def test_listed_other_types_are_empty_noerror(self):
        for qtype in (28, 64, 65, 16):
            response = self.answer(make_query("github.com", qtype=qtype))
            parsed = parse_response(response)
            self.assertEqual(parsed["rcode"], 0, qtype)
            self.assertEqual(parsed["ancount"], 0, qtype)
            self.assertTrue(parsed["aa"])
            self.assertTrue(parsed["ra"])

    def test_actions_wildcard_and_case(self):
        response = self.answer(
            make_query("RUN-ACTIONS-1-AZURE-EASTUS.ACTIONS.GITHUBUSERCONTENT.COM")
        )
        parsed = parse_response(response)
        self.assertEqual(parsed["rcode"], 0)
        self.assertEqual(parsed["ancount"], 1)

    def test_two_label_actions_name_is_nxdomain(self):
        response = self.answer(make_query("a.b.actions.githubusercontent.com"))
        parsed = parse_response(response)
        self.assertEqual(parsed["rcode"], 3)
        self.assertEqual(parsed["ancount"], 0)

    def test_unlisted_names_are_nxdomain(self):
        for name in (
            "m2.dv8tion.net",
            "ghcr.io",
            "evil.example",
            "productionresultssa9999.blob.core.windows.net",
        ):
            response = self.answer(make_query(name))
            parsed = parse_response(response)
            self.assertEqual(parsed["rcode"], 3, name)
            self.assertEqual(parsed["ancount"], 0, name)
            self.assertEqual(parsed["qdcount"], 1, name)

    def test_malformed_queries_are_dropped_or_formerr(self):
        self.assertIsNone(self.answer(b"\x12\x34"))
        self.assertIsNone(self.answer(make_query("github.com", flags=0x8100)))
        for qdcount in (0, 2):
            response = self.answer(
                make_query("github.com", qdcount=qdcount)
            )
            self.assertEqual(parse_response(response)["rcode"], 1, qdcount)
        self.assertEqual(
            parse_response(self.answer(make_query("github.com", opcode=2)))["rcode"],
            4,
        )
        self.assertEqual(
            parse_response(self.answer(make_query("github.com", qclass=3)))["rcode"],
            1,
        )

    def test_bad_question_shapes_are_formerr(self):
        header = struct.pack("!HHHHHH", 7, 0x0100, 1, 0, 0, 0)
        cases = [
            header + b"\xc0\x0c" + struct.pack("!HH", 1, 1),
            header + b"\x40" + b"x" * 64 + b"\x00" + struct.pack("!HH", 1, 1),
            header + b"\x05ab" + b"\x00" + struct.pack("!HH", 1, 1),
            header + b"\x0agithub.com\x00" + struct.pack("!HH", 1, 1),
            header + b"\x04git\x00github\x00" + struct.pack("!HH", 1, 1),
            header + b"\x03g\x00t\x00" + struct.pack("!HH", 1, 1),
        ]
        for data in cases:
            response = self.answer(data)
            self.assertIsNotNone(response)
            self.assertEqual(parse_response(response)["rcode"], 1)

    def test_additional_records_do_not_break_the_answer(self):
        query = make_query("github.com", extra=b"\x00" + struct.pack("!HHIH", 41, 1232, 0, 0))
        parsed = parse_response(self.answer(query))
        self.assertEqual(parsed["rcode"], 0)
        self.assertEqual(parsed["ancount"], 1)

    def test_tcp_framing_one_query_per_connection(self):
        query = make_query("github.com")

        class FakeConn:
            def __init__(self, payload):
                self.payload = payload
                self.sent = b""
                self.closed = False

            def settimeout(self, _):
                pass

            def recv(self, count):
                chunk = self.payload[:count]
                self.payload = self.payload[count:]
                return chunk

            def sendall(self, data):
                self.sent += data

            def close(self):
                self.closed = True

        conn = FakeConn(struct.pack("!H", len(query)) + query)
        self.dns.handle_tcp_connection(conn, self.allow)
        self.assertTrue(conn.closed)
        self.assertTrue(conn.sent.startswith(struct.pack("!H", len(conn.sent) - 2)))
        parsed = parse_response(conn.sent[2:])
        self.assertEqual(parsed["rcode"], 0)
        self.assertEqual(parsed["ancount"], 1)

    def test_tcp_rejects_empty_or_truncated_framing(self):
        class FakeConn:
            def __init__(self, payload):
                self.payload = payload
                self.sent = b""
                self.closed = False

            def settimeout(self, _):
                pass

            def recv(self, count):
                chunk = self.payload[:count]
                self.payload = self.payload[count:]
                return chunk

            def sendall(self, data):
                self.sent += data

            def close(self):
                self.closed = True

        for payload in (b"", b"\x00\x00", b"\x00\x10short"):
            conn = FakeConn(payload)
            self.dns.handle_tcp_connection(conn, self.allow)
            self.assertTrue(conn.closed)
            self.assertEqual(conn.sent, b"")


class ConnectionThreadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dns = load_module("dns")
        cls.allow = cls.dns.load_allow()

    def test_refused_thread_closes_only_that_connection(self):
        class FakeConn:
            def __init__(self):
                self.closed = False

            def close(self):
                self.closed = True

        class RefusingThread:
            def __init__(self, *args, **kwargs):
                pass

            def start(self):
                raise RuntimeError("can't start new thread")

        conn = FakeConn()
        with mock.patch.object(self.dns.threading, "Thread", RefusingThread):
            self.dns.start_connection(conn, self.allow)
        self.assertTrue(conn.closed)

    def test_started_thread_is_daemon(self):
        seen = {}

        class Recorder:
            def __init__(self, **kwargs):
                seen.update(kwargs)

            def start(self):
                seen["started"] = True

        class FakeConn:
            def close(self):
                pass

        with mock.patch.object(self.dns.threading, "Thread", Recorder):
            self.dns.start_connection(FakeConn(), self.allow)
        self.assertTrue(seen.get("started"))
        self.assertTrue(seen.get("daemon"))
        self.assertIs(seen.get("target"), self.dns.handle_tcp_connection)


class ProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = load_module("deny_probe")

    def run_probe(self, factory):
        module = types.SimpleNamespace(
            socket=lambda *args, **kwargs: factory(),
            AF_INET=2,
            SOCK_DGRAM=2,
        )
        with mock.patch.object(self.probe, "socket", module), mock.patch("sys.stderr"):
            return self.probe.main()

    def test_eperm_is_the_only_success(self):
        addresses = []

        class FakeSocket:
            def sendto(self, data, address):
                addresses.append((data, address))
                raise OSError(errno.EPERM, "denied")

            def close(self):
                pass

        self.assertEqual(self.run_probe(FakeSocket), 0)
        self.assertEqual(addresses, [(b"", ("192.0.2.1", 9))])

    def test_other_errno_and_success_fail(self):
        class OtherErrno:
            def sendto(self, data, address):
                raise OSError(errno.EACCES, "blocked")

            def close(self):
                pass

        class Reachable:
            def sendto(self, data, address):
                return len(data)

            def close(self):
                pass

        self.assertEqual(self.run_probe(OtherErrno), 1)
        self.assertEqual(self.run_probe(Reachable), 1)


class NixTextTests(unittest.TestCase):
    def nix_code(self):
        text = NIX_FILE.read_text(encoding="utf-8")
        return "\n".join(
            line for line in text.splitlines() if not line.lstrip().startswith("#")
        )

    def test_module_is_off_by_default_and_has_one_gate(self):
        text = NIX_FILE.read_text(encoding="utf-8")
        self.assertEqual(text.count("lib.mkIf cfg.enable"), 1)
        self.assertEqual(text.count("lib.mkEnableOption"), 1)
        self.assertNotIn("wantedBy", text)
        self.assertNotIn("enable = true", text)
        self.assertNotIn("RefuseManualStart", text)
        self.assertIn("services.project-alpha-console-egress", text)

    def test_exec_assignments_are_pinned_in_order(self):
        expected = [
            'ExecStart = "${pkgs.python3}/bin/python3 -I -B ${assets}/overlap.py";',
            'ExecStart = "${netnsSetup}/bin/project-alpha-egress-netns-setup";',
            'ExecStart = "${pkgs.python3}/bin/python3 -I -B ${assets}/dns.py";',
            'ExecStartPre = "${pkgs.python3}/bin/python3 -I -B ${assets}/deny_probe.py";',
            'ExecStart = "${pkgs.haproxy}/bin/haproxy -db -f ${assets}/haproxy.cfg";',
            'ExecStartPost = "${pkgs.coreutils}/bin/sleep 1";',
            'ExecStart = "${pkgs.passt}/bin/passt ${lib.escapeShellArgs units.passtArgs}";',
        ]
        actual = [
            " ".join(line.split())
            for line in self.nix_code().splitlines()
            if re.match(r"\s*Exec[A-Za-z]*\s*=", line)
        ]
        self.assertEqual(actual, expected)

    def test_relay_deny_is_set_once_and_allow_is_absent(self):
        code = self.nix_code()
        self.assertEqual(code.count("IPAddressDeny"), 1)
        self.assertIn("IPAddressDeny = denyAddresses;", code)
        deny = code.index("IPAddressDeny = denyAddresses;")
        self.assertLess(code.index("systemd.services.project-alpha-egress-relay"), deny)
        self.assertLess(deny, code.index("systemd.sockets.project-alpha-egress ="))
        self.assertNotIn("IPAddressAllow", code)

    def test_list_reader_definitions_are_exact(self):
        code = self.nix_code()
        read_list = re.search(r"readList\s*=.*?\bentries;", code, re.DOTALL)
        self.assertIsNotNone(read_list)
        self.assertEqual(
            " ".join(read_list.group(0).split()),
            'readList = file: let strip = line: lib.removeSuffix "\\r" '
            '(builtins.head (lib.splitString "#" line)); entries = map strip '
            '(lib.splitString "\\n" (builtins.readFile file)); in '
            'builtins.filter (entry: entry != "") entries;',
        )
        deny = re.search(r"denyAddresses\s*=.*?;", code, re.DOTALL)
        self.assertIsNotNone(deny)
        self.assertEqual(
            " ".join(deny.group(0).split()),
            'denyAddresses = readList (assets + "/deny-ipv4.list") '
            '++ readList (assets + "/deny-ipv6.list");',
        )

    def test_runner_gets_only_the_two_a8_lines(self):
        text = RUNNER_FILE.read_text(encoding="utf-8")
        self.assertEqual(
            text.count('requires = [ "project-alpha-egress.socket" ];'), 1
        )
        self.assertEqual(
            text.count('after = [ "project-alpha-egress.socket" ];'), 1
        )

    def test_console_imports_the_module_once(self):
        text = (HERE.parents[2] / "configurations/nixos/console/default.nix").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            text.count(
                "../../../modules/nixos/console/project-alpha-egress.nix"
            ),
            1,
        )

    def test_asset_directory_is_complete(self):
        for name in (
            "allow-exact.list",
            "deny-ipv4.list",
            "deny-ipv6.list",
            "haproxy.cfg",
            "namespace.nft",
            "netns-setup.sh",
            "dns.py",
            "overlap.py",
            "deny_probe.py",
            "units.json",
        ):
            self.assertTrue((ASSETS / name).is_file(), name)

    def test_overlap_unit_gets_iproute2_on_path(self):
        text = NIX_FILE.read_text(encoding="utf-8")
        self.assertEqual(text.count("path = [ pkgs.iproute2 ];"), 1)
        start = text.index("systemd.services.project-alpha-egress-overlap")
        end = text.index("systemd.services.project-alpha-egress-netns")
        self.assertIn("path = [ pkgs.iproute2 ];", text[start:end])

    def test_egress_socket_parent_regex(self):
        text = NIX_FILE.read_text(encoding="utf-8")
        match = re.search(
            r'builtins\.match "([^"]+)" runner\.egressSocket', text
        )
        self.assertIsNotNone(match)
        compiled = re.compile(match.group(1))
        accepted = [
            "/run/project-alpha-egress/gateway",
            "/run/project-alpha-egress/gw.sock",
            "/run/project-alpha-a0/a-b_c.d",
            "/run/project-alpha-9/Z",
        ]
        rejected = [
            "/run/systemd/x",
            "/run/wrappers/x",
            "/run/../x",
            "/run/x",
            "/run/other/x",
            "/run/project-alpha-/x",
            "/run/project-alpha-egress/",
            "/run/project-alpha-egress/a/b",
            "/tmp/project-alpha-egress/x",
            "/run/project-alpha-egress/.hidden",
            "/run/project-alpha-egress/-x",
        ]
        for path in accepted:
            self.assertIsNotNone(compiled.fullmatch(path), path)
        for path in rejected:
            self.assertIsNone(compiled.fullmatch(path), path)

    def test_python_entries_are_isolated_and_bytecode_free(self):
        text = NIX_FILE.read_text(encoding="utf-8")
        lines = [line for line in text.splitlines() if "/bin/python3" in line]
        self.assertEqual(len(lines), 3)
        for line in lines:
            self.assertIn("/bin/python3 -I -B ", line)


if __name__ == "__main__":
    unittest.main(verbosity=2)
