import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Services

Scope {
    id: root

    readonly property list<var> warnLevels: [...GlobalConfig.general.battery.warnLevels.values].sort((a, b) => a.level - b.level)
    property real lastPercentage: 100
    readonly property real percentage: UPower.displayDevice.percentage * 100
    readonly property bool criticalBattery: UPower.displayDevice.ready && UPower.onBattery
        && percentage <= GlobalConfig.general.battery.criticalLevel

    onCriticalBatteryChanged: {
        if (!criticalBattery) {
            hibernateTimer.stop();
            return;
        }
        Toaster.toast(Tr.tr("Hibernating in 5 seconds"), Tr.tr("Hibernating to prevent data loss"), "battery_android_alert", Toast.Error);
        hibernateTimer.restart();
    }

    function handleBatteryWarnings(): void {
        const p = percentage;

        if (!UPower.onBattery) {
            root.lastPercentage = p;
            return;
        }

        if (root.lastPercentage >= 0) {
            for (const level of root.warnLevels) {
                if (p <= level.level && root.lastPercentage > level.level) {
                    Toaster.toast(Tr.trMarked(level.title || Tr.tr("Battery warning")), Tr.trMarked(level.message || Tr.tr("Battery level is low")), level.icon || "battery_android_alert", level.critical ? Toast.Error : Toast.Warning);
                    break;
                }
            }
        }

        root.lastPercentage = p;
    }

    Connections {
        function onOnBatteryChanged(): void {
            if (!UPower.displayDevice.ready)
                return;

            if (UPower.onBattery) {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(Tr.tr("Charger unplugged"), Tr.tr("Battery is discharging"), "power_off");
                root.handleBatteryWarnings();
            } else {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(Tr.tr("Charger plugged in"), Tr.tr("Battery is charging"), "power");
                root.lastPercentage = 100;
            }
        }

        target: UPower
    }

    Connections {
        function onReadyChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Connections {
        function onPercentageChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Timer {
        id: hibernateTimer

        interval: 5000
        onTriggered: {
            if (root.criticalBattery)
                SessionManager.hibernate();
        }
    }
}
