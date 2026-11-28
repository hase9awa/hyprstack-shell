pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
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
    property var windowSizes: []
    property string focusRequest: ""
    property int focusSequence: 0
    property bool holdLayout: false
    property WindowPreview hoveredPreview: null
    readonly property bool capturePaused: focusRequest.length > 0
    readonly property bool switchingWindow: capturePaused && holdLayout
    readonly property bool opened: popouts.hasCurrent && popouts.currentName === "workspacewindows"
    readonly property real spacing: Tokens.spacing.small
    readonly property real maxWidth: Math.max(1, popouts.screen.width - (Tokens.padding.large + Config.border.thickness * Tokens.scale) * 2)
    readonly property real maxPreviewWidth: Math.min(maxWidth, Math.max(1, Tokens.sizes.bar.windowPreviewSize))
    readonly property real heightLimit: Math.min(maxPreviewWidth * 9 / 16, popouts.screen.height * 0.3)
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
    readonly property var previewOffsets: {
        let left = 0;
        return previewSizes.map(size => {
            const offset = left;
            left += size.width + spacing;
            return offset;
        });
    }
    readonly property real rowWidth: previewSizes.reduce((width, size) => width + size.width, 0)
        + Math.max(0, windowSizes.length - 1) * spacing
    readonly property real rowHeight: previewSizes.reduce((height, size) => Math.max(height, size.height), 0)
    readonly property real stripHeight: rowHeight + (rowWidth > maxWidth ? Tokens.padding.small : 0)

    implicitWidth: Math.min(maxWidth, windowSizes.length ? Math.max(rowWidth, actions.implicitWidth) : 360 * Tokens.scale)
    implicitHeight: windowSizes.length ? stripHeight + spacing + actions.height : 46 * Tokens.scale

    Binding on windowSizes {
        when: !root.switchingWindow
        value: root.shownWindows.map(window => {
            const size = Hypr.clientData(window)?.size;
            return size?.[0] > 0 && size?.[1] > 0 ? Qt.size(size[0], size[1]) : Qt.size(1280, 720);
        })
        restoreMode: Binding.RestoreNone
    }

    function borderStyle(value: string, fallback: color): var {
        const parts = (value ?? "").split(/\s+/);
        const colors = parts.filter(part => /^[0-9a-f]{8}$/i.test(part)).map(part => "#" + part);
        const angle = parts.find(part => part.endsWith("deg"));
        return {colors: colors.length ? colors : [fallback.toString()], angle: (parseFloat(angle) || 0) * Math.PI / 180};
    }

    function refreshWindowModel(): void {
        if (switchingWindow)
            return;
        if (windows.length !== shownWindows.length || windows.some((window, index) => window !== shownWindows[index]))
            shownWindows = windows;
    }

    onWindowsChanged: refreshWindowModel()
    onSwitchingWindowChanged: if (!switchingWindow) refreshWindowModel()
    onOpenedChanged: {
        if (opened) {
            Hypr.extras.refreshOptions();
            if (Hypr.usingLua) {
                // Offscreen windows get a still image. Wait for any motion
                // already in progress so that image starts with settled content.
                const args = [popouts.screen.name, beginFocusTransition(false)].map(value => JSON.stringify(value)).join(", ");
                Hypr.extras.message(`eval hyprstack_layouts.settle_previews(${args}, true)`);
            }
        } else {
            hoveredPreview = null;
            finishFocusTransition();
        }
    }
    Component.onCompleted: {
        refreshWindowModel();
        Hypr.extras.refreshClients();
    }

    function finishFocusTransition(): void {
        focusTimeout.stop();
        focusRequest = "";
    }

    function beginFocusTransition(freezeLayout: bool): string {
        holdLayout = freezeLayout;
        focusRequest = `${popouts.screen.name}-${Date.now()}-${++focusSequence}`;
        focusTimeout.restart();
        return focusRequest;
    }

    function act(window: HyprlandToplevel, operation: string): void {
        const client = Hypr.clientData(window);
        if (!client?.address || (Hypr.usingLua && !client.stableId))
            return;

        const request = beginFocusTransition(operation !== "close");

        if (Hypr.usingLua) {
            const args = [operation, client.address, client.stableId, request].map(value => JSON.stringify(value)).join(", ");
            Hypr.extras.message(`eval hyprstack_layouts.action(${args})`);
            return;
        }

        const address = " address:" + client.address;
        if (operation === "close" || operation === "toggle-floating") {
            Hypr.dispatch((operation === "close" ? "closewindow" : "togglefloating") + address);
            return;
        }
        const commands = ["dispatch focuswindow" + address];
        if (operation === "maximize-preview")
            commands.push("dispatch fullscreen 1");
        if (Hypr.options["cursor:no_warps"] === false) {
            commands.unshift("keyword cursor:no_warps true");
            commands.push("keyword cursor:no_warps false");
        }
        Hypr.extras.batchMessage(commands);
    }

    function updateActionHover(): void {
        if (hoveredPreview?.hovered || actionHover.hovered)
            hideActions.stop();
        else
            hideActions.restart();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root.capturePaused && event.name === "custom" && event.data === "hyprstack-preview-settled:" + root.focusRequest)
                root.finishFocusTransition();
        }
    }

    Timer {
        id: focusTimeout
        interval: Hypr.usingLua ? 1600 : 550
        onTriggered: root.finishFocusTransition()
    }

    Timer {
        id: hideActions
        interval: 200
        onTriggered: root.hoveredPreview = null
    }

    StyledText {
        anchors.fill: parent
        visible: root.windowSizes.length === 0
        text: Tr.tr("No windows on this workspace")
        color: Colours.palette.m3onSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    Flickable {
        id: list
        objectName: "workspaceWindowStrip"

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.stripHeight
        clip: true
        contentWidth: Math.max(width, root.rowWidth)
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
                const steps = ticks * root.rowWidth / Math.max(1, root.windowSizes.length);
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

        Repeater {
            // Keep each capture and its rendered frame when the layout reorders
            // windows or another window opens or closes.
            model: ScriptModel { values: root.shownWindows }
            delegate: WindowPreview {}
        }
    }

    Row {
        id: actions
        objectName: "workspaceWindowActions"

        readonly property WindowPreview thumbnail: root.hoveredPreview
        readonly property real buttonSize: 32 * Tokens.scale
        readonly property bool floating: thumbnail?.client?.floating ?? false
        readonly property bool maximized: Hypr.isMaximized(thumbnail?.modelData ?? null)

        anchors.bottom: parent.bottom
        x: Math.max(0, Math.min(root.width - width,
            list.x + (thumbnail?.x ?? 0) - list.contentX + (thumbnail?.width ?? 0) / 2 - width / 2))
        spacing: Tokens.spacing.extraSmall
        height: buttonSize
        visible: root.opened && !!thumbnail?.inViewport && !!thumbnail?.modelData

        HoverHandler {
            id: actionHover
            onHoveredChanged: root.updateActionHover()
        }

        PreviewAction {
            objectName: "workspaceWindowSettings"
            icon: "settings"
            actionLabel: Tr.tr("Settings")
            onClicked: root.popouts.windowInfoRequested(actions.thumbnail?.modelData ?? null)
        }

        PreviewAction {
            objectName: "workspaceWindowFloat"
            icon: actions.floating ? "view_column" : "picture_in_picture_alt"
            actionLabel: actions.floating ? Tr.tr("Tile") : Tr.tr("Float")
            disabled: !!actions.thumbnail?.client?.pinned || (actions.thumbnail?.client?.workspace?.id ?? 0) < -1
            onClicked: root.act(actions.thumbnail?.modelData ?? null, "toggle-floating")
        }

        PreviewAction {
            objectName: "workspaceWindowMaximize"
            icon: actions.maximized ? "filter_none" : "crop_square"
            actionLabel: actions.maximized ? Tr.tr("Restore window size") : Tr.tr("Toggle maximized")
            onClicked: root.act(actions.thumbnail?.modelData ?? null, "maximize-preview")
        }

        PreviewAction {
            objectName: "workspaceWindowClose"
            icon: "close"
            actionLabel: Tr.tr("Close window")
            inactiveOnColour: hovered ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            onClicked: root.act(actions.thumbnail?.modelData ?? null, "close")
        }
    }

    component PreviewAction: IconButton {
        id: button

        required property string actionLabel

        width: actions.buttonSize
        height: actions.buttonSize
        type: IconButton.Text
        defaultRadius: Tokens.rounding.small
        font: Tokens.font.icon.small

        Accessible.role: Accessible.Button
        Accessible.name: actionLabel
        Accessible.description: actions.thumbnail?.windowTitle ?? ""
        Accessible.onPressAction: if (!disabled) clicked()

        ToolTip {
            parent: button
            visible: button.visible && button.hovered
            delay: 600
            y: button.height + Tokens.spacing.extraSmall
            text: button.actionLabel
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
        readonly property bool hovered: hover.hovered

        x: (root.previewOffsets[index] ?? 0) + Math.max(0, (list.width - root.rowWidth) / 2)
        width: root.previewSizes[index]?.width ?? 0
        height: root.previewSizes[index]?.height ?? 0
        readonly property real rounding: Math.min(root.previewRounding,
            Math.max(0, Math.min(width, height) / 2 - root.borderWidth))

        Accessible.role: Accessible.Button
        Accessible.name: windowTitle
        Accessible.onPressAction: root.act(modelData, "focus-preview")

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
                paused: root.capturePaused
                fit: false
            }
        }

        Canvas {
            objectName: "workspaceWindowFrame"

            readonly property var style: hover.hovered || (root.hoveredPreview === thumbnail && actionHover.hovered)
                ? root.hoverBorder : root.inactiveBorder
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
            onHoveredChanged: {
                if (hovered)
                    root.hoveredPreview = thumbnail;
                root.updateActionHover();
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton)
                    root.popouts.windowInfoRequested(thumbnail.modelData);
                else
                    root.act(thumbnail.modelData, "focus-preview");
            }
        }
    }
}
