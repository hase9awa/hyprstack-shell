pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Portals
import qs.services

Scope {
    id: root

    required property AccessPortal portal

    Instantiator {
        model: ScriptModel {
            values: [...root.portal.requests]
        }

        AccessDialog {
            required property AccessRequest modelData

            request: modelData
            // Evaluated while the dialog is being built, before it takes a
            // surface, so the prompt never shows up on the wrong monitor.
            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

            // A prompt that has to be answered deserves a clear screen.
            Component.onCompleted: {
                Overview.close(false);
                WindowSwitcher.close();
                ShellState.closeDrawers();
            }
        }
    }
}
