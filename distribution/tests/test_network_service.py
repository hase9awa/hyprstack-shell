"""Exercise the QML NetworkManager service on a private bus with a fake nmcli."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FAKE_NMCLI = r'''#!/bin/sh
echo "$*" >> "$NET_FIXTURE/calls"
case "$*" in
    monitor)
        while [ ! -f "$NET_FIXTURE/emit" ]; do sleep .05; done
        echo BURST >> "$NET_FIXTURE/calls"
        for i in 1 2 3 4 5 6 7 8; do echo 'device changed'; done
        exec sleep 60 ;;
    'device wifi connect needs-secret') sleep .1; echo 'Secrets were required for this activation' >&2; exit 10 ;;
    'connection show unrelated') echo 'Secrets were required for an unrelated query' >&2; exit 10 ;;
    'device wifi connect superseded') sleep .2; echo failure >&2; exit 10 ;;
    'device wifi connect changed password fixture bssid AA:BB') echo 'Secrets were required' >&2; exit 10 ;;
    *'connection show id changed') printf '%s\n' 'connection.uuid:fixture-uuid' '802-11-wireless.ssid:changed' '802-11-wireless-security.key-mgmt:sae' ;;
    'device wifi connect retry')
        if [ ! -f "$NET_FIXTURE/retried" ]; then touch "$NET_FIXTURE/retried"; exit 10; fi ;;
    'radio wifi') echo enabled ;;
    *'d w') printf '%s\n' 'yes:80:2412:Lab\:A\\B:AA\:BB:WPA2' ;;
    *'device status') printf '%s\n' 'wlan0:wifi:connected:Lab\:A\\B' ;;
    'device show wlan0') echo 'IP4.ADDRESS[1]: 192.0.2.1/24' ;;
    *'NAME,TYPE connection show') printf '%s\n' 'Profile\:1:802-11-wireless' 'Ethernet:802-3-ethernet' ;;
    *'connection show Profile:1') printf '%s\n' '802-11-wireless.ssid:Lab\:A\\B' '802-11-wireless-security.key-mgmt:sae' ;;
esac
'''
QML = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root
    property int completed: 0
    property int savedReplies: 0
    property list<QtObject> commands
    Component.onCompleted: {
        for (let i = 0; i < 4; ++i)
            Nmcli.loadSavedConnections(ssids => { if (ssids.length === 1) root.savedReplies++; });
        for (let i = 0; i < 24; ++i) {
            Nmcli.executeCommand(["test"], () => root.completed++);
            commands.push(Nmcli.activeProcesses[Nmcli.activeProcesses.length - 1]);
        }
    }
    FileView {
        id: trigger
        path: Quickshell.env("NET_FIXTURE") + "/emit"
        printErrors: false
    }
    Timer {
        running: root.completed === 24
        interval: 150
        onTriggered: trigger.setText("go")
    }
    Timer {
        running: true
        interval: 2500
        onTriggered: {
            console.log("NETWORK_RESULT", JSON.stringify({completed: root.completed,
                retained: root.commands.filter(p => p !== null).length, ssid: Nmcli.active?.ssid,
                bssid: Nmcli.active?.bssid, connection: Nmcli.wirelessInterfaces[0]?.connection,
                address: Nmcli.wirelessDeviceDetails?.ipAddress, saved: Nmcli.savedConnectionSsids,
                savedReplies: root.savedReplies, security: Nmcli.savedSecurityFor(Nmcli.active?.ssid ?? "")}));
            Qt.quit();
        }
    }
}'''


@unittest.skipUnless(os.environ.get("HYPRSTACK_TEST_PREFIX"), "set HYPRSTACK_TEST_PREFIX to a staged build")
class NetworkServiceTests(unittest.TestCase):
    def run_service(self, qml):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / "runtime").mkdir(mode=0o700)
            (base / "services").mkdir()
            (base / "services/Nmcli.qml").symlink_to(ROOT / "shell/services/Nmcli.qml")
            (base / "shell.qml").write_text(qml)
            nmcli = base / "nmcli"
            nmcli.write_text(FAKE_NMCLI)
            nmcli.chmod(0o755)
            qml_path = str(Path(os.environ["HYPRSTACK_TEST_PREFIX"]).resolve() / "share/hyprstack/qml")
            env = dict(os.environ, HOME=temp, XDG_RUNTIME_DIR=str(base / "runtime"),
                       XDG_CONFIG_HOME=temp, XDG_CACHE_HOME=temp, XDG_STATE_HOME=temp, XDG_DATA_HOME=temp,
                       QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", NET_FIXTURE=temp,
                       QML_IMPORT_PATH=qml_path, QML2_IMPORT_PATH=qml_path, PATH=temp + ":" + os.environ["PATH"])
            result = subprocess.run(["dbus-run-session", "--", "qs", "-p", temp, "--no-color"],
                                    env=env, text=True, capture_output=True, timeout=15)
            output = result.stdout + result.stderr
            marker = next((s.partition("NETWORK_RESULT ")[2] for s in output.splitlines() if "NETWORK_RESULT " in s), "")
            self.assertTrue(marker, output)
            state = json.loads(marker)
            calls = (base / "calls").read_text().splitlines()
            return state, calls

    def test_monitor_burst_and_command_lifetime(self):
        state, calls = self.run_service(QML)
        queries = [c for c in calls[calls.index("BURST") + 1:] if c.endswith(" d w")]
        self.assertEqual((len(queries), state["retained"], state["completed"]), (1, 0, 24))
        self.assertEqual(state["ssid"], r"Lab:A\B")
        self.assertEqual(state["connection"], state["ssid"])
        self.assertEqual(state["bssid"], "AA:BB")
        self.assertEqual(state["address"], "192.0.2.1")
        self.assertEqual((state["saved"], state["security"], state["savedReplies"]), ([state["ssid"]], "sae", 4))
        self.assertEqual(sum(c.endswith("NAME,TYPE connection show") for c in calls), 2)

    def test_activation_results_belong_to_the_request(self):
        state, calls = self.run_service('''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property var replies: []
    property int step: 0
    function record(label: string, result: var): void {
        replies.push([label, result.success, result.needsPassword === true, result.error.trim()]);
    }
    Timer {
        interval: 60
        running: true
        repeat: true
        onTriggered: {
            if (root.step === 0) {
                root.step++;
                Nmcli.connectToNetwork("needs-secret", "", "", r => root.record("secret", r));
                Nmcli.executeCommand(["connection", "show", "unrelated"], r => root.record("query", r));
            } else if (root.step === 1 && root.replies.length >= 2) {
                root.step++;
                Nmcli.connectToNetwork("superseded", "", "", r => root.record("stale", r));
                Nmcli.connectToNetwork("good", "", "", r => root.record("good", r));
            } else if (root.step === 2 && root.replies.some(r => r[0] === "good")) {
                root.step++;
                Nmcli.connectToNetwork("retry", "", "", r => root.record("retry", r));
            } else if (root.step === 3 && root.replies.some(r => r[0] === "retry")) {
                root.step++;
                Nmcli.connectToNetwork("changed", "fixture", "AA:BB", r => root.record("saved", r));
            } else if (root.step === 4 && root.replies.some(r => r[0] === "saved")) {
                console.log("NETWORK_RESULT", JSON.stringify({replies: root.replies,
                    pending: Nmcli.pendingConnection, subnet: Nmcli.cidrToSubnetMask("0")}));
                Qt.quit();
            }
        }
    }
}''')
        self.assertEqual(sorted(state["replies"]), [
            ["good", True, False, ""],
            ["query", False, False, "Secrets were required for an unrelated query"],
            ["retry", True, False, ""],
            ["saved", True, False, ""],
            ["secret", False, True, "Secrets were required for this activation"],
        ])
        self.assertEqual(calls.count("device wifi connect superseded"), 1)
        self.assertEqual(calls.count("device wifi connect retry"), 2)
        self.assertIn("connection modify uuid fixture-uuid 802-11-wireless-security.psk fixture", calls)
        self.assertIn("connection up uuid fixture-uuid ap AA:BB", calls)
        self.assertFalse(any("connection delete" in call for call in calls))
        self.assertIsNone(state["pending"])
        self.assertEqual(state["subnet"], "0.0.0.0")


if __name__ == "__main__":
    unittest.main()
