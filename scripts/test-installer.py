#!/usr/bin/env python3
"""Validate installer file operations with isolated destinations and mocked macOS tools.

These tests do not establish that the real macOS bundle builds or launches.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="atb-installer-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repo = self.root / "repo"
        shutil.copytree(ROOT / "scripts", self.repo / "scripts")
        shutil.copytree(ROOT / "Resources", self.repo / "Resources")
        for notice in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
            shutil.copy2(ROOT / notice, self.repo / notice)
        self.bin = self.root / "tools"
        self.bin.mkdir()
        self.products = self.root / "products"
        self.products.mkdir()
        for name in ("AgentTouchbar", "atb"):
            (self.products / name).write_text("new binary")
        self.tool("uname", "echo Darwin")
        self.tool("swift", 'case " $* " in *" --show-bin-path "*) echo "$TEST_PRODUCTS" ;; esac')
        self.tool("codesign", 'if [ "${FAIL_VERIFY:-0}" = 1 ] && [ "$1" = --verify ]; then exit 1; fi')
        self.tool("ditto", '/bin/cp -R "$1" "$2"')
        self.tool("pkill", "exit 0")
        self.tool("open", 'exit "${FAIL_OPEN:-0}"')
        self.destination = self.root / "Applications"
        self.app = self.destination / "agentTouchbar.app"
        self.app.mkdir(parents=True)
        (self.app / "previous.txt").write_text("previous installation")
        self.links = self.root / "links"
        self.environment = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                                TEST_PRODUCTS=str(self.products), INSTALL_DIR=str(self.destination),
                                BIN_DIR=str(self.links))

    def tool(self, name, command):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -e\n" + command + "\n")
        path.chmod(0o755)

    def install(self, **changes):
        return subprocess.run(["bash", str(self.repo / "scripts/install.sh")],
                              env=dict(self.environment, **changes), text=True,
                              capture_output=True, timeout=10)

    def test_success_replaces_only_application_and_links_cli(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.app / "Contents/MacOS/atb").read_text(), "new binary")
        self.assertTrue((self.app / "Contents/Resources/THIRD_PARTY_NOTICES.md").is_file())
        self.assertEqual((self.links / "atb").resolve(), self.app / "Contents/MacOS/atb")
        self.assertFalse(list(self.destination.glob(".agentTouchbar-install.*")))

    def test_launch_failure_restores_previous_application(self):
        result = self.install(FAIL_OPEN="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.app / "previous.txt").read_text(), "previous installation")
        self.assertFalse(list(self.destination.glob(".agentTouchbar-install.*")))
        self.assertFalse((self.links / "atb").is_symlink())

    def test_failed_installation_restores_existing_cli_link(self):
        self.links.mkdir()
        previous = self.root / "previous-atb"
        previous.write_text("previous CLI")
        (self.links / "atb").symlink_to(previous)
        self.assertNotEqual(self.install(FAIL_OPEN="1").returncode, 0)
        self.assertEqual((self.links / "atb").resolve(), previous)
        self.assertEqual((self.links / "atb").read_text(), "previous CLI")

    def test_signature_failure_preserves_existing_application(self):
        result = self.install(FAIL_VERIFY="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.app / "previous.txt").read_text(), "previous installation")

    def test_symlink_destination_is_not_replaced(self):
        shutil.rmtree(self.app)
        target = self.root / "untouched.app"
        target.mkdir()
        self.app.symlink_to(target)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertTrue(self.app.is_symlink())
        self.assertTrue(target.is_dir())


if __name__ == "__main__":
    unittest.main(verbosity=2)
