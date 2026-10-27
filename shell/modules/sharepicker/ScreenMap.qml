pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.services

// The outputs drawn where they actually sit, at the size they actually are.
// Two identical screens are told apart by their place in the arrangement,
// which a list of names cannot do.
Item {
    id: root

    required property list<ShellScreen> screens
    property string selectedName

    signal picked(name: string)
    signal activated

    // The arrangement, in the compositor's own coordinates.
    readonly property real originX: root.screens.length === 0 ? 0 : Math.min(...root.screens.map(s => s.x))
    readonly property real originY: root.screens.length === 0 ? 0 : Math.min(...root.screens.map(s => s.y))
    readonly property real layoutWidth: root.screens.length === 0 ? 1 : Math.max(...root.screens.map(s => s.x + s.width)) - root.originX
    readonly property real layoutHeight: root.screens.length === 0 ? 1 : Math.max(...root.screens.map(s => s.y + s.height)) - root.originY

    readonly property real factor: Math.min(width / root.layoutWidth, height / root.layoutHeight)
    readonly property real offsetX: (width - root.layoutWidth * root.factor) / 2
    readonly property real offsetY: (height - root.layoutHeight * root.factor) / 2

    // Screens meet edge to edge, so each one is drawn a little inside its
    // own place to leave a seam between neighbours.
    readonly property real seam: Tokens.spacing.extraSmall

    // The screen nearest in the direction asked for, so the arrangement is
    // walked the way it looks rather than in the order it was reported.
    function neighbour(dx: real, dy: real): ShellScreen {
        const current = root.screens.find(s => s.name === root.selectedName);
        if (!current)
            return null;

        const cx = current.x + current.width / 2;
        const cy = current.y + current.height / 2;
        let best = null;
        let shortest = Infinity;
        for (const screen of root.screens) {
            if (screen === current)
                continue;
            const sx = screen.x + screen.width / 2 - cx;
            const sy = screen.y + screen.height / 2 - cy;
            if (sx * dx + sy * dy <= 0)
                continue;
            const distance = Math.hypot(sx, sy);
            if (distance < shortest) {
                best = screen;
                shortest = distance;
            }
        }
        return best;
    }

    function step(dx: real, dy: real): void {
        const next = root.neighbour(dx, dy);
        if (next)
            root.picked(next.name);
    }

    // A screen can go away while the prompt is open; the choice then moves
    // to one that is still there.
    onScreensChanged: {
        if (root.screens.length > 0 && !root.screens.some(s => s.name === root.selectedName))
            root.picked(root.screens[0].name);
    }

    Keys.onLeftPressed: root.step(-1, 0)
    Keys.onRightPressed: root.step(1, 0)
    Keys.onUpPressed: root.step(0, -1)
    Keys.onDownPressed: root.step(0, 1)

    Repeater {
        model: root.screens

        StyledRect {
            id: output

            required property ShellScreen modelData
            readonly property bool selected: output.modelData.name === root.selectedName

            x: root.offsetX + (output.modelData.x - root.originX) * root.factor + root.seam / 2
            y: root.offsetY + (output.modelData.y - root.originY) * root.factor + root.seam / 2
            implicitWidth: Math.max(0, output.modelData.width * root.factor - root.seam)
            implicitHeight: Math.max(0, output.modelData.height * root.factor - root.seam)

            radius: Tokens.rounding.small
            color: output.selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
            border.width: 1
            border.color: output.selected ? Colours.palette.m3secondary : Colours.palette.m3outlineVariant

            StateLayer {
                color: output.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                onClicked: root.picked(output.modelData.name)
                onDoubleClicked: {
                    root.picked(output.modelData.name);
                    root.activated();
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: output.modelData.name
                    color: output.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    font: Tokens.font.label.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    // A screen too small to hold both lines is named only.
                    visible: output.implicitHeight > implicitHeight * 3
                    horizontalAlignment: Text.AlignHCenter
                    text: `${output.modelData.width}×${output.modelData.height}`
                    color: output.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }
    }
}
