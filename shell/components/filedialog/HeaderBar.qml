pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root
    required property var dialog

    function editPath(): void {
        pathField.text = dialog.currentPath;
        pathField.forceActiveFocus();
        pathField.selectAll();
    }

    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2
    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: inner
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        IconButton {
            objectName: "fileDialogBack"
            icon: "arrow_back"
            disabled: !root.dialog.canBack
            onClicked: root.dialog.goHistory(-1)
        }
        IconButton {
            objectName: "fileDialogForward"
            icon: "arrow_forward"
            disabled: !root.dialog.canForward
            onClicked: root.dialog.goHistory(1)
        }
        IconButton {
            objectName: "fileDialogUp"
            icon: "arrow_upward"
            disabled: !root.dialog.canUp
            onClicked: root.dialog.goUp()
        }
        StyledTextField {
            id: pathField
            objectName: "fileDialogPath"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            verticalPadding: Tokens.padding.small
            horizontalPadding: Tokens.padding.medium
            placeholderText: Tr.tr("Folder path (Ctrl+L)")
            selectByMouse: true
            Component.onCompleted: text = root.dialog.currentPath
            onAccepted: root.dialog.navigate(text)
            Connections {
                target: root.dialog
                function onCurrentPathChanged(): void { pathField.text = root.dialog.currentPath; }
            }
        }
        IconButton {
            objectName: "fileDialogGo"
            icon: "arrow_forward_ios"
            onClicked: root.dialog.navigate(pathField.text)
        }
        IconButton {
            objectName: "fileDialogHidden"
            icon: root.dialog.showHidden ? "visibility" : "visibility_off"
            isToggle: true
            checked: root.dialog.showHidden
            onClicked: root.dialog.showHidden = !root.dialog.showHidden
        }
    }
}
