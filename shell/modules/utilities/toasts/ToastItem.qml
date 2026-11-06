import QtQuick
import QtQuick.Layouts
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    required property Toast modelData
    readonly property bool compact: modelData.compact

    anchors.left: parent.left
    anchors.right: parent.right
    implicitWidth: compact ? Math.max(88 * Tokens.scale, compactRow.implicitWidth + Tokens.padding.medium * 2) : 0
    implicitHeight: compact ? Math.max(36 * Tokens.scale, compactRow.implicitHeight + Tokens.padding.small * 2)
        : layout.implicitHeight + Tokens.padding.large

    radius: compact ? implicitHeight / 2 : Tokens.rounding.large
    color: {
        if (root.modelData.type === Toast.Success)
            return Colours.palette.m3successContainer;
        if (root.modelData.type === Toast.Warning)
            return Colours.palette.m3secondary;
        if (root.modelData.type === Toast.Error)
            return Colours.palette.m3errorContainer;
        return Colours.palette.m3surface;
    }

    border.width: 1
    border.color: {
        let colour = Colours.palette.m3outlineVariant;
        if (root.modelData.type === Toast.Success)
            colour = Colours.palette.m3success;
        if (root.modelData.type === Toast.Warning)
            colour = Colours.palette.m3secondaryContainer;
        if (root.modelData.type === Toast.Error)
            colour = Colours.palette.m3error;
        return Qt.alpha(colour, 0.3);
    }

    Elevation {
        anchors.fill: parent
        radius: parent.radius
        opacity: parent.opacity
        z: -1
        level: 3
    }

    RowLayout {
        id: layout

        visible: !root.compact
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            radius: Tokens.rounding.large
            color: {
                if (root.modelData.type === Toast.Success)
                    return Colours.palette.m3success;
                if (root.modelData.type === Toast.Warning)
                    return Colours.palette.m3secondaryContainer;
                if (root.modelData.type === Toast.Error)
                    return Colours.palette.m3error;
                return Colours.palette.m3surfaceContainerHigh;
            }

            implicitWidth: implicitHeight
            implicitHeight: icon.implicitHeight + Tokens.padding.large

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: root.modelData.icon
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onSuccess;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondaryContainer;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onError;
                    return Colours.palette.m3onSurfaceVariant;
                }
                fontStyle: Tokens.font.icon.builders.large.scale(1.2).build()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: title

                Layout.fillWidth: true
                text: Tr.trMarked(root.modelData.title)
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onSuccessContainer;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondary;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onErrorContainer;
                    return Colours.palette.m3onSurface;
                }
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                textFormat: Text.StyledText
                text: Tr.trMarked(root.modelData.message)
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onSuccessContainer;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondary;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onErrorContainer;
                    return Colours.palette.m3onSurface;
                }
                opacity: 0.8
                elide: Text.ElideRight
            }
        }
    }

    RowLayout {
        id: compactRow

        visible: root.compact
        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.modelData.icon
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3primary
        }

        StyledText {
            text: root.modelData.title
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }
    }

    Behavior on border.color {
        CAnim {}
    }
}
