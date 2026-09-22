#!/usr/bin/env python3
"""Regression tests for the isolated loopback fixture, without WebKit or DNS."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from urllib.request import urlopen
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "web_capture_fixture", Path(__file__).with_name("web-capture-fixture.py"))
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)

RUNNER_SPEC = importlib.util.spec_from_file_location(
    "web_capture_runner", Path(__file__).with_name("test-web-capture.py"))
RUNNER = importlib.util.module_from_spec(RUNNER_SPEC)
RUNNER_SPEC.loader.exec_module(RUNNER)


class FixtureStartupTests(unittest.TestCase):
    def test_binding_numeric_loopback_never_resolves_a_hostname(self):
        with patch("socket.getfqdn", side_effect=AssertionError("Unexpected DNS lookup")):
            with FIXTURE.FixtureServer() as server:
                self.assertEqual(server.server_address[0], "127.0.0.1")
                self.assertEqual(server.server_name, "localhost")
                self.assertGreater(server.server_port, 0)

    def test_real_fixture_serves_locally_and_retains_startup_log(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with RUNNER.loopback_fixture(output) as port:
                with urlopen(f"http://127.0.0.1:{port}/ledger", timeout=2) as response:
                    self.assertEqual(response.read(), b"[]")
            log = (output / "fixture.log").read_text()
            self.assertIn("Binding loopback fixture", log)
            self.assertIn(f"Loopback fixture ready on port {port}", log)
            self.assertFalse((output / "port.pending").exists())

    def test_failed_child_keeps_its_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            script = output / "failed-fixture.py"
            script.write_text("import sys\nprint('synthetic startup failure', file=sys.stderr)\nsys.exit(7)\n")
            with self.assertRaisesRegex(RuntimeError, r"exit 7.*fixture.log"):
                with RUNNER.loopback_fixture(output, script=script):
                    self.fail("A failed fixture cannot become ready")
            self.assertIn("synthetic startup failure", (output / "fixture.log").read_text())

    def test_readiness_timeout_remains_fail_closed_with_a_log(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            script = output / "waiting-fixture.py"
            script.write_text("import time\ntime.sleep(60)\n")
            with self.assertRaisesRegex(RuntimeError, "readiness timeout.*fixture.log"):
                with RUNNER.loopback_fixture(output, script=script, startup_timeout=0):
                    self.fail("An unready fixture cannot run tests")
            self.assertIn("Starting isolated loopback fixture", (output / "fixture.log").read_text())


if __name__ == "__main__":
    unittest.main()
