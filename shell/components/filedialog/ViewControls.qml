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
    implicitWidth: options.implicitWidth
    implicitHeight: options.implicitHeight
    color: "transparent"

    RowLayout {
        id: options
        anchors.fill: parent
        spacing: Tokens.spacing.small
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
