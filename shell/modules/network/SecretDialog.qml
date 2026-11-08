pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

DialogWindow {
    id: root

    required property SecretRequest request
    property bool revealSecret
    readonly property bool canSubmit: secret.text.length > 0
    readonly property string headline: root.request.connectionName
        ? Tr.tr("Password for %1").arg(root.request.connectionName) : Tr.tr("Password required")
    readonly property string icon: {
        if (root.request.connectionType === "vpn" || root.request.setting === "vpn")
            return "vpn_key";
        if (root.request.setting === "802-11-wireless-security")
            return "wifi_password";
        return "password";
    }
    // What exactly NetworkManager is short of, since a connection can need
    // any of several passwords and only one of them at a time.
    readonly property string body: {
        if (root.request.key.toLowerCase().includes("otp") || root.request.key === "token")
            return Tr.tr("Enter the one-time code.");
        if (root.request.key === "pin")
            return Tr.tr("The modem is asking for its PIN.");
        if (root.request.key === "private-key-password")
            return Tr.tr("The private key is locked.");
        switch (root.request.setting) {
        case "802-11-wireless-security":
            return Tr.tr("The Wi-Fi network is asking for its password.");
        case "802-1x":
            return Tr.tr("The network is asking for your account password.");
        case "vpn":
            return Tr.tr("The VPN is asking for its password.");
        default:
            return Tr.tr("NetworkManager needs a password to bring the connection up.");
        }
    }

    function submit(): void {
        if (!root.canSubmit)
            return;
        const value = secret.text;
        secret.clear();
        root.revealSecret = false;
        root.request.submit(value);
    }

    function cancel(): void {
        secret.clear();
        root.revealSecret = false;
        root.request.reject();
    }

    name: "nmsecret"
    onCloseRequested: root.cancel()
    visible: !root.request.answered
    dialogWidth: Math.min(480 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    dialogHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
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

    Connections {
        target: root.request
        function onKeyChanged(): void {
            secret.clear();
            root.revealSecret = false;
            root.focusInput();
        }
    }

    StyledRect {
        objectName: "nmSecretSurface"
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
                        text: root.icon
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }
                }

                StyledText {
                    objectName: "nmSecretTitle"
                    Layout.fillWidth: true
                    text: root.headline
                    font: Tokens.font.title.medium
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }

            StyledText {
                objectName: "nmSecretBody"
                Layout.fillWidth: true
                text: root.request.message ? root.request.message + "\n" + root.body : root.body
                textFormat: Text.PlainText
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledRect {
                objectName: "nmSecretField"
                Layout.fillWidth: true
                implicitHeight: field.implicitHeight + Tokens.padding.small * 2

                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh

                StateLayer {
                    hoverEnabled: false
                    cursorShape: Qt.IBeamCursor
                    onClicked: secret.forceActiveFocus()
                }

                RowLayout {
                    id: field

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraSmall
                    anchors.leftMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "lock"
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0

                        clip: true

                        StyledText {
                            anchors.centerIn: parent
                            text: Tr.tr("Password")
                            color: Colours.palette.m3outline
                            opacity: secret.text ? 0 : 1

                            Behavior on opacity {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }

                        PasswordCharacters {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: implicitWidth > parent.width ? -(implicitWidth - parent.width) / 2 : 0

                            buffer: secret.text
                            revealed: root.revealSecret
                        }

                        // The characters are drawn as shapes, so the field
                        // itself only has to collect them.
                        TextInput {
                            id: secret

                            objectName: "nmSecretInput"
                            anchors.fill: parent

                            opacity: 0
                            focus: true
                            activeFocusOnTab: true
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            onAccepted: root.submit()
                            Keys.onEscapePressed: root.cancel()
                        }
                    }

                    IconButton {
                        objectName: "nmSecretReveal"
                        type: IconButton.Text
                        icon: root.revealSecret ? "visibility_off" : "visibility"
                        activeFocusOnTab: true
                        Accessible.name: root.revealSecret ? Tr.tr("Hide password") : Tr.tr("Show password")
                        onClicked: {
                            root.revealSecret = !root.revealSecret;
                            secret.forceActiveFocus();
                        }
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                    }
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

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    objectName: "nmSecretCancel"
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.cancel()
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                TextButton {
                    objectName: "nmSecretSubmit"
                    text: root.request.hasNext ? Tr.trCtx("Next", "button") : Tr.trCtx("Connect", "button")
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
