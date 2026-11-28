pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Item {
    id: root

    required property HyprlandToplevel client
    required property ShellScreen screen
    property bool captureEnabled: visible
    property bool paused: false
    property bool fit: true

    readonly property var windowData: Hypr.clientData(client)
    readonly property bool offscreen: {
        const output = client?.monitor?.lastIpcObject;
        if (!output || !screen || !windowData?.at || !windowData?.size)
            return false;
        const [x, y] = windowData.at;
        const [width, height] = windowData.size;
        return x + width <= output.x || y + height <= output.y
            || x >= output.x + screen.width || y >= output.y + screen.height;
    }
    readonly property bool canStream: captureEnabled && !paused && !!client?.wayland && !offscreen
    readonly property bool hasFrame: hasLiveFrame || snapshot.status === Image.Ready
    readonly property real aspect: {
        const size = windowData?.size;
        return size?.[0] > 0 && size?.[1] > 0 ? size[0] / size[1] : 16 / 9;
    }

    property bool hasLiveFrame: false
    property bool streamTimedOut: false

    onClientChanged: {
        hasLiveFrame = false;
        streamTimedOut = false;
        snapshot.source = "";
    }

    Item {
        id: frame

        anchors.centerIn: parent
        width: root.fit ? Math.min(parent.width, parent.height * root.aspect) : parent.width
        height: root.fit ? Math.min(parent.height, parent.width / root.aspect) : parent.height

        Loader {
            id: stream

            anchors.fill: parent
            asynchronous: true
            active: root.canStream || root.hasLiveFrame

            sourceComponent: ScreencopyView {
                objectName: "workspaceWindowThumbnail"

                captureSource: root.canStream ? root.client.wayland : null
                live: root.canStream
                onHasContentChanged: if (hasContent) root.hasLiveFrame = true
            }
        }

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: stream.item
            hideSource: true
            // Keep the displayed texture through a focus transition or when
            // scrolling takes its source outside the live capture area.
            live: root.canStream && (stream.item?.hasContent ?? false)
            visible: root.hasLiveFrame
        }

        Image {
            id: snapshot
            objectName: "workspaceWindowSnapshot"

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: !root.hasLiveFrame && status === Image.Ready
        }
    }

    Timer {
        interval: 300
        running: root.captureEnabled && !root.paused && Hypr.usingLua && !root.offscreen && !root.hasFrame && !root.streamTimedOut
        onTriggered: root.streamTimedOut = true
    }

    Process {
        id: capture
        property string requestedWindow

        running: root.captureEnabled && !root.paused && Hypr.usingLua && !!root.windowData?.stableId && !root.hasFrame
            && (root.offscreen || root.streamTimedOut)
        command: {
            const address = JSON.stringify(root.windowData?.address ?? "");
            const stableId = JSON.stringify(root.windowData?.stableId ?? "");
            return ["hyprctl", "repl", `if hl.plugin.hyprstack_previews then return hl.plugin.hyprstack_previews.capture(${address}, ${stableId}) end`];
        }
        onStarted: requestedWindow = root.windowData?.stableId ?? ""

        stdout: StdioCollector {
            onStreamFinished: {
                const url = text.trim();
                if (capture.requestedWindow === root.windowData?.stableId && url.startsWith("data:image/png;base64,"))
                    snapshot.source = url;
            }
        }
    }
}
