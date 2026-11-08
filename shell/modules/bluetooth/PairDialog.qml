pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

DialogWindow {
    id: root

    required property BluezRequest request

    // bluez names only the device's object path, which is how the shell tells
    // its own devices apart; everything shown about it comes from there.
    readonly property BluetoothDevice device: Bluetooth.devices.values.find(d => d.dbusPath === root.request.device) ?? null // qmllint disable unresolved-type
    // A code the user has to read off this screen and type on the device.
    readonly property bool shown: root.request.kind === BluezRequest.ShownPin
        || root.request.kind === BluezRequest.ShownPasskey
    // A code the device shows, which the user types here.
    readonly property bool asked: root.request.kind === BluezRequest.AskedPin
        || root.request.kind === BluezRequest.AskedPasskey
    readonly property bool canSubmit: !root.asked || (code.text.length > 0 && code.valid)
    // A device bluez has nothing on yet has no name to put in the sentence,
    // which the sentence itself has to account for.
    readonly property string headline: {
        const name = root.device?.name ?? "";
        if (root.request.kind === BluezRequest.Service)
            return name ? Tr.tr("%1 wants to connect").arg(name) : Tr.tr("A device wants to connect");
        return name ? Tr.tr("Pair with %1").arg(name) : Tr.tr("Pair with the device");
    }
    readonly property string body: {
        switch (root.request.kind) {
        case BluezRequest.Compare:
            return Tr.tr("Check that the device shows the same code.");
        case BluezRequest.Authorize:
            return Tr.tr("The device is asking to pair with this computer.");
        case BluezRequest.Service:
            return Tr.tr("It is asking for a service it has not been allowed yet.");
        case BluezRequest.ShownPin:
        case BluezRequest.ShownPasskey:
            return Tr.tr("Type this code on the device.");
        default:
            return Tr.tr("Enter the code the device is showing.");
        }
    }

    function answer(): void {
        if (!root.canSubmit)
            return;
        if (root.asked)
            root.request.submit(code.text);
        else
            root.request.accept();
    }

    function refuse(): void {
        if (!root.shown) {
            root.request.reject();
            return;
        }

        // bluez is waiting on the device by now rather than on an answer, so
        // the pairing itself is what has to be called off.
        root.device?.cancelPair();
        root.request.dismiss();
    }

    name: "bluezpair"
    onCloseRequested: root.refuse()
    visible: !root.request.answered
    dialogWidth: Math.min(440 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    dialogHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // A newly loaded layer acquires its backing window after completion, so
    // the field is focused again once that window has actually appeared.
    function focusInput(): void {
        Qt.callLater(() => {
            if (root.asked && root.visible && root.backingWindowVisible)
                code.forceActiveFocus();
        });
    }

    Component.onCompleted: focusInput()
    onBackingWindowVisibleChanged: if (backingWindowVisible) focusInput()

    // bluez withdraws a question it no longer needs, but a code the device
    // took is answered by the device itself: the prompt goes once it is in.
    Connections {
        target: root.shown ? root.device : null

        function onBondedChanged(): void {
            if (root.device?.bonded)
                root.request.dismiss();
        }
    }

    StyledRect {
        objectName: "bluezPairSurface"
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainer
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
        // Holds the keys until the entry takes them, so the prompt answers
        // Escape whether it has one or not.
        focus: true

        Keys.onEscapePressed: event => {
            root.refuse();
            event.accepted = true;
        }

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
                        text: Icons.getBluetoothIcon(root.device?.icon ?? "")
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        objectName: "bluezPairTitle"
                        Layout.fillWidth: true
                        text: root.headline
                        font: Tokens.font.title.medium
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        // The address is the only thing telling two devices of
                        // the same name apart.
                        text: root.device?.address ?? ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }
                }
            }

            StyledText {
                objectName: "bluezPairBody"
                Layout.fillWidth: true
                text: root.body
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.request.service
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledRect {
                objectName: "bluezPairCode"
                Layout.fillWidth: true
                visible: root.request.code.length > 0
                implicitHeight: codeText.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainerHigh

                StyledText {
                    id: codeText

                    anchors.centerIn: parent
                    text: root.request.code
                    font: Tokens.font.headline.builders.medium.weight(Font.Medium).build()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.request.kind === BluezRequest.ShownPasskey && root.request.typed > 0
                text: Tr.trN("%n digit entered on the device", "%n digits entered on the device", root.request.typed)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            StyledTextField {
                id: code

                objectName: "bluezPairEntry"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.asked
                placeholderText: root.request.kind === BluezRequest.AskedPasskey
                    ? Tr.tr("Code") : Tr.tr("PIN")
                leadingIcon: "password"
                // A passkey is six digits to bluez, and nothing else will do;
                // a pin is whatever the device printed on itself.
                inputMethodHints: root.request.kind === BluezRequest.AskedPasskey
                    ? Qt.ImhDigitsOnly : Qt.ImhNone
                validate: root.request.kind === BluezRequest.AskedPasskey ? /^\d{1,6}$/ : null
                activeFocusOnTab: true
                onAccepted: root.answer()
                Keys.onEscapePressed: root.refuse()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    objectName: "bluezPairRefuse"
                    text: root.request.kind === BluezRequest.Service
                        ? Tr.trCtx("Deny", "button") : Tr.trCtx("Cancel", "button")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.refuse()
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                TextButton {
                    objectName: "bluezPairAccept"
                    // A code the device has to be given leaves nothing to
                    // agree to here: it is done on the device.
                    visible: !root.shown
                    text: root.request.kind === BluezRequest.Service
                        ? Tr.trCtx("Allow", "button") : Tr.trCtx("Pair", "button")
                    disabled: !root.canSubmit
                    activeFocusOnTab: !disabled
                    onClicked: root.answer()
                    Keys.onReturnPressed: root.answer()
                    Keys.onSpacePressed: root.answer()
                }
            }
        }
    }
}
