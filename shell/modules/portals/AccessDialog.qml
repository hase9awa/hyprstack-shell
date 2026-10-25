pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
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

StyledWindow {
    id: root

    required property AccessRequest request
    // Each choice's id mapped onto the option id it was answered with.
    // Nothing binds to it: the controls keep their own state and only write
    // the answer back here for grant() to collect.
    readonly property var selections: ({})
    readonly property string appName: {
        const id = root.request.appId;
        if (!id)
            return "";
        return DesktopEntries.heuristicLookup(id)?.name ?? id;
    }
    readonly property url appIcon: {
        const name = root.request.icon;
        return name ? Quickshell.iconPath(name, true) : "";
    }

    name: "access"
    Config.screen: screen?.name ?? ""
    Tokens.screen: screen?.name ?? ""
    visible: !request.answered
    implicitWidth: Math.min(440 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    implicitHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // A prompt the application asked to be modeless leaves the keyboard where
    // it is; the user can still answer it with the pointer.
    WlrLayershell.keyboardFocus: visible && request.modal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    StyledRect {
        objectName: "accessSurface"
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainer
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        Flickable {
            id: scroller

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            contentWidth: width
            contentHeight: contents.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            focus: true

            Keys.onEscapePressed: event => {
                root.request.deny();
                event.accepted = true;
            }

            ColumnLayout {
                id: contents

                width: scroller.width
                spacing: Tokens.spacing.large

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 48 * Tokens.scale
                        implicitHeight: implicitWidth
                        radius: Tokens.rounding.medium
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: !root.appIcon
                            text: "privacy_tip"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.large
                        }

                        CachingIconImage {
                            anchors.centerIn: parent
                            implicitSize: 28 * Tokens.scale
                            source: root.appIcon
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            objectName: "accessTitle"
                            Layout.fillWidth: true
                            text: root.request.title || Tr.tr("Permission request")
                            font: Tokens.font.title.medium
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        StyledText {
                            // The title names the application in most cases;
                            // say it only when it does not, so the user is
                            // never left guessing who is asking.
                            Layout.fillWidth: true
                            visible: root.appName && !root.request.title.includes(root.appName)
                            text: Tr.tr("Requested by %1").arg(root.appName)
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }
                }

                StyledText {
                    objectName: "accessSubtitle"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.request.subtitle
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.request.body
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                Repeater {
                    model: root.request.choices

                    ColumnLayout {
                        id: choice

                        required property var modelData
                        // A choice without options asks for a plain yes or no.
                        readonly property bool boolean: modelData.options.length === 0

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ButtonGroup {
                            id: group
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: choice.boolean
                            spacing: Tokens.spacing.medium

                            StyledText {
                                Layout.fillWidth: true
                                text: choice.modelData.label
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            }

                            StyledSwitch {
                                checked: choice.modelData.selected === "true"
                                onToggled: root.selections[choice.modelData.id] = checked ? "true" : "false"
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !choice.boolean
                            text: choice.modelData.label
                            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }

                        Repeater {
                            model: choice.boolean ? [] : choice.modelData.options

                            StyledRadioButton {
                                required property var modelData

                                Layout.fillWidth: true
                                ButtonGroup.group: group
                                checked: choice.modelData.selected === modelData.id
                                text: modelData.label
                                activeFocusOnTab: true
                                onClicked: root.selections[choice.modelData.id] = modelData.id
                                Keys.onReturnPressed: clicked()
                                Keys.onSpacePressed: clicked()
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item { Layout.fillWidth: true }

                    TextButton {
                        objectName: "accessDeny"
                        text: root.request.denyLabel || Tr.trCtx("Deny", "button")
                        type: TextButton.Tonal
                        activeFocusOnTab: true
                        onClicked: root.request.deny()
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                    }

                    TextButton {
                        objectName: "accessGrant"
                        text: root.request.grantLabel || Tr.trCtx("Allow", "button")
                        activeFocusOnTab: true
                        onClicked: root.request.grant(root.selections)
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                    }
                }
            }
        }
    }
}
