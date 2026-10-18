import QtQuick
import Quickshell
import Hyprstack.Config
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        Notifs;
        Players;
        WindowSwitcher;
        Brightness;
        Weather.reload();
        ThemeSync.requestSync();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
