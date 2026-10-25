pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Scope {
    id: root

    // One socket per Hyprland session, in the runtime directory, which is
    // the user's own: nothing else on the machine can ask for a secret or
    // read one back.
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/hyprstack-askpass-${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}.sock`
    readonly property bool listening: server.active
    property var requests: []

    function submit(request: var, secret: string): void {
        // Base64 keeps a passphrase with a newline or an unusual encoding in
        // it from running past the end of its own line.
        root.reply(request, { ok: true, secret: Qt.btoa(secret) });
    }

    function cancel(request: var): void {
        root.reply(request, { ok: false });
    }

    function reply(request: var, answer: var): void {
        request.write(`${JSON.stringify(answer)}\n`);
        request.flush();
        request.connected = false;
    }

    SocketServer {
        id: server

        // A nested compositor shares the runtime directory with the desktop
        // that started it and must not answer for the real session.
        active: Quickshell.env("HYPRSTACK_NESTED") !== "1"
        path: root.socketPath

        handler: Socket {
            id: connection

            property string prompt
            property bool asked

            parser: SplitParser {
                splitMarker: "\n"

                onRead: line => {
                    // One question per connection; anything further is a
                    // caller that misunderstood the exchange.
                    if (connection.asked) {
                        connection.connected = false;
                        return;
                    }

                    try {
                        connection.prompt = (JSON.parse(line).prompt ?? "").trim();
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
                if (!connected)
                    root.requests = root.requests.filter(request => request !== connection);
            }
        }
    }

    Instantiator {
        model: ScriptModel {
            values: [...root.requests]
        }

        AskpassDialog {
            required property var modelData

            askpass: root
            request: modelData
            // Evaluated while the dialog is being built, before it takes a
            // surface, so the prompt never shows up on the wrong monitor.
            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
        }
    }

    IpcHandler {
        target: "askpass"

        function status(): string {
            return JSON.stringify({listening: root.listening, path: root.socketPath, pending: root.requests.length});
        }
    }
}
