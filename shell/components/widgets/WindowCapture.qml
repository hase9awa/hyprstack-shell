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
    property bool refreshOffscreen: false
    property bool preferNative: false

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
    readonly property bool independentCapture: offscreen || preferNative
    readonly property bool canCapture: captureEnabled && !paused
    readonly property bool canStream: canCapture && !!client?.wayland && !independentCapture
    readonly property bool frameReady: canStream && (stream.item?.hasContent ?? false)
        && matchesGeometry(stream.item.sourceSize)
    readonly property bool wantsNative: canCapture && Hypr.usingLua && !!windowData?.stableId
        && (independentCapture || streamTimedOut) && !frameReady
        && (refreshOffscreen || snapshot.status !== Image.Ready)
    readonly property bool hasLiveFrame: displayedBuffer >= 0
    readonly property bool hasFrame: hasLiveFrame || snapshot.status === Image.Ready
    readonly property string geometryKey: windowData?.size?.join("x") ?? ""
    readonly property real aspect: {
        const size = windowData?.size;
        return size?.[0] > 0 && size?.[1] > 0 ? size[0] / size[1] : 16 / 9;
    }
    readonly property int textureSide: 640

    property bool showingNative: false
    property bool streamTimedOut: false
    property int captureGeneration: 0
    property string nativeRevision: ""
    property int streamGeneration: 0
    property int displayedGeneration: -1
    property int pendingGeneration: -1
    property int displayedBuffer: -1
    property int pendingBuffer: -1

    onClientChanged: {
        ++captureGeneration;
        ++streamGeneration;
        displayedBuffer = -1;
        showingNative = false;
        streamTimedOut = false;
        nativeRevision = "";
        snapshot.source = "";
    }
    onCanCaptureChanged: {
        ++captureGeneration;
        if (!canCapture) {
            capture.running = false;
            streamTimedOut = false;
        }
    }
    onGeometryKeyChanged: {
        ++captureGeneration;
        streamTimedOut = false;
        nativeRevision = "";
    }
    onWantsNativeChanged: {
        if (wantsNative)
            Qt.callLater(requestNative);
    }
    onFrameReadyChanged: {
        ++streamGeneration;
        stageFrame();
    }

    function matchesGeometry(size: size): bool {
        const dimensions = windowData?.size;
        const scale = client?.monitor?.lastIpcObject?.scale ?? 1;
        return size.width > 0 && size.height > 0 && (!dimensions
            || (Math.abs(size.width - dimensions[0] * scale) <= 3 && Math.abs(size.height - dimensions[1] * scale) <= 3));
    }

    function stageFrame(): void {
        if (!frameReady || pendingBuffer >= 0)
            return;
        pendingGeneration = streamGeneration;
        pendingBuffer = displayedBuffer === 0 ? 1 : 0;
        (pendingBuffer === 0 ? firstBuffer : secondBuffer).scheduleUpdate();
    }

    function presentFrame(buffer: int): void {
        if (buffer !== pendingBuffer)
            return;
        pendingBuffer = -1;
        if (frameReady && pendingGeneration === streamGeneration) {
            displayedGeneration = pendingGeneration;
            displayedBuffer = buffer;
            showingNative = false;
            streamTimedOut = false;
        } else {
            stageFrame();
        }
    }

    function requestNative(): void {
        if (!wantsNative || capture.running)
            return;
        capture.requestedGeneration = captureGeneration;
        const args = [windowData.address, windowData.stableId];
        if (refreshOffscreen)
            args.push(nativeRevision);
        const parameters = args.map(value => JSON.stringify(value)).join(", ");
        capture.exec(["hyprctl", "repl", `if hl.plugin.hyprstack_previews then return hl.plugin.hyprstack_previews.capture(${parameters}) end`]);
    }

    Item {
        id: frame

        anchors.centerIn: parent
        width: root.fit ? Math.min(parent.width, parent.height * root.aspect) : parent.width
        height: root.fit ? Math.min(parent.height, parent.width / root.aspect) : parent.height
        clip: true

        Loader {
            id: stream

            asynchronous: true
            active: root.canStream || root.hasLiveFrame || root.pendingBuffer >= 0

            sourceComponent: ScreencopyView {
                objectName: "workspaceWindowThumbnail"

                width: root.textureSide
                height: root.textureSide
                captureSource: root.canStream ? root.client.wayland : null
                live: root.canStream
            }
        }

        PreviewBuffer {
            id: firstBuffer
            index: 0
        }

        PreviewBuffer {
            id: secondBuffer
            index: 1
        }

        Image {
            id: snapshot
            objectName: "workspaceWindowSnapshot"

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            retainWhileLoading: true
            visible: root.showingNative
            onStatusChanged: {
                if (status === Image.Ready && !root.frameReady)
                    root.showingNative = true;
            }
        }
    }

    // Render the first frame of a new stream separately. An interrupted
    // capture can then finish without overwriting the displayed frame.
    component PreviewBuffer: ShaderEffectSource {
        required property int index
        readonly property bool displayed: root.displayedBuffer === index

        objectName: displayed ? "workspaceWindowLiveFrame" : ""
        sourceItem: stream.item
        hideSource: true
        textureSize: Qt.size(root.textureSide, root.textureSide)
        width: parent.width
        height: parent.height
        visible: displayed || root.pendingBuffer === index
        // Qt renders the pending texture outside the visible clip.
        x: displayed && !root.showingNative ? 0 : -width
        live: displayed && root.frameReady && root.displayedGeneration === root.streamGeneration
        onScheduledUpdateCompleted: root.presentFrame(index)
    }

    Timer {
        interval: 300
        running: root.canCapture && Hypr.usingLua && !root.independentCapture && !root.frameReady && !root.streamTimedOut
        onTriggered: root.streamTimedOut = true
    }

    Timer {
        interval: 125
        repeat: true
        running: root.refreshOffscreen && root.wantsNative
        onTriggered: root.requestNative()
    }

    Process {
        id: capture
        property int requestedGeneration

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.wantsNative || capture.requestedGeneration !== root.captureGeneration)
                    return;
                const result = text.trim();
                const start = result.indexOf("data:image/png;base64,");
                if (start === -1 || (start > 0 && !/^[0-9]+:$/.test(result.slice(0, start))))
                    return;
                root.nativeRevision = start > 0 ? result.slice(0, start - 1) : "";
                snapshot.source = result.slice(start);
                if (snapshot.status === Image.Ready && !root.frameReady)
                    root.showingNative = true;
            }
        }
    }
}
