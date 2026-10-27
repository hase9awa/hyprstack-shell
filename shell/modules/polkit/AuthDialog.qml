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

    required property var flow
    property bool submitting
    property bool revealResponse
    readonly property bool awaitingResponse: !!flow?.isResponseRequired && !flow?.isCompleted && !flow?.isCancelled
    readonly property bool canSubmit: awaitingResponse && !submitting && response.text.length > 0
    readonly property bool inputFocused: response.activeFocus
    readonly property string prompt: {
        const message = flow?.inputPrompt?.trim() ?? "";
        if (!message || (!flow?.responseVisible && /^password(?:\s+for\s+.+)?\s*:?$/i.test(message)))
            return Tr.tr("Password");
        return message;
    }

    // The key that closes a window cannot close a layer surface, so the
    // shell is asked to, and this answers it the way Escape does.
    signal closeRequested

    Component.onCompleted: Dialogs.register(root)
    Component.onDestruction: Dialogs.unregister(root)
    onCloseRequested: root.cancel()

    name: "polkit"
    Config.screen: screen?.name ?? ""
    Tokens.screen: screen?.name ?? ""
    visible: !!flow && !flow.isCompleted && !flow.isCancelled
    implicitWidth: Math.min(480 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    implicitHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function identityLabel(identity: var): string {
        if (!identity)
            return "";
        const name = identity.string;
        return identity.displayName && identity.displayName !== name
            ? `${identity.displayName} (${name})` : name;
    }

    function resetInput(): void {
        response.clear();
        revealResponse = false;
        submitting = false;
        focusInput();
    }

    function focusInput(): void {
        // A newly loaded layer acquires its backing window after component
        // completion. Focus it again once that window has actually appeared.
        Qt.callLater(() => {
            if (root.visible && root.backingWindowVisible && root.awaitingResponse)
                response.forceActiveFocus();
        });
    }

    function submit(): void {
        if (!canSubmit)
            return;
        const value = response.text;
        submitting = true;
        response.clear();
        revealResponse = false;
        flow.submit(value);
    }

    function cancel(): void {
        response.clear();
        revealResponse = false;
        flow?.cancelAuthenticationRequest();
    }

    onFlowChanged: resetInput()
    onAwaitingResponseChanged: focusInput()
    onBackingWindowVisibleChanged: if (backingWindowVisible) focusInput()
    Component.onCompleted: resetInput()

    Connections {
        target: root.flow

        function onIsResponseRequiredChanged(): void { root.resetInput(); }
        function onInputPromptChanged(): void { root.resetInput(); }
        function onSelectedIdentityChanged(): void { root.resetInput(); }
        function onAuthenticationFailed(): void { root.resetInput(); }
        function onIsCompletedChanged(): void { root.resetInput(); }
        function onIsCancelledChanged(): void { root.resetInput(); }
    }

    StyledRect {
        objectName: "polkitSurface"
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

            Keys.onEscapePressed: event => {
                root.cancel();
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
                            text: "shield_lock"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.large
                        }
                    }

                    StyledText {
                        objectName: "polkitTitle"
                        Layout.fillWidth: true
                        text: Tr.tr("Authentication required")
                        font: Tokens.font.title.medium
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                StyledText {
                    objectName: "polkitMessage"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.flow?.message ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Authorizing as %1").arg(root.identityLabel(root.flow?.selectedIdentity))
                        font: Tokens.font.label.medium
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    Repeater {
                        model: (root.flow?.identities.length ?? 0) > 1 ? root.flow.identities : []

                        IconTextButton {
                            id: accountButton

                            required property var modelData
                            Layout.fillWidth: true
                            icon: root.flow?.selectedIdentity === modelData ? "check" : "person"
                            text: root.identityLabel(modelData)
                            type: root.flow?.selectedIdentity === modelData ? IconTextButton.Filled : IconTextButton.Tonal
                            activeFocusOnTab: true
                            onClicked: root.flow.selectedIdentity = modelData
                            Keys.onReturnPressed: clicked()
                            Keys.onSpacePressed: clicked()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.awaitingResponse
                    spacing: Tokens.spacing.small

                    StyledTextField {
                        id: response

                        objectName: "polkitResponse"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        placeholderText: root.prompt
                        leadingIcon: root.flow?.responseVisible ? "keyboard" : "lock"
                        echoMode: root.flow?.responseVisible || root.revealResponse ? TextInput.Normal : TextInput.Password
                        inputMethodHints: root.flow?.responseVisible ? Qt.ImhNone : Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        readOnly: !root.awaitingResponse || root.submitting
                        activeFocusOnTab: true
                        focus: root.awaitingResponse
                        onAccepted: root.submit()
                        Keys.onEscapePressed: root.cancel()
                    }

                    IconButton {
                        objectName: "polkitReveal"
                        visible: !root.flow?.responseVisible
                        type: IconButton.Text
                        icon: root.revealResponse ? "visibility_off" : "visibility"
                        activeFocusOnTab: true
                        Accessible.name: root.revealResponse ? Tr.tr("Hide password") : Tr.tr("Show password")
                        onClicked: {
                            root.revealResponse = !root.revealResponse;
                            response.forceActiveFocus();
                        }
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                    }
                }

                StyledText {
                    objectName: "polkitFeedback"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.flow?.supplementaryMessage || (root.flow?.failed ? Tr.tr("Authentication failed. Please try again.") : "")
                    color: root.flow?.supplementaryIsError || root.flow?.failed ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    Accessible.role: Accessible.AlertMessage
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.awaitingResponse
                    spacing: Tokens.spacing.small

                    LoadingIndicator {
                        implicitSize: 24 * Tokens.scale
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Waiting for authentication...")
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.awaitingResponse && !root.flow?.responseVisible && Hypr.capsLock
                    text: Tr.tr("Caps Lock is on")
                    color: Colours.palette.m3tertiary
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item { Layout.fillWidth: true }

                    TextButton {
                        objectName: "polkitCancel"
                        text: Tr.trCtx("Cancel", "button")
                        type: TextButton.Tonal
                        activeFocusOnTab: true
                        onClicked: root.cancel()
                        Keys.onReturnPressed: clicked()
                        Keys.onSpacePressed: clicked()
                    }

                    TextButton {
                        objectName: "polkitSubmit"
                        text: Tr.trCtx("Authenticate", "button")
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
}
