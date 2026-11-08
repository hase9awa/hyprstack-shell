pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Hyprstack.I18n
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    id: pickerScope

    // A region to share is a geometry and nothing else, so the picker hands
    // one over instead of taking a capture of it.
    signal regionPicked(output: string, region: rect)
    signal regionAbandoned

    function openPicker(frozen: bool): void {
        if (root.active || clipboardCopy.running)
            return;
        root.freeze = frozen;
        root.closing = false;
        root.regionOnly = false;
        root.activeAsync = true;
    }

    function pickRegion(): bool {
        // A picker already busy with a screenshot keeps it: the caller is
        // told so rather than left waiting for a region.
        if (root.active || clipboardCopy.running)
            return false;
        root.freeze = false;
        root.closing = false;
        root.regionOnly = true;
        root.activeAsync = true;
        return true;
    }

    // This process outlives the picker windows and finishes copying before
    // reporting that the screenshot is ready. A preview opens only on demand.
    Process {
        id: clipboardCopy

        property string imagePath
        stdout: StdioCollector { id: copyOutput }
        onExited: (code, status) => {
            if (code !== 0) {
                try {
                    Notifs.lastError = JSON.parse(copyOutput.text).error;
                } catch (_) {
                    Notifs.lastError = "Unable to copy screenshot to clipboard";
                }
                return;
            }
            Quickshell.execDetached(["notify-send", "-a", "hyprstack", "-i", "image-x-generic-symbolic",
                "-h", "string:image-path:" + imagePath, "-h", "boolean:x-hyprstack-screenshot:true",
                Tr.tr("Screenshot taken"), Tr.tr("Screenshot copied to clipboard")]);
        }
    }

    Connections {
        target: Notifs
        function onScreenshotRequested(path: string): void {
            preview.path = path;
            preview.active = true;
        }
    }

    LazyLoader {
        id: preview

        property string path

        active: false

        ScreenshotPreview {
            path: preview.path
            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            onDismissed: preview.active = false
        }
    }

    LazyLoader {
        id: root

        property bool freeze
        property bool closing
        property bool regionOnly
        property bool regionReported

        function completeRegion(output: string, region: rect): void {
            regionReported = true;
            pickerScope.regionPicked(output, region);
        }

        function completeCapture(path: string): void {
            clipboardCopy.imagePath = path;
            clipboardCopy.command = ["python3", Notifs.imageHelper, "action", "copy", path, path];
            clipboardCopy.running = true;
        }

        // Whoever asked for a region is waiting for an answer, so a picker
        // dismissed without one says so rather than leaving it waiting.
        onActiveChanged: {
            if (active || !regionOnly)
                return;
            regionOnly = false;
            if (!regionReported)
                pickerScope.regionAbandoned();
            regionReported = false;
        }

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "area-picker"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
                mask: root.closing ? empty : null

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Region {
                    id: empty
                }

                Picker {
                    loader: root
                    screen: win.modelData
                }
            }
        }
    }

    IpcHandler {
        function open(): void {
            pickerScope.openPicker(false);
        }

        function openFreeze(): void {
            pickerScope.openPicker(true);
        }

        function openClip(): void {
            pickerScope.openPicker(false);
        }

        function openFreezeClip(): void {
            pickerScope.openPicker(true);
        }

        target: "picker"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshot"
        description: "Open screenshot tool"
        onPressed: pickerScope.openPicker(false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotFreeze"
        description: "Open screenshot tool (freeze mode)"
        onPressed: pickerScope.openPicker(true)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotClip"
        description: "Open screenshot tool (clipboard)"
        onPressed: pickerScope.openPicker(false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotFreezeClip"
        description: "Open screenshot tool (freeze mode, clipboard)"
        onPressed: pickerScope.openPicker(true)
    }
}
