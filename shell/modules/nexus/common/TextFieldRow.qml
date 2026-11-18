pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property string value
    property alias placeholderText: input.placeholderText
    property string errorText
    property alias maximumLength: input.maximumLength
    property alias validate: input.validate
    property alias validator: input.validator
    property alias leadingIcon: input.leadingIcon
    property bool smallField
    readonly property alias field: input
    property alias menuItems: menu.items

    signal valueEdited(value: string)
    signal editingFinished(value: string)
    signal menuSelected(item: MenuItem)

    function clear(): void {
        input.clear();
    }

    Component.onDestruction: {
        if (value !== input.text)
            editingFinished(input.text);
    }

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium + Math.max(0, Tokens.padding.large - input.verticalPadding) * 2

    RowLayout {
        id: rowLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                Layout.minimumWidth: 0
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtext
                text: input.isError && root.errorText ? root.errorText : root.subtext
                color: input.isError && root.errorText ? Colours.palette.m3error : Colours.palette.m3outline
                font: Tokens.font.label.small
                Layout.minimumWidth: 0
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                animate: root.errorText
            }
        }

        StyledTextField {
            id: input

            Layout.preferredWidth: root.smallField ? Tokens.sizes.nexus.smallTextFieldWidth : Tokens.sizes.nexus.textFieldWidth
            Layout.maximumWidth: root.width / 2
            Layout.alignment: Qt.AlignVCenter
            verticalPadding: Tokens.padding.small

            text: root.value

            onTextEdited: root.valueEdited(text)
            onEditingFinished: root.editingFinished(text)
        }

        IconButton {
            id: expandBtn

            visible: root.menuItems.length > 0
            Layout.alignment: Qt.AlignVCenter
            icon: "expand_more"
            type: IconButton.Tonal
            onClicked: menu.expanded = !menu.expanded
        }
    }

    Menu {
        id: menu

        attachTo: expandBtn
        marginY: Tokens.spacing.small
        active: null
        onItemSelected: item => {
            root.menuSelected(item);
            // Manual typing breaks the text: root.value binding; re-establish it
            // so the field follows the value (and language) after a preset pick.
            input.text = Qt.binding(() => root.value);
        }
    }
}
