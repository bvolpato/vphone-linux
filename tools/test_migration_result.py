#!/usr/bin/env python3
"""Focused tests for the first-boot migration acceptance gate."""

import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path


HELPER_PATH = Path(__file__).with_name("migration-result.py")
SPEC = importlib.util.spec_from_file_location("migration_result", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
migration_result = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(migration_result)


class MigrationResultTests(unittest.TestCase):
    def _rpc(self, result):
        return json.dumps({"id": 1, "result": result})

    def _migration(self, build="22C", success=True):
        return self._rpc({"values": {"DMLastMigrationResults": {"value": {
            "buildVersion": build,
            **({"success": success} if success is not None else {}),
        }}}})

    def test_expected_build_requires_one_matching_prepared_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            restore = root / "iPhone17,3_Restore"
            restore.mkdir()
            manifest = restore / "iPhone-BuildManifest.plist"
            with manifest.open("wb") as stream:
                plistlib.dump({
                    "SupportedProductTypes": ["iPhone17,3"],
                    "ProductVersion": "27.2",
                    "ProductBuildVersion": "22C123",
                }, stream)

            self.assertEqual(
                migration_result.expected_build(root, "iPhone17,3", "27.2", "22C123"),
                "22C123",
            )
            with self.assertRaisesRegex(ValueError, "contradicts"):
                migration_result.expected_build(root, "iPhone17,3", "27.2", "22C999")
            with self.assertRaisesRegex(ValueError, "does not support"):
                migration_result.expected_build(root, "iPhone18,2", "27.2", "22C123")
            with self.assertRaisesRegex(ValueError, "contradicts"):
                migration_result.expected_build(root, "iPhone17,3", "26.6.2", "22C123")
            duplicate = root / "iPhone17,3_other_Restore"
            duplicate.mkdir()
            with self.assertRaisesRegex(ValueError, "expected one"):
                migration_result.expected_build(root, "iPhone17,3", "27.2", "22C123")

    def test_accepts_only_matching_success_and_completed_setup(self):
        setup_done = self._rpc({"data_migration_done": True})
        self.assertEqual(migration_result.migration_status(self._migration(), setup_done, "22C"), 0)
        self.assertEqual(migration_result.migration_status(self._migration(success=1), setup_done, "22C"), 0)
        self.assertEqual(migration_result.migration_status(self._migration("21A"), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(success=False), setup_done, "22C"), 2)
        self.assertEqual(migration_result.migration_status(self._migration(success=0), setup_done, "22C"), 2)
        self.assertEqual(migration_result.migration_status(self._migration("21A", success=False), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(success=None), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(success="true"), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(success="1"), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(success=1.0), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(success=2), setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(), self._rpc({"data_migration_done": False}), "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(), self._rpc({"data_migration_done": 1}), "22C"), 1)

    def test_malformed_or_failed_guest_responses_never_accept(self):
        setup_done = self._rpc({"data_migration_done": True})
        self.assertEqual(migration_result.migration_status("not json", setup_done, "22C"), 1)
        guest_error = json.dumps({"id": 1, "error": {"code": "unavailable"}})
        self.assertEqual(migration_result.migration_status(guest_error, setup_done, "22C"), 1)
        self.assertEqual(migration_result.migration_status(self._migration(), "not json", "22C"), 1)


if __name__ == "__main__":
    unittest.main()
