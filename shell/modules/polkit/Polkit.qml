pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Hyprstack.Config
import qs.services

Scope {
    id: root

    readonly property bool registered: agentLoader.item?.registered ?? false
    readonly property bool active: agentLoader.item?.active ?? false
    readonly property bool inputFocused: agentLoader.item?.inputFocused ?? false

    // Private compositor tests must not register an agent for the real login.
    LazyLoader {
        id: agentLoader

        active: Quickshell.env("HYPRSTACK_NESTED") !== "1" && GlobalConfig.services.polkitAgent

        Scope {
            id: agentScope

            readonly property bool registered: agent.isRegistered
            readonly property bool active: agent.isActive
            readonly property bool inputFocused: dialogLoader.item?.inputFocused ?? false
            property ShellScreen requestScreen

            PolkitAgent {
                id: agent

                path: "/org/hyprstack/PolkitAgent"

                onFlowChanged: {
                    if (!flow)
                        return;
                    agentScope.requestScreen = Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name)
                        ?? Quickshell.screens[0];
                    Overview.close(false);
                    WindowSwitcher.close();
                    ShellState.closeDrawers();
                }
            }

            LazyLoader {
                id: dialogLoader
                active: agent.isActive

                AuthDialog {
                    flow: agent.flow
                    screen: Quickshell.screens.includes(agentScope.requestScreen)
                        ? agentScope.requestScreen : Quickshell.screens[0]
                }
            }
        }
    }

    IpcHandler {
        target: "polkit"

        function status(): string {
            return JSON.stringify({registered: root.registered, active: root.active, inputFocused: root.inputFocused});
        }
    }
}
