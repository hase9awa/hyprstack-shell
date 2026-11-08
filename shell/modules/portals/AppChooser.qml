pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Portals
import qs.services

Scope {
    id: root

    required property AppChooserPortal portal

    Instantiator {
        model: ScriptModel {
            values: [...root.portal.requests]
        }

        AppChooserDialog {
            required property AppChooserRequest modelData

            request: modelData
            // Evaluated while the dialog is being built, before it takes a
            // surface, so the chooser never shows up on the wrong monitor.
            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

            // A dialog that has to be answered deserves a clear screen.
            Component.onCompleted: {
                Overview.close(false);
                WindowSwitcher.close();
                ShellState.closeDrawers();
            }
        }
    }
}
