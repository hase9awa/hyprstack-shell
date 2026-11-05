//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma IconTheme Adwaita

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import "modules/overview" as OverviewModule
import "modules/switcher" as SwitcherModule
import "modules/askpass" as AskpassModule
import "modules/bluetooth" as BluetoothModule
import "modules/polkit" as PolkitModule
import "modules/portals" as PortalsModule
import "modules/sharepicker" as SharePickerModule
import QtQuick
import Quickshell
import Hyprstack
import qs.services

ShellRoot {
    id: root

    settings.watchFiles: false

    Component.onCompleted: AnimationClock.activate()

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    GSFLoader {}
    ServiceLoader {}
    PolkitModule.Polkit {}
    AskpassModule.Askpass {}
    BluetoothModule.Pairing {}
    SharePickerModule.SharePicker {
        areaPicker: areaPicker
    }
    PortalsModule.Portals {}

    Background {}
    Drawers {}
    AreaPicker {
        id: areaPicker
    }
    Lock {
        id: lock
    }

    Shortcuts {}
    OverviewModule.OverviewWindows {}
    SwitcherModule.WindowSwitcher {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
