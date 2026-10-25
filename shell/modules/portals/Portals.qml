pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Portals
import qs.services

Scope {
    id: root

    readonly property bool registered: hostLoader.item?.registered ?? false
    readonly property var interfaces: hostLoader.item?.interfaces ?? []

    // A nested compositor shares the session bus with the desktop that started
    // it and must not take the backend name away from the real shell.
    LazyLoader {
        id: hostLoader

        active: Quickshell.env("HYPRSTACK_NESTED") !== "1"

        Scope {
            id: hostScope

            readonly property bool registered: host.registered
            readonly property var interfaces: host.interfaces

            PortalHost {
                id: host

                SettingsPortal {
                    // The committed scheme, not the preview: browsing themes
                    // must not repaint every application on the desktop.
                    colourScheme: Colours.currentLight ? SettingsPortal.Light : SettingsPortal.Dark
                    // The key colour of the palette rather than the primary
                    // role: applications derive their own light and dark
                    // variants and expect the accent itself to hold still.
                    accentColour: Colours.current.m3primary_paletteKeyColor
                }

                FileChooserPortal {
                    id: fileChooser
                }

                AccessPortal {
                    id: access
                }

                AppChooserPortal {
                    id: appChooser
                }
            }

            FileChooser {
                portal: fileChooser
            }

            Access {
                portal: access
            }

            AppChooser {
                portal: appChooser
            }
        }
    }

    IpcHandler {
        target: "portals"

        function status(): string {
            return JSON.stringify({registered: root.registered, interfaces: root.interfaces});
        }
    }
}
