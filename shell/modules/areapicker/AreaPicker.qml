pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Hyprstack.I18n
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    id: pickerScope

    function openPicker(frozen: bool, clipboardOnly: bool): void {
        if (root.active || clipboardCopy.running)
            return;
        root.freeze = frozen;
        root.closing = false;
        root.clipboardOnly = clipboardOnly;
        root.activeAsync = true;
    }

    // This process outlives the picker windows and finishes copying before
    // opening the editor or reporting that the screenshot is ready.
    Process {
        id: clipboardCopy

        property string imagePath
        property bool clipboardOnly
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
            if (!clipboardOnly)
                ThemeSync.exec(["env", "GDK_BACKEND=wayland", "swappy", "-f", imagePath]);
            Quickshell.execDetached(["notify-send", "-a", "hyprstack", "-i", "image-x-generic-symbolic",
                "-h", "string:image-path:" + imagePath, "-h", "boolean:x-hyprstack-screenshot:true",
                Tr.tr("Screenshot taken"), Tr.tr("Screenshot copied to clipboard")]);
        }
    }

    LazyLoader {
        id: root

        property bool freeze
        property bool closing
        property bool clipboardOnly

        function completeCapture(path: string): void {
            clipboardCopy.imagePath = path;
            clipboardCopy.clipboardOnly = clipboardOnly;
            clipboardCopy.command = ["python3", Notifs.imageHelper, "action", "copy", path, path];
            clipboardCopy.running = true;
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
            pickerScope.openPicker(false, false);
        }

        function openFreeze(): void {
            pickerScope.openPicker(true, false);
        }

        function openClip(): void {
            pickerScope.openPicker(false, true);
        }

        function openFreezeClip(): void {
            pickerScope.openPicker(true, true);
        }

        target: "picker"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshot"
        description: "Open screenshot tool"
        onPressed: pickerScope.openPicker(false, false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotFreeze"
        description: "Open screenshot tool (freeze mode)"
        onPressed: pickerScope.openPicker(true, false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotClip"
        description: "Open screenshot tool (clipboard)"
        onPressed: pickerScope.openPicker(false, true)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotFreezeClip"
        description: "Open screenshot tool (freeze mode, clipboard)"
        onPressed: pickerScope.openPicker(true, true)
    }
}
