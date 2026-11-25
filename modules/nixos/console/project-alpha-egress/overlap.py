#!/usr/bin/env python3
"""Refuse to start the egress namespace if 198.18.0.0/30 overlaps the host.

Runs in the host namespace before the private one exists. `ip -4 route show
table all` is deliberate: plain `ip -4 route` misses policy-routing tables
such as NetBird's. Any command error, JSON error or unexpected shape is a
refusal, not a warning.

Standard library only; does not create a socket.
"""

import ipaddress
import json
import subprocess
import sys

CONTRACT = ipaddress.ip_network("198.18.0.0/30")


class ParseError(Exception):
    """The host's `ip` output could not be trusted."""


def parse_json(text, what):
    try:
        value = json.loads(text)
    except (TypeError, ValueError) as exc:
        raise ParseError(f"{what} output is not valid JSON") from exc
    if not isinstance(value, list):
        raise ParseError(f"{what} output is not a JSON list")
    return value


def parse_routes(text):
    prefixes = []
    for entry in parse_json(text, "ip route"):
        if not isinstance(entry, dict) or not isinstance(entry.get("dst"), str):
            raise ParseError("ip route entry has no destination")
        if entry["dst"] == "default":
            continue
        try:
            prefixes.append(ipaddress.ip_network(entry["dst"], strict=False))
        except ValueError as exc:
            raise ParseError("ip route destination is not a prefix") from exc
    return prefixes


def parse_addresses(text):
    prefixes = []
    for entry in parse_json(text, "ip addr"):
        if not isinstance(entry, dict):
            raise ParseError("ip addr entry is not an object")
        infos = entry.get("addr_info")
        if not isinstance(infos, list):
            raise ParseError("ip addr entry has no addr_info list")
        for info in infos:
            if not isinstance(info, dict):
                raise ParseError("ip addr addr_info entry is not an object")
            if info.get("family") != "inet":
                continue
            local = info.get("local")
            prefixlen = info.get("prefixlen")
            if not isinstance(local, str) or not isinstance(prefixlen, int):
                raise ParseError("ip addr entry is missing local or prefixlen")
            try:
                prefixes.append(
                    ipaddress.ip_network(f"{local}/{prefixlen}", strict=False)
                )
            except ValueError as exc:
                raise ParseError("ip addr local is not an address") from exc
    return prefixes


def overlaps(prefixes):
    return [str(prefix) for prefix in prefixes if prefix.overlaps(CONTRACT)]


def run_ip(*args):
    try:
        result = subprocess.run(
            ["ip", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ParseError("ip could not be run") from exc
    if result.returncode != 0:
        raise ParseError(f"ip {args[-1]} failed")
    return result.stdout


def main():
    try:
        prefixes = parse_routes(run_ip("-4", "-j", "route", "show", "table", "all"))
        prefixes += parse_addresses(run_ip("-4", "-j", "addr"))
    except ParseError as exc:
        print(f"egress overlap check failed: {exc}", file=sys.stderr)
        return 1
    bad = overlaps(prefixes)
    if bad:
        print(
            "egress overlap check failed: 198.18.0.0/30 overlaps "
            + ", ".join(bad),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
