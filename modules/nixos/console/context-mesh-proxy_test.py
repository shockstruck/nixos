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
        self.assertEqual(proxy.allowed_json_rpc(json.dumps(batch).encode()), (False, 2))
        allowed = [
            json.loads(rpc("initialize", {}, 1)),
            json.loads(rpc("tools/call", {"name": "search", "arguments": {}}, 2)),
        ]
        self.assertTrue(proxy.allowed_json_rpc(json.dumps(allowed).encode())[0])

    def test_other_methods_notifications_and_malformed_json(self):
        self.assertTrue(proxy.allowed_json_rpc(rpc("initialize", {}))[0])
        self.assertTrue(proxy.allowed_json_rpc(rpc("notifications/initialized", None, None))[0])
        self.assertEqual(proxy.allowed_json_rpc(b"not json"), (False, None))


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

    def do_POST(self):
        type(self).seen.append((self.path, self.headers.get("Authorization")))
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
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

    def request(self, path, body, authorization="Bearer caller-supplied-value"):
        connection = proxy.http.client.HTTPConnection("127.0.0.1", self.proxy_server.server_port, timeout=5)
        connection.request(
            "POST",
            path,
            body=body,
            headers={"Content-Type": "application/json", "Authorization": authorization},
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
            [("/mcp/squad/homelab/mesh/tools/list?cursor=a%2Fb", "Bearer minted-jwt-1")],
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
        self.assertEqual([auth for _, auth in Upstream.seen], ["Bearer minted-jwt-1", "Bearer minted-jwt-2"])
        self.assertEqual(len(self.mints), 2)


if __name__ == "__main__":
    unittest.main()
