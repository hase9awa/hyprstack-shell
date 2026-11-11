#!/usr/bin/env python3
"""Isolated release/update tests. Never build, log out or modify the desktop."""
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import updates
from update_transaction import File, atomic_json


def release(tag="v2.0.0", **fields):
    return io.BytesIO(json.dumps(dict(tag_name=tag, body="Release notes", draft=False, prerelease=False, **fields)).encode())


def archive(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as tar:
        for name, value in entries:
            member = tarfile.TarInfo(name)
            if isinstance(value, bytes):
                member.size = len(value)
                tar.addfile(member, io.BytesIO(value))
            else:
                member.type, member.linkname = value
                tar.addfile(member)
    return output.getvalue()


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hyprstack updates ")
        self.home = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, {"HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / "config"), "XDG_DATA_HOME": str(self.home / "data"),
            "XDG_STATE_HOME": str(self.home / "state"), "XDG_CACHE_HOME": str(self.home / "cache"),
            "HYPRSTACK_DATA_DIR": str(self.home / "data/hyprstack"), "HYPRLAND_INSTANCE_SIGNATURE": "test-session"})
        self.environment.start()
        self.uid = patch.object(updates.os, "geteuid", return_value=1000)
        self.uid.start()
        self.tools = patch.object(updates.shutil, "which", side_effect=lambda name: "/usr/bin/" + name)
        self.tools.start()
        self.capture = patch.object(updates.deployment, "capture", side_effect=lambda cmd:
            '{"version":"0.57.1","abiHash":"test-abi"}' if cmd[0] == "Hyprland" else "6.10.0")
        self.capture.start()
        self.manager = updates.Updates("1.0.0")
        self.original_root = updates.deployment.ROOT

    def tearDown(self):
        updates.deployment.ROOT = self.original_root
        self.capture.stop()
        self.tools.stop()
        self.uid.stop()
        self.environment.stop()
        self.temporary.cleanup()

    def files(self, stage):
        values = {
            "bin/hyprstack": "NEW BINARY",
            "share/hyprstack/version.json": '{"version":"2.0.0"}',
            "share/hyprstack/shell/assets/hyprland/config/hyprland.lua": "NEW CONFIG",
            "share/hyprstack/shell/assets/hyprland/config/scheme/current.lua": "DEFAULT THEME",
            "share/hyprstack/defaults/hyprstack/shell.json": "DEFAULT SETTINGS",
            "share/hyprstack/defaults/hyprstack/hypr-user.lua": "NEW OWNED CONFIG",
            "share/hyprstack/defaults/xdg-desktop-portal/hyprland-portals.conf": "DEFAULT PORTALS",
            "share/hyprstack/systemd/hyprstack-session.service": "SESSION UNIT",
            "share/hyprstack/systemd/hyprstack-vpn.service": "VPN UNIT",
        }
        for name, text in values.items():
            path = stage / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def staged(self):
        self.files(self.manager.stage)
        self.manager.installation.staging = self.manager.stage
        atomic_json(self.manager.ready_file, {"stage": str(self.manager.stage), "version": "2.0.0",
            "context": self.manager.context(), "abi": "test-abi", "qt": "6.10.0",
            "digest": self.manager.digest(list(self.manager.installation.plan()))})
        self.manager.save(phase="ready", latest_version="2.0.0")

    def installed(self):
        self.binary = self.manager.installation.bin / "hyprstack"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text("OLD BINARY")
        self.settings = self.manager.installation.config / "hyprstack/shell.json"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text("MY SETTINGS")
        self.theme = self.manager.installation.config / "hypr/scheme/current.lua"
        self.theme.parent.mkdir(parents=True)
        self.theme.write_text("MY THEME")

    def test_numeric_versions_prereleases_and_no_downgrades(self):
        self.assertGreater(updates.version("1.10.0"), updates.version("v1.9.9"))
        self.assertGreater(updates.version("1.0.0"), updates.version("1.0.0-rc.1"))
        for invalid in ("main", "v1.2", "v1.2.3/../../main", "1.02.3"):
            with self.assertRaises(ValueError):
                updates.version(invalid)
        for current, available in (("1.0.0", True), ("2.0.0", False), ("2.1.0", False)):
            self.manager.current = current
            with patch.object(updates, "request", return_value=release()):
                self.manager.check()
            self.assertEqual(self.manager.status()["available"], available)

    def test_no_published_releases_and_invalid_release_response(self):
        with patch.object(updates, "request", side_effect=HTTPError(updates.API, 404, "Not found", {}, None)):
            self.assertTrue(self.manager.check()["no_releases"])
        for value in ({"tag_name": "v2.0.0", "prerelease": True}, {"tag_name": "main"}, []):
            with patch.object(updates, "request", return_value=io.BytesIO(json.dumps(value).encode())):
                with self.assertRaises(ValueError):
                    self.manager.check()

    def test_network_failure_retains_the_known_release_and_has_one_json_report(self):
        self.manager.save(phase="idle", latest_version="2.0.0", checked_at=123)
        output = io.StringIO()
        with patch.object(updates, "request", side_effect=URLError("offline")), redirect_stdout(output):
            code = updates.main(["--current-version", "1.0.0", "check"])
        report = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertTrue(report["available"])
        self.assertEqual(report["checked_at"], 123)
        self.assertIn("offline", report["error"])
        self.assertFalse(self.manager.installation.bin.exists())

    def test_concurrent_operation_keeps_the_owners_status(self):
        self.manager.save(phase="building", pid=os.getpid(), latest_version="2.0.0")
        before = self.manager.status_file.read_bytes()
        with updates.deployment.installation_lock(self.manager.installation), redirect_stdout(io.StringIO()):
            self.assertEqual(updates.main(["--current-version", "1.0.0", "check"]), 1)
        self.assertEqual(self.manager.status_file.read_bytes(), before)

    def test_status_recovers_after_interruption_and_corrupt_cache(self):
        self.manager.save(phase="building", pid=999999999)
        self.assertEqual(self.manager.status()["phase"], "error")
        self.manager.status_file.write_text("invalid json")
        self.assertEqual(self.manager.status()["phase"], "idle")
        self.manager.ready_file.write_text("[]")
        self.assertFalse(self.manager.status()["ready"])
        self.manager.status_file.write_text('{"latest_version":23,"phase":[]}')
        self.assertFalse(self.manager.status()["available"])
        self.assertEqual(self.manager.status()["phase"], "idle")

    def test_archive_traversal_and_links_are_rejected(self):
        for name, value in (("../outside", b"bad"), ("/absolute", b"bad"),
                ("root/link", (tarfile.SYMTYPE, "../../outside")),
                ("root/hardlink", (tarfile.LNKTYPE, "/etc/passwd")),
                ("root/pipe", (tarfile.FIFOTYPE, ""))):
            path = self.home / "archive.tar.gz"
            path.write_bytes(archive([(name, value)]))
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                updates.extract(path, self.home / "extracted")
        self.assertFalse((self.home / "outside").exists())

    def test_prepare_builds_a_tag_without_changing_the_installed_files(self):
        self.installed()
        content = archive([
            ("root/CMakeLists.txt", b"project(hyprstack VERSION 2.0.0 LANGUAGES CXX)"),
            ("root/distribution/update.py", b"# updater"), ("root/shell/shell.qml", b"// shell"),
            ("root/third_party/m3shapes/CMakeLists.txt", b"# shapes")])
        def install(command, **kwargs):
            stage = Path(kwargs["env"]["DESTDIR"]) / str(self.home / ".local").lstrip("/")
            self.files(stage)
        with patch.object(updates, "request", side_effect=[release(), io.BytesIO(content)]), \
             patch.object(updates.deployment, "preflight", return_value={"abiHash": "test-abi"}), \
             patch.object(updates.deployment, "build", return_value=self.home / "build"), \
             patch.object(updates.subprocess, "run", side_effect=install):
            self.manager.prepare(2)
        self.assertEqual(self.binary.read_text(), "OLD BINARY")
        self.assertEqual(self.settings.read_text(), "MY SETTINGS")
        self.assertTrue(self.manager.status()["ready"])
        self.manager.prepared()
        self.assertFalse(self.manager.installation.manifest.exists())

    def test_source_version_mismatch_is_rejected_before_build(self):
        content = archive([("root/CMakeLists.txt", b"project(hyprstack VERSION 9.9.9)")])
        with patch.object(updates, "request", side_effect=[release(), io.BytesIO(content)]), \
             patch.object(updates.deployment, "build") as build:
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.manager.prepare(2)
        build.assert_not_called()
        self.assertFalse(self.manager.ready_file.exists())

    def test_changed_stage_context_and_abi_are_rejected_before_logout(self):
        self.staged()
        self.manager.prepared()
        binary = self.manager.stage / "bin/hyprstack"
        binary.write_text("CORRUPTED")
        with self.assertRaisesRegex(ValueError, "staged files have changed"):
            self.manager.prepared()
        binary.write_text("NEW BINARY")
        with patch.object(updates.deployment, "capture", return_value="{}"):
            with self.assertRaisesRegex(ValueError, "changed after the build"):
                self.manager.prepared()
        ready = json.loads(self.manager.ready_file.read_text())
        ready["context"][0] = "/another/user"
        atomic_json(self.manager.ready_file, ready)
        with self.assertRaisesRegex(ValueError, "another installation"):
            self.manager.prepared()

    def test_install_survives_shell_exit_and_passes_explicit_paths_to_systemd(self):
        self.staged()
        with patch.object(updates.subprocess, "run") as run:
            self.manager.start_install()
        command = run.call_args.args[0]
        self.assertEqual(command[0], "systemd-run")
        self.assertIn("--setenv=XDG_DATA_HOME=" + str(self.home / "data"), command)
        self.assertIn("--setenv=HYPRLAND_INSTANCE_SIGNATURE=test-session", command)
        self.assertEqual(command[-1], "_apply")
        self.assertTrue(self.manager.ready_file.exists())

    def test_systemd_failure_keeps_the_build_and_does_not_log_out(self):
        self.staged()
        with patch.object(updates.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "systemd-run", stderr="no user manager")) as run, \
             redirect_stdout(io.StringIO()) as output:
            self.assertEqual(updates.main(["--current-version", "1.0.0", "install"]), 1)
        self.assertIn("no user manager", json.loads(output.getvalue())["error"])
        self.assertEqual(run.call_count, 1)
        self.assertTrue(self.manager.ready_file.exists())

    def test_apply_waits_for_logout_preserves_preferences_and_supports_rollback(self):
        self.installed()
        self.staged()
        commands = []
        with patch.object(updates.subprocess, "run", side_effect=lambda command, **kwargs: commands.append(command)), \
             patch.object(updates.deployment, "active_compositors", side_effect=[["test-session"], [], []]):
            self.manager.apply()
        self.assertIn(["hyprctl", "-i", "test-session", "dispatch", "exit"], commands)
        self.assertEqual(self.binary.read_text(), "NEW BINARY")
        self.assertEqual(self.settings.read_text(), "MY SETTINGS")
        self.assertEqual(self.theme.read_text(), "MY THEME")
        self.assertEqual(self.manager.status()["phase"], "done")
        self.assertFalse(self.manager.ready_file.exists())
        with redirect_stdout(io.StringIO()):
            updates.deployment.rollback(self.manager.installation)
        self.assertEqual(self.binary.read_text(), "OLD BINARY")
        self.assertEqual(self.settings.read_text(), "MY SETTINGS")
        self.assertEqual(self.theme.read_text(), "MY THEME")

    def test_failed_install_restores_the_previous_files(self):
        self.installed()
        self.staged()
        ensure = self.manager.installation.ensure_parents
        count = 0
        def fail(path, created):
            nonlocal count
            count += 1
            if count == 4:
                raise OSError("disk full")
            ensure(path, created)
        with patch.object(updates.subprocess, "run"), patch.object(updates.deployment, "active_compositors", return_value=[]), \
             patch.object(self.manager.installation, "ensure_parents", side_effect=fail):
            with self.assertRaisesRegex(OSError, "disk full"):
                self.manager.apply()
        self.assertEqual(self.binary.read_text(), "OLD BINARY")
        self.assertEqual(self.settings.read_text(), "MY SETTINGS")
        self.assertTrue(self.manager.ready_file.exists())

    def test_other_session_or_logout_timeout_never_replaces_installed_files(self):
        self.installed()
        self.staged()
        with patch.object(updates.subprocess, "run") as run, \
             patch.object(updates.deployment, "active_compositors", return_value=["another-session"]):
            with self.assertRaisesRegex(ValueError, "other Hyprland sessions"):
                self.manager.apply()
        self.assertFalse(any("exit" in call.args[0] for call in run.call_args_list))
        with patch.object(updates.subprocess, "run"), \
             patch.object(updates.deployment, "active_compositors", return_value=["test-session"]), \
             patch.object(updates.time, "monotonic", side_effect=[0, 61]):
            with self.assertRaisesRegex(ValueError, "no installed files were changed"):
                self.manager.apply()
        self.assertEqual(self.binary.read_text(), "OLD BINARY")

    def test_managed_installation_checks_releases_but_cannot_prepare(self):
        self.manager.data = Path("/nix/store/example/share/hyprstack")
        self.assertEqual(self.manager.capabilities()["install_reason"], "nix")
        with patch.object(updates, "request", return_value=release()):
            self.assertTrue(self.manager.check()["available"])
        with self.assertRaisesRegex(ValueError, "configuration/package manager"):
            self.manager.prepare(2)

    def test_legacy_installation_reads_version_from_the_installed_cli(self):
        with patch.object(updates.deployment, "capture", return_value="hyprstack 1.4.10"):
            self.assertEqual(updates.Updates().current, "1.4.10")

    def test_default_command_does_not_build_or_log_out_when_up_to_date(self):
        with patch.object(updates, "Updates", return_value=self.manager), \
             patch.object(self.manager, "check", return_value={"available": False}), \
             patch.object(self.manager, "prepare") as prepare, \
             patch.object(self.manager, "start_install") as install, \
             patch.object(updates, "confirm_logout") as confirm, redirect_stdout(io.StringIO()) as output:
            self.assertEqual(updates.main([]), 0)
        prepare.assert_not_called()
        install.assert_not_called()
        confirm.assert_not_called()
        self.assertIn("актуальная версия", output.getvalue())

    def test_default_command_reuses_the_build_and_keeps_it_if_logout_is_declined(self):
        self.staged()
        with patch.object(self.manager, "check", side_effect=self.manager.status), \
             patch.object(self.manager, "prepare") as prepare, \
             patch.object(self.manager, "start_install") as install, \
             patch.object(updates.subprocess, "run"), \
             patch.object(updates.deployment, "active_compositors", return_value=["test-session"]), \
             patch.object(updates, "confirm_logout", return_value=False), redirect_stdout(io.StringIO()):
            self.assertEqual(updates.update_command(self.manager, 2), 0)
        prepare.assert_not_called()
        install.assert_not_called()
        self.assertTrue(self.manager.status()["ready"])

    def test_one_command_installs_only_after_confirmation_or_explicit_yes(self):
        self.staged()
        for yes in (False, True):
            with patch.object(self.manager, "check", side_effect=self.manager.status), \
                 patch.object(self.manager, "start_install") as install, \
                 patch.object(updates.subprocess, "run"), \
                 patch.object(updates.deployment, "active_compositors", return_value=["test-session"]), \
                 patch.object(updates, "confirm_logout", return_value=True) as confirm, redirect_stdout(io.StringIO()):
                self.assertEqual(updates.update_command(self.manager, 2, yes), 0)
            install.assert_called_once()
            self.assertEqual(confirm.call_count, 0 if yes else 1)

    def test_tty_update_installs_without_a_graphical_signature_or_logout(self):
        self.installed()
        self.staged()
        commands = []
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}), \
             patch.object(self.manager, "check", side_effect=self.manager.status), \
             patch.object(updates.subprocess, "run", side_effect=lambda command, **kwargs: commands.append(command)), \
             patch.object(updates.deployment, "active_compositors", return_value=[]), \
             patch.object(updates, "confirm_logout") as confirm, redirect_stdout(io.StringIO()):
            self.assertEqual(updates.update_command(self.manager, 2), 0)
        confirm.assert_not_called()
        self.assertFalse(any("exit" in command for command in commands))
        self.assertEqual(self.binary.read_text(), "NEW BINARY")
        self.assertEqual(self.settings.read_text(), "MY SETTINGS")

    def test_installed_rollback_command_restores_the_previous_version(self):
        self.installed()
        metadata = self.manager.data / "version.json"
        metadata.parent.mkdir(parents=True)
        metadata.write_text('{"version":"1.0.0"}')
        self.staged()
        with patch.object(updates.subprocess, "run"), \
             patch.object(updates.deployment, "active_compositors", return_value=[]), redirect_stdout(io.StringIO()):
            self.manager.apply(logout=False)
            self.assertEqual(updates.main(["rollback"]), 0)
        self.assertEqual(self.binary.read_text(), "OLD BINARY")
        self.assertEqual(json.loads(metadata.read_text())["version"], "1.0.0")

    def test_piped_bootstrap_downloads_the_tagged_helpers_and_forwards_arguments(self):
        mock = self.home / "mock-python"
        mock.mkdir()
        report = self.home / "bootstrap.json"
        (mock / "sitecustomize.py").write_text('''import io, json, urllib.request
def download(request, timeout=30):
    url = request.full_url
    if url.endswith('/releases/latest'):
        return io.BytesIO(b'{"tag_name":"v2.0.0"}')
    assert '/v2.0.0/distribution/' in url, url
    if url.endswith('/updates.py'):
        return io.BytesIO(b"import json,os,sys\\nfrom pathlib import Path\\nPath(os.environ['BOOTSTRAP_REPORT']).write_text(json.dumps({'args':sys.argv[1:],'file':__file__}))\\n")
    return io.BytesIO(b'# helper')
urllib.request.urlopen = download
''')
        source = Path(__file__).resolve().parents[2] / "update.sh"
        environment = dict(os.environ, PATH="/usr/bin:/bin", PYTHONPATH=str(mock), BOOTSTRAP_REPORT=str(report))
        result = subprocess.run(["/usr/bin/bash", "-s", "--", "check"], input=source.read_text(),
            env=environment, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(report.read_text())
        self.assertEqual(data["args"], ["check"])
        helper = Path(data["file"])
        self.assertEqual(helper.parent, self.home / "cache/hyprstack-bootstrap/v2.0.0")
        self.assertTrue(all((helper.parent / name).exists() for name in
            ("updates.py", "update.py", "update_transaction.py", "check_headers.py")))

    def test_directory_symlink_is_planned_as_the_link_without_traversing_it(self):
        target = self.home / "private-module"
        target.mkdir()
        (target / "Module.qml").write_text("PRIVATE")
        link = self.home / "module-link"
        link.symlink_to(target, target_is_directory=True)
        files = list(self.manager.installation.tree(link, link))
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0].path, link)
        self.assertEqual(files[0].link, str(target))
        dangling = self.home / "dangling-link"
        dangling.symlink_to(self.home / "missing-target", target_is_directory=True)
        self.assertEqual(list(self.manager.installation.tree(dangling, dangling))[0].link,
            str(self.home / "missing-target"))

    def test_update_retires_old_public_modules_and_preserves_private_overlay_entries(self):
        self.staged()
        installation = self.manager.installation
        target = self.home / "private-module"
        target.mkdir()
        (target / "Module.qml").write_text("MY MODULE")
        link = installation.data / "hyprstack-personal/shell/modules/private"
        link.parent.mkdir(parents=True)
        link.symlink_to(target, target_is_directory=True)
        retired = installation.data / "hyprstack/shell/services/Retired.qml"
        before = list(installation.plan()) + [File(link, link=str(target)), File(retired, b"OLD MODULE")]
        with patch.object(installation, "plan", return_value=iter(before)), redirect_stdout(io.StringIO()):
            installation.transaction("install")
        with redirect_stdout(io.StringIO()):
            installation.transaction("install")
        self.assertFalse(retired.exists())
        self.assertTrue(link.is_symlink())
        self.assertEqual((link / "Module.qml").read_text(), "MY MODULE")
        self.assertIn(str(link), json.loads(installation.manifest.read_text())["files"])

    @unittest.skipUnless(shutil.which("node"), "node is required to exercise settings search")
    def test_settings_search_opens_update_controls_in_both_languages(self):
        script = """
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const scope = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8').replace(/^\\.pragma library\\s*/, ''), scope);
const translated = {'Check for updates':'Проверить обновления', 'Updates':'Обновления'};
const tr = text => translated[text] ?? text;
for (const [query, target] of [['Check for updates','updatesCheck'], ['Проверить обновления','updatesCheck'],
    ['Download and prepare update','updatesPrepare'], ['Install update','updatesInstall']]) {
    const result = scope.find(query, tr)[0];
    assert.equal(result?.page, 10, query);
    assert.equal(result?.target, target, query);
}
assert.ok(scope.find('обновления', tr).some(result => result.page === 10));
"""
        source = Path(__file__).resolve().parents[2] / "shell/utils/scripts/settings-search.js"
        subprocess.run(["node", "-e", script, str(source)], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
