#!/usr/bin/env python3
"""Loopback-only Context-Mesh proxy using a TPM-sealed Kong app password."""

import base64
import hashlib
import http.client
import json
import logging
import os
import posixpath
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8790
MESH_PREFIX = "/mcp/agents/context-mesh"
UPSTREAM_HOST = "kong.panic.ac"
UPSTREAM_PORT = 443
TOKEN_URL = "https://auth.panic.ac/application/o/token/"
CLIENT_ID = "kong-ai"
USERNAME = "kong-ai-nixos-workstation-operator-console"
SCOPE = "openid kong-ai"
EXPIRY_MARGIN_SECONDS = 60
TOKEN_TIMEOUT_SECONDS = 15
UPSTREAM_TIMEOUT_SECONDS = 3600
ALLOWED_TOOL_NAMES = {"search", "get_schema", "call"}
ALLOWED_SOURCE_PREFIXES = ("context7.", "deepwiki.", "octocode.")
ALLOWED_METHODS = {"initialize", "ping", "tools/list", "tools/call"}
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}
log = logging.getLogger("context-mesh-proxy")


class AuthError(Exception):
    """The local credential is missing or rejected by the token endpoint."""


class UpstreamError(Exception):
    """An upstream service could not be reached."""


def in_prefix(raw_path, prefixes=(MESH_PREFIX,)):
    """Accept only canonical paths inside an allowed prefix."""
    path = raw_path.split("?", 1)[0].split("#", 1)[0]
    decoded = urllib.parse.unquote(path)
    if "\\" in decoded or "\x00" in decoded or "//" in decoded:
        return False
    if any(segment in (".", "..") for segment in decoded.split("/")):
        return False
    normalized = posixpath.normpath(decoded)
    return any(normalized == prefix or normalized.startswith(prefix + "/") for prefix in prefixes)


def jwt_exp(token):
    """Return the exp claim of an unverified JWT, or None."""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return float(json.loads(base64.urlsafe_b64decode(payload))["exp"])
    except (IndexError, ValueError, KeyError, TypeError):
        return None


def mint_token(username, password):
    body = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": CLIENT_ID,
            "username": username,
            "password": password,
            "scope": SCOPE,
        }
    ).encode()
    request = urllib.request.Request(TOKEN_URL, data=body, method="POST")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(request, timeout=TOKEN_TIMEOUT_SECONDS) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as err:
        if err.code in (400, 401, 403):
            raise AuthError("token refused") from None
        raise UpstreamError("token endpoint status %d" % err.code) from None
    except (urllib.error.URLError, OSError, ValueError):
        raise UpstreamError("token endpoint unreachable") from None
    token = payload.get("access_token")
    if not token:
        raise AuthError("no access_token")
    exp = jwt_exp(token)
    if exp is None:
        exp = time.time() + float(payload.get("expires_in", 0))
    return token, exp


class TokenCache:
    def __init__(self, mint=mint_token, clock=time.time):
        self._mint = mint
        self._clock = clock
        self._lock = threading.Lock()
        self._entries = {}

    @staticmethod
    def _key(username, password):
        return hashlib.sha256((username + ":" + password).encode()).hexdigest()

    def get(self, username, password):
        key = self._key(username, password)
        with self._lock:
            entry = self._entries.get(key)
            if entry and self._clock() < entry[1] - EXPIRY_MARGIN_SECONDS:
                return entry[0]
        token, exp = self._mint(username, password)
        with self._lock:
            self._entries[key] = (token, exp)
        return token

    def drop(self, username, password):
        with self._lock:
            self._entries.pop(self._key(username, password), None)


def allowed_json_rpc(body):
    """Fail closed on malformed JSON-RPC and disallowed tools/call requests."""
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    def reject_constant(_value):
        raise ValueError("non-standard JSON constant")

    try:
        payload = json.loads(body.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=reject_constant)
    except (UnicodeDecodeError, ValueError):
        return False, None, None
    items = payload if isinstance(payload, list) else [payload]
    if not items or not all(isinstance(item, dict) for item in items):
        return False, None, None
    for item in items:
        request_id = item.get("id")
        if item.get("jsonrpc") != "2.0" or not isinstance(item.get("method"), str):
            return False, request_id, None
        if item["method"] not in ALLOWED_METHODS and not item["method"].startswith("notifications/"):
            return False, request_id, None
        if item["method"] != "tools/call":
            continue
        params = item.get("params")
        if not isinstance(params, dict) or params.get("name") not in ALLOWED_TOOL_NAMES:
            return False, request_id, None
        arguments = params.get("arguments")
        if not isinstance(arguments, dict):
            return False, request_id, None
        name = params["name"]
        if name == "call":
            source_id = arguments.get("id")
            if not isinstance(source_id, str) or not source_id.startswith(ALLOWED_SOURCE_PREFIXES):
                return False, request_id, None
        elif name == "get_schema":
            ids = arguments.get("ids")
            if (
                not isinstance(ids, list)
                or not ids
                or not all(
                    isinstance(source_id, str) and source_id.startswith(ALLOWED_SOURCE_PREFIXES)
                    for source_id in ids
                )
            ):
                return False, request_id, None
    return True, None, payload


def make_handler(cache, password):
    class Handler(BaseHTTPRequestHandler):
        server_version = "context-mesh-proxy"
        sys_version = ""

        def log_message(self, *args):
            pass

        def _reply(self, status, body=b"", content_type="application/json"):
            self.send_response(status)
            if body:
                self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            if body and self.command != "HEAD":
                self.wfile.write(body)

        def _read_body(self):
            length = int(self.headers.get("Content-Length") or 0)
            return self.rfile.read(length) if length else b""

        def _forward(self, token, body):
            target = urllib.parse.urlsplit(self.path)
            suffix = target.path[len(MESH_PREFIX) :]
            upstream_path = "/mcp/squad/homelab/mesh" + suffix
            if target.query:
                upstream_path += "?" + target.query
            connection = http.client.HTTPSConnection(
                UPSTREAM_HOST, UPSTREAM_PORT, timeout=UPSTREAM_TIMEOUT_SECONDS
            )
            excluded = HOP_BY_HOP | {"host", "content-length", "authorization"}
            headers = {key: value for key, value in self.headers.items() if key.lower() not in excluded}
            headers["Authorization"] = "Bearer " + token
            headers["Host"] = UPSTREAM_HOST
            if body:
                headers["Content-Length"] = str(len(body))
            connection.request(self.command, upstream_path, body=body or None, headers=headers)
            return connection, connection.getresponse()

        def _stream(self, connection, response):
            try:
                self.send_response(response.status)
                for key, value in response.getheaders():
                    if key.lower() not in HOP_BY_HOP and key.lower() != "content-length":
                        self.send_header(key, value)
                self.send_header("Connection", "close")
                self.end_headers()
                while True:
                    chunk = response.read1(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            finally:
                connection.close()

        def _handle(self):
            path = urllib.parse.urlsplit(self.path).path
            if path == "/healthz" and self.command == "GET":
                self._reply(200, b"ok\n", "text/plain")
                return
            if not in_prefix(self.path):
                self._reply(404, b"")
                return
            if self.command in ("GET", "DELETE"):
                try:
                    if int(self.headers.get("Content-Length") or 0) > 0 or self.headers.get("Transfer-Encoding"):
                        self._reply(403, b"")
                        return
                except ValueError:
                    self._reply(403, b"")
                    return
            body = self._read_body()
            if self.command in ("GET", "DELETE") and body:
                self._reply(403, b"")
                return
            if self.command == "POST":
                accepted, request_id, payload = allowed_json_rpc(body)
                if not accepted:
                    error = json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "error": {"code": -32000, "message": "Forbidden"},
                        },
                        separators=(",", ":"),
                    ).encode()
                    self._reply(403, error)
                    return
                body = json.dumps(payload, separators=(",", ":")).encode()
            try:
                token = cache.get(USERNAME, password)
                connection, response = self._forward(token, body)
                if response.status == 401:
                    response.read()
                    connection.close()
                    cache.drop(USERNAME, password)
                    connection, response = self._forward(cache.get(USERNAME, password), body)
                self._stream(connection, response)
            except AuthError:
                self._reply(401, b"")
            except (UpstreamError, OSError, http.client.HTTPException, ValueError):
                self._reply(502, b"")

        do_GET = _handle
        do_POST = _handle
        do_DELETE = _handle

    return Handler


def main():
    credentials_directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if not credentials_directory:
        raise SystemExit("systemd credential directory is unavailable")
    try:
        with open(os.path.join(credentials_directory, "kong-ai-operator-console"), encoding="utf-8") as credential:
            password = credential.read().rstrip()
    except OSError:
        raise SystemExit("app-password credential is unavailable") from None
    if not password:
        raise SystemExit("app-password credential is empty")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), make_handler(TokenCache(), password))
    server.serve_forever()


if __name__ == "__main__":
    main()
