#!/usr/bin/env python3
"""Runs the job-started hook only as a stubbed copy.

The committed hook terminates every process it can signal. This test never
executes that file and never runs its fail path with the real call: it checks
the committed text, writes a copy whose one such call is replaced by a
recorder, and runs only the copy under `bash -euo pipefail` with an explicit
minimal environment that is never inherited from the test process.
"""

import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "project-alpha-job-started.sh")
KILL_CALL = "builtin kill -KILL -1"
MESSAGE = "Project Alpha runner job started outside the pinned repository"
REPOSITORY_ID = "1207177553"
SERVER_URL = "https://github.com"


def code_lines(text):
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            lines.append(line)
    return lines


class HookTextTest(unittest.TestCase):
    def setUp(self):
        with open(SCRIPT, encoding="utf-8") as handle:
            self.text = handle.read()

    def test_first_line_is_the_shellcheck_directive_and_there_is_no_shebang(self):
        self.assertEqual(self.text.splitlines()[0], "# shellcheck shell=bash")
        self.assertFalse(self.text.startswith("#!"))

    def test_kill_appears_once_on_the_fallback_line(self):
        code = "\n".join(code_lines(self.text))
        self.assertEqual(code.count("kill"), 1)
        kill_lines = [line.strip() for line in code_lines(self.text) if "kill" in line]
        self.assertEqual(len(kill_lines), 1)
        self.assertTrue(kill_lines[0].startswith(KILL_CALL))
        self.assertEqual(kill_lines[0][len(KILL_CALL):].strip(), "|| true")


class HookBehaviourTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.copy_path = os.path.join(self.temporary.name, "hook.sh")
        self.recorder = os.path.join(self.temporary.name, "recorder")
        with open(SCRIPT, encoding="utf-8") as handle:
            text = handle.read()
        self.assertEqual(text.count(KILL_CALL), 1)
        stubbed = text.replace(KILL_CALL, 'printf "hit\\n" >> "$RECORDER"')
        self.assertNotIn("kill", stubbed)
        with open(self.copy_path, "w", encoding="utf-8") as handle:
            handle.write(stubbed)

    def run_hook(self, **overrides):
        env = {"PATH": "/usr/bin:/bin", "RECORDER": self.recorder}
        env.update(overrides)
        return subprocess.run(
            ["bash", "-euo", "pipefail", self.copy_path],
            capture_output=True,
            text=True,
            env=env,
        )

    def recorded(self):
        if not os.path.exists(self.recorder):
            return []
        with open(self.recorder, encoding="utf-8") as handle:
            return handle.read().splitlines()

    def assert_failed(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, MESSAGE + "\n")
        self.assertEqual(self.recorded(), ["hit"])

    def test_pass(self):
        result = self.run_hook(GITHUB_REPOSITORY_ID=REPOSITORY_ID, GITHUB_SERVER_URL=SERVER_URL)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.recorded(), [])

    def test_failures(self):
        good = {"GITHUB_REPOSITORY_ID": REPOSITORY_ID, "GITHUB_SERVER_URL": SERVER_URL}
        cases = {
            "id-absent": {"GITHUB_SERVER_URL": SERVER_URL},
            "url-absent": {"GITHUB_REPOSITORY_ID": REPOSITORY_ID},
            "both-absent": {},
            "id-empty": {**good, "GITHUB_REPOSITORY_ID": ""},
            "url-empty": {**good, "GITHUB_SERVER_URL": ""},
            "id-wrong": {**good, "GITHUB_REPOSITORY_ID": "1207177554"},
            "url-wrong": {**good, "GITHUB_SERVER_URL": "https://example.invalid"},
            "id-trailing-newline": {**good, "GITHUB_REPOSITORY_ID": REPOSITORY_ID + "\n"},
            "url-trailing-newline": {**good, "GITHUB_SERVER_URL": SERVER_URL + "\n"},
            "id-surrounding-space": {**good, "GITHUB_REPOSITORY_ID": " " + REPOSITORY_ID + " "},
            "url-surrounding-space": {**good, "GITHUB_SERVER_URL": " " + SERVER_URL + " "},
            "id-leading-zero": {**good, "GITHUB_REPOSITORY_ID": "0" + REPOSITORY_ID},
            "http": {**good, "GITHUB_SERVER_URL": "http://github.com"},
            "trailing-slash": {**good, "GITHUB_SERVER_URL": SERVER_URL + "/"},
            "upper-case-host": {**good, "GITHUB_SERVER_URL": "https://GitHub.com"},
        }
        for name, env in cases.items():
            with self.subTest(name=name):
                if os.path.exists(self.recorder):
                    os.unlink(self.recorder)
                self.assert_failed(self.run_hook(**env))


if __name__ == "__main__":
    unittest.main()
