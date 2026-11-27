pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
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
    readonly property real minWidthLimit: Math.min(maxPreviewWidth, 150 * Tokens.scale)
    readonly property real widthLimit: Math.min(maxPreviewWidth, Math.max(minWidthLimit,
        Math.floor((maxWidth - Math.max(0, windows.length - 1) * spacing) / Math.max(1, windows.length))))
    readonly property real heightLimit: Math.min(maxPreviewWidth * 9 / 16, popouts.screen.height * 0.3)
    readonly property var previewSizes: windows.map(window => {
        const size = Hypr.clientData(window)?.size;
        const ratio = size?.[0] > 0 && size?.[1] > 0 ? size[0] / size[1] : 16 / 9;
        const width = Math.max(1, Math.min(widthLimit, Math.round(heightLimit * ratio)));
        return Qt.size(width, Math.max(1, Math.min(heightLimit, Math.round(width / ratio))));
    })
    readonly property real rowWidth: previewSizes.reduce((width, size) => width + size.width, 0)
        + Math.max(0, windows.length - 1) * spacing
    readonly property real rowHeight: previewSizes.reduce((height, size) => Math.max(height, size.height), 0)

    implicitWidth: Math.min(maxWidth, windows.length ? rowWidth : 360 * Tokens.scale)
    implicitHeight: windows.length ? rowHeight + (rowWidth > maxWidth ? Tokens.padding.small : 0) : 46 * Tokens.scale

    function refreshWindowModel(): void {
        if (windows.length !== shownWindows.length || windows.some((window, index) => window !== shownWindows[index]))
            shownWindows = windows;
    }

    onWindowsChanged: refreshWindowModel()
    Component.onCompleted: {
        refreshWindowModel();
        Hypr.extras.refreshClients();
    }

    function focusWindow(window: HyprlandToplevel): void {
        const address = Hypr.clientData(window)?.address;
        if (!address)
            return;
        const target = "address:" + address;
        popouts.hasCurrent = false;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({window = ${JSON.stringify(target)}})` : "focuswindow " + target);
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

    ListView {
        id: list
        objectName: "workspaceWindowStrip"

        anchors.fill: parent
        clip: true
        orientation: ListView.Horizontal
        cacheBuffer: 0
        spacing: root.spacing
        boundsBehavior: Flickable.StopAtBounds
        model: root.shownWindows

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const overflow = list.contentWidth - list.width;
                const pixels = event.pixelDelta.x || event.pixelDelta.y;
                const ticks = (event.angleDelta.x || event.angleDelta.y) / 120;
                const steps = ticks * (root.widthLimit + list.spacing);
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

        delegate: Item {
            id: thumbnail
            objectName: "workspaceWindow"

            required property HyprlandToplevel modelData
            required property int index
            readonly property var client: Hypr.clientData(modelData)
            readonly property string windowTitle: modelData?.title || client?.class || ""
            readonly property bool hasLivePreview: liveCapture.item?.hasContent ?? false
            property bool liveCaptureTimedOut: false
            readonly property bool offscreen: {
                const output = root.monitor?.lastIpcObject;
                if (!client?.at || !client?.size || !output)
                    return false;
                const screen = root.popouts.screen;
                const [x, y] = client.at;
                const [width, height] = client.size;
                return x + width <= output.x || y + height <= output.y
                    || x >= output.x + screen.width || y >= output.y + screen.height;
            }

            width: root.previewSizes[index]?.width ?? 0
            height: root.previewSizes[index]?.height ?? 0

            Accessible.role: Accessible.Button
            Accessible.name: windowTitle
            Accessible.onPressAction: root.focusWindow(modelData)

            Rectangle {
                anchors.fill: parent
                color: Colours.palette.m3surfaceContainerLowest
                visible: !thumbnail.hasLivePreview && snapshot.status !== Image.Ready
            }

            Loader {
                id: liveCapture

                anchors.centerIn: parent
                asynchronous: true
                active: visible && !!thumbnail.modelData?.wayland && (!thumbnail.offscreen || !Hypr.usingLua)
                sourceComponent: ScreencopyView {
                    objectName: "workspaceWindowThumbnail"
                    captureSource: thumbnail.modelData?.wayland ?? null
                    live: root.opened && visible
                    constraintSize: Qt.size(Math.max(1, thumbnail.width), Math.max(1, thumbnail.height))
                }
            }

            Image {
                id: snapshot
                objectName: "workspaceWindowSnapshot"

                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                visible: !thumbnail.hasLivePreview && status === Image.Ready
            }

            Timer {
                interval: 300
                running: root.opened && thumbnail.visible && Hypr.usingLua
                    && !thumbnail.offscreen && !thumbnail.hasLivePreview && !thumbnail.liveCaptureTimedOut
                onTriggered: thumbnail.liveCaptureTimedOut = true
            }

            Process {
                running: root.opened && thumbnail.visible && Hypr.usingLua && !!thumbnail.client?.stableId
                    && !thumbnail.hasLivePreview && (thumbnail.offscreen || thumbnail.liveCaptureTimedOut)
                command: {
                    const address = JSON.stringify(thumbnail.client?.address ?? "");
                    const stableId = JSON.stringify(thumbnail.client?.stableId ?? "");
                    return ["hyprctl", "repl", `if hl.plugin.hyprstack_previews then return hl.plugin.hyprstack_previews.capture(${address}, ${stableId}) end`];
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        const url = text.trim();
                        if (url.startsWith("data:image/png;base64,"))
                            snapshot.source = url;
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWindow(thumbnail.modelData)
            }
        }
    }
}
