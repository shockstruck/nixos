import importlib.util
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "context_mesh_proxy", os.path.join(os.path.dirname(__file__), "context-mesh-proxy.py")
)
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


def rpc(method, params=None, request_id=1):
    payload = {"jsonrpc": "2.0", "id": request_id, "method": method}
    if params is not None:
        payload["params"] = params
    return json.dumps(payload).encode()


class FilterTest(unittest.TestCase):
    def test_allowed_tools_and_source_ids(self):
        for name, arguments in (
            ("search", {}),
            ("get_schema", {"ids": ["context7.lib"]}),
            ("call", {"id": "octocode.search", "arguments": {}}),
            ("call", {"id": "deepwiki.repo", "arguments": {}}),
        ):
            with self.subTest(name=name, arguments=arguments):
                self.assertTrue(proxy.allowed_json_rpc(rpc("tools/call", {"name": name, "arguments": arguments}))[0])

    def test_disallowed_tools_and_source_ids(self):
        denied = (
            {"name": "annotate", "arguments": {}},
            {"name": "relate", "arguments": {}},
            {"name": "review_annotations", "arguments": {}},
            {"name": "unknown", "arguments": {}},
            {"name": "call", "arguments": {"id": "kubernetes.pods"}},
            {"name": "get_schema", "arguments": {"ids": ["context7.lib", "supabase.query"]}},
        )
        for params in denied:
            with self.subTest(params=params):
                self.assertEqual(proxy.allowed_json_rpc(rpc("tools/call", params))[0], False)

    def test_batch_checks_every_element_and_echoes_denied_id(self):
        batch = [
            json.loads(rpc("tools/call", {"name": "search", "arguments": {}}, 1)),
            json.loads(rpc("tools/call", {"name": "call", "arguments": {"id": "flux.resources"}}, 2)),
        ]
        self.assertEqual(proxy.allowed_json_rpc(json.dumps(batch).encode()), (False, 2, None))
        allowed = [
            json.loads(rpc("initialize", {}, 1)),
            json.loads(rpc("tools/call", {"name": "search", "arguments": {}}, 2)),
        ]
        self.assertTrue(proxy.allowed_json_rpc(json.dumps(allowed).encode())[0])

    def test_other_methods_notifications_and_malformed_json(self):
        self.assertTrue(proxy.allowed_json_rpc(rpc("initialize", {}))[0])
        self.assertTrue(proxy.allowed_json_rpc(rpc("ping", {}))[0])
        self.assertTrue(proxy.allowed_json_rpc(rpc("notifications/initialized", None, None))[0])
        self.assertEqual(proxy.allowed_json_rpc(b"not json"), (False, None, None))

    def test_unlisted_json_rpc_methods_are_refused(self):
        for method in ("resources/list", "prompts/get", "completion/complete"):
            with self.subTest(method=method):
                self.assertFalse(proxy.allowed_json_rpc(rpc(method))[0])

    def test_duplicate_keys_and_nonstandard_numbers_are_refused(self):
        for body in (
            b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","name":"relate","arguments":{}}}',
            b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"call","arguments":{"id":"context7.ok","id":"supabase.no"}}}',
            b'{"jsonrpc":"2.0","id":1,"method":"ping","params":{"value":NaN}}',
            b'{"jsonrpc":"2.0","id":1,"method":"ping","params":{"value":Infinity}}',
        ):
            with self.subTest(body=body):
                self.assertFalse(proxy.allowed_json_rpc(body)[0])


class PathTest(unittest.TestCase):
    def test_mesh_prefix_and_query_are_allowed(self):
        for path in (
            "/mcp/agents/context-mesh",
            "/mcp/agents/context-mesh/",
            "/mcp/agents/context-mesh/sse?a=1",
        ):
            with self.subTest(path=path):
                self.assertTrue(proxy.in_prefix(path))

    def test_traversal_and_noncanonical_paths_are_denied(self):
        base = "/mcp/agents/context-mesh"
        for path in (
            base + "/../../claude/v1/messages",
            base + "/%2e%2e/%2e%2e/claude/v1/messages",
            base + "/%2E%2E/%2E%2E/claude/v1/messages",
            base + "/./x",
            base + "//x",
            base + "/%2fx",
            base + "/..%5cx",
            base + "/x%00",
            "/mcp/agents/context-meshX",
        ):
            with self.subTest(path=path):
                self.assertFalse(proxy.in_prefix(path))


class Upstream(BaseHTTPRequestHandler):
    seen = []
    reject_first = False

    def log_message(self, *args):
        pass

    def _handle(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        type(self).seen.append((self.command, self.path, self.headers.get("Authorization"), body))
        if type(self).reject_first and len(type(self).seen) == 1:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b"streamed response"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_DELETE = _handle


class ForwardingTest(unittest.TestCase):
    def setUp(self):
        Upstream.seen = []
        Upstream.reject_first = False
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        self.proxy_server = ThreadingHTTPServer(
            ("127.0.0.1", 0), proxy.make_handler(proxy.TokenCache(mint=self.mint), "test-password")
        )
        self.threads = []
        for server in (self.upstream, self.proxy_server):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)
        self.connection_patch = mock.patch.object(
            proxy.http.client,
            "HTTPSConnection",
            side_effect=lambda host, port, timeout: proxy.http.client.HTTPConnection(
                "127.0.0.1", self.upstream.server_port, timeout=timeout
            ),
        )
        self.connection_patch.start()
        self.mints = []

    def tearDown(self):
        self.connection_patch.stop()
        for server in (self.proxy_server, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=2)

    def mint(self, username, password):
        self.mints.append((username, password))
        return "minted-jwt-%d" % len(self.mints), 4102444800.0

    def request(self, path, body, authorization="Bearer caller-supplied-value", method="POST", headers=None):
        connection = proxy.http.client.HTTPConnection("127.0.0.1", self.proxy_server.server_port, timeout=5)
        request_headers = {"Content-Type": "application/json", "Authorization": authorization}
        request_headers.update(headers or {})
        connection.request(
            method,
            path,
            body=body,
            headers=request_headers,
        )
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_incoming_authorization_is_replaced_and_path_query_rewritten(self):
        status, body = self.request(
            "/mcp/agents/context-mesh/tools/list?cursor=a%2Fb", rpc("tools/list", {})
        )
        self.assertEqual((status, body), (200, b"streamed response"))
        self.assertEqual(
            Upstream.seen,
            [
                (
                    "POST",
                    "/mcp/squad/homelab/mesh/tools/list?cursor=a%2Fb",
                    "Bearer minted-jwt-1",
                    b'{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}',
                )
            ],
        )
        self.assertNotIn("caller-supplied-value", repr(Upstream.seen))
        self.assertEqual(
            self.mints,
            [(proxy.USERNAME, "test-password")],
        )

    def test_denied_filter_returns_json_rpc_error_before_mint_or_forward(self):
        status, body = self.request(
            "/mcp/agents/context-mesh",
            rpc("tools/call", {"name": "call", "arguments": {"id": "supabase.query"}}, 42),
        )
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body)["id"], 42)
        self.assertEqual(self.mints, [])
        self.assertEqual(Upstream.seen, [])

    def test_cache_and_single_remint_after_401(self):
        Upstream.reject_first = True
        status, _ = self.request("/mcp/agents/context-mesh", rpc("initialize", {}))
        self.assertEqual(status, 200)
        self.assertEqual([auth for _, _, auth, _ in Upstream.seen], ["Bearer minted-jwt-1", "Bearer minted-jwt-2"])
        self.assertEqual(len(self.mints), 2)

    def test_get_and_delete_bodies_are_refused_without_mint_or_forward(self):
        for method in ("GET", "DELETE"):
            with self.subTest(method=method):
                status, _ = self.request("/mcp/agents/context-mesh", b"non-empty", method=method)
                self.assertEqual(status, 403)
        status, _ = self.request(
            "/mcp/agents/context-mesh", None, method="GET", headers={"Content-Length": "1"}
        )
        self.assertEqual(status, 403)
        self.assertEqual(self.mints, [])
        self.assertEqual(Upstream.seen, [])

    def test_get_and_delete_without_bodies_forward_empty_bodies(self):
        for method in ("GET", "DELETE"):
            with self.subTest(method=method):
                status, _ = self.request("/mcp/agents/context-mesh", None, method=method)
                self.assertEqual(status, 200)
        self.assertEqual([item[0] for item in Upstream.seen], ["GET", "DELETE"])
        self.assertEqual([item[3] for item in Upstream.seen], [b"", b""])

    def test_duplicate_keys_fail_closed_and_accepted_json_is_canonical(self):
        duplicated = (
            b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","name":"relate","arguments":{}}}',
            b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"call","arguments":{"id":"context7.ok","id":"supabase.no"}}}',
        )
        for body in duplicated:
            with self.subTest(body=body):
                status, _ = self.request("/mcp/agents/context-mesh", body)
                self.assertEqual(status, 403)
        self.assertEqual(self.mints, [])
        self.assertEqual(Upstream.seen, [])

        raw = b'{ "jsonrpc" : "2.0", "id" : 7, "method" : "tools/list" }'
        canonical = b'{"jsonrpc":"2.0","id":7,"method":"tools/list"}'
        status, _ = self.request("/mcp/agents/context-mesh", raw)
        self.assertEqual(status, 200)
        self.assertEqual(Upstream.seen[-1][3], canonical)


if __name__ == "__main__":
    unittest.main()
