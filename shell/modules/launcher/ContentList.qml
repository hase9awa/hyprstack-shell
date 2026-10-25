pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property bool showClipboard: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}clipboard `)
    readonly property var currentList: showWallpapers ? wallpaperList.item : showClipboard ? clipList.item : appList.item // Can be either ListView or PathView, so can't type properly
    property string animState: showWallpapers ? "wallpapers" : showClipboard ? "clipboard" : "apps"

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight
                wallpaperList.active: true
            }
        },
        State {
            name: "clipboard"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, clipList.implicitHeight > 0 ? clipList.implicitHeight : empty.implicitHeight)
                clipList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            objectName: "launcherWallpaperList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    Loader {
        id: clipList

        asynchronous: true
        active: false

        anchors.fill: parent

        sourceComponent: ClipboardList {
            objectName: "launcherClipboardList"

            search: root.search
            screenState: root.screenState
        }
    }

    Row {
        id: empty

        opacity: root.currentList?.count === 0 ? 1 : 0
        scale: root.currentList?.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large
        width: root.width

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            id: emptyIcon
            text: {
                if (root.state === "wallpapers")
                    return "wallpaper_slideshow";
                return root.state === "clipboard" ? "content_paste_off" : "manage_search";
            }
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, empty.width - empty.padding * 2 - emptyIcon.width - empty.spacing)

            StyledText {
                width: parent.width
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                text: {
                    if (root.state === "wallpapers")
                        return Tr.tr("No wallpapers found");
                    return root.state === "clipboard" ? Tr.tr("Clipboard is empty") : Tr.tr("No results");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                width: parent.width
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                text: {
                    if (root.state === "wallpapers" && Wallpapers.list.length === 0)
                        return Tr.tr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir));
                    if (root.state === "clipboard" && Clipboard.entries.length === 0)
                        return Tr.tr("Copy something and it will show up here");
                    return Tr.tr("Try searching for something else");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher

        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher

        Anim {}
    }
}
