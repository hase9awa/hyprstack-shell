pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Models
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root
    objectName: "fileDialogContents"

    required property var dialog
    readonly property FileEntry currentItem: view.currentItem as FileEntry
    property list<string> selectedPaths
    readonly property bool listMode: FileDialogSettings.viewMode === "list"
    readonly property int modifiedWidth: 160 * Tokens.scale
    readonly property int sizeWidth: 80 * Tokens.scale
    readonly property int typeWidth: 85 * Tokens.scale
    property bool reordering: false
    property string focusedPath

    function restoreCurrent(): void {
        const entries = [...view.model.entries];
        view.currentIndex = focusedPath ? entries.findIndex(entry => entry.path === focusedPath) : -1;
        reordering = false;
    }

    function focusContents(): void { view.forceActiveFocus(); }

    Shortcut { sequence: "F5"; context: Qt.WindowShortcut; onActivated: view.model.refresh() }

    function activateCurrent(): void {
        const file = currentItem?.modelData;
        if (file?.isDir) dialog.navigate(file.path);
        else dialog.submit();
    }

    function contains(name: string): bool {
        if (!name)
            return false;
        for (const entry of view.model.entries)
            if (entry.name === name)
                return true;
        return false;
    }

    // What a click means depends on the mode: saving fills the name in,
    // picking a folder answers with the folder already shown, and opening
    // builds the selection.
    function select(file: FileSystemEntry): void {
        if (dialog.mode === FileDialog.Save) {
            if (!file.isDir)
                dialog.saveName = file.name;
            return;
        }
        if (dialog.mode === FileDialog.SelectFolder)
            return;

        if (!dialog.matchesFilter(file)) {
            if (!file.isDir || !dialog.multiple)
                selectedPaths = [];
            return;
        }

        if (!dialog.multiple) {
            selectedPaths = [file.path];
        } else if (selectedPaths.includes(file.path)) {
            selectedPaths = selectedPaths.filter(path => path !== file.path);
        } else {
            selectedPaths = [...selectedPaths, file.path];
        }
    }

    StyledRect {
        anchors.fill: parent
        color: Colours.tPalette.m3surfaceContainer

        layer.enabled: true
        layer.effect: Mask {
            maskSource: mask
            maskInverted: true
        }
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall
            radius: Tokens.rounding.medium
        }
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent

        opacity: view.count === 0 ? 1 : 0
        active: opacity > 0

        sourceComponent: ColumnLayout {
            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "scan_delete"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.Medium).build()
            }

            StyledText {
                text: Tr.tr("This folder is empty")
                color: Colours.palette.m3outline
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    RowLayout {
        id: columns
        visible: root.listMode
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.extraSmall + Tokens.padding.medium * 2 + 26 * Tokens.scale + Tokens.spacing.medium
        anchors.rightMargin: Tokens.padding.extraSmall + Tokens.padding.medium * 2
        spacing: Tokens.spacing.medium
        ColumnHeader { Layout.fillWidth: true; field: "name"; label: Tr.trCtx("Name", "file column") }
        ColumnHeader { Layout.preferredWidth: root.modifiedWidth; field: "modified"; label: Tr.tr("Date modified") }
        ColumnHeader { Layout.preferredWidth: root.sizeWidth; field: "size"; label: Tr.trCtx("Size", "file column") }
        ColumnHeader { Layout.preferredWidth: root.typeWidth; field: "type"; label: Tr.trCtx("Type", "file column") }
    }

    component ColumnHeader: Item {
        id: header
        required property string field
        required property string label
        readonly property bool active: FileDialogSettings.sortBy === field
        objectName: "fileDialogSort_" + field
        implicitHeight: heading.implicitHeight + Tokens.padding.small * 2
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: FileDialogSettings.chooseSort(field)

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.small
            color: header.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            disabled: !FileDialogSettings.loaded
            onClicked: FileDialogSettings.chooseSort(header.field)
        }

        StyledText {
            id: heading
            anchors.fill: parent
            anchors.rightMargin: indicator.visible ? indicator.implicitWidth + Tokens.spacing.extraSmall : 0
            verticalAlignment: Text.AlignVCenter
            text: header.label
            color: header.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
        }

        MaterialIcon {
            id: indicator
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: header.active
            text: FileDialogSettings.reverse ? "arrow_downward" : "arrow_upward"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.small
        }
    }

    GridView {
        id: view
        objectName: "fileDialogEntries"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: columns.visible ? columns.bottom : parent.top
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        anchors.topMargin: root.listMode ? Tokens.spacing.small : Tokens.padding.extraSmall + Tokens.padding.medium

        cellWidth: root.listMode ? width : Sizes.itemWidth + Tokens.spacing.small
        cellHeight: root.listMode ? 46 * Tokens.scale : Sizes.itemWidth + Tokens.spacing.large + Tokens.padding.medium * 2 + 1

        clip: true
        focus: true
        currentIndex: -1
        Keys.onEscapePressed: currentIndex = -1

        Keys.onReturnPressed: root.activateCurrent()
        Keys.onEnterPressed: root.activateCurrent()
        onCurrentIndexChanged: {
            if (!root.reordering && currentItem?.modelData && !root.dialog.multiple)
                root.select(currentItem.modelData);
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: view
        }

        model: FileSystemModel {
            path: root.dialog.currentPath
            showHidden: root.dialog.showHidden
            sortBy: ({name: FileSystemModel.Name, modified: FileSystemModel.Modified,
                size: FileSystemModel.Size, type: FileSystemModel.Type})[FileDialogSettings.sortBy]
            sortReverse: FileDialogSettings.reverse
            // Offering files while the caller asked for a folder only invites
            // picking the wrong thing.
            filter: root.dialog.mode === FileDialog.SelectFolder ? FileSystemModel.Dirs : FileSystemModel.NoFilter
            onPathChanged: {
                view.currentIndex = -1;
                root.selectedPaths = [];
            }
        }

        Connections {
            target: view.model
            function onLayoutAboutToBeChanged(): void {
                if (!root.reordering) root.focusedPath = view.currentItem?.modelData?.path ?? "";
                root.reordering = true;
            }
            function onLayoutChanged(): void { Qt.callLater(root.restoreCurrent); }
        }

        delegate: FileEntry {}

        add: Transition {
            Anim {
                properties: "opacity,scale"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                to: 0
            }
            Anim {
                property: "scale"
                to: 0.5
            }
        }

        displaced: Transition {
            Anim {
                type: Anim.DefaultEffects
                properties: "opacity,scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }
    }

    CurrentItem {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.extraSmall

        currentItem: view.currentItem
        selectedCount: root.selectedPaths.length
    }

    component FileEntry: StyledRect {
        id: item
        objectName: "fileDialogEntry_" + (modelData?.name ?? "")

        required property int index
        required property FileSystemEntry modelData
        readonly property bool selected: !!modelData && (root?.selectedPaths ?? []).includes(modelData.path)

        readonly property real nonAnimHeight: root.listMode ? view.cellHeight : icon.implicitHeight + name.anchors.topMargin + name.implicitHeight + Tokens.padding.medium * 2

        implicitWidth: root.listMode ? view.cellWidth : Sizes.itemWidth
        implicitHeight: nonAnimHeight

        radius: root.listMode ? Tokens.rounding.medium : Tokens.rounding.large
        color: Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, selected || GridView.isCurrentItem ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
        z: GridView.isCurrentItem || implicitHeight !== nonAnimHeight ? 1 : 0
        clip: true

        StateLayer {
            color: item.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            onClicked: {
                view.currentIndex = item.index;
                root.select(item.modelData);
            }
            onDoubleClicked: {
                if (item.modelData.isDir)
                    root.dialog.navigate(item.modelData.path);
                else
                    root.dialog.submit();
            }
        }

        Loader {
            asynchronous: true
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraSmall

            active: item.selected && root.dialog.multiple
            visible: active

            sourceComponent: MaterialIcon {
                text: "check_circle"
                color: Colours.palette.m3primary
                fill: 1
            }
        }

        Item {
            id: icon

            anchors.horizontalCenter: root.listMode ? undefined : parent.horizontalCenter
            anchors.left: root.listMode ? parent.left : undefined
            anchors.leftMargin: Tokens.padding.medium
            anchors.verticalCenter: root.listMode ? parent.verticalCenter : undefined
            anchors.top: root.listMode ? undefined : parent.top
            anchors.topMargin: Tokens.padding.medium

            implicitWidth: root.listMode ? 26 * Tokens.scale : Sizes.itemWidth - Tokens.padding.medium * 2
            implicitHeight: implicitWidth

            readonly property url iconSource: {
                const file = item.modelData;
                if (!file) return "";
                if (file.isImage) return Paths.fileUrl(file.path);
                let names;
                if (!file.isDir)
                    names = [file.mimeType.replace("/", "-"), `${file.mimeType.split("/")[0]}-x-generic`, "text-x-generic"];
                else {
                    // The desktop's own folders are known by their paths:
                    // their names are in the user's language, their icons
                    // are not.
                    const kind = [[Paths.desktop, "desktop"], [Paths.documents, "documents"],
                        [Paths.downloads, "download"], [Paths.music, "music"],
                        [Paths.pictures, "pictures"], [Paths.videos, "videos"]]
                        .find(entry => entry[0] && entry[0] === file.path);
                    names = [kind ? `folder-${kind[1]}` : "folder", "folder", "inode-directory"];
                }
                // The default missing-icon checkerboard reports Ready too.
                // Check existence before asking the provider for a texture.
                for (const name of names) {
                    const path = Quickshell.iconPath(name, true);
                    if (path) return path;
                }
                return "";
            }

            CachingIconImage {
                id: image
                objectName: "fileDialogImage"
                anchors.fill: parent
                source: icon.iconSource
                visible: status === Image.Ready
            }

            MaterialIcon {
                objectName: "fileDialogFallbackIcon"
                anchors.centerIn: parent
                visible: image.status !== Image.Ready
                text: item.modelData?.isDir ? "folder" : "draft"
                color: item.modelData?.isDir ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fill: item.modelData?.isDir ? 1 : 0
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(root.listMode ? 0.75 : 2).build()
            }
        }

        StyledText {
            id: name

            anchors.left: root.listMode ? icon.right : parent.left
            anchors.right: root.listMode ? metadata.left : parent.right
            anchors.top: root.listMode ? undefined : icon.bottom
            anchors.verticalCenter: root.listMode ? parent.verticalCenter : undefined
            anchors.topMargin: root.listMode ? 0 : Tokens.spacing.small
            anchors.leftMargin: root.listMode ? Tokens.spacing.medium : Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium

            horizontalAlignment: root.listMode ? Text.AlignLeft : Text.AlignHCenter
            elide: !root.listMode && item.GridView.isCurrentItem ? Text.ElideNone : Text.ElideRight
            wrapMode: !root.listMode && item.GridView.isCurrentItem ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
            color: item.selected ? Colours.palette.m3primary : Colours.palette.m3onSurface

            text: item.modelData?.name ?? ""
        }

        RowLayout {
            id: metadata
            visible: root.listMode
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.medium
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.medium
            StyledText {
                Layout.preferredWidth: root.modifiedWidth
                text: item.modelData ? Qt.formatDateTime(item.modelData.modified, Qt.locale(), Locale.ShortFormat) : ""
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
            StyledText {
                Layout.preferredWidth: root.sizeWidth
                text: !item.modelData || item.modelData.isDir ? "—" : Units.formatBytes(item.modelData.size)
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
            StyledText {
                Layout.preferredWidth: root.typeWidth
                text: item.modelData?.isDir ? Tr.tr("Folder") : item.modelData?.suffix.toUpperCase() || Tr.tr("File")
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }

        Behavior on implicitHeight {
            enabled: !root.listMode
            Anim {}
        }
    }
}
