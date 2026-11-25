#!/usr/bin/env python3
"""Fail unless the egress cgroup filter turns a denied UDP send into EPERM.

`IPAddressDeny=` has no effect where the kernel or systemd lacks eBPF cgroup
support, so a deny list alone can be silently absent. This probe runs before
the relay starts: the only acceptable outcome is EPERM. Reaching the
documentation-range address, or any other errno, fails the unit with fixed
text.

Standard library only; sends one empty datagram and exits.
"""

import errno
import socket
import sys

DENIED_ADDRESS = "192.0.2.1"
DENIED_PORT = 9
UNEXPECTED = "egress deny probe: the deny filter did not return EPERM"
REACHABLE = "egress deny probe: the denied destination was reachable"


def main():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.sendto(b"", (DENIED_ADDRESS, DENIED_PORT))
    except OSError as exc:
        if exc.errno == errno.EPERM:
            return 0
        print(UNEXPECTED, file=sys.stderr)
        return 1
    finally:
        probe.close()
    print(REACHABLE, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
