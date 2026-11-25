#!/usr/bin/env python3
"""Runs the committed JIT-state decoder against synthetic payloads.

The decoder is the `.sh` fragment the guest module embeds in a
`writeShellApplication`; it is executed here under `bash -euo pipefail` with
the current user, so every payload is built in code and no encoded blob or key
is stored in the repository.
"""

import base64
import json
import os
import pwd
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "project-alpha-jit-state.sh")
EXPECTED_URL = "https://github.com/project-alpha-rsps/server"
SERVICE_URL = "https://pipelines.actions.githubusercontent.com/placeholder/"
SERVICE_URL_V2 = "https://pipelines.actions.githubusercontent.com/v2/another"
RUNNER_USER = pwd.getpwuid(os.getuid()).pw_name
CREDENTIALS = {"scheme": "OAuth", "token": "placeholder"}

STATE_MESSAGE = "JIT payload names unsupported runner state"
GITHUB_URL_MESSAGE = "JIT .runner state gitHubUrl does not match the expected repository"
SERVICE_MESSAGE = "JIT .runner state has no valid runner service URL"

# The shape recorded from a real JIT `.runner` in 2023: PascalCase keys,
# string booleans, a null pool name and no GitHubUrl.
RECORDED_RUNNER = {
    "AgentId": "1",
    "AgentName": "example-runner",
    "DisableUpdate": "True",
    "Ephemeral": "True",
    "PoolId": "1",
    "PoolName": None,
    "ServerUrl": "https://pipelines.actions.githubusercontent.com/placeholder/",
    "WorkFolder": "_work",
}

# Each of these is rejected by guest rule 2's service-host pattern.
BAD_SERVICE_URLS = {
    "userinfo": "https://user@pipelines.actions.githubusercontent.com/placeholder",
    "port": "https://pipelines.actions.githubusercontent.com:443/placeholder",
    "host-suffix": "https://pipelines.actions.githubusercontent.com.evil.example/",
    "backslash": "https://pipelines.actions.githubusercontent.com\\placeholder",
    "embedded-newline": "https://pipelines.actions.githubusercontent.com/place\nholder",
    "trailing-newline": "https://pipelines.actions.githubusercontent.com/placeholder\n",
    "http": "http://pipelines.actions.githubusercontent.com/placeholder",
    "upper-case-host": "https://Pipelines.actions.githubusercontent.com/placeholder",
    "empty-label": "https://.actions.githubusercontent.com/placeholder",
    "query": "https://pipelines.actions.githubusercontent.com/?job=1",
    "fragment": "https://pipelines.actions.githubusercontent.com/#job",
    "missing-host-label": "https://actions.githubusercontent.com/placeholder",
}


def b64(value):
    if isinstance(value, str):
        value = value.encode()
    return base64.b64encode(value).decode()


def outer(files):
    return b64(json.dumps(files))


def payload_for(runner, credentials=CREDENTIALS, rsaparams=None, extra=None):
    files = {
        ".runner": b64(runner if isinstance(runner, str) else json.dumps(runner)),
        ".credentials": b64(credentials if isinstance(credentials, str) else json.dumps(credentials)),
    }
    if rsaparams is not None:
        files[".credentials_rsaparams"] = b64(rsaparams)
    files.update(extra or {})
    return outer(files)


def runner_fields(**overrides):
    fields = {
        "agentId": "1",
        "agentName": "example-runner",
        "ephemeral": True,
        "workFolder": "_work",
        "gitHubUrl": EXPECTED_URL,
        "serverUrl": SERVICE_URL,
    }
    fields.update(overrides)
    return fields


def without(fields, *keys):
    result = dict(fields)
    for key in keys:
        del result[key]
    return result


class DecoderTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.runner_root = os.path.join(self.temporary.name, "runner")
        os.mkdir(self.runner_root)
        self.tmpdir = os.path.join(self.temporary.name, "tmp")
        os.mkdir(self.tmpdir)
        self.payload_path = os.path.join(self.temporary.name, "payload")

    def decode(self, content):
        if isinstance(content, str):
            content = content.encode()
        with open(self.payload_path, "wb") as handle:
            handle.write(content)
        return subprocess.run(
            [
                "bash",
                "-euo",
                "pipefail",
                SCRIPT,
                self.payload_path,
                self.runner_root,
                RUNNER_USER,
                EXPECTED_URL,
            ],
            capture_output=True,
            text=True,
            env={**os.environ, "TMPDIR": self.tmpdir},
        )

    def state_files(self):
        return sorted(os.listdir(self.runner_root))

    def assert_accepted(self, result, expected_runner, expected_files=(".credentials", ".runner")):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.state_files(), sorted(expected_files))
        for name in self.state_files():
            mode = stat.S_IMODE(os.stat(os.path.join(self.runner_root, name)).st_mode)
            self.assertEqual(mode, 0o600, name)
        with open(os.path.join(self.runner_root, ".runner")) as handle:
            written = handle.read()
        self.assertEqual(written.rstrip("\n"), json.dumps(expected_runner, separators=(",", ":")))
        self.assertEqual(json.loads(written), expected_runner)

    def assert_rejected(self, result, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.state_files(), [])

    def assert_rejected_exactly(self, result, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, message + "\n")
        self.assertEqual(self.state_files(), [])

    def test_valid_camel_case_runner_is_written_normalised(self):
        self.assert_accepted(self.decode(payload_for(runner_fields())), runner_fields())

    def test_valid_with_rsaparams(self):
        self.assert_accepted(
            self.decode(payload_for(runner_fields(), rsaparams="placeholder-rsa-parameters")),
            runner_fields(),
            expected_files=(".credentials", ".credentials_rsaparams", ".runner"),
        )

    def test_recorded_shape_verbatim_is_accepted(self):
        self.assert_accepted(self.decode(payload_for(RECORDED_RUNNER)), RECORDED_RUNNER)

    def test_githuburl_absent_is_accepted(self):
        fields = without(runner_fields(), "gitHubUrl")
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_githuburl_case_variant_is_accepted(self):
        fields = without(runner_fields(), "gitHubUrl")
        fields["GitHubUrl"] = EXPECTED_URL
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_serverurl_only_is_accepted(self):
        fields = without(runner_fields(), "gitHubUrl")
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_serverurlv2_only_is_accepted(self):
        fields = without(runner_fields(), "gitHubUrl", "serverUrl")
        fields["serverUrlV2"] = SERVICE_URL_V2
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_both_service_urls_are_accepted(self):
        fields = runner_fields(serverUrlV2=SERVICE_URL_V2)
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_case_variant_service_keys_are_accepted(self):
        fields = without(runner_fields(), "gitHubUrl", "serverUrl")
        fields["ServerUrl"] = SERVICE_URL
        fields["SERVERURLV2"] = SERVICE_URL_V2
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_githuburl_rejections(self):
        cases = {
            "null": (runner_fields(gitHubUrl=None), GITHUB_URL_MESSAGE),
            "empty": (runner_fields(gitHubUrl=""), GITHUB_URL_MESSAGE),
            "non-string": (runner_fields(gitHubUrl=123), GITHUB_URL_MESSAGE),
            "case-variant-mismatch": (
                {**without(runner_fields(), "gitHubUrl"), "GitHubUrl": "https://github.com/project-alpha-rsps/other"},
                GITHUB_URL_MESSAGE,
            ),
        }
        for name, (fields, message) in cases.items():
            with self.subTest(name=name):
                self.assert_rejected(self.decode(payload_for(fields)), message)

    def test_service_url_rejections(self):
        cases = {
            "neither": (without(runner_fields(), "gitHubUrl", "serverUrl"), SERVICE_MESSAGE),
            "serverurl-null": (runner_fields(serverUrl=None), SERVICE_MESSAGE),
            "serverurl-empty": (runner_fields(serverUrl=""), SERVICE_MESSAGE),
            "serverurl-non-string": (runner_fields(serverUrl=123), SERVICE_MESSAGE),
            "serverurlv2-null": (runner_fields(serverUrlV2=None), SERVICE_MESSAGE),
            "serverurlv2-empty": (runner_fields(serverUrlV2=""), SERVICE_MESSAGE),
            "serverurlv2-non-string": (runner_fields(serverUrlV2=123), SERVICE_MESSAGE),
            "serverurl-good-v2-bad": (runner_fields(serverUrlV2="https://example.invalid/"), SERVICE_MESSAGE),
            "serverurl-bad-v2-good": (
                runner_fields(serverUrl="https://example.invalid/", serverUrlV2=SERVICE_URL_V2),
                SERVICE_MESSAGE,
            ),
        }
        for name, (fields, message) in cases.items():
            with self.subTest(name=name):
                self.assert_rejected(self.decode(payload_for(fields)), message)

    def test_bad_service_url_forms(self):
        for key in ("serverUrl", "serverUrlV2"):
            for name, url in BAD_SERVICE_URLS.items():
                with self.subTest(key=key, name=name):
                    fields = runner_fields(**{key: url})
                    self.assert_rejected(self.decode(payload_for(fields)), SERVICE_MESSAGE)

    def test_rejections(self):
        bad_runner = json.dumps(runner_fields(ephemeral=False))
        good_runner = json.dumps(runner_fields())
        good_payload = outer(
            {".runner": b64(good_runner), ".credentials": b64(json.dumps(CREDENTIALS))}
        )
        two_credentials = json.dumps(CREDENTIALS) + "\n" + json.dumps({"scheme": "OAuth"})
        cases = {
            "not-base64": ("not base64!", "JIT payload is not valid base64"),
            "not-json": (b64("not json"), "JIT payload is not a JSON object"),
            "payload-two-documents": (
                good_payload + "\n" + good_payload,
                "JIT payload is not a JSON object",
            ),
            "runner-two-documents-bad-good": (
                payload_for(bad_runner + "\n" + good_runner),
                "JIT .runner state is not an object with unique alphanumeric keys",
            ),
            "runner-two-documents-good-bad": (
                payload_for(good_runner + "\n" + bad_runner),
                "JIT .runner state is not an object with unique alphanumeric keys",
            ),
            "credentials-two-documents": (
                payload_for(runner_fields(), credentials=two_credentials),
                "JIT .credentials state is not a JSON object",
            ),
            "trailing-newline-key": (
                payload_for({**runner_fields(), "a\n": "placeholder"}),
                "JIT .runner state is not an object with unique alphanumeric keys",
            ),
            "missing-both": (outer({"other": b64("{}")}), STATE_MESSAGE),
            "missing-credentials": (
                outer({".runner": b64(json.dumps(runner_fields()))}),
                "JIT payload is missing .runner or .credentials",
            ),
            "unexpected-filename": (
                payload_for(runner_fields(), extra={".agent": b64("{}")}),
                STATE_MESSAGE,
            ),
            "unexpected-traversal": (
                payload_for(runner_fields(), extra={"../../etc/evil": b64("{}")}),
                STATE_MESSAGE,
            ),
            "non-ephemeral": (payload_for(runner_fields(ephemeral=False)), "JIT .runner state is not ephemeral"),
            "missing-workfolder": (
                payload_for(without(runner_fields(), "workFolder")),
                "JIT .runner state has no non-empty workFolder",
            ),
            "runner-not-base64": (
                outer({".runner": "not base64!", ".credentials": b64(json.dumps(CREDENTIALS))}),
                "JIT .runner state is not valid base64",
            ),
            "bad-rsaparams": (
                outer(
                    {
                        ".runner": b64(json.dumps(runner_fields())),
                        ".credentials": b64(json.dumps(CREDENTIALS)),
                        ".credentials_rsaparams": "not base64!",
                    }
                ),
                "JIT .credentials_rsaparams state is not valid base64",
            ),
            "credentials-not-json": (
                payload_for(runner_fields(), credentials="not json"),
                "JIT .credentials state is not a JSON object",
            ),
            "another-repository": (
                payload_for(runner_fields(gitHubUrl="https://github.com/project-alpha-rsps/other")),
                GITHUB_URL_MESSAGE,
            ),
            "organization-url": (
                payload_for(runner_fields(gitHubUrl="https://github.com/project-alpha-rsps")),
                GITHUB_URL_MESSAGE,
            ),
            "trailing-slash": (
                payload_for(runner_fields(gitHubUrl=EXPECTED_URL + "/")),
                GITHUB_URL_MESSAGE,
            ),
            "upper-case-host": (
                payload_for(runner_fields(gitHubUrl="https://GitHub.com/project-alpha-rsps/server")),
                GITHUB_URL_MESSAGE,
            ),
            "duplicate-ephemeral": (
                payload_for({**runner_fields(), "Ephemeral": "True"}),
                "JIT .runner state is not an object with unique alphanumeric keys",
            ),
            "duplicate-githuburl": (
                payload_for({**runner_fields(), "GitHubUrl": EXPECTED_URL}),
                "JIT .runner state is not an object with unique alphanumeric keys",
            ),
            "non-alphanumeric-key": (
                payload_for({**runner_fields(), "Work Folder": "_work"}),
                "JIT .runner state is not an object with unique alphanumeric keys",
            ),
            "ephemeral-false-string": (
                payload_for(runner_fields(ephemeral="False")),
                "JIT .runner state is not ephemeral",
            ),
            "ephemeral-one-string": (
                payload_for(runner_fields(ephemeral="1")),
                "JIT .runner state is not ephemeral",
            ),
            "ephemeral-one-number": (
                payload_for(runner_fields(ephemeral=1)),
                "JIT .runner state is not ephemeral",
            ),
            "ephemeral-yes": (
                payload_for(runner_fields(ephemeral="yes")),
                "JIT .runner state is not ephemeral",
            ),
            "ephemeral-null": (
                payload_for(runner_fields(ephemeral=None)),
                "JIT .runner state is not ephemeral",
            ),
            "ephemeral-absent": (
                payload_for(without(runner_fields(), "ephemeral")),
                "JIT .runner state is not ephemeral",
            ),
        }
        for name, (content, message) in cases.items():
            with self.subTest(name=name):
                self.assert_rejected(self.decode(content), message)

    def test_outer_key_rejections_print_one_fixed_line(self):
        marker = "MARKER_FROM_PAYLOAD"
        cases = {
            "empty": {"": b64("{}")},
            "newline": {"\n": b64("{}")},
            "marker": {marker: b64("{}")},
            "ansi-newline-marker": {"\x1b[31m\n" + marker: b64("{}")},
        }
        for name, extra in cases.items():
            with self.subTest(name=name):
                result = self.decode(payload_for(runner_fields(), extra=extra))
                self.assert_rejected_exactly(result, STATE_MESSAGE)
                self.assertNotIn(marker, result.stdout + result.stderr)

    def test_payload_values_never_reach_either_stream(self):
        marker = "MARKER_FROM_PAYLOAD"
        cases = {
            "gitHubUrl": (runner_fields(gitHubUrl=marker), GITHUB_URL_MESSAGE),
            "serverUrl": (runner_fields(serverUrl=marker), SERVICE_MESSAGE),
            "serverUrlV2": (runner_fields(serverUrlV2=marker), SERVICE_MESSAGE),
        }
        for name, (fields, message) in cases.items():
            with self.subTest(name=name):
                result = self.decode(payload_for(fields))
                self.assert_rejected_exactly(result, message)
                self.assertNotIn(marker, result.stdout)
                self.assertNotIn(marker, result.stderr)


if __name__ == "__main__":
    unittest.main()
