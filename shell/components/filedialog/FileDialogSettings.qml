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
    property var folderSort: ({})
    property bool loaded: false

    function persist(): void {
        const data = {viewMode: viewMode, sortBy: sortBy, reverse: reverse};
        if (Object.keys(folderSort).length) data.folderSort = folderSort;
        storage.setText(JSON.stringify(data));
    }

    function setView(mode: string): void {
        if (!loaded || !["icons", "list"].includes(mode)) return;
        viewMode = mode;
        persist();
    }

    function sortFor(path: string): var {
        const scoped = folderSort[path];
        return ["name", "modified", "size", "type"].includes(scoped?.sortBy)
            ? {sortBy: scoped.sortBy, reverse: scoped.reverse === true, foldersFirst: scoped.foldersFirst !== false}
            : {sortBy: sortBy, reverse: reverse, foldersFirst: true};
    }

    function chooseSort(field: string, path: string): void {
        if (!loaded || !["name", "modified", "size", "type"].includes(field)) return;
        const current = sortFor(path);
        const next = {sortBy: field, reverse: current.sortBy === field
            ? !current.reverse : ["modified", "size"].includes(field)};
        if (folderSort[path]) {
            if (!current.foldersFirst) next.foldersFirst = false;
            const updated = Object.assign({}, folderSort);
            updated[path] = next;
            folderSort = updated;
        } else {
            reverse = next.reverse;
            sortBy = next.sortBy;
        }
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
                root.folderSort = data.folderSort && typeof data.folderSort === "object" ? data.folderSort : ({});
            } catch (error) {
                console.warn(`Unable to load file dialog preferences: ${error}`);
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
}
