import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Hyprstack.Config
import qs.components
import qs.services

Item {
    id: root
    objectName: "windowInfo"

    required property ShellScreen screen
    required property HyprlandToplevel client

    readonly property real maxWidth: Math.max(1, screen.width - Config.border.thickness * Tokens.scale * 2)
    readonly property real detailsWidth: Math.min(Tokens.sizes.winfo.detailsWidth, maxWidth / 2)
    readonly property real previewRatio: {
        const size = Hypr.clientData(client)?.size;
        const aspect = size?.[0] > 0 && size?.[1] > 0 ? size[0] / size[1] : 16 / 9;
        return Math.min(aspect, screen.width / screen.height);
    }

    implicitWidth: Math.min(maxWidth,
        implicitHeight * previewRatio + detailsWidth + Tokens.padding.large * 2 + child.spacing)
    implicitHeight: screen.height * Tokens.sizes.winfo.heightMult

    RowLayout {
        id: child

        anchors.fill: parent
        anchors.margins: Tokens.padding.large

        spacing: Tokens.spacing.medium

        Preview {
            Layout.fillWidth: true
            Layout.minimumWidth: 0

            client: root.client
        }

        ColumnLayout {
            spacing: Tokens.spacing.medium

            Layout.preferredWidth: root.detailsWidth
            Layout.fillHeight: true

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true

                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.large
                clip: true

                Details {
                    client: root.client
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: buttons.implicitHeight

                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.large

                Buttons {
                    id: buttons

                    client: root.client
                }
            }
        }
    }
}
