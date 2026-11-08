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

    required property var dialog
    readonly property FileEntry currentItem: view.currentItem as FileEntry
    property list<string> selectedPaths

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
            if (!file.isDir)
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

    GridView {
        id: view

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium

        cellWidth: Sizes.itemWidth + Tokens.spacing.small
        cellHeight: Sizes.itemWidth + Tokens.spacing.large + Tokens.padding.medium * 2 + 1

        clip: true
        focus: true
        currentIndex: -1
        Keys.onEscapePressed: currentIndex = -1

        Keys.onReturnPressed: root.dialog.submit()
        Keys.onEnterPressed: root.dialog.submit()

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: view
        }

        model: FileSystemModel {
            path: root.dialog.currentPath
            // Offering files while the caller asked for a folder only invites
            // picking the wrong thing.
            filter: root.dialog.mode === FileDialog.SelectFolder ? FileSystemModel.Dirs : FileSystemModel.NoFilter
            onPathChanged: {
                view.currentIndex = -1;
                root.selectedPaths = [];
            }
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

        required property int index
        required property FileSystemEntry modelData
        readonly property bool selected: !!modelData && (root?.selectedPaths ?? []).includes(modelData.path)

        readonly property real nonAnimHeight: icon.implicitHeight + name.anchors.topMargin + name.implicitHeight + Tokens.padding.medium * 2

        implicitWidth: Sizes.itemWidth
        implicitHeight: nonAnimHeight

        radius: Tokens.rounding.large
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
                    root.dialog.cwd.push(item.modelData.name);
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

        CachingIconImage {
            id: icon

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Tokens.padding.medium

            implicitSize: Sizes.itemWidth - Tokens.padding.medium * 2

            Component.onCompleted: {
                const file = item.modelData;
                if (file.isImage)
                    source = Qt.resolvedUrl(file.path);
                else if (!file.isDir)
                    source = Quickshell.iconPath(file.mimeType.replace("/", "-"), "application-x-zerosize");
                else {
                    // The desktop's own folders are known by their paths:
                    // their names are in the user's language, their icons
                    // are not.
                    const kind = [[Paths.desktop, "desktop"], [Paths.documents, "documents"],
                        [Paths.downloads, "download"], [Paths.music, "music"],
                        [Paths.pictures, "pictures"], [Paths.videos, "videos"]]
                        .find(entry => entry[0] && entry[0] === file.path);
                    source = Quickshell.iconPath(kind ? `folder-${kind[1]}` : "inode-directory", "inode-directory");
                }
            }
        }

        StyledText {
            id: name

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: icon.bottom
            anchors.topMargin: Tokens.spacing.small
            anchors.margins: Tokens.padding.medium

            horizontalAlignment: Text.AlignHCenter
            elide: item.GridView.isCurrentItem ? Text.ElideNone : Text.ElideRight
            wrapMode: item.GridView.isCurrentItem ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
            color: item.selected ? Colours.palette.m3primary : Colours.palette.m3onSurface

            Component.onCompleted: text = item.modelData.name
        }

        Behavior on implicitHeight {
            Anim {}
        }
    }
}
