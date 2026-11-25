#!/usr/bin/env python3
"""Answer the guest's DNS sinkhole from the exact allow list.

The daemon receives one TCP listening socket and one UDP socket through
systemd socket activation, classifies them with SO_TYPE, and never creates a
socket of its own. It never forwards a query and never logs a guest-supplied
name: a rejection is a fixed rcode, an accepted name is not logged at all.

Listed A queries answer 198.18.0.1 with TTL 60. Listed AAAA, SVCB, HTTPS and
every other type answer NOERROR with an empty answer section; unlisted names
answer NXDOMAIN. AA and RA are set because glibc treats an empty NOERROR with
neither as a lame referral. Malformed queries are FORMERR or dropped, never
forwarded.

Standard library only.
"""

import os
import re
import selectors
import socket
import struct
import sys
import threading
import time
from pathlib import Path

ACTIONS_RE = re.compile(r"\A[a-z0-9-]+\.actions\.githubusercontent\.com\Z")
ALLOW_FILE = Path(__file__).with_name("allow-exact.list")

GATEWAY_ADDRESS = "198.18.0.1"
ANSWER_TTL = 60
TCP_DEADLINE_SECONDS = 2.0
UDP_MAX_BYTES = 4096
TCP_MAX_QUERY = 4096

RCODE_NOERROR = 0
RCODE_FORMERR = 1
RCODE_NXDOMAIN = 3
RCODE_NOTIMP = 4

QTYPE_A = 1
QCLASS_IN = 1


class FormatError(Exception):
    """The query cannot be parsed far enough to answer it."""


class HeaderError(Exception):
    """The header is readable, but the query is not a single standard query."""

    def __init__(self, qid, flags, rcode):
        super().__init__(rcode)
        self.qid = qid
        self.flags = flags
        self.rcode = rcode


def load_allow(path=ALLOW_FILE):
    names = set()
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        names.add(line.lower())
    return names


def name_allowed(name, allow):
    lowered = name.lower()
    return lowered in allow or ACTIONS_RE.match(lowered) is not None


def parse_header(data):
    if len(data) < 12:
        raise FormatError("short header")
    qid, flags, qdcount, ancount, nscount, arcount = struct.unpack(
        "!HHHHHH", data[:12]
    )
    if flags & 0x8000:
        raise FormatError("response bit set")
    opcode = (flags >> 11) & 0xF
    if opcode != 0:
        raise HeaderError(qid, flags, RCODE_NOTIMP)
    if qdcount != 1:
        raise HeaderError(qid, flags, RCODE_FORMERR)
    return qid, flags, opcode


def parse_question(data):
    qid, flags, opcode = parse_header(data)
    offset = 12
    labels = []
    while True:
        if offset >= len(data):
            raise HeaderError(qid, flags, RCODE_FORMERR)
        length = data[offset]
        if length == 0:
            offset += 1
            break
        if length & 0xC0 or length > 63:
            raise HeaderError(qid, flags, RCODE_FORMERR)
        offset += 1
        if offset + length > len(data):
            raise HeaderError(qid, flags, RCODE_FORMERR)
        label = data[offset : offset + length]
        # A dot or NUL inside a label would conflate names when joined and
        # could smuggle a listed name past the exact comparison.
        if b"." in label or b"\x00" in label:
            raise HeaderError(qid, flags, RCODE_FORMERR)
        labels.append(label)
        offset += length
    if offset + 4 > len(data):
        raise HeaderError(qid, flags, RCODE_FORMERR)
    qtype, qclass = struct.unpack("!HH", data[offset : offset + 4])
    name = ".".join(label.decode("ascii", "replace") for label in labels)
    return qid, flags, opcode, name, qtype, qclass, data[12 : offset + 4]


def _flags(flags, rcode):
    # QR, copy opcode and RD, always AA and RA.
    return 0x8000 | (flags & 0x7800) | (flags & 0x0100) | 0x0400 | 0x0080 | rcode


def _reply(qid, flags, question, answer):
    return (
        struct.pack(
            "!HHHHHH",
            qid,
            flags,
            1 if question else 0,
            1 if answer else 0,
            0,
            0,
        )
        + question
        + answer
    )


def _a_answer():
    # Compression pointer to the question name at offset 12.
    return (
        b"\xc0\x0c"
        + struct.pack("!HHIH", QTYPE_A, QCLASS_IN, ANSWER_TTL, 4)
        + socket.inet_aton(GATEWAY_ADDRESS)
    )


def answer_query(data, allow):
    """Return response bytes, or None when the datagram must be dropped."""
    try:
        qid, flags, opcode, name, qtype, qclass, question = parse_question(data)
    except HeaderError as exc:
        return _reply(exc.qid, _flags(exc.flags, exc.rcode), b"", b"")
    except FormatError:
        return None

    if qclass != QCLASS_IN:
        return _reply(qid, _flags(flags, RCODE_FORMERR), b"", b"")

    if not name_allowed(name, allow):
        return _reply(
            qid, _flags(flags, RCODE_NXDOMAIN), question, b""
        )
    if qtype == QTYPE_A:
        return _reply(qid, _flags(flags, RCODE_NOERROR), question, _a_answer())
    return _reply(qid, _flags(flags, RCODE_NOERROR), question, b"")


def read_exact(conn, count, deadline):
    chunks = bytearray()
    while len(chunks) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        conn.settimeout(remaining)
        try:
            chunk = conn.recv(count - len(chunks))
        except OSError:
            return None
        if not chunk:
            return None
        chunks.extend(chunk)
    return bytes(chunks)


def handle_tcp_connection(conn, allow):
    deadline = time.monotonic() + TCP_DEADLINE_SECONDS
    try:
        header = read_exact(conn, 2, deadline)
        if header is None:
            return
        (length,) = struct.unpack("!H", header)
        if length == 0 or length > TCP_MAX_QUERY:
            return
        data = read_exact(conn, length, deadline)
        if data is None:
            return
        response = answer_query(data, allow)
        if response is None:
            return
        conn.sendall(struct.pack("!H", len(response)) + response)
    except OSError:
        return
    finally:
        conn.close()


def handle_udp(sock, allow):
    try:
        data, peer = sock.recvfrom(UDP_MAX_BYTES)
    except OSError:
        return
    response = answer_query(data, allow)
    if response is None:
        return
    try:
        sock.sendto(response, peer)
    except OSError:
        return


def listen_fds():
    pid = os.environ.get("LISTEN_PID")
    try:
        count = int(os.environ.get("LISTEN_FDS", "0"))
        pid_ok = pid is not None and int(pid) == os.getpid()
    except ValueError:
        count = 0
        pid_ok = False
    if count < 1 or not pid_ok:
        raise SystemExit("dns: expected systemd socket activation")
    return range(3, 3 + count)


def serve(allow):
    selector = selectors.DefaultSelector()
    for fd in listen_fds():
        sock = socket.socket(fileno=fd)
        kind = sock.getsockopt(socket.SOL_SOCKET, socket.SO_TYPE)
        if kind == socket.SOCK_DGRAM:
            selector.register(sock, selectors.EVENT_READ, handle_udp)
        elif kind == socket.SOCK_STREAM:
            selector.register(sock, selectors.EVENT_READ, None)
        else:
            raise SystemExit("dns: unexpected socket type")

    while True:
        for key, _ in selector.select():
            if key.data is None:
                try:
                    conn, _ = key.fileobj.accept()
                except OSError:
                    continue
                conn.setblocking(True)
                threading.Thread(
                    target=handle_tcp_connection,
                    args=(conn, allow),
                    daemon=True,
                ).start()
            else:
                key.data(key.fileobj, allow)


def main():
    serve(load_allow())


if __name__ == "__main__":
    sys.exit(main())
