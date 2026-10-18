"""Application theme integration and restoration, using isolated XDG directories."""
import copy
import json
import os
import pty
from pathlib import Path
import shutil
import select
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ASSETS = Path(__file__).resolve().parents[1] / "shell/assets"
sys.path.insert(0, str(ASSETS))
import theme_manager as themes
import theme_sync as sync


class ThemeSyncTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="hyprstack colours ")
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.config, self.data, self.state = [self.home / name for name in ("config", "data", "state")]
        environment = patch.dict(os.environ, {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
            "XDG_DATA_HOME": str(self.data), "XDG_STATE_HOME": str(self.state), "HYPRSTACK_NESTED": "1",
            "HYPRLAND_INSTANCE_SIGNATURE": "", "DBUS_SESSION_BUS_ADDRESS": "", "JAVA_TOOL_OPTIONS": "-Xmx1g"})
        environment.start()
        self.addCleanup(environment.stop)
        plugin = patch.object(sync, "THRONE_GTK_PLUGIN", self.home / "bundled-qt/platformthemes/libqgtk3.so")
        plugin.start()
        self.addCleanup(plugin.stop)
        kde_plugin = patch.object(sync, "qt6ct_supports_kde", return_value=False)
        kde_plugin.start()
        self.addCleanup(kde_plugin.stop)
        self.settings = dict(sync.DEFAULTS)
        self.set_palette("dark")

    def set_palette(self, mode, theme=0):
        variant = next(v for v in themes.builtins()[theme]["variants"] if v["mode"] == mode)
        self.scheme = {"name": "test", "mode": mode, "colours": variant["colours"]}
        self.c = variant["colours"]
        self.write(self.state / "hyprstack/scheme.json", json.dumps(self.scheme))

    def write(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def apply(self, settings=None, live=False):
        with patch.object(sync.shutil, "which", return_value=None):
            return sync.sync_current(settings or self.settings, live=live)

    def assert_ok(self, report):
        self.assertEqual(report["errors"], [], report)

    def test_all_file_formats_change_and_restore_exactly(self):
        originals = {
            self.config / "gtk-3.0/settings.ini": "# my GTK settings\n[Settings]\ngtk-font-name=Sans 11\ngtk-theme-name=Old\n",
            self.config / "gtk-3.0/gtk.css": "/* mine */\nbutton { border-radius: 4px; }",
            self.config / "gtk-4.0/gtk.css": "/* other css */\n",
            self.home / ".gtkrc-2.0": 'gtk-font-name="Sans 11"\n',
            self.config / "qt5ct/qt5ct.conf": "[Appearance]\nstyle=kvantum\ncustom_palette=false\n[Fonts]\ngeneral=Sans,11\n",
            self.config / "kdeglobals": "[General]\nBrowserApplication=firefox.desktop\n[Colors:Window]\nBackgroundNormal=1,2,3\n",
            self.config / "kitty/kitty.conf": "font_size 13\nbackground #112233\n",
            self.config / "foot/foot.ini": "font=monospace:size=12\n[colors-dark]\nbackground=112233\nalpha=0.8\n",
            self.config / "alacritty/alacritty.toml": '[font]\nsize = 12\n[colors.primary]\nbackground = "#112233"\n',
            self.home / ".wezterm.lua": "local config = {font_size = 13}\nreturn config\n",
            self.config / "ghostty/config": "font-size = 12\nbackground = #112233\n",
            self.data / "konsole/Personal.profile": "[General]\nName=Personal\n[Appearance]\nColorScheme=Old\n",
            self.config / "xfce4/terminal/terminalrc": "[Configuration]\nFontName=monospace 12\nColorUseTheme=TRUE\n",
            self.home / ".Xresources": "Xft.dpi: 96\nXTerm*background: #112233\n",
        }
        for path, content in originals.items():
            self.write(path, content)
        self.assert_ok(self.apply())
        import tomllib
        alacritty = tomllib.loads((self.config / "alacritty/alacritty.toml").read_text())
        self.assertEqual(alacritty["font"]["size"], 12)
        self.assertEqual(alacritty["colors"]["normal"]["red"], "#" + self.c["term1"])
        self.assertIn("background=" + self.c["surface"], (self.config / "foot/foot.ini").read_text())
        self.assertIn("ColorScheme=Hyprstack", (self.data / "konsole/Personal.profile").read_text())
        for mode, theme in (("light", 0), ("dark", 1), ("dark", 0)):
            self.set_palette(mode, theme)
            self.assert_ok(self.apply())
        self.assertEqual((self.home / ".wezterm.lua").read_text().count("local function _hyprstack_user_config"), 1)
        self.assertEqual((self.config / "kitty/kitty.conf").read_text().count("include "), 1)
        self.assert_ok(self.apply({**self.settings, "enabled": False}))
        for path, content in originals.items():
            self.assertEqual(path.read_text(), content, str(path))
        files = {p for root in (self.config, self.data) for p in root.rglob("*") if p.is_file()}
        self.assertEqual(files, {p for p in originals if p.is_relative_to(self.config) or p.is_relative_to(self.data)})

    def test_unrelated_changes_survive_disabling_individual_integrations(self):
        foot = self.write(self.config / "foot/foot.ini", "font=monospace:size=11\n[colors-dark]\nbackground=112233\n")
        kitty = self.write(self.config / "kitty/kitty.conf", "font_size 11\n")
        self.assert_ok(self.apply())
        foot.write_text(foot.read_text().replace("size=11", "size=15"))
        kitty.write_text(kitty.read_text() + "scrollback_lines 5000\n")
        self.assert_ok(self.apply({**self.settings, "foot": False, "kitty": False}))
        self.assertIn("font=monospace:size=15", foot.read_text())
        self.assertIn("background=112233", foot.read_text())
        self.assertEqual(kitty.read_text(), "font_size 11\nscrollback_lines 5000\n")
        self.assertTrue((self.config / "qt5ct/qt5ct.conf").exists())

    def test_user_edit_to_managed_key_is_preserved_on_restore(self):
        foot = self.write(self.config / "foot/foot.ini", "[colors-dark]\nbackground=112233\n")
        self.assert_ok(self.apply())
        foot.write_text(foot.read_text().replace("background=" + self.c["surface"], "background=abcdef"))
        self.assert_ok(self.apply({**self.settings, "enabled": False}))
        self.assertIn("background=abcdef", foot.read_text())

    def test_environment_preserves_java_options_and_restores_unset_values(self):
        with patch.dict(os.environ, {"QT_QPA_PLATFORMTHEME": "kde", "GTK_THEME": "Old"}):
            report = self.apply()
            self.assert_ok(report)
            self.assertEqual(report["environment"]["QT_QPA_PLATFORMTHEME"], "qt5ct")
            self.assertEqual(report["environment"]["JAVA_TOOL_OPTIONS"], "-Xmx1g " + sync.JAVA_OPTION)
            self.assertEqual(self.apply()["environment"]["JAVA_TOOL_OPTIONS"].count(sync.JAVA_OPTION), 1)
            report = self.apply({**self.settings, "enabled": False})
            self.assertEqual(report["environment"]["QT_QPA_PLATFORMTHEME"], "kde")
            self.assertEqual(report["environment"]["GTK_THEME"], "Old")
            self.assertEqual(report["environment"]["JAVA_TOOL_OPTIONS"], "-Xmx1g")
            self.assertIsNone(report["environment"]["QT_QUICK_CONTROLS_STYLE"])
            self.assertFalse((self.config / "hyprstack/theme/environment.lua").exists())

    def test_disabled_groups_write_no_application_files(self):
        settings = {**self.settings, "enabled": False}
        self.assert_ok(self.apply(settings))
        self.assertFalse(self.config.exists())
        self.assertFalse(self.data.exists())

    def test_user_local_qt_plugin_path_preserves_and_restores_existing_paths(self):
        plugins = self.home / ".local/lib/qt6/plugins"
        self.write(plugins / "platformthemes/libqt6ct.so", "test plugin")
        with patch.dict(os.environ, {"QT_PLUGIN_PATH": "/existing/plugins"}):
            report = self.apply()
            self.assert_ok(report)
            self.assertEqual(report["environment"]["QT_PLUGIN_PATH"], "/existing/plugins:" + str(plugins))
            self.assertEqual(self.apply()["environment"]["QT_PLUGIN_PATH"].count(str(plugins)), 1)
            report = self.apply({**self.settings, "qt": False})
            self.assertEqual(report["environment"]["QT_PLUGIN_PATH"], "/existing/plugins")
            self.assertTrue((plugins / "platformthemes/libqt6ct.so").exists())

    def test_missing_applications_are_skipped(self):
        report = self.apply({**self.settings, "gtk": False, "qt": False, "java": False, "system": False})
        self.assert_ok(report)
        self.assertIn("kitty", report["skipped"])
        self.assertIn("alacritty", report["skipped"])
        self.assertFalse(self.config.exists())

    def test_kde_applications_select_shared_scheme_and_restore_previous_choice(self):
        path = self.write(self.config / "kdeglobals", "[UiSettings]\nColorScheme=BreezeLight\n[General]\nBrowserApplication=firefox.desktop\n")
        self.assert_ok(self.apply())
        self.assertIn("ColorScheme=Hyprstack", "".join(v for _, v in sync.ini_lines(path.read_text(), "UiSettings", "ColorScheme")))
        self.set_palette("light")
        self.assert_ok(self.apply())
        scheme = (self.data / "color-schemes/Hyprstack.colors").read_text()
        self.assertIn("BackgroundNormal=" + sync.rgb(self.c["surface"]), scheme)
        self.assert_ok(self.apply({**self.settings, "qt": False}))
        self.assertEqual(path.read_text(), "[UiSettings]\nColorScheme=BreezeLight\n[General]\nBrowserApplication=firefox.desktop\n")

    def test_bundled_throne_uses_gtk_plugin_without_changing_system_desktop_files(self):
        self.write(sync.THRONE_GTK_PLUGIN, "matching GTK platform plugin")
        system_data = self.home / "system-data"
        original = "[Desktop Entry]\nName=Throne\nType=Application\nExec=throne %U\nIcon=Throne\n"
        system_entry = self.write(system_data / "applications/Throne.desktop", original)
        url_original = '[Desktop Entry]\nName=Throne\nExec="/opt/Throne/Throne" %U\nNoDisplay=true\n'
        url_entry = self.write(self.data / "applications/throne-url-handler.desktop", url_original)
        with patch.dict(os.environ, {"XDG_DATA_DIRS": str(system_data)}):
            self.assert_ok(self.apply())
            self.assert_ok(self.apply())
            user_entry = self.data / "applications/Throne.desktop"
            self.assertIn("Exec=env QT_QPA_PLATFORMTHEME=gtk3 throne %U", user_entry.read_text())
            self.assertEqual(user_entry.read_text().count("QT_QPA_PLATFORMTHEME="), 1)
            self.assertIn('Exec=env QT_QPA_PLATFORMTHEME=gtk3 "/opt/Throne/Throne" %U', url_entry.read_text())
            self.assertEqual(system_entry.read_text(), original)
            self.assert_ok(self.apply({**self.settings, "gtk": False}))
            self.assertFalse(user_entry.exists())
            self.assertEqual(url_entry.read_text(), url_original)

    def test_kde_aware_qt_plugin_uses_system_choice_and_alternating_palette_paths(self):
        with patch.object(sync, "qt6ct_supports_kde", return_value=True):
            paths = []
            for mode, theme in (("dark", 0), ("light", 0), ("dark", 1), ("light", 1)):
                self.set_palette(mode, theme)
                self.assert_ok(self.apply())
                config = (self.config / "qt6ct/qt6ct.conf").read_text()
                palette = Path(sync.ini_lines(config, "Appearance", "color_scheme_path")[0][1].split("=", 1)[1].strip())
                self.assertIn("BackgroundNormal=" + sync.rgb(self.c["surface"]), palette.read_text())
                paths.append(palette)
                globals_config = (self.config / "kdeglobals").read_text()
                self.assertEqual(sync.ini_lines(globals_config, "UiSettings", "ColorScheme")[0][1].strip(), "ColorScheme=")
            self.assertEqual(len(set(paths)), 2)
            self.assertNotEqual(paths[0], paths[1])

    def test_disabled_gtk_also_disables_java_bridge(self):
        self.assert_ok(self.apply())
        report = self.apply({**self.settings, "gtk": False})
        self.assert_ok(report)
        self.assertEqual(report["environment"]["JAVA_TOOL_OPTIONS"], "-Xmx1g")
        self.assertIsNone(report["environment"]["GTK_THEME"])
        self.assertFalse((self.config / "gtk-3.0/gtk.css").exists())

    def test_read_only_config_does_not_block_other_integrations(self):
        path = self.write(self.config / "foot/foot.ini", "font=monospace\n")
        path.chmod(0o444)
        self.write(self.config / "alacritty/alacritty.toml", "[font]\nsize = 12\n")
        report = self.apply()
        self.assertTrue(any("Read-only" in error for error in report["errors"]))
        self.assertIn("[colors.normal]", (self.config / "alacritty/alacritty.toml").read_text())
        self.assertEqual(path.read_text(), "font=monospace\n")

    def test_symlink_dotfile_remains_a_symlink(self):
        target = self.write(self.home / "dotfiles/foot.ini", "font=monospace\n")
        path = self.config / "foot/foot.ini"
        path.parent.mkdir(parents=True)
        path.symlink_to(target)
        self.assert_ok(self.apply())
        self.assertTrue(path.is_symlink())
        self.assertIn("[colors-dark]", target.read_text())
        self.assert_ok(self.apply({**self.settings, "enabled": False}))
        self.assertTrue(path.is_symlink())
        self.assertEqual(target.read_text(), "font=monospace\n")

    def test_invalid_alacritty_inline_table_is_preserved(self):
        original = '[colors]\nprimary = { background = "#123456" }\n'
        path = self.write(self.config / "alacritty/alacritty.toml", original)
        self.write(self.config / "ghostty/config.ghostty", "font-size = 11\n")
        report = self.apply()
        self.assertTrue(any("alacritty:" in e for e in report["errors"]), report)
        self.assertEqual(path.read_text(), original)
        self.assertIn("config-file", (self.config / "ghostty/config.ghostty").read_text())

    def test_legacy_foot_uses_supported_section(self):
        path = self.write(self.config / "foot/foot.ini", "font=monospace\n")
        engine = sync.Sync(self.settings, live=False)
        with patch.object(sync.shutil, "which", return_value="/usr/bin/foot"), patch.object(sync, "command", return_value="foot version: 1.22.3"):
            engine.terminal("foot", self.c, "dark")
        self.assertIn("[colors]", path.read_text())
        self.assertNotIn("[colors-dark]", path.read_text())
        self.assertNotIn("initial-color-theme", path.read_text())

    @unittest.skipUnless(shutil.which("lua"), "Lua is required")
    def test_wezterm_wrapper_accepts_table_and_builder_configs_and_reloads(self):
        path = self.home / ".wezterm.lua"
        for source in ("return {font_size=12}", "local config = {font_size=12}\nreturn config\n"):
            self.write(path, source)
            self.assert_ok(self.apply())
            fixture = "package.preload['wezterm'] = function() return {add_to_config_reload_watch_list=function() end} end\n"
            fixture += f"local c=dofile({sync.lua_string(str(path))}); assert(c.font_size==12); assert(c.colors.background=='#{self.c['surface']}')"
            subprocess.run(["lua", "-"], input=fixture, text=True, check=True, capture_output=True)
            self.assert_ok(self.apply({**self.settings, "wezterm": False}))
            self.assertEqual(path.read_text(), source)

    def test_invalid_settings_and_scheme_cannot_change_application_files(self):
        for values in ({"enabled": "false"}, []):
            with self.assertRaises(ValueError):
                sync.sync_current(values, live=False)
        self.write(self.state / "hyprstack/scheme.json", '{"colours": {"background": "BAD"}}')
        with self.assertRaises(ValueError):
            self.apply()
        self.assertFalse(self.config.exists())

    def test_gsettings_apply_restore_and_user_changes(self):
        values = {"gtk-theme": "'Old'", "color-scheme": "'default'"}
        original = copy.deepcopy(values)
        def fake(args, input=None):
            self.assertEqual(args[0], "gsettings")
            if args[1] == "get":
                return values[args[3]]
            values[args[3]] = args[4]
            return ""
        with patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": "test-bus"}), patch.object(sync, "session_matches", return_value=True), \
                patch.object(sync.shutil, "which", side_effect=lambda name: "/bin/gsettings" if name == "gsettings" else None), patch.object(sync, "command", side_effect=fake):
            report = sync.sync_current(self.settings)
            self.assert_ok(report)
            self.assertEqual(values["color-scheme"], "'prefer-dark'")
            self.assertIn("Hyprstack", values["gtk-theme"])
            self.set_palette("light")
            self.assert_ok(sync.sync_current(self.settings))
            self.assertEqual(values["color-scheme"], "'prefer-light'")
            self.assert_ok(sync.sync_current({**self.settings, "enabled": False}))
            self.assertEqual(values, original)
            sync.sync_current(self.settings)
            values["gtk-theme"] = "'My manual theme'"
            sync.sync_current({**self.settings, "enabled": False})
            self.assertEqual(values["gtk-theme"], "'My manual theme'")

    def test_nested_or_different_xdg_session_never_contacts_parent_desktop(self):
        with patch.object(sync, "command", side_effect=AssertionError("unexpected external command")):
            self.assertFalse(sync.session_matches())
            self.assert_ok(self.apply(live=True))
        with patch.dict(os.environ, {"HYPRSTACK_NESTED": "0", "HYPRLAND_INSTANCE_SIGNATURE": "parent"}), \
                patch.object(sync.shutil, "which", return_value="/bin/hyprctl"), \
                patch.object(sync, "command", return_value='[{"instance":"parent","pid":123}]'), \
                patch.object(Path, "read_bytes", return_value=b"HOME=/different-home\0"):
            self.assertFalse(sync.session_matches())

    def test_terminal_profile_schemas_paths_and_cursor_selection_colours(self):
        uuid = "b1dcc9dd-5262-4d8d-a863-c897e6d979b9"
        engine = sync.Sync(self.settings, live=False)
        for name, schema, target in (("gnomeTerminal", "org.gnome.Terminal", "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:"),
                                    ("tilix", "com.gexperts.Tilix", "com.gexperts.Tilix.Profile:/com/gexperts/Tilix/profiles/")):
            calls = []
            with patch.object(sync, "command", return_value=f"['{uuid}']"), patch.object(engine, "gsetting", side_effect=lambda *args: calls.append(args)):
                engine.terminal_profiles(name, schema, self.c)
            self.assertTrue(all(call[1] == target + uuid + "/" for call in calls))
            values = {call[2]: call[3] for call in calls}
            self.assertEqual(values["cursor-background-color"], repr("#" + self.c["primary"]))
            self.assertEqual(values["highlight-foreground-color"], repr("#" + self.c["onPrimary"]))

    def test_live_osc_output_is_scoped_to_selected_terminal_and_session(self):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        index = Path(os.ttyname(slave)).name
        process = self.home / "proc/123"
        self.write(process / "fdinfo/5", f"tty-index:\t{index}\n")
        self.write(process / "environ", "WAYLAND_DISPLAY=theme-test\0")
        (process / "exe").symlink_to("/usr/bin/foot")
        iterdir = Path.iterdir
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "theme-test"}), \
                patch.object(Path, "iterdir", lambda path: iter([process]) if path == Path("/proc") else iterdir(path)):
            sync.update_terminals(self.c, self.settings)
            self.assertTrue(select.select([master], [], [], 1)[0])
            output = os.read(master, 4096)
            self.assertIn(f"\x1b]11;#{self.c['surface']}\x1b\\".encode(), output)
            self.assertIn(f"\x1b]4;15;#{self.c['term15']}\x1b\\".encode(), output)
            sync.update_terminals(self.c, {**self.settings, "foot": False})
            self.assertFalse(select.select([master], [], [], 0)[0])
            self.write(process / "environ", "WAYLAND_DISPLAY=another-session\0")
            sync.update_terminals(self.c, self.settings)
            self.assertFalse(select.select([master], [], [], 0)[0])

    def test_cli_theme_and_mode_also_sync_without_a_running_shell(self):
        path = self.write(self.config / "kitty/kitty.conf", "font_size 12\n")
        commands = ([sys.executable, str(ASSETS / "theme_manager.py"), "apply", "catppuccin", "dark"],
                    [sys.executable, str(ASSETS / "theme_manager.py"), "mode", "light"])
        for args in commands:
            result = subprocess.run(args, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            current = json.loads((self.state / "hyprstack/scheme.json").read_text())
            self.assertIn("background #" + current["colours"]["surface"], (self.config / "hyprstack/theme/kitty.conf").read_text())
        result = subprocess.run([sys.executable, str(ASSETS / "theme_sync.py"), "--settings-stdin", "--no-live"],
            input='{"enabled":false}', text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(path.read_text(), "font_size 12\n")


if __name__ == "__main__":
    unittest.main()
