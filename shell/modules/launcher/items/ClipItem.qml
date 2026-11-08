pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property var modelData
    required property var list
    required property ScreenState screenState

    readonly property string thumbnail: modelData.pinned ? modelData.file : (Clipboard.thumbnails[modelData.id] ?? "")

    implicitHeight: Tokens.sizes.launcher.clipHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    // Only a picture that is on screen is worth decoding.
    Component.onCompleted: Clipboard.requestThumbnail(modelData)

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            Clipboard.activate(root.modelData);
            root.screenState.launcher = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        StyledClippingRect {
            id: preview

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: parent.height
            implicitHeight: parent.height
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHigh

            MaterialIcon {
                anchors.centerIn: parent
                visible: !root.modelData.isImage || !root.thumbnail
                text: root.modelData.isImage ? "image" : "content_copy"
                color: Colours.palette.m3onSurfaceVariant
            }

            CachingImage {
                anchors.fill: parent
                visible: root.modelData.isImage && root.thumbnail
                path: root.thumbnail
                fillMode: Image.PreserveAspectCrop
            }
        }

        Item {
            anchors.left: preview.right
            anchors.right: buttons.left
            anchors.leftMargin: Tokens.spacing.medium
            anchors.rightMargin: Tokens.spacing.small
            anchors.verticalCenter: parent.verticalCenter

            implicitHeight: label.implicitHeight + info.implicitHeight

            StyledText {
                id: label

                width: parent.width
                // A picture has no text to show, so it is named by what it is
                // and described underneath.
                text: root.modelData.isImage ? Tr.tr("Image") : root.modelData.label
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: info

                anchors.top: label.bottom
                width: parent.width
                visible: text.length > 0
                text: [root.modelData.info, root.modelData.pinned ? Tr.tr("Pinned") : ""]
                    .filter(part => part).join(" · ")
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
            }
        }

        Row {
            id: buttons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.extraSmall

            IconButton {
                type: IconButton.Text
                icon: root.modelData.pinned ? "keep_off" : "keep"
                // An image can only be kept once it has been decoded.
                disabled: root.modelData.isImage && !root.modelData.pinned && !root.thumbnail
                Accessible.name: root.modelData.pinned ? Tr.tr("Unpin") : Tr.tr("Pin")
                onClicked: Clipboard.togglePin(root.modelData)
            }

            IconButton {
                type: IconButton.Text
                icon: "delete"
                Accessible.name: Tr.tr("Delete entry")
                onClicked: Clipboard.remove(root.modelData)
            }
        }
    }
}
