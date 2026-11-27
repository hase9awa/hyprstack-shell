pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property var bar

    readonly property var client: Hypr.activeToplevelFor(bar.screen)
    readonly property bool opensOnHover: Config.bar.activeWindow.showOnHover && Config.bar.popouts.activeWindow
    readonly property bool opened: bar.popouts.hasCurrent && bar.popouts.currentName === "workspacewindows"
    readonly property string windowTitle: {
        const title = client?.title;
        if (!title)
            return Tr.trCtx("Desktop", "shown when no window is focused");
        if (Config.bar.activeWindow.compact) {
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    property Title current: text1

    function open(): void {
        if (opened)
            return;
        bar.popouts.currentName = "workspacewindows";
        bar.popouts.currentCenter = root.parent.x + root.width / 2;
        bar.popouts.hasCurrent = true;
    }

    function toggle(): void {
        if (opened)
            bar.popouts.close();
        else
            open();
    }

    implicitWidth: Math.min(bar.taskbarWidth, icon.implicitWidth + current.implicitWidth + Tokens.spacing.small)
    implicitHeight: bar.height
    clip: true

    Accessible.role: Accessible.Button
    Accessible.name: windowTitle
    Accessible.onPressAction: toggle()

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    TapHandler {
        onTapped: root.toggle()
    }

    MaterialIcon {
        id: icon

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        animate: true
        text: Icons.getAppCategoryIcon(root.client?.lastIpcObject.class, "desktop_windows")
        color: Colours.palette.m3primary
    }

    Title { id: text1 }
    Title { id: text2 }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: Math.max(0, root.bar.taskbarWidth - icon.width - root.Tokens.spacing.small)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    Behavior on implicitWidth {
        Anim {}
    }

    component Title: StyledText {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: icon.right
        anchors.leftMargin: Tokens.spacing.small

        font: metrics.font
        color: Colours.palette.m3primary
        opacity: root.current === this ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
