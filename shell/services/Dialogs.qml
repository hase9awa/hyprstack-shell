pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components.misc
import qs.services

// What the shell puts up in front of the windows: its own dialogs, and the
// menus it opens. A layer surface is not a window, so the compositor cannot
// close one with the key the user closes windows with; the shell keeps the
// list and does it instead.
Singleton {
    id: root

    property var dialogs: []
    readonly property bool anyOpen: root.dialogs.some(dialog => dialog.visible) || ShellState.menuOpen

    // The compositor reads this before closing a window, so that the key
    // keeps closing windows when the shell has nothing up, or no shell is
    // running at all.
    readonly property string flagPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/hyprstack-dialogs-${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}`

    function register(dialog: var): void {
        root.dialogs = [...root.dialogs, dialog];
    }

    function unregister(dialog: var): void {
        root.dialogs = root.dialogs.filter(other => other !== dialog);
    }

    // The newest dialog is the one in front, and the one a close is meant
    // for. A dialog that stepped aside for something else is not in front.
    // Dialogs stand in front of the menus, so they answer first.
    function closeFront(): void {
        const open = root.dialogs.filter(dialog => dialog.visible);
        if (open.length > 0)
            open[open.length - 1].closeRequested();
        else
            ShellState.closeDrawers();
    }

    // A shell that went away with a dialog up must not leave the key
    // pointing at something that is no longer there.
    Component.onCompleted: flag.setText("0\n")

    onAnyOpenChanged: flag.setText(root.anyOpen ? "1\n" : "0\n")

    FileView {
        id: flag

        path: root.flagPath
        printErrors: false
        atomicWrites: false
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "closeDialog"
        description: "Close the shell's own dialog or menu"
        onPressed: root.closeFront()
    }
}
