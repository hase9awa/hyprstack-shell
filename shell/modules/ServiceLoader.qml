import QtQuick
import Quickshell
import Hyprstack.Config
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        // The pointer settings reach the compositor on every start, not only
        // when the settings page is opened.
        Pointer;
        Animations;
        // Its shortcut has to be registered before the first dialog, since
        // the compositor hands the key over only once one is up.
        Dialogs;
        Notifs;
        Updates;
        Players;
        WindowSwitcher;
        Brightness;
        Weather;
        ThemeSync.requestSync();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
