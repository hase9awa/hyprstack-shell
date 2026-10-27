import QtQuick
import Quickshell
import Quickshell.Wayland
import Hyprstack
import Hyprstack.Config
import qs.components
import qs.services

// A dialog the shell puts up on its own: it floats above everything, starts
// in the middle of the screen and can be dragged anywhere from there.
//
// The compositor does not move a layer surface the way it moves an ordinary
// window, and moving one from here means feeding its new position back
// through pointer coordinates that moved with it, which shakes. So the
// surface covers the screen and stays put, and the dialog is an item inside
// it that drags like any other. Input is masked to the dialog, so a press
// anywhere else reaches whatever is underneath.
StyledWindow {
    id: root

    // The dialog's own size. The window no longer carries it, since the
    // window is the whole screen.
    property real dialogWidth
    property real dialogHeight
    default property alias contents: frame.data

    // What the key that closes windows means here, since the compositor
    // cannot close a layer surface itself. Each dialog answers it the way it
    // answers Escape.
    signal closeRequested

    Component.onCompleted: Dialogs.register(root)
    Component.onDestruction: Dialogs.unregister(root)

    Config.screen: screen?.name ?? ""
    Tokens.screen: screen?.name ?? ""

    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    mask: Region {
        x: frame.x
        y: frame.y
        width: frame.width
        height: frame.height
    }

    Item {
        id: frame

        // The size that arrives while the dialog is still being built is the
        // one it opens at; growing into it from nothing would only look like
        // the dialog crawling out of a corner.
        property bool settled

        // Centred until it is dragged, which replaces these outright.
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: root.dialogWidth
        height: root.dialogHeight

        Component.onCompleted: settled = true

        Behavior on width {
            enabled: frame.settled

            Anim {}
        }

        Behavior on height {
            enabled: frame.settled

            Anim {}
        }

        // Underneath whatever the dialog holds, so a press lands on a
        // button when there is one and starts a drag when there is not.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

            drag.target: frame
            drag.axis: Drag.XAndYAxis
            drag.threshold: 0

            // Held on screen here rather than through the drag's own limits:
            // those clamp the moment they are set, which would throw the
            // dialog into a corner before it has been touched.
            onPositionChanged: {
                if (!drag.active)
                    return;
                frame.x = CUtils.clamp(frame.x, 0, Math.max(0, root.width - frame.width));
                frame.y = CUtils.clamp(frame.y, 0, Math.max(0, root.height - frame.height));
            }
        }
    }
}
