import QtQuick
import Quickshell
import Quickshell.Wayland
import Hyprstack
import Hyprstack.Config

// A dialog the shell puts up on its own: it floats above everything, starts
// in the middle of the screen and can be dragged anywhere from there.
//
// The compositor cannot move a layer surface the way it moves an ordinary
// window, so the dialog moves itself. The area doing it sits underneath
// whatever the dialog puts inside, which means a press lands on a button
// when there is one and starts a drag when there is not.
StyledWindow {
    id: root

    readonly property real centredX: Math.max(0, ((screen?.width ?? 0) - width) / 2)
    readonly property real centredY: Math.max(0, ((screen?.height ?? 0) - height) / 2)
    // Where the dialog has been dragged to, or less than zero while it has
    // not been dragged and belongs in the middle.
    property real placedX: -1
    property real placedY: -1

    Config.screen: screen?.name ?? ""
    Tokens.screen: screen?.name ?? ""

    anchors.top: true
    anchors.left: true
    // qmllint disable unqualified unresolved-type
    margins.left: placedX < 0 ? centredX : placedX
    margins.top: placedY < 0 ? centredY : placedY
    // qmllint enable unqualified unresolved-type

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    MouseArea {
        id: drag

        property real grabX
        property real grabY

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

        onPressed: event => {
            grabX = event.x;
            grabY = event.y;
        }

        onPositionChanged: event => {
            if (!pressed)
                return;
            // Keeping it on the screen matters more here than anywhere
            // else: a layer surface has no title bar to grab it back by.
            root.placedX = CUtils.clamp(root.margins.left + event.x - grabX, 0, // qmllint disable unresolved-type
                Math.max(0, (root.screen?.width ?? 0) - root.width));
            root.placedY = CUtils.clamp(root.margins.top + event.y - grabY, 0, // qmllint disable unresolved-type
                Math.max(0, (root.screen?.height ?? 0) - root.height));
        }
    }
}
