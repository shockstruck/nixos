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
RUNNER_USER = pwd.getpwuid(os.getuid()).pw_name
CREDENTIALS = {"scheme": "OAuth", "token": "placeholder"}

# The shape recorded from a real JIT `.runner` in 2023: PascalCase keys,
# string booleans, a null pool name and no GitHubUrl.
RECORDED_RUNNER = {
    "AgentId": "1",
    "AgentName": "example-runner",
    "DisableUpdate": "True",
    "Ephemeral": "True",
    "PoolId": "1",
    "PoolName": None,
    "ServerUrl": EXPECTED_URL,
    "WorkFolder": "_work",
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
    }
    fields.update(overrides)
    return fields


def without(fields, key):
    result = dict(fields)
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
        self.assertEqual(self.state_files(), [])

    def test_valid_camel_case_runner_is_written_normalised(self):
        self.assert_accepted(self.decode(payload_for(runner_fields())), runner_fields())

    def test_valid_with_rsaparams(self):
        self.assert_accepted(
            self.decode(payload_for(runner_fields(), rsaparams="placeholder-rsa-parameters")),
            runner_fields(),
            expected_files=(".credentials", ".credentials_rsaparams", ".runner"),
        )

    def test_recorded_shape_with_pinned_url_is_accepted(self):
        fields = dict(RECORDED_RUNNER)
        fields["GitHubUrl"] = EXPECTED_URL
        self.assert_accepted(self.decode(payload_for(fields)), fields)

    def test_rejections(self):
        cases = {
            "not-base64": ("not base64!", "JIT payload is not valid base64"),
            "not-json": (b64("not json"), "JIT payload is not a JSON object"),
            "missing-both": (outer({"other": b64("{}")}), "JIT payload names unsupported runner state: other"),
            "missing-credentials": (
                outer({".runner": b64(json.dumps(runner_fields()))}),
                "JIT payload is missing .runner or .credentials",
            ),
            "unexpected-filename": (
                payload_for(runner_fields(), extra={".agent": b64("{}")}),
                "JIT payload names unsupported runner state: .agent",
            ),
            "unexpected-traversal": (
                payload_for(runner_fields(), extra={"../../etc/evil": b64("{}")}),
                "JIT payload names unsupported runner state: ../../etc/evil",
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
            "recorded-shape-verbatim": (
                payload_for(RECORDED_RUNNER),
                "JIT .runner state is missing gitHubUrl",
            ),
            "another-repository": (
                payload_for(runner_fields(gitHubUrl="https://github.com/project-alpha-rsps/other")),
                "JIT .runner state gitHubUrl does not match the expected repository",
            ),
            "organization-url": (
                payload_for(runner_fields(gitHubUrl="https://github.com/project-alpha-rsps")),
                "JIT .runner state gitHubUrl does not match the expected repository",
            ),
            "trailing-slash": (
                payload_for(runner_fields(gitHubUrl=EXPECTED_URL + "/")),
                "JIT .runner state gitHubUrl does not match the expected repository",
            ),
            "upper-case-host": (
                payload_for(runner_fields(gitHubUrl="https://GitHub.com/project-alpha-rsps/server")),
                "JIT .runner state gitHubUrl does not match the expected repository",
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


if __name__ == "__main__":
    unittest.main()
