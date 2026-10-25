pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Portals
import qs.services

Scope {
    id: root

    required property WallpaperPortal portal

    // Hyprstack keeps a single wallpaper, shown on the desktop and behind
    // the lock screen alike, so every target lands in the same place.
    function apply(request: WallpaperRequest): void {
        Wallpapers.setWallpaper(request.path);
        request.accept();
    }

    Instantiator {
        model: ScriptModel {
            values: [...root.portal.requests]
        }

        WallpaperDialog {
            required property WallpaperRequest modelData

            request: modelData
            // Evaluated while the dialog is being built, before it takes a
            // surface, so the preview never shows up on the wrong monitor.
            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

            Component.onCompleted: {
                // A picture the shell cannot open is nothing to offer.
                if (!modelData.path) {
                    modelData.reject();
                    return;
                }
                // Without a preview there is nothing to show, and the
                // desktop portal has already asked whether this is allowed.
                if (!modelData.showPreview) {
                    root.apply(modelData);
                    return;
                }
                Overview.close(false);
                WindowSwitcher.close();
                ShellState.closeDrawers();
            }
        }
    }
}
