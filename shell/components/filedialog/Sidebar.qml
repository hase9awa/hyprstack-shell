pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils

StyledRect {
    id: root

    required property var dialog

    // The folders the desktop keeps, named as this system names them, and
    // only the ones it actually has. Home is the one place that is named
    // here instead: its folder is called after the user.
    readonly property var places: [
        {path: Paths.home, name: Tr.trCtx("Home", "file dialog place"), icon: "home"},
        {path: Paths.downloads, icon: "file_download"},
        {path: Paths.desktop, icon: "desktop_windows"},
        {path: Paths.documents, icon: "description"},
        {path: Paths.music, icon: "music_note"},
        {path: Paths.pictures, icon: "image"},
        {path: Paths.videos, icon: "video_library"}
    ].filter((place, index) => place.path && (index === 0 || place.path !== Paths.home) && CUtils.isDirectory(place.path))
        .map(place => ({
            path: place.path,
            name: place.name || place.path.slice(place.path.lastIndexOf("/") + 1),
            icon: place.icon
        }))

    implicitWidth: Sizes.sidebarWidth
    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer

    Bookmarks {
        id: bookmarks
    }

    StyledFlickable {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

        contentHeight: inner.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        clip: true

        ColumnLayout {
            id: inner

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.padding.extraSmall / 2
                Layout.bottomMargin: Tokens.spacing.medium
                text: Tr.trCtx("Files", "file dialog sidebar heading")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
            }

            Repeater {
                model: root.places

                Place {}
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.medium
                Layout.bottomMargin: Tokens.spacing.small
                visible: bookmarks.places.length > 0
                text: Tr.trCtx("Pinned", "file dialog sidebar heading")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
            }

            Repeater {
                model: bookmarks.places

                Place {}
            }
        }
    }

    component Place: StyledRect {
        id: place

        required property var modelData
        readonly property bool selected: modelData.path === root.dialog.currentPath

        Layout.fillWidth: true
        implicitHeight: placeInner.implicitHeight + Tokens.padding.medium * 2

        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3secondaryContainer, selected ? 1 : 0)

        StateLayer {
            color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            onClicked: root.dialog.cwd = root.dialog.segmentsFor(place.modelData.path)
        }

        RowLayout {
            id: placeInner

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large

            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: place.modelData.icon
                color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.medium
                fill: place.selected ? 1 : 0

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: place.modelData.name
                color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }
    }
}
