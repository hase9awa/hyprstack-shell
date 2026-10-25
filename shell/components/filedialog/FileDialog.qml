pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.I18n
import qs.components
import qs.services
import qs.utils

LazyLoader {
    id: loader

    enum Mode {
        Open,
        Save,
        SelectFolder
    }

    property int mode: FileDialog.Open
    property bool multiple
    property list<string> cwd: ["Home"]
    property string filterLabel: Tr.tr("All files")
    property list<string> filters: ["*"]
    // Named groups are the richer form of filterLabel and filters: each entry
    // is {label, patterns}. Callers that only ever offer one set keep using
    // the plain pair.
    property var filterGroups: []
    property int currentFilter
    property string title: Tr.tr("Select a file")
    property string acceptLabel
    property string suggestedName

    readonly property var groups: filterGroups.length > 0 ? filterGroups
        : [{label: filterLabel, patterns: filters}]
    readonly property string defaultAcceptLabel: {
        if (mode === FileDialog.Save)
            return Tr.trCtx("Save", "button");
        if (mode === FileDialog.SelectFolder)
            return Tr.trCtx("Select folder", "button");
        return Tr.trCtx("Select", "button");
    }

    signal accepted(paths: list<string>)
    signal rejected

    function open(): void {
        activeAsync = true;
    }

    function close(): void {
        rejected();
    }

    onAccepted: activeAsync = false
    onRejected: activeAsync = false

    FloatingWindow {
        id: root

        property list<string> cwd: loader.cwd
        property int currentFilter: loader.currentFilter
        property string saveName: loader.suggestedName

        readonly property int mode: loader.mode
        readonly property bool multiple: loader.multiple && loader.mode === FileDialog.Open
        readonly property var groups: loader.groups
        readonly property var activeGroup: groups[Math.max(0, Math.min(currentFilter, groups.length - 1))] ?? null
        readonly property list<string> patterns: activeGroup?.patterns ?? ["*"]
        readonly property string acceptLabel: loader.acceptLabel || loader.defaultAcceptLabel

        readonly property string currentPath: cwd[0] === "Home"
            ? `${Paths.home}${cwd.length > 1 ? "/" : ""}${cwd.slice(1).join("/")}` : cwd.join("/")

        function matchesFilter(file: var): bool {
            if (!file || file.isDir)
                return false;
            return patterns.includes("*") || patterns.some(pattern => pattern.toLowerCase() === file.suffix.toLowerCase());
        }

        readonly property bool selectionValid: {
            if (mode === FileDialog.SelectFolder)
                return true;
            if (mode === FileDialog.Save)
                return saveName.trim().length > 0;
            return folderContents.selectedPaths.length > 0;
        }

        // Saving over an existing file is allowed, but the button says so.
        readonly property bool overwriting: mode === FileDialog.Save && folderContents.contains(saveName.trim())

        function accepted(paths: list<string>): void {
            loader.currentFilter = currentFilter;
            loader.accepted(paths);
        }

        function submit(): void {
            if (!selectionValid)
                return;
            if (mode === FileDialog.SelectFolder)
                accepted([currentPath]);
            else if (mode === FileDialog.Save)
                accepted([`${currentPath}/${saveName.trim()}`]);
            else
                accepted(folderContents.selectedPaths);
        }

        function rejected(): void {
            loader.rejected();
        }

        implicitWidth: 1000
        implicitHeight: 600
        minimumSize.width: 400
        minimumSize.height: 300
        color: Colours.tPalette.m3surface
        surfaceFormat.opaque: false
        title: loader.title

        onVisibleChanged: {
            if (!visible)
                rejected();
        }

        RowLayout {
            anchors.fill: parent

            spacing: 0

            Sidebar {
                Layout.fillHeight: true
                dialog: root
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                spacing: 0

                HeaderBar {
                    Layout.fillWidth: true
                    dialog: root
                }

                FolderContents {
                    id: folderContents

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    dialog: root
                }

                DialogButtons {
                    Layout.fillWidth: true
                    dialog: root
                    folder: folderContents
                }
            }
        }

        Behavior on color {
            CAnim {}
        }
    }
}
