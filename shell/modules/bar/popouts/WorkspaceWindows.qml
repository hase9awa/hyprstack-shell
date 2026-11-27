pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root
    objectName: "workspaceWindows"

    required property PopoutState popouts
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(popouts.screen)
    readonly property var windows: {
        const special = monitor?.lastIpcObject?.specialWorkspace;
        const workspace = special?.name ? special.id : monitor?.activeWorkspace?.id;
        return workspace === undefined ? [] : Hypr.toplevelsForWs(workspace);
    }
    readonly property real rowHeight: Math.max(46 * Tokens.scale, Tokens.font.body.medium.pointSize * 3.4)
    readonly property real rowGap: Tokens.spacing.extraSmall

    implicitWidth: Math.min(360 * Tokens.scale, Math.max(1, popouts.screen.width - Tokens.padding.large * 4))
    implicitHeight: Math.min(
        windows.length ? windows.length * rowHeight + (windows.length - 1) * rowGap : rowHeight,
        Math.max(rowHeight, popouts.screen.height * 0.55))

    function focusWindow(window: HyprlandToplevel): void {
        const address = Hypr.clientData(window)?.address;
        if (!address)
            return;
        const target = "address:" + address;
        popouts.hasCurrent = false;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({window = ${JSON.stringify(target)}})` : "focuswindow " + target);
    }

    StyledText {
        anchors.fill: parent
        visible: root.windows.length === 0
        text: Tr.tr("No windows on this workspace")
        color: Colours.palette.m3onSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    StyledListView {
        id: list

        anchors.fill: parent
        clip: true
        spacing: root.rowGap
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: root.windows }

        ScrollBar.vertical: StyledScrollBar { flickable: list }

        delegate: StyledRect {
            id: windowRow
            objectName: "workspaceWindow"

            required property HyprlandToplevel modelData
            readonly property string appClass: Hypr.clientData(modelData)?.class ?? ""
            readonly property string windowTitle: modelData.title || appClass
            readonly property bool inverted: Config.bar.activeWindow.inverted
            readonly property bool focused: Hypr.activeToplevel === modelData

            width: list.width
            height: root.rowHeight
            color: focused ? Colours.palette.m3secondaryContainer : "transparent"
            radius: Tokens.rounding.medium

            Accessible.role: Accessible.Button
            Accessible.name: windowTitle
            Accessible.onPressAction: root.focusWindow(modelData)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                IconImage {
                    Layout.alignment: Qt.AlignVCenter
                    implicitSize: 24 * Tokens.scale
                    asynchronous: true
                    source: Icons.getAppIcon(windowRow.appClass, "application-x-executable")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: windowRow.inverted ? windowRow.appClass : windowRow.windowTitle
                        color: windowRow.focused ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: windowRow.appClass !== windowRow.windowTitle
                        text: windowRow.inverted ? windowRow.windowTitle : windowRow.appClass
                        color: windowRow.focused ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }
            }

            StateLayer {
                radius: windowRow.radius
                onClicked: root.focusWindow(windowRow.modelData)
            }
        }
    }
}
