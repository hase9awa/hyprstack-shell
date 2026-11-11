"""Render and click the real VPN controls with an isolated fake backend.

HYPRSTACK_TEST_PREFIX=/path/to/staged/prefix python3 distribution/tests/test_vpn_ui.py
No VPN connection, system permission, or real user configuration is changed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

BACKEND = '''import json,os,sys
from pathlib import Path
path=Path(os.environ['XDG_STATE_HOME'])/'fake-vpn.json'
action=sys.argv[1]
payload=json.load(sys.stdin) if action not in ('overview','status') else {}
value=json.loads(path.read_text()) if path.exists() else {'profiles':[],'routes':[],'selectedProfile':-1,'mode':'tun','connected':False,'installed':True,'canTun':True,'operations':[]}
if action=='fixture':
 value=payload;value['operations']=[]
elif action not in ('overview','status'):
 value['operations'].append(action)
 if action=='import' and payload.get('text')=='invalid':
  print(json.dumps({'error':'Invalid test profile'}));sys.exit(1)
 if action=='install':value['installed']=True
 if action=='authorize':value['canTun']=True
 if action=='connect':value['connected']=True;value['server']=next(p['name']for p in value['profiles']if p['id']==value['selectedProfile'])
 if action=='disconnect':value['connected']=False
 if action=='select':value['selectedProfile']=payload['id']
 if action=='import':value['profiles'].append({'id':'c9012abc','name':'Imported','type':'trojan','latency_ms':-1})
 if action=='delete':value['profiles']=[p for p in value['profiles']if p['id']!=payload['id']]
path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))
print(json.dumps(value))
'''

VPN = '''pragma Singleton
import QtQuick
import qs.services
QtObject {
 property bool nativeSelected: true
 property bool otherConnected: false
 readonly property var active: ({name:nativeSelected?"native":"external",displayName:nativeSelected?"VPN":"Other VPN"})
 readonly property bool connected: nativeSelected ? ManagedVPN.connected : otherConnected
 readonly property bool connecting: ManagedVPN.busy && ManagedVPN.action==="connect"
 readonly property bool disconnecting: ManagedVPN.busy && ManagedVPN.action==="disconnect"
 readonly property var status: ({state:connected?"connected":"disconnected"})
 function selectManagedProvider(): bool { if(otherConnected)return false;nativeSelected=true;return true; }
 function checkStatus(): void {}
 function disconnect(): void { if(!nativeSelected)otherConnected=false;else ManagedVPN.run("disconnect",{}); }
 function toggle(): void { ManagedVPN.run(connected?"disconnect":"connect",{}); }
}
'''


@unittest.skipUnless(os.environ.get("HYPRSTACK_TEST_PREFIX"), "set HYPRSTACK_TEST_PREFIX to a built installation")
class VpnInterfaceTests(unittest.TestCase):
    def test_click_through_vpn_calendar_and_about(self):
        prefix = Path(os.environ["HYPRSTACK_TEST_PREFIX"]).resolve()
        with tempfile.TemporaryDirectory(prefix="hs-vpn-ui-") as temporary:
            base = Path(temporary)
            def write(name, contents):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
            def copy(name, source):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, path)
            (base / "components").symlink_to(ROOT / "shell/components")
            (base / "assets").mkdir()
            (base / "assets/material-symbols").symlink_to(ROOT / "shell/assets/material-symbols")
            (base / "assets/google-sans-flex").symlink_to(ROOT / "shell/assets/google-sans-flex")
            copy("services/ManagedVPN.qml", ROOT / "shell/services/ManagedVPN.qml")
            copy("modules/vpn/VpnWindow.qml", ROOT / "shell/modules/vpn/VpnWindow.qml")
            copy("modules/dashboard/dash/Calendar.qml", ROOT / "shell/modules/dashboard/dash/Calendar.qml")
            copy("modules/dashboard/dash/Resources.qml", ROOT / "shell/modules/dashboard/dash/Resources.qml")
            copy("modules/nexus/pages/AboutPage.qml", ROOT / "shell/modules/nexus/pages/AboutPage.qml")
            copy("fixtures/VpnToggle.qml", ROOT / "shell/modules/bar/components/VpnToggle.qml")
            copy("utils/scripts/vpn-flow.js", ROOT / "shell/utils/scripts/vpn-flow.js")
            for name in ("RowButton", "ConnectedRect", "ToggleRow", "InfoRow", "SectionHeader", "AnimatedLogo"):
                copy("modules/nexus/common/" + name + ".qml", ROOT / "shell/modules/nexus/common" / (name + ".qml"))
            write("modules/nexus/common/PageBase.qml", '''import QtQuick
Item { property string title; property var nState; readonly property int cappedWidth: width; default property alias contents: container.data; Item { id:container; anchors.fill:parent } }
''')
            write("modules/nexus/WindowFactory.qml", '''pragma Singleton
import QtQuick
QtObject { property int opened:0; property var lastScreen; function create(parent,props) {opened++;lastScreen=props.screen;} }
''')
            write("services/VPN.qml", VPN)
            write("services/Hypr.qml", 'pragma Singleton\nimport QtQuick\nQtObject {readonly property bool stacking:false}\n')
            write("services/Effects.qml", 'pragma Singleton\nimport QtQuick\nQtObject {readonly property bool uiShadowsEnabled:false;readonly property real shadowOpacity:0.35;readonly property real shadowSize:18}\n')
            names = set()
            for source in (ROOT / "shell").rglob("*.qml"):
                names.update(re.findall(r"Colours\.(?:tPalette|palette)\.(\w+)", source.read_text()))
            colors = {"m3surface":"#191a22", "m3surfaceContainer":"#252630", "m3primary":"#b4c2ff", "m3onPrimary":"#101838"}
            fields = "\n".join('readonly property color ' + name + ':"' + colors.get(name, "#eeeeff" if name.startswith("m3on") else "#585b70") + '"' for name in sorted(names))
            write("services/Colours.qml", 'pragma Singleton\nimport QtQuick\nQtObject {readonly property bool light:false;readonly property QtObject palette:QtObject {'+fields+'};readonly property QtObject tPalette:palette;function layer(c,l){return c;} }\n')
            write("utils/Paths.qml", 'pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject {readonly property string scripts:Quickshell.shellDir+"/assets"}\n')
            write("utils/SysInfo.qml", 'pragma Singleton\nimport QtQuick\nQtObject {readonly property string hostname:"Test";readonly property string device:"Test";readonly property string osPrettyName:"Test";readonly property string osName:"Test";readonly property string kernel:"Test";readonly property string firmware:"Test"}\n')
            write("assets/vpn.py", BACKEND)
            copy("shell.qml", ROOT / "distribution/tests/vpn_ui_shell.qml")
            (base / "home").mkdir()
            (base / "runtime").mkdir(mode=0o700)
            environment = dict(os.environ, HOME=str(base / "home"), XDG_CONFIG_HOME=str(base / "config"),
                XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"), XDG_DATA_HOME=str(base / "data"),
                XDG_RUNTIME_DIR=str(base / "runtime"), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                QT_QPA_PLATFORMTHEME="", QML_IMPORT_PATH=str(prefix / "share/hyprstack/qml"),
                QML2_IMPORT_PATH=str(prefix / "share/hyprstack/qml"))
            environment.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
            environment.pop("WAYLAND_DISPLAY", None)
            result = subprocess.run(["dbus-run-session", "--", shutil.which("qs"), "-p", str(base), "--no-color"],
                env=environment, capture_output=True, text=True, timeout=40)
            output = result.stdout + result.stderr
            marker = next((line.split("VPN_UI_COMPLETE ", 1)[1] for line in output.splitlines() if "VPN_UI_COMPLETE " in line), None)
            self.assertIsNotNone(marker, output[-12000:])
            self.assertEqual(json.loads(marker)["failures"], 0, output[-16000:])
            self.assertNotIn("TypeError:", output)
            self.assertNotIn("ReferenceError:", output)
            self.assertNotIn("Binding loop", output)


if __name__ == "__main__":
    unittest.main()
