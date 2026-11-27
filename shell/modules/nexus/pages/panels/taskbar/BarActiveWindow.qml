pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Workspace windows")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: Tr.tr("Icon only")
            checked: Config.bar.activeWindow.compact
            onToggled: GlobalConfig.bar.activeWindow.compact = checked
        }

        ToggleRow {
            text: Tr.trCtx("Inverted", "taskbar active window: swap the title and class order")
            checked: Config.bar.activeWindow.inverted
            onToggled: GlobalConfig.bar.activeWindow.inverted = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Show on hover")
            subtext: Tr.tr("Open the workspace window list on hover")
            checked: Config.bar.activeWindow.showOnHover && Config.bar.popouts.activeWindow
            onToggled: {
                GlobalConfig.bar.activeWindow.showOnHover = checked;
                if (checked)
                    GlobalConfig.bar.popouts.activeWindow = true;
            }
        }
    }
}
