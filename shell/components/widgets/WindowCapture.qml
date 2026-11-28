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
    property bool snapshotOnly: false
    property int snapshotRevision: 0

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
    readonly property bool canCapture: captureEnabled && !paused && (!snapshotOnly || snapshot.source.toString() === "")
    readonly property bool canStream: canCapture && !!client?.wayland && !offscreen
    readonly property bool hasFrame: hasLiveFrame || snapshot.status === Image.Ready
    readonly property real aspect: {
        const size = windowData?.size;
        return size?.[0] > 0 && size?.[1] > 0 ? size[0] / size[1] : 16 / 9;
    }

    property bool hasLiveFrame: false
    property bool streamTimedOut: false
    // Retain the result while the snapshot uses its in-memory URL.
    property var grabbedFrame: null

    onClientChanged: resetFrame()
    onSnapshotRevisionChanged: resetFrame()

    function resetFrame(): void {
        hasLiveFrame = false;
        streamTimedOut = false;
        snapshot.source = "";
        grabbedFrame = null;
    }

    function keepFrame(view: Item): void {
        const revision = snapshotRevision;
        const window = client;
        const scale = Math.min(1, 400 / Math.max(view.width, view.height));
        const size = Qt.size(Math.max(1, Math.round(view.width * scale)), Math.max(1, Math.round(view.height * scale)));
        // Keep the pixels independently of the export buffer and the effects
        // that display it. Focus and scroll can outlast the compositor's motion.
        if (!view.grabToImage(result => {
            if (root.canStream && root.snapshotRevision === revision && root.client === window
                && stream.item === view && result.url.toString() !== "") {
                root.grabbedFrame = result;
                snapshot.source = result.url;
            }
        }, size)) {
            streamTimedOut = true;
        }
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
                id: copy
                objectName: "workspaceWindowThumbnail"

                visible: !root.snapshotOnly
                captureSource: root.canStream ? root.client.wayland : null
                live: root.canStream && !root.snapshotOnly
                onHasContentChanged: if (root.snapshotOnly && hasContent) root.keepFrame(copy)
            }
        }

        Loader {
            anchors.fill: parent
            active: !root.snapshotOnly

            sourceComponent: ShaderEffectSource {
                readonly property bool freshContent: root.canStream && (stream.item?.hasContent ?? false)
                property bool presenting: false

                sourceItem: stream.item
                hideSource: true
                live: freshContent && presenting
                visible: root.hasLiveFrame || freshContent
                onFreshContentChanged: {
                    presenting = false;
                    if (freshContent)
                        scheduleUpdate();
                }
                onScheduledUpdateCompleted: {
                    if (freshContent) {
                        root.hasLiveFrame = true;
                        presenting = true;
                    }
                }
            }
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
        running: root.canCapture && Hypr.usingLua && !root.offscreen && !root.hasFrame && !root.streamTimedOut
        onTriggered: root.streamTimedOut = true
    }

    Process {
        id: capture
        property string requestedWindow
        property int requestedRevision

        running: root.canCapture && Hypr.usingLua && !!root.windowData?.stableId && !root.hasFrame
            && (root.offscreen || root.streamTimedOut)
        command: {
            const address = JSON.stringify(root.windowData?.address ?? "");
            const stableId = JSON.stringify(root.windowData?.stableId ?? "");
            return ["hyprctl", "repl", `if hl.plugin.hyprstack_previews then return hl.plugin.hyprstack_previews.capture(${address}, ${stableId}) end`];
        }
        onStarted: {
            requestedWindow = root.windowData?.stableId ?? "";
            requestedRevision = root.snapshotRevision;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const url = text.trim();
                if (root.canCapture && capture.requestedRevision === root.snapshotRevision
                    && capture.requestedWindow === root.windowData?.stableId && url.startsWith("data:image/png;base64,"))
                    snapshot.source = url;
            }
        }
    }
}
