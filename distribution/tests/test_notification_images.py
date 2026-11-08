#!/usr/bin/env python3
"""Check screenshot history fallback, saving and cache retention without a desktop."""
import base64
from datetime import datetime
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / "shell/assets/notification_tools.py"
spec = importlib.util.spec_from_file_location("notification_tools", SOURCE)
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")


class ScreenshotImages(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hs-notification-images-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / "cache"
        self.history = self.root / "history.json"
        self.original = self.root / "original.png"
        self.original.write_bytes(PNG)
        self.patches = patch.multiple(tools, CACHE=self.cache, STATE=self.history)
        self.patches.start()
        self.addCleanup(self.patches.stop)

    def test_preview_uses_cached_image_after_original_is_removed(self):
        cached = Path(tools.cache_image(str(self.original))["path"])
        self.assertEqual(cached.read_bytes(), PNG)
        self.original.unlink()
        # A history click must resolve a real image without launching another app.
        with patch.object(tools.subprocess, "Popen", side_effect=AssertionError("external viewer")):
            result = tools.screenshot_action("preview", str(self.original), str(cached))
        self.assertEqual(result, {"action": "preview", "path": str(cached)})

    def test_missing_image_reports_an_error(self):
        self.original.unlink()
        with self.assertRaisesRegex(ValueError, "no longer available"):
            tools.screenshot_action("preview", str(self.original), "")

    def test_save_respects_custom_directory_and_never_overwrites(self):
        directory = self.root / "Снимки экрана"
        class Clock:
            @staticmethod
            def now(): return datetime(2026, 11, 8, 12, 0)
        with patch.dict(os.environ, HYPRSTACK_SCREENSHOTS_DIR=str(directory)), patch.object(tools, "datetime", Clock):
            saved = Path(tools.screenshot_action("save", str(self.original), "")["path"])
            self.assertEqual(saved.parent, directory)
            self.assertEqual(saved.read_bytes(), PNG)
            self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                tools.screenshot_action("save", str(self.original), "")
            self.assertEqual(saved.read_bytes(), PNG)

    def test_pruning_keeps_images_referenced_by_notification_history(self):
        cached = Path(tools.cache_image(str(self.original))["path"])
        unreferenced = self.cache / ("0" * 64 + ".png")
        unreferenced.write_bytes(PNG)
        for path in [cached, unreferenced]:
            os.utime(path, (time.time() - 1000,) * 2)
        self.history.write_text(json.dumps({"notifications": [{"image": str(cached)}]}))
        self.assertEqual(tools.prune_cache()["removed"], 1)
        self.assertTrue(cached.is_file())
        self.assertTrue(self.original.is_file())


if __name__ == "__main__":
    unittest.main()
