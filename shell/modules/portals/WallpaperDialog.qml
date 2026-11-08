pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Portals
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

DialogWindow {
    id: root

    required property WallpaperRequest request
    readonly property string appName: {
        const id = root.request.appId;
        if (!id)
            return "";
        const bare = id.replace(/\.desktop$/, "");
        const entries = DesktopEntries.applications.values;
        const entry = entries.find(e => e.id === bare) ?? entries.find(e => e.id === id);
        return entry?.name ?? bare;
    }

    name: "wallpaper"
    onCloseRequested: root.request.reject()
    visible: request.showPreview && !request.answered
    dialogWidth: Math.min(480 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    dialogHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.keyboardFocus: visible && request.modal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    StyledRect {
        objectName: "wallpaperSurface"
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainer
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        ColumnLayout {
            id: contents

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.large

            focus: true
            Keys.onEscapePressed: event => {
                root.request.reject();
                event.accepted = true;
            }

            StyledText {
                objectName: "wallpaperTitle"
                Layout.fillWidth: true
                text: root.appName ? Tr.tr("Set %1 as the wallpaper?").arg(root.appName)
                    : Tr.tr("Set this picture as the wallpaper?")
                font: Tokens.font.title.medium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledClippingRect {
                Layout.fillWidth: true
                Layout.preferredHeight: width * 9 / 16
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerHigh

                CachingImage {
                    anchors.fill: parent
                    path: root.request.path
                    fillMode: Image.PreserveAspectCrop
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item { Layout.fillWidth: true }

                TextButton {
                    objectName: "wallpaperCancel"
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.request.reject()
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                TextButton {
                    objectName: "wallpaperSet"
                    text: Tr.trCtx("Set wallpaper", "button")
                    activeFocusOnTab: true
                    onClicked: {
                        Wallpapers.setWallpaper(root.request.path);
                        root.request.accept();
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }
            }
        }
    }
}
