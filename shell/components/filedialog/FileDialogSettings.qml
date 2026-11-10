pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root
    property string viewMode: "icons"
    property string sortBy: "name"
    property bool reverse: false
    property bool loaded: false

    function persist(): void {
        storage.setText(JSON.stringify({viewMode: viewMode, sortBy: sortBy, reverse: reverse}));
    }

    function setView(mode: string): void {
        if (!loaded || !["icons", "list"].includes(mode)) return;
        viewMode = mode;
        persist();
    }

    function chooseSort(field: string): void {
        if (!loaded || !["name", "modified", "size", "type"].includes(field)) return;
        reverse = sortBy === field ? !reverse : ["modified", "size"].includes(field);
        sortBy = field;
        persist();
    }

    FileView {
        id: storage
        path: `${Paths.config}/file-dialog.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.viewMode = ["icons", "list"].includes(data.viewMode) ? data.viewMode : "icons";
                root.sortBy = ["name", "modified", "size", "type"].includes(data.sortBy) ? data.sortBy : "name";
                root.reverse = data.reverse === true;
            } catch (error) {
                console.warn(`Unable to load file dialog preferences: ${error}`);
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
}
