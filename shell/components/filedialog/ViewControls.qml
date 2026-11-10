pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services

StyledRect {
    id: root
    implicitHeight: options.implicitHeight + Tokens.padding.small * 2
    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: options
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.topMargin: Tokens.padding.small
        anchors.bottomMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        Repeater {
            model: [
                {key: "name", label: Tr.trCtx("Name", "file column")},
                {key: "modified", label: Tr.tr("Date modified")},
                {key: "size", label: Tr.trCtx("Size", "file column")},
                {key: "type", label: Tr.trCtx("Type", "file column")}
            ]
            TextButton {
                required property var modelData
                objectName: "fileDialogSort_" + modelData.key
                type: TextButton.Text
                checked: FileDialogSettings.sortBy === modelData.key
                disabled: !FileDialogSettings.loaded
                text: modelData.label + (checked ? FileDialogSettings.reverse ? " ↓" : " ↑" : "")
                onClicked: FileDialogSettings.chooseSort(modelData.key)
            }
        }
        Item { Layout.fillWidth: true }
        IconButton {
            objectName: "fileDialogIconsView"
            icon: "grid_view"
            type: IconButton.Text
            checked: FileDialogSettings.viewMode === "icons"
            disabled: !FileDialogSettings.loaded
            onClicked: FileDialogSettings.setView("icons")
            Accessible.name: Tr.tr("Icons")
        }
        IconButton {
            objectName: "fileDialogListView"
            icon: "view_list"
            type: IconButton.Text
            checked: FileDialogSettings.viewMode === "list"
            disabled: !FileDialogSettings.loaded
            onClicked: FileDialogSettings.setView("list")
            Accessible.name: Tr.tr("List")
        }
    }
}
