import QtQuick
import QtTest
import Quickshell
import Hyprstack.Config
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.dashboard.dash
import qs.modules.nexus.pages
import "fixtures" as Fixtures

ShellRoot {
    Component.onCompleted: GlobalConfig.general.language = "en"
    ScreenState { id: state; modelData: Quickshell.screens[0]; dashboard: true }
    FloatingWindow {
        id: host
        visible: true
        color: Colours.palette.m3surface
        implicitWidth: 1100
        implicitHeight: 650
        contentItem.Config.screen: screen.name
        contentItem.Tokens.screen: screen.name
        Item {
            x: 20; y: 20; width: 440; height: 400
            Calendar { id: calendar; screenState: state }
        }
        AboutPage { id: about; visible: false; width: 600; height: 600; nState: null }
        Fixtures.VpnToggle { id: barVpn; x: 480; y: 30 }
        TestCase {
            name: "FriendlyVpn"
            when: ManagedVPN.window !== null && ManagedVPN.loaded
            property int serial: 0
            function control(name) {
                function visual(item) {
                    if (item.objectName === name) return item;
                    for (const child of item.children ?? []) {
                        const found = visual(child);
                        if (found) return found;
                    }
                    return null;
                }
                return findChild(ManagedVPN.window, name) ?? visual(ManagedVPN.window.contentItem);
            }
            function click(item) {
                verify(!!item);
                verify(item.visible);
                mouseClick(item, item.width / 2, item.height / 2);
            }
            function fixture(changes) {
                VPN.otherConnected = false;
                VPN.nativeSelected = true;
                ManagedVPN.error = "";
                const value = Object.assign({profiles:[
                    {id:"a12bc34d",name:"Server A",type:"trojan",latency_ms:23},
                    {id:"b56de78f",name:"Server B",type:"vless",latency_ms:-1}],
                    groups:[],routes:[{id:"all",name:"All traffic",active:true}],
                    selectedProfile:"a12bc34d",mode:"tun",connected:false,
                    installed:true,canTun:true,fixtureSerial:++serial}, changes ?? {});
                ManagedVPN.run("fixture", value);
                tryVerify(() => !ManagedVPN.busy && ManagedVPN.data.fixtureSerial === serial, 3000);
                wait(40);
            }
            function init() { fixture({}); }
            function cleanup() {
                console.log("VPN_UI_CASE " + qtest_results.functionName + " failed=" + qtest_results.failed);
            }
            function test_about_has_no_plugin_placeholder() {
                verify(about.pluginCount === undefined);
                function labels(item) {
                    if (item.text === "Loaded plugins" || item.text === "Plugins") return true;
                    return [...(item.children ?? [])].some(labels);
                }
                verify(!labels(about));
            }
            function test_calendar_opens_settings_on_the_same_screen() {
                state.dashboard = true;
                const before = WindowFactory.opened;
                click(findChild(calendar, "dashboardSettingsButton"));
                compare(state.dashboard, false);
                compare(WindowFactory.opened, before + 1);
                compare(WindowFactory.lastScreen, state.modelData);
            }
            function test_calendar_settings_fit_a_narrow_dashboard() {
                const width = calendar.parent.width;
                try {
                    for (const size of [320, 440]) {
                        calendar.parent.width = size;
                        wait(40);
                        const button = findChild(calendar, "dashboardSettingsButton");
                        const point = button.mapToItem(calendar, 0, 0);
                        verify(point.x >= 0 && point.x + button.width <= calendar.width);
                    }
                } finally {
                    calendar.parent.width = width;
                }
            }
            function test_empty_state_has_one_obvious_import_action() {
                fixture({profiles:[],selectedProfile:-1,installed:false,canTun:false});
                compare(ManagedVPN.window.primaryAction, "import");
                compare(control("vpnConnectButton").text, "Add connection");
                click(control("vpnConnectButton"));
                tryVerify(() => control("vpnImportDialog").opened);
                control("vpnImportDialog").close();
            }
            function test_setup_steps_do_not_connect_implicitly() {
                fixture({installed:false,canTun:false});
                compare(ManagedVPN.window.primaryAction, "install");
                click(control("vpnConnectButton"));
                tryVerify(() => !ManagedVPN.busy && ManagedVPN.data.installed === true);
                compare(ManagedVPN.window.primaryAction, "authorize");
                verify(!ManagedVPN.connected);
                click(control("vpnConnectButton"));
                tryVerify(() => !ManagedVPN.busy && ManagedVPN.data.canTun === true);
                compare(ManagedVPN.window.primaryAction, "connect");
                verify(!ManagedVPN.connected);
            }
            function test_connect_and_disconnect_are_explicit() {
                click(control("vpnConnectButton"));
                tryVerify(() => ManagedVPN.connected && !ManagedVPN.busy);
                compare(control("vpnConnectButton").text, "Disconnect");
                click(control("vpnConnectButton"));
                tryVerify(() => !ManagedVPN.connected && !ManagedVPN.busy);
            }
            function test_server_selection_preserves_opaque_ids() {
                click(control("vpnProfile_b56de78f"));
                tryVerify(() => ManagedVPN.data.selectedProfile === "b56de78f" && !ManagedVPN.busy);
                wait(60);
                const operations = ManagedVPN.data.operations.length;
                click(control("vpnProfile_b56de78f"));
                wait(100);
                compare(ManagedVPN.data.operations.length, operations);
                verify(!ManagedVPN.connected);
            }
            function test_other_provider_is_never_silently_replaced() {
                VPN.nativeSelected = false;
                VPN.otherConnected = true;
                compare(ManagedVPN.window.primaryAction, "disconnect-other");
                click(control("vpnConnectButton"));
                verify(!VPN.otherConnected);
                verify(!ManagedVPN.connected);
                compare(ManagedVPN.data.operations.length, 0);
                click(control("vpnConnectButton"));
                tryVerify(() => ManagedVPN.connected && !ManagedVPN.busy);
                verify(VPN.nativeSelected);
            }
            function test_keyboard_can_choose_a_server() {
                const server = control("vpnProfile_b56de78f");
                verify(!!server);
                server.forceActiveFocus();
                keyClick(Qt.Key_Space);
                tryVerify(() => ManagedVPN.data.selectedProfile === "b56de78f" && !ManagedVPN.busy);
                verify(!ManagedVPN.connected);
            }
            function test_bar_icon_opens_controls_without_toggling_connection() {
                fixture({connected:true,server:"Server A"});
                click(barVpn);
                wait(100);
                verify(ManagedVPN.connected);
                compare(ManagedVPN.data.operations.length, 0);
            }
            function test_import_success_closes_the_form_and_failure_keeps_input() {
                click(control("vpnAddConnectionButton"));
                tryVerify(() => control("vpnImportDialog").opened);
                control("vpnImportInput").text = "invalid";
                click(control("vpnImportButton"));
                tryVerify(() => !!ManagedVPN.error && !ManagedVPN.busy);
                verify(control("vpnImportDialog").opened);
                compare(control("vpnImportInput").text, "invalid");
                control("vpnImportInput").text = "trojan://example@example.com:443#Demo";
                click(control("vpnImportButton"));
                tryVerify(() => !control("vpnImportDialog").opened && ManagedVPN.profiles.length === 3);
                compare(control("vpnImportInput").text, "");
                verify(!ManagedVPN.connected);
            }
            function test_delete_confirmation_keeps_the_original_target() {
                click(control("vpnDeleteButton"));
                tryVerify(() => control("vpnDeleteDialog").opened);
                ManagedVPN.run("select", {id:"b56de78f"});
                tryVerify(() => !ManagedVPN.busy && ManagedVPN.data.selectedProfile === "b56de78f");
                click(control("vpnConfirmDeleteButton"));
                tryVerify(() => !ManagedVPN.busy && ManagedVPN.profiles.length === 1);
                compare(ManagedVPN.profiles[0].id, "b56de78f");
            }
            function test_proxy_mode_needs_no_tunnel_authorization() {
                fixture({mode:"proxy",canTun:false});
                compare(ManagedVPN.window.primaryAction, "connect");
            }
            function test_small_window_keeps_import_actions_reachable() {
                const height = ManagedVPN.window.height;
                const scale = GlobalConfig.appearance.scale;
                try {
                    GlobalConfig.appearance.scale = 1.5;
                    ManagedVPN.window.height = 480;
                    click(control("vpnAddConnectionButton"));
                    tryVerify(() => control("vpnImportDialog").opened);
                    control("vpnImportType").currentIndex = 1;
                    wait(100);
                    const button = control("vpnImportButton");
                    const point = button.mapToItem(ManagedVPN.window.contentItem, 0, 0);
                    verify(point.y >= 0 && point.y + button.height <= ManagedVPN.window.height);
                } finally {
                    control("vpnImportDialog").close();
                    GlobalConfig.appearance.scale = scale;
                    ManagedVPN.window.height = height;
                }
            }
            function cleanupTestCase() {
                const directory = Quickshell.env("HYPRSTACK_UI_SCREENSHOT_DIR");
                if (directory) {
                    fixture({});
                    GlobalConfig.general.language = "ru_RU";
                    wait(150);
                    grabImage(ManagedVPN.window.contentItem).save(directory + "/vpn.png");
                    grabImage(calendar).save(directory + "/calendar.png");
                    click(control("vpnAddConnectionButton"));
                    tryVerify(() => control("vpnImportDialog").opened);
                    grabImage(ManagedVPN.window.contentItem).save(directory + "/vpn-import.png");
                }
                console.log("VPN_UI_COMPLETE " + JSON.stringify({failures:qtest_results.failCount,passed:qtest_results.passCount}));
                Qt.quit();
            }
        }
    }
    Timer { interval:100;running:true;onTriggered:ManagedVPN.openSettings() }
    Timer { interval:30000;running:true;onTriggered:{console.error("VPN_UI_TIMEOUT");Qt.quit();} }
}
