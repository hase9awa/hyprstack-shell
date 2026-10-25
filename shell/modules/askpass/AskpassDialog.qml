pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

StyledWindow {
    id: root

    required property var askpass
    required property var request
    property bool revealSecret
    readonly property bool canSubmit: secret.text.length > 0

    function submit(): void {
        if (!root.canSubmit)
            return;
        const value = secret.text;
        secret.clear();
        root.revealSecret = false;
        root.askpass.submit(root.request, value);
    }

    function cancel(): void {
        secret.clear();
        root.revealSecret = false;
        root.askpass.cancel(root.request);
    }

    name: "askpass"
    Config.screen: screen?.name ?? ""
    Tokens.screen: screen?.name ?? ""
    implicitWidth: Math.min(480 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    implicitHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // A newly loaded layer acquires its backing window after completion, so
    // the field is focused again once that window has actually appeared.
    function focusInput(): void {
        Qt.callLater(() => {
            if (root.visible && root.backingWindowVisible)
                secret.forceActiveFocus();
        });
    }

    Component.onCompleted: focusInput()
    onBackingWindowVisibleChanged: if (backingWindowVisible) focusInput()

    StyledRect {
        objectName: "askpassSurface"
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainer
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        ColumnLayout {
            id: contents

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
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
                        text: "key"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }
                }

                StyledText {
                    objectName: "askpassTitle"
                    Layout.fillWidth: true
                    text: Tr.tr("Passphrase required")
                    font: Tokens.font.title.medium
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }

            StyledText {
                objectName: "askpassPrompt"
                Layout.fillWidth: true
                visible: text.length > 0
                // Whatever asked wrote this, and it is the only thing that
                // says which key or account is meant.
                text: root.request.prompt
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledTextField {
                    id: secret

                    objectName: "askpassSecret"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    placeholderText: Tr.tr("Passphrase")
                    leadingIcon: "lock"
                    echoMode: root.revealSecret ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    activeFocusOnTab: true
                    focus: true
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.cancel()
                }

                IconButton {
                    objectName: "askpassReveal"
                    type: IconButton.Text
                    icon: root.revealSecret ? "visibility_off" : "visibility"
                    activeFocusOnTab: true
                    Accessible.name: root.revealSecret ? Tr.tr("Hide passphrase") : Tr.tr("Show passphrase")
                    onClicked: {
                        root.revealSecret = !root.revealSecret;
                        secret.forceActiveFocus();
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.revealSecret && Hypr.capsLock
                text: Tr.tr("Caps Lock is on")
                color: Colours.palette.m3tertiary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item { Layout.fillWidth: true }

                TextButton {
                    objectName: "askpassCancel"
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.cancel()
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                TextButton {
                    objectName: "askpassSubmit"
                    text: Tr.trCtx("Unlock", "button")
                    disabled: !root.canSubmit
                    activeFocusOnTab: !disabled
                    onClicked: root.submit()
                    Keys.onReturnPressed: root.submit()
                    Keys.onSpacePressed: root.submit()
                }
            }
        }
    }
}
