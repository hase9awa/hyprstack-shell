pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import qs.utils

// The folders the user pinned in their file manager. GTK keeps that list in
// a file of its own, and every GTK application reads it from there, so the
// shell's dialog offers the same pins as the rest of the desktop rather
// than a list of its own that nobody else knows about.
Scope {
    id: root

    readonly property string path: `${Quickshell.env("XDG_CONFIG_HOME") || `${Paths.home}/.config`}/gtk-3.0/bookmarks`
    property list<var> places: []

    function parse(text: string): void {
        const pinned = [];
        for (const line of text.split("\n")) {
            const entry = line.trim();
            // A line names a folder and may give it a name of its own.
            // Anything that is not a local folder, a share among them, is
            // not something this dialog can open.
            if (!entry.startsWith("file://"))
                continue;
            const space = entry.indexOf(" ");
            const folder = decodeURIComponent((space < 0 ? entry : entry.slice(0, space)).slice(7));
            const label = space < 0 ? "" : entry.slice(space + 1).trim();
            if (!CUtils.isDirectory(folder))
                continue;
            pinned.push({
                path: folder,
                name: label || folder.slice(folder.lastIndexOf("/") + 1),
                icon: "bookmark"
            });
        }
        root.places = pinned;
    }

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false

        onLoaded: root.parse(text())
        onFileChanged: reload()
        // A desktop with no GTK about it has no such file, and nothing in it
        // is pinned.
        onLoadFailed: root.places = []
    }
}
