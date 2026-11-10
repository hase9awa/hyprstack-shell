pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

// What a picked screenshot lands in. The capture itself is written to a
// temporary file, so this is where it is kept, copied again or left behind.
DialogWindow {
    id: root

    required property string path
    signal dismissed

    onCloseRequested: root.dismissed()

    readonly property string fileName: path.split("/").pop()
    // Only the proportions are wanted, so the picture is decoded small for
    // them and drawn at size by the view below.
    readonly property real aspect: metrics.implicitHeight > 0 ? metrics.implicitWidth / metrics.implicitHeight : 16 / 9
    readonly property real viewWidth: Math.min(640 * Tokens.scale, (screen?.width ?? 1280) * 0.5)

    function copy(): void {
        Quickshell.execDetached(["python3", Notifs.imageHelper, "action", "copy", root.path, root.path]);
    }

    // The screenshots folder is the one the command line tool writes to, so
    // both ways of taking one end up together.
    function keep(): void {
        if (saveProc.running)
            return;
        saveProc.command = ["python3", Notifs.imageHelper, "action", "save", root.path, root.path];
        saveProc.running = true;
    }

    function saveAs(target: string): void {
        if (!CUtils.copyFile(Paths.fileUrl(root.path), Paths.fileUrl(target))) {
            Notifs.lastError = "Unable to save the screenshot";
            return;
        }
        root.dismissed();
    }

    name: "screenshot"
    dialogWidth: viewWidth + Tokens.padding.large * 2
    dialogHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 96 * Tokens.scale)
    WlrLayershell.keyboardFocus: dialog.active ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: !dialog.active
        onActivated: root.dismissed()
    }

    Image {
        id: metrics

        source: Paths.fileUrl(root.path)
        sourceSize.width: 64
        asynchronous: true
        visible: false
    }

    Process {
        id: saveProc

        onExited: code => { // qmllint disable signal-handler-parameters
            if (code !== 0) {
                Notifs.lastError = "Unable to save the screenshot";
                return;
            }
            root.dismissed();
        }
    }

    StyledRect {
        objectName: "screenshotSurface"
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainer
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        ColumnLayout {
            id: contents

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        objectName: "screenshotTitle"
                        Layout.fillWidth: true
                        text: Tr.tr("Screenshot taken")
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Copied to the clipboard")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    objectName: "closeScreenshot"
                    icon: "close"
                    type: IconButton.Text
                    onClicked: root.dismissed()
                    Accessible.name: Tr.trCtx("Close", "button")
                }
            }

            StyledClippingRect {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(width / root.aspect, (root.screen?.height ?? 720) * 0.45)
                radius: Tokens.rounding.medium
                color: Colours.palette.m3surfaceContainerHigh

                CachingImage {
                    anchors.fill: parent
                    path: root.path
                    fillMode: Image.PreserveAspectFit
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item { Layout.fillWidth: true }

                IconTextButton {
                    objectName: "copyScreenshot"
                    type: IconTextButton.Tonal
                    verticalPadding: Tokens.padding.extraSmall
                    icon: "content_copy"
                    text: Tr.trCtx("Copy", "button")
                    onClicked: root.copy()
                }

                IconTextButton {
                    objectName: "saveScreenshotAs"
                    type: IconTextButton.Tonal
                    verticalPadding: Tokens.padding.extraSmall
                    icon: "save_as"
                    text: Tr.trCtx("Save as", "button")
                    onClicked: dialog.open()
                }

                IconTextButton {
                    objectName: "saveScreenshot"
                    verticalPadding: Tokens.padding.extraSmall
                    icon: "download"
                    text: Tr.trCtx("Save", "button")
                    onClicked: root.keep()
                }
            }
        }
    }

    FileDialog {
        id: dialog

        mode: FileDialog.Save
        title: Tr.tr("Save the screenshot")
        suggestedName: root.fileName
        cwd: ["Home", "Pictures"]

        onAccepted: paths => root.saveAs(paths[0])
    }
}
