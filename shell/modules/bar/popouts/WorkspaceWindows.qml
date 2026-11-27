pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root
    objectName: "workspaceWindows"

    required property PopoutState popouts
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(popouts.screen)
    readonly property var windows: {
        const special = monitor?.lastIpcObject?.specialWorkspace;
        const workspace = special?.name ? special.id : monitor?.activeWorkspace?.id;
        if (workspace === undefined)
            return [];

        // HyprStack scrolls from top to bottom on portrait outputs.
        const vertical = !special?.name && popouts.screen.height > popouts.screen.width;
        const axis = vertical ? 1 : 0;
        const entries = Hypr.toplevelsForWs(workspace).map(window => ({
            window,
            position: Hypr.clientData(window)?.at ?? [0, 0]
        }));
        entries.sort((a, b) => a.position[axis] - b.position[axis] || a.position[1 - axis] - b.position[1 - axis]);
        return entries.map(entry => entry.window);
    }
    property var shownWindows: []
    readonly property bool opened: popouts.hasCurrent && popouts.currentName === "workspacewindows"
    readonly property real spacing: Tokens.spacing.small
    readonly property real maxWidth: Math.max(1, popouts.screen.width - (Tokens.padding.large + Config.border.thickness * Tokens.scale) * 2)
    readonly property real maxPreviewWidth: Math.min(maxWidth, Math.max(1, Tokens.sizes.bar.windowPreviewSize))
    readonly property real heightLimit: Math.min(maxPreviewWidth * 9 / 16, popouts.screen.height * 0.3)
    readonly property var windowSizes: windows.map(window => {
        const size = Hypr.clientData(window)?.size;
        return size?.[0] > 0 && size?.[1] > 0 ? Qt.size(size[0], size[1]) : Qt.size(1280, 720);
    })
    readonly property real previewScale: {
        if (!windowSizes.length)
            return 1;
        const widest = Math.max(...windowSizes.map(size => size.width));
        const tallest = Math.max(...windowSizes.map(size => size.height));
        const totalWidth = windowSizes.reduce((sum, size) => sum + size.width, 0);
        const widthToFit = maxWidth - (windowSizes.length - 1) * spacing - windowSizes.length * 2;
        return Math.min(maxPreviewWidth / widest, heightLimit / tallest,
            Math.max(150 * Tokens.scale / widest, widthToFit / totalWidth));
    }
    readonly property real previewRounding: (Hypr.options["decoration:rounding"] ?? Tiling.windowRounding) * previewScale
    readonly property real borderWidth: Math.max(1, (Hypr.options["general:border_size"] ?? Tiling.focusBorderWidth) * previewScale)
    readonly property var inactiveBorder: borderStyle(Hypr.options["general:col.inactive_border"], Colours.palette.m3outline)
    readonly property var hoverBorder: borderStyle(Hypr.options["general:col.active_border"], Colours.palette.m3primary)
    readonly property var previewSizes: windowSizes.map(size => Qt.size(
        Math.max(1, Math.round(size.width * previewScale)) + borderWidth * 2,
        Math.max(1, Math.round(size.height * previewScale)) + borderWidth * 2))
    readonly property real rowWidth: previewSizes.reduce((width, size) => width + size.width, 0)
        + Math.max(0, windows.length - 1) * spacing
    readonly property real rowHeight: previewSizes.reduce((height, size) => Math.max(height, size.height), 0)

    implicitWidth: Math.min(maxWidth, windows.length ? rowWidth : 360 * Tokens.scale)
    implicitHeight: windows.length ? rowHeight + (rowWidth > maxWidth ? Tokens.padding.small : 0) : 46 * Tokens.scale

    function borderStyle(value: string, fallback: color): var {
        const parts = (value ?? "").split(/\s+/);
        const colors = parts.filter(part => /^[0-9a-f]{8}$/i.test(part)).map(part => "#" + part);
        const angle = parts.find(part => part.endsWith("deg"));
        return {colors: colors.length ? colors : [fallback.toString()], angle: (parseFloat(angle) || 0) * Math.PI / 180};
    }

    function refreshWindowModel(): void {
        if (windows.length !== shownWindows.length || windows.some((window, index) => window !== shownWindows[index]))
            shownWindows = windows;
    }

    onWindowsChanged: refreshWindowModel()
    onOpenedChanged: if (opened) Hypr.extras.refreshOptions()
    Component.onCompleted: {
        refreshWindowModel();
        Hypr.extras.refreshClients();
    }

    function focusWindow(window: HyprlandToplevel): void {
        if (Hypr.usingLua) {
            Hypr.windowAction("focus-preview", window);
            return;
        }
        const address = Hypr.clientData(window)?.address;
        if (!address)
            return;
        const focus = "focuswindow address:" + address;
        if (Hypr.options["cursor:no_warps"] === false)
            Hypr.extras.batchMessage(["keyword cursor:no_warps true", "dispatch " + focus, "keyword cursor:no_warps false"]);
        else
            Hypr.dispatch(focus);
    }

    StyledText {
        anchors.fill: parent
        visible: root.windows.length === 0
        text: Tr.tr("No windows on this workspace")
        color: Colours.palette.m3onSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    Flickable {
        id: list
        objectName: "workspaceWindowStrip"

        anchors.fill: parent
        clip: true
        contentWidth: root.rowWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const overflow = list.contentWidth - list.width;
                const pixels = event.pixelDelta.x || event.pixelDelta.y;
                const ticks = (event.angleDelta.x || event.angleDelta.y) / 120;
                const steps = ticks * root.rowWidth / Math.max(1, root.windows.length);
                const amount = event.device.type === PointerDevice.TouchPad ? pixels || steps : steps || pixels;
                if (overflow <= 0 || amount === 0) {
                    event.accepted = false;
                    return;
                }
                list.contentX = Math.max(list.originX, Math.min(list.contentX - amount, list.originX + overflow));
            }
        }

        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AsNeeded
            visible: root.rowWidth > root.maxWidth
            height: Tokens.padding.extraSmall
            padding: 0

            contentItem: StyledRect {
                radius: height / 2
                color: Colours.palette.m3outline
            }
        }

        Row {
            spacing: root.spacing

            Repeater {
                model: root.shownWindows
                delegate: WindowPreview {}
            }
        }
    }

    component WindowPreview: Item {
        id: thumbnail
        objectName: "workspaceWindow"

        required property HyprlandToplevel modelData
        required property int index
        readonly property var client: Hypr.clientData(modelData)
        readonly property string windowTitle: modelData?.title || client?.class || ""
        readonly property bool inViewport: x + width > list.contentX && x < list.contentX + list.width

        width: root.previewSizes[index]?.width ?? 0
        height: root.previewSizes[index]?.height ?? 0
        readonly property real rounding: Math.min(root.previewRounding,
            Math.max(0, Math.min(width, height) / 2 - root.borderWidth))

        Accessible.role: Accessible.Button
        Accessible.name: windowTitle
        Accessible.onPressAction: root.focusWindow(modelData)

        StyledClippingRect {
            anchors.fill: parent
            anchors.margins: root.borderWidth
            radius: thumbnail.rounding
            color: Colours.palette.m3surfaceContainerLowest
            visible: thumbnail.inViewport

            WindowCapture {
                objectName: "windowCapture"
                anchors.fill: parent
                client: thumbnail.modelData
                screen: root.popouts.screen
                captureEnabled: root.opened && thumbnail.inViewport
                fit: false
            }
        }

        Canvas {
            objectName: "workspaceWindowFrame"

            readonly property var style: hover.hovered ? root.hoverBorder : root.inactiveBorder
            readonly property real thickness: root.borderWidth
            readonly property real rounding: thumbnail.rounding
            anchors.fill: parent
            visible: thumbnail.inViewport
            onStyleChanged: requestPaint()
            onThicknessChanged: requestPaint()
            onRoundingChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()

            onPaint: {
                if (!visible || width <= thickness || height <= thickness)
                    return;
                const ctx = getContext("2d");
                const inset = thickness / 2;
                ctx.clearRect(0, 0, width, height);
                ctx.lineWidth = thickness;
                if (style.colors.length > 1) {
                    const sine = Math.sin(style.angle);
                    const x = Math.sign(Math.cos(style.angle)) * (1 - Math.abs(sine)) / width;
                    const y = sine / height;
                    const span = (Math.abs(x) * width + Math.abs(y) * height) / (2 * (x * x + y * y));
                    const gradient = ctx.createLinearGradient(width / 2 - x * span, height / 2 - y * span,
                        width / 2 + x * span, height / 2 + y * span);
                    style.colors.forEach((color, index) => gradient.addColorStop(index / (style.colors.length - 1), color));
                    ctx.strokeStyle = gradient;
                } else {
                    ctx.strokeStyle = style.colors[0];
                }
                ctx.beginPath();
                if (rounding > 0) {
                    const radius = rounding + inset;
                    ctx.roundedRect(inset, inset, width - thickness, height - thickness, radius, radius);
                } else {
                    ctx.rect(inset, inset, width - thickness, height - thickness);
                }
                ctx.stroke();
            }
        }

        HoverHandler {
            id: hover
            enabled: thumbnail.inViewport
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton)
                    root.popouts.windowInfoRequested(thumbnail.modelData);
                else
                    root.focusWindow(thumbnail.modelData);
            }
        }

        StyledRect {
            objectName: "workspaceWindowSettings"

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Math.max(root.borderWidth + Tokens.padding.extraSmall, thumbnail.rounding / 2)
            width: settingsIcon.implicitWidth + Tokens.padding.small
            height: width
            visible: hover.hovered && width + anchors.margins * 2 <= Math.min(parent.width, parent.height)
            color: Colours.palette.m3surfaceContainerHigh
            radius: Tokens.rounding.small

            Accessible.role: Accessible.Button
            Accessible.name: Tr.tr("Settings")
            Accessible.description: thumbnail.windowTitle
            Accessible.onPressAction: root.popouts.windowInfoRequested(thumbnail.modelData)

            StateLayer {
                onClicked: root.popouts.windowInfoRequested(thumbnail.modelData)
            }

            MaterialIcon {
                id: settingsIcon

                anchors.centerIn: parent
                text: "settings"
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
