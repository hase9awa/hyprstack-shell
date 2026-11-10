pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.services
import qs.utils
import "Filters.js" as Filters

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

    readonly property var groups: filterGroups.length > 0 ? filterGroups : [
        {
            label: filterLabel,
            patterns: filters
        }
    ]
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

    DialogWindow {
        id: root

        name: "filechooser"
        onCloseRequested: rejected()
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: root.rejected()
        }

        property list<string> cwd: loader.cwd
        property int currentFilter: loader.currentFilter
        property string saveName: loader.suggestedName
        property bool showHidden: false
        property string errorMessage
        property list<string> history: []
        property int historyIndex: -1
        readonly property bool canBack: historyIndex > 0
        readonly property bool canForward: historyIndex >= 0 && historyIndex < history.length - 1
        readonly property bool canUp: currentPath !== "/"

        readonly property int mode: loader.mode
        readonly property bool multiple: loader.multiple && loader.mode === FileDialog.Open
        readonly property var groups: loader.groups
        readonly property var activeGroup: groups[Math.max(0, Math.min(currentFilter, groups.length - 1))] ?? null
        readonly property list<string> patterns: activeGroup?.patterns ?? ["*"]
        readonly property string acceptLabel: loader.acceptLabel || loader.defaultAcceptLabel

        readonly property string currentPath: cwd[0] === "Home" ? `${Paths.home}${cwd.length > 1 ? "/" : ""}${cwd.slice(1).join("/")}` : (cwd.join("/") || "/")

        // The same path the other way round: the segments the bar walks,
        // with home named rather than spelled out.
        function segmentsFor(path: string): list<string> {
            if (path === "/") return [""];
            if (path === Paths.home)
                return ["Home"];
            if (path.startsWith(`${Paths.home}/`))
                return ["Home", ...path.slice(Paths.home.length + 1).split("/")];
            return path.split("/");
        }

        function navigate(input: string): bool {
            const path = CUtils.resolveFilePath(input, currentPath);
            const info = path ? CUtils.fileInfo(path) : null;
            if (!info?.exists) {
                errorMessage = Tr.tr("This path does not exist");
                return false;
            }
            if (!info.readable) {
                errorMessage = Tr.tr("This location is not accessible");
                return false;
            }
            if (!info.isDir) {
                if (mode === FileDialog.SelectFolder) {
                    errorMessage = Tr.tr("Choose a folder");
                    return false;
                }
                if (mode === FileDialog.Open && !Filters.matches(info.name, patterns)) {
                    errorMessage = Tr.tr("This file does not match the selected filter");
                    return false;
                }
                if (!navigate(info.parent)) return false;
                if (mode === FileDialog.Save) saveName = info.name;
                else folderContents.selectedPaths = [path];
                return true;
            }
            errorMessage = "";
            if (currentPath !== path) {
                cwd = segmentsFor(path);
                history = [...history.slice(0, historyIndex + 1), path];
                historyIndex = history.length - 1;
            }
            folderContents.focusContents();
            return true;
        }

        function goHistory(offset: int): void {
            const index = historyIndex + offset;
            if (index < 0 || index >= history.length) return;
            const path = history[index];
            const info = CUtils.fileInfo(path);
            if (!info.isDir || !info.readable) {
                errorMessage = Tr.tr("This location is not accessible");
                return;
            }
            historyIndex = index;
            cwd = segmentsFor(path);
            errorMessage = "";
            folderContents.focusContents();
        }

        function goUp(): void {
            if (canUp) navigate(CUtils.fileInfo(currentPath).parent);
        }

        Shortcut { sequence: "Ctrl+L"; context: Qt.WindowShortcut; onActivated: header.editPath() }
        Shortcut { sequence: "Alt+Left"; context: Qt.WindowShortcut; onActivated: root.goHistory(-1) }
        Shortcut { sequence: "Alt+Right"; context: Qt.WindowShortcut; onActivated: root.goHistory(1) }
        Shortcut { sequence: "Alt+Up"; context: Qt.WindowShortcut; onActivated: root.goUp() }
        Shortcut { sequence: "Ctrl+H"; context: Qt.WindowShortcut; onActivated: root.showHidden = !root.showHidden }

        Component.onCompleted: {
            const path = CUtils.resolveFilePath(currentPath, Paths.home);
            const info = path ? CUtils.fileInfo(path) : null;
            if (!info?.isDir || !info.readable) {
                cwd = ["Home"];
                errorMessage = Tr.tr("The requested folder is unavailable; showing Home");
            } else cwd = segmentsFor(path);
            history = [currentPath];
            historyIndex = 0;
        }

        function matchesFilter(file: var): bool {
            if (!file || file.isDir)
                return false;
            return Filters.matches(file.name, patterns);
        }

        readonly property bool selectionValid: {
            if (mode === FileDialog.SelectFolder)
                return true;
            if (mode === FileDialog.Save)
                return saveName.length > 0 && saveName !== "." && saveName !== ".." && !saveName.includes("/") && !saveName.includes("\0");
            return folderContents.selectedPaths.length > 0;
        }

        // Saving over an existing file is allowed, but the button says so.
        readonly property bool overwriting: mode === FileDialog.Save && folderContents.contains(saveName)

        function accepted(paths: list<string>): void {
            loader.currentFilter = currentFilter;
            loader.accepted(paths);
        }

        function submit(): void {
            if (!selectionValid)
                return;
            if (mode === FileDialog.SelectFolder)
                accepted([currentPath]);
            else if (mode === FileDialog.Save) {
                const path = `${currentPath === "/" ? "" : currentPath}/${saveName}`;
                if (CUtils.isDirectory(path)) {
                    navigate(path);
                    return;
                }
                if (!CUtils.fileInfo(currentPath).writable) {
                    errorMessage = Tr.tr("This folder is read-only");
                    return;
                }
                accepted([path]);
            }
            else
                accepted(folderContents.selectedPaths);
        }

        function rejected(): void {
            loader.rejected();
        }

        dialogWidth: Math.min(1000 * Tokens.scale, (screen?.width ?? 1080) - 48 * Tokens.scale)
        dialogHeight: Math.min(600 * Tokens.scale, (screen?.height ?? 720) - 96 * Tokens.scale)

        onVisibleChanged: {
            if (!visible)
                rejected();
        }

        StyledClippingRect {
            anchors.fill: parent
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surface

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
                        id: header
                        Layout.fillWidth: true
                        dialog: root
                    }

                    ViewControls {
                        Layout.fillWidth: true
                    }

                    FolderContents {
                        id: folderContents

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        dialog: root
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.medium
                        Layout.rightMargin: Tokens.padding.medium
                        visible: root.errorMessage.length > 0
                        text: root.errorMessage
                        color: Colours.palette.m3error
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    DialogButtons {
                        Layout.fillWidth: true
                        dialog: root
                        folder: folderContents
                    }
                }
            }
        }
    }
}
