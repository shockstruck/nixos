#!/usr/bin/env bash
# Prepare the egress network namespace. The only unit with a capability:
# systemd creates a private network namespace (PrivateNetwork=) and this
# script holds CAP_NET_ADMIN inside it, so the guard below runs before any
# change and refuses to touch a namespace that looks like the host's.
#
# The guest reaches only 198.18.0.1 in this namespace. passt presents that
# gateway address, answers DHCP itself, and splices guest flows onto the DNS
# socket and the relay socket listening here. There is no forwarding, no
# default route and no NAT.
#
# shellcheck shell=bash

set -euo pipefail

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Before any change: only `lo` may be up, no non-loopback address may exist,
# and the ruleset must be empty. A missing PrivateNetwork= would otherwise
# have this script firewall the host.
links_up=$(ip -o link show up | awk -F': ' '{ print $2 }' | grep -vx 'lo' || true)
[ -z "$links_up" ] || fail "egress namespace guard: a non-loopback link is up"

addresses=$(ip -o addr show | awk '$2 != "lo" { print $2 " " $4 }')
[ -z "$addresses" ] || fail "egress namespace guard: a non-loopback address exists"

ruleset=$(nft list ruleset)
[ -z "$ruleset" ] || fail "egress namespace guard: the ruleset is not empty"

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# Order matters: the drop-by-default firewall exists before the interface can
# carry a single packet.
nft -f "$here/namespace.nft"
ip link add pa-egress0 type dummy
ip addr add 198.18.0.1/30 dev pa-egress0
ip link set pa-egress0 up

# A namespace that inherited a default route could leave without the relay.
if [ -n "$(ip -4 route show default)" ] || [ -n "$(ip -6 route show default)" ]; then
    fail "egress namespace guard: a default route exists"
fi
