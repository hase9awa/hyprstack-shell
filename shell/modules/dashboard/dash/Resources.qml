import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus

Item {
    id: root

    required property ScreenState screenState

    function openSettings(): void {
        screenState.dashboard = false;
        WindowFactory.create(null, {screen: screenState.modelData});
    }

    anchors.top: parent.top
    anchors.bottom: parent.bottom

    implicitWidth: layout.implicitWidth + layout.anchors.margins * 2

    ServiceRef {
        service: root.visible ? Cpu : null
    }

    ServiceRef {
        service: root.visible ? Memory : null
    }

    ServiceRef {
        service: root.visible ? Storage : null
    }

    ColumnLayout {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        Resource {
            icon: "memory"
            value: Cpu.percentage
        }

        Resource {
            icon: "memory_alt"
            value: Memory.percentage
            fgColour: Colours.palette.m3tertiary
        }

        Resource {
            icon: "hard_disk"
            value: Storage.percentage
            fgColour: Colours.palette.m3secondary
        }

        IconButton {
            objectName: "dashboardSettingsButton"
            Layout.alignment: Qt.AlignHCenter
            isRound: true
            icon: "settings"
            type: IconButton.Filled
            padding: Tokens.padding.medium
            activeFocusOnTab: true
            stateLayer.manualHoverOverride: activeFocus
            Accessible.role: Accessible.Button
            Accessible.name: Tr.tr("Settings")
            Accessible.onPressAction: root.openSettings()
            ToolTip.visible: hovered || activeFocus
            ToolTip.text: Tr.tr("Settings")
            Keys.onReturnPressed: root.openSettings()
            Keys.onSpacePressed: root.openSettings()
            onClicked: root.openSettings()
        }
    }
    component Resource: CircularProgress {
        id: res

        required property string icon

        Layout.fillHeight: true
        implicitSize: height
        strokeWidth: Tokens.sizes.dashboard.resourceProgressThickness

        Behavior on clampedVal {
            Anim {}
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: res.icon
            font: Tokens.font.icon.large
            color: res.fgColour
        }
    }
}
