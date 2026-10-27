pragma ComponentBehavior: Bound

import "../areapicker"
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Scope {
    id: root

    required property AreaPicker areaPicker

    // One socket per Hyprland session, in the runtime directory, which is
    // the user's own: nothing else on the machine can be asked what to share
    // or read the answer back.
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/hyprstack-share-picker-${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}.sock`
    readonly property bool listening: server.active
    property var requests: []
    property var regionRequest: null
    property bool regionToken

    function submit(request: var, selection: string, token: bool): void {
        root.reply(request, {
            ok: true,
            selection: selection,
            token: token
        });
    }

    function cancel(request: var): void {
        root.reply(request, {
            ok: false
        });
    }

    // The region overlay wants the screen to itself, so the dialog steps
    // aside for it and comes back if nothing was picked.
    function pickRegion(request: var, token: bool): void {
        if (root.regionRequest || !root.areaPicker.pickRegion())
            return;
        root.regionRequest = request;
        root.regionToken = token;
        request.picking = true;
    }

    function reply(request: var, answer: var): void {
        request.write(`${JSON.stringify(answer)}\n`);
        request.flush();
        request.connected = false;
    }

    Connections {
        target: root.areaPicker

        function onRegionPicked(output: string, region: rect): void {
            const request = root.regionRequest;
            root.regionRequest = null;
            if (!request?.connected)
                return;
            root.submit(request, `region:${output}@${region.x},${region.y},${region.width},${region.height}`, root.regionToken);
        }

        function onRegionAbandoned(): void {
            const request = root.regionRequest;
            root.regionRequest = null;
            if (request)
                request.picking = false;
        }
    }

    SocketServer {
        id: server

        // A nested compositor shares the runtime directory with the desktop
        // that started it and must not answer for the real session.
        active: Quickshell.env("HYPRSTACK_NESTED") !== "1"
        path: root.socketPath

        handler: Socket {
            id: connection

            property var windows: []
            property bool allowToken
            property bool asked
            property bool picking

            parser: SplitParser {
                splitMarker: "\n"

                onRead: line => {
                    // One request per connection; anything further is a
                    // caller that misunderstood the exchange.
                    if (connection.asked) {
                        connection.connected = false;
                        return;
                    }

                    try {
                        const question = JSON.parse(line);
                        connection.windows = question.windows ?? [];
                        connection.allowToken = question.allowToken === true;
                    } catch (error) {
                        connection.connected = false;
                        return;
                    }

                    connection.asked = true;
                    Overview.close(false);
                    WindowSwitcher.close();
                    ShellState.closeDrawers();
                    root.requests = [...root.requests, connection];
                }
            }

            onConnectionStateChanged: {
                if (connected)
                    return;
                if (root.regionRequest === connection)
                    root.regionRequest = null;
                root.requests = root.requests.filter(request => request !== connection);
            }
        }
    }

    Instantiator {
        model: ScriptModel {
            values: [...root.requests]
        }

        SharePickerDialog {
            required property var modelData

            sharePicker: root
            request: modelData
            // Evaluated while the dialog is being built, before it takes a
            // surface, so the prompt never shows up on the wrong monitor.
            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
        }
    }

    IpcHandler {
        target: "sharepicker"

        function status(): string {
            return JSON.stringify({listening: root.listening, path: root.socketPath, pending: root.requests.length});
        }
    }
}
