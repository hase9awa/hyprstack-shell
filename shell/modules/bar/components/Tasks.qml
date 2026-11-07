pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.popouts as BarPopouts

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property real maxWidth
    required property BarPopouts.Wrapper popouts
    readonly property alias buttons: taskRepeater
    readonly property var appEntries: DesktopEntries.applications.values
    property Item popupTask: null
    property string draggedKey: ""
    property string dropKey: ""
    property bool dropAfter
    property real dragX
    property string dragName
    property string dragIcon
    property real dragWidth
    property string lastTargets: ""
    readonly property real buttonHeight: Math.max(0, height - Tokens.padding.extraSmall * 2 - 4 * Tokens.scale)
    readonly property real buttonInset: (height - buttonHeight) / 2
    readonly property Item selectionButton: {
        let active = null;
        for (let i = 0; i < taskRepeater.count; ++i) {
            const button = taskRepeater.itemAt(i);
            if (button?.active) active = button;
        }
        return active;
    }

    function lookup(app: string): var {
        return appEntries.find(e => !!e.startupClass && e.startupClass.toLowerCase() === app.toLowerCase())
            ?? DesktopEntries.heuristicLookup(app)
            ?? DesktopEntries.heuristicLookup(app.replace(/-browser$/, ""))
            ?? DesktopEntries.heuristicLookup(app.replace(/\.desktop$/, "").split(".").pop());
    }

    function updateDrag(x: real): void {
        dragX = Math.max(0, Math.min(width - dragWidth, x - dragWidth / 2));
        dropKey = "";
        for (let i = 0; i < taskRepeater.count; i++) {
            const button = taskRepeater.itemAt(i);
            if (!button || button.group.key === draggedKey) continue;
            const start = button.mapToItem(root, 0, 0).x;
            dropKey = button.group.key;
            dropAfter = x > start + button.width / 2;
            if (!dropAfter) break;
        }
    }

    function finishDrag(): void {
        const key = draggedKey, target = dropKey, after = dropAfter;
        draggedKey = dropKey = "";
        Qt.callLater(() => Taskbar.move(key, target, after, groups.map(g => g.key)));
    }

    function reportTargets(): void {
        if (!Hypr.stacking || !visible || !QsWindow.window) return;
        const targets = [];
        const monitor = Hypr.monitorFor(screen)?.lastIpcObject;
        const originX = monitor?.x ?? screen.x, originY = monitor?.y ?? screen.y;
        const barTop = originY + mapToItem(QsWindow.window.contentItem, 0, 0).y;
        for (let i = 0; i < taskRepeater.count; i++) {
            const button = taskRepeater.itemAt(i);
            if (!button) continue;
            const p = button.mapToItem(QsWindow.window.contentItem, 0, buttonInset);
            for (const window of button.windows) {
                const client = Hypr.clientData(window);
                if (!client) continue;
                targets.push({ address: client.address, id: client.stableId,
                    x: Math.round(originX + p.x), y: Math.round(originY + p.y),
                    w: Math.round(button.width), h: buttonHeight, barTop: Math.round(barTop) });
            }
        }
        const data = JSON.stringify(targets);
        if (data !== lastTargets) {
            lastTargets = data;
            Hypr.setTaskTargets(screen.name, targets);
        }
    }

    function closePopup(): void {
        if (popupTask)
            popupTask.popupOpen = false;
        popupTask = null;
        if (popouts.currentName === "tasks")
            popouts.close();
    }

    onVisibleChanged: {
        if (!visible) {
            closePopup(); draggedKey = dropKey = "";
            Hypr.setTaskTargets(screen.name, []);
        }
        lastTargets = "";
    }
    onGroupsChanged: Qt.callLater(reportTargets)
    onWidthChanged: Qt.callLater(reportTargets)
    readonly property var groups: {
        const groups = new Map();
        const windows = Hypr.taskWindows(screen).slice().sort((a, b) =>
            Hypr.clientData(a).stableId.localeCompare(Hypr.clientData(b).stableId));
        for (const window of windows) {
            const app = Hypr.clientData(window).class;
            const entry = lookup(app);
            const key = entry?.id ?? app.toLowerCase();
            if (!groups.has(key))
                groups.set(key, { app: app, key: key, entry: entry, windows: [] });
            groups.get(key).windows.push(window);
        }
        for (const key of Taskbar.pinned) {
            if (groups.has(key)) continue;
            const entry = DesktopEntries.byId(key) ?? lookup(key);
            if (entry) groups.set(key, { app: key, key: key, entry: entry, windows: [] });
        }
        return Array.from(groups.values()).sort((a, b) => {
            const ai = Taskbar.order.indexOf(a.key), bi = Taskbar.order.indexOf(b.key);
            return (ai < 0 ? 100000 : ai) - (bi < 0 ? 100000 : bi);
        });
    }

    implicitWidth: Math.min(maxWidth, taskRow.implicitWidth + Tokens.padding.extraSmall * 2)
    implicitHeight: 40 * Tokens.scale
    radius: Tokens.rounding.full
    color: "transparent"

    GroupBackground {}

    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: root.visible && Hypr.stacking
        onTriggered: root.reportTargets()
    }

    Flickable {
        id: taskFlickable
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.extraSmall
        anchors.rightMargin: Tokens.padding.extraSmall
        contentWidth: taskRow.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        StyledRect {
            id: selection
            property real start
            property real end

            function runAnim(): void {
                const button = root.selectionButton;
                if (!button) return;
                const newStart = button.x;
                const movingLeft = newStart < start;
                const leading = Tokens.anim.durations.expressiveDefaultSpatial;
                const trailing = leading * (Config.bar.workspaces.activeTrail ? 1.5 : 1);
                startAnim.stop(); endAnim.stop();
                startAnim.to = newStart;
                endAnim.to = newStart + button.width;
                startAnim.duration = movingLeft ? leading : trailing;
                endAnim.duration = movingLeft ? trailing : leading;
                startAnim.start(); endAnim.start();
            }

            x: start
            y: root.buttonInset
            width: Math.max(0, end - start)
            height: root.buttonHeight
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
            visible: !!root.selectionButton
            Anim on start { id: startAnim }
            Anim on end { id: endAnim }
            Connections {
                target: root
                function onSelectionButtonChanged(): void { Qt.callLater(selection.runAnim); }
            }
            Connections {
                target: root.selectionButton
                function onXChanged(): void { selection.runAnim(); }
                function onWidthChanged(): void { selection.runAnim(); }
            }
            Component.onCompleted: Qt.callLater(runAnim)
        }

        Row {
            id: taskRow
            spacing: Tokens.spacing.extraSmall

            Repeater {
                id: taskRepeater
                model: ScriptModel { values: root.groups.map(g => g.app) }

                delegate: Item {
                    id: task

                    required property string modelData
                    readonly property var group: root.groups.find(g => g.app === modelData)
                    readonly property var windows: group?.windows ?? []
                    readonly property bool active: windows.some(w => w === Hypr.activeToplevel && !Hypr.isMinimized(w))
                    readonly property bool minimizing: windows.some(w => Hypr.windowState(w).minimized?.animating)
                    readonly property bool emphasized: root.selectionButton === task
                    readonly property bool allMinimized: windows.length > 0 && windows.every(w => Hypr.isMinimized(w))
                    readonly property bool pinned: Taskbar.pinned.includes(group.key)
                    readonly property var entry: group?.entry
                    readonly property string iconSource: entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""
                    property bool popupOpen
                    property bool menuMode
                    readonly property bool previewOpen: root.popouts.hasCurrent && root.popouts.currentName === "tasks" && root.popouts.taskButton === task
                    readonly property bool hovered: mouse.containsMouse || popupOpen || previewOpen
                    readonly property alias pinControl: pinButton
                    onPopupOpenChanged: if (!popupOpen && root.popupTask === task) root.popupTask = null

                    width: Math.min(210 * Tokens.scale, Math.max(100 * Tokens.scale, (root.maxWidth - Tokens.padding.extraSmall * 2
                        - (root.groups.length - 1) * taskRow.spacing) / Math.max(1, root.groups.length)))
                    height: root.implicitHeight
                    opacity: root.draggedKey === group.key ? 0.35 : 1

                    StyledRect {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.buttonInset
                        width: parent.width
                        height: root.buttonHeight
                        radius: Tokens.rounding.full
                        color: task.hovered ? Qt.alpha(task.emphasized ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface, 0.12)
                            : Config.bar.workspaces.occupiedBg && !task.emphasized && !task.allMinimized
                                ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : "transparent"
                    }

                    function showPopup(menu: bool): void {
                        if (root.draggedKey || (!menu && windows.length === 0)) return;
                        hoverTimer.stop();
                        closeTimer.stop();
                        if (!menu) {
                            if (root.popupTask?.menuMode) return;
                            menuMode = false;
                            root.popouts.taskButton = task;
                            root.popouts.currentName = "tasks";
                            root.popouts.currentCenter = Qt.binding(() => task.mapToItem(root.parent, task.width / 2, 0).x);
                            root.popouts.hasCurrent = true;
                            return;
                        }
                        root.closePopup();
                        menuMode = menu;
                        popupOpen = true;
                        root.popupTask = task;
                    }

                    function act(operation: string, window: HyprlandToplevel): void {
                        hoverTimer.stop();
                        closeTimer.stop();
                        root.reportTargets();
                        root.closePopup();
                        Hypr.windowAction(operation, window);
                    }

                    function clickAction(): var {
                        const ordered = windows.slice().sort((a, b) =>
                            (a.lastIpcObject.focusHistoryID < 0 ? 100000 : a.lastIpcObject.focusHistoryID)
                            - (b.lastIpcObject.focusHistoryID < 0 ? 100000 : b.lastIpcObject.focusHistoryID));
                        const current = ordered.find(w => w === Hypr.activeToplevel && !Hypr.isMinimized(w));
                        if (ordered.length === 1)
                            return { operation: "task-click", window: ordered[0] };
                        // Click activates the most recently used window. Clicking
                        // an active group cycles; hover still offers every preview.
                        return { operation: "activate", window: current ? ordered[1] : ordered[0] };
                    }

                    function launch(): void {
                        root.closePopup();
                        entry?.execute();
                    }

                    IconImage {
                        id: appIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 9 * Tokens.scale
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 20 * Tokens.scale
                        visible: !!task.iconSource && status !== Image.Error
                        source: task.iconSource
                        opacity: task.allMinimized ? 0.55 : 1
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    MaterialIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 9 * Tokens.scale
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20 * Tokens.scale
                        visible: !appIcon.visible
                        text: Icons.getAppCategoryIcon(task.entry?.id ?? task.modelData, "apps")
                        color: task.emphasized ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        Behavior on color { CAnim {} }
                        opacity: task.allMinimized ? 0.55 : 1
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 37 * Tokens.scale
                        anchors.right: parent.right
                        anchors.rightMargin: (task.windows.length > 1 ? 39 : 9) * Tokens.scale
                        anchors.verticalCenter: parent.verticalCenter
                        text: task.entry?.name ?? task.modelData
                        elide: Text.ElideRight
                        font: Tokens.font.body.small
                        color: task.emphasized ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        Behavior on color { CAnim {} }
                        opacity: task.allMinimized ? 0.65 : 1
                    }

                    Item {
                        id: multiplicity
                        objectName: "taskMultiplicity"
                        readonly property int count: Math.min(task.windows.length, 3)
                        readonly property color ink: task.emphasized ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        anchors.right: parent.right
                        anchors.rightMargin: 10 * Tokens.scale
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24 * Tokens.scale
                        height: 20 * Tokens.scale
                        visible: task.windows.length > 1
                        opacity: task.allMinimized ? 0.55 : 1

                        Repeater {
                            model: multiplicity.count
                            Rectangle {
                                required property int index
                                x: index * 4
                                y: (multiplicity.count - index - 1) * 4
                                width: 15 * Tokens.scale
                                height: 12 * Tokens.scale
                                radius: 3 * Tokens.scale
                                color: task.emphasized ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer
                                border.width: 1.5
                                border.color: multiplicity.ink
                                Behavior on color { CAnim {} }

                                Rectangle {
                                    x: 3
                                    y: 3
                                    width: parent.width - 6
                                    height: 1 * Tokens.scale
                                    color: multiplicity.ink
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        property point pressPoint
                        property bool dragged
                        property var pressedAction: null
                        onEntered: {
                            closeTimer.stop();
                            if (!root.draggedKey && !root.popupTask?.menuMode)
                                hoverTimer.restart();
                        }
                        onExited: { hoverTimer.stop(); if (!task.menuMode) closeTimer.restart(); }
                        onPressed: event => {
                            pressPoint = Qt.point(event.x, event.y);
                            dragged = false;
                            hoverTimer.stop();
                            pressedAction = event.button === Qt.LeftButton ? task.clickAction() : null;
                        }
                        onPositionChanged: event => {
                            if (!(pressedButtons & Qt.LeftButton)) return;
                            if (!dragged && Math.abs(event.x - pressPoint.x) > 6) {
                                dragged = true;
                                root.closePopup();
                                hoverTimer.stop();
                                root.draggedKey = task.group.key;
                                root.dragName = task.entry?.name ?? task.modelData;
                                root.dragIcon = task.iconSource;
                                root.dragWidth = task.width;
                            }
                            if (dragged) root.updateDrag(task.mapToItem(root, event.x, event.y).x);
                        }
                        onReleased: if (dragged) root.finishDrag()
                        onCanceled: { root.draggedKey = root.dropKey = ""; pressedAction = null; }
                        onClicked: event => {
                            if (dragged) return;
                            if (event.button === Qt.RightButton) {
                                task.showPopup(true);
                            } else if (task.windows.length === 0) {
                                task.launch();
                            } else if (event.button === Qt.MiddleButton) {
                                const window = task.windows.find(w => w === Hypr.activeToplevel) ?? task.windows[0];
                                task.act("close", window);
                            } else {
                                const action = pressedAction ?? task.clickAction();
                                if (action.window) task.act(action.operation, action.window);
                            }
                            pressedAction = null;
                        }
                        onWheel: event => {
                            if (task.windows.length === 0) return;
                            const current = task.windows.findIndex(w => w === Hypr.activeToplevel);
                            const next = (current + (event.angleDelta.y > 0 ? 1 : -1) + task.windows.length) % task.windows.length;
                            task.act("activate", task.windows[next]);
                            event.accepted = true;
                        }
                    }

                    Timer {
                        id: hoverTimer
                        interval: 400
                        onTriggered: task.showPopup(false)
                    }

                    Timer {
                        id: closeTimer
                        interval: 250
                        onTriggered: {
                            if (!popupHover.hovered && !mouse.containsMouse) task.popupOpen = false;
                            if (task.previewOpen && !root.popouts.parent.hovered && !mouse.containsMouse) root.popouts.close();
                        }
                    }

                    PopupWindow {
                        id: popup
                        anchor.item: task
                        anchor.edges: Edges.Top
                        anchor.gravity: Edges.Top
                        anchor.rect.y: -8
                        anchor.rect.width: task.width
                        visible: task.popupOpen && task.menuMode && Hypr.stacking
                        grabFocus: task.menuMode
                        onVisibleChanged: if (!visible) task.popupOpen = false
                        color: "transparent"
                        implicitWidth: Math.min(root.screen.width - 24 * Tokens.scale, 300 * Tokens.scale)
                        implicitHeight: menuColumn.implicitHeight + 24 * Tokens.scale

                        Rectangle {
                            anchors.fill: parent
                            color: Colours.palette.m3surfaceContainerLow
                            border.color: Colours.palette.m3outlineVariant
                            border.width: 1
                            radius: Tokens.rounding.large
                            focus: true
                            Keys.onEscapePressed: task.popupOpen = false

                            HoverHandler {
                                id: popupHover
                                onHoveredChanged: {
                                    if (hovered) closeTimer.stop();
                                    else if (!task.menuMode) closeTimer.restart();
                                }
                            }

                            Column {
                                id: menuColumn
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 12 * Tokens.scale
                                visible: task.menuMode
                                spacing: 4 * Tokens.scale

                                StyledText {
                                    width: parent.width
                                    text: task.entry?.name ?? task.modelData
                                    elide: Text.ElideRight
                                    font: Tokens.font.body.medium
                                }

                                TaskMenuButton {
                                    id: pinButton
                                    objectName: "taskPinButton"
                                    width: parent.width
                                    visible: !!task.entry
                                    text: task.pinned ? Tr.tr("Unpin from taskbar") : Tr.tr("Pin to taskbar")
                                    onClicked: {
                                        root.closePopup();
                                        Taskbar.togglePin(task.group.key);
                                    }
                                }

                                TaskMenuButton {
                                    width: parent.width
                                    visible: !!task.entry
                                    text: Tr.tr("Open new window")
                                    onClicked: task.launch()
                                }

                                Repeater {
                                    model: ScriptModel { values: task.windows }
                                    delegate: Column {
                                        id: menuWindow
                                        required property HyprlandToplevel modelData
                                        width: menuColumn.width
                                        spacing: 4 * Tokens.scale
                                        StyledText {
                                            width: parent.width
                                            text: menuWindow.modelData?.title ?? ""
                                            elide: Text.ElideRight
                                            font: Tokens.font.body.small
                                            color: Colours.palette.m3onSurfaceVariant
                                        }
                                        Row {
                                            spacing: 6 * Tokens.scale
                                            WindowButton { icon: "open_in_full"; onClicked: task.act("activate", menuWindow.modelData) }
                                            WindowButton { icon: "minimize"; onClicked: task.act("minimize", menuWindow.modelData) }
                                            WindowButton { icon: Hypr.isMaximized(menuWindow.modelData) ? "filter_none" : "crop_square"; onClicked: task.act("maximize", menuWindow.modelData) }
                                            WindowButton { icon: "close"; danger: true; onClicked: task.act("close", menuWindow.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        z: 10
        visible: !!root.draggedKey
        x: root.dragX
        y: root.buttonInset
        width: root.dragWidth
        height: root.buttonHeight
        color: Colours.palette.m3surfaceContainerHighest
        radius: Tokens.rounding.full
        border.color: Colours.palette.m3primary
        IconImage {
            anchors.left: parent.left
            anchors.leftMargin: 9 * Tokens.scale
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 20 * Tokens.scale
            source: root.dragIcon
        }
        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 37 * Tokens.scale
            anchors.right: parent.right
            anchors.rightMargin: 9 * Tokens.scale
            anchors.verticalCenter: parent.verticalCenter
            text: root.dragName
            elide: Text.ElideRight
            font: Tokens.font.body.small
        }
    }

    Rectangle {
        z: 11
        visible: !!root.draggedKey && !!root.dropKey
        y: root.buttonInset
        x: {
            const index = root.groups.findIndex(g => g.key === root.dropKey);
            const button = taskRepeater.itemAt(index);
            return button ? button.mapToItem(root, 0, 0).x + (root.dropAfter ? button.width + 2 : -4) : 0;
        }
        width: 2 * Tokens.scale
        height: root.buttonHeight
        color: Colours.palette.m3primary
    }

    component TaskMenuButton: Rectangle {
        required property string text
        signal clicked
        implicitHeight: 34 * Tokens.scale
        radius: Tokens.rounding.small
        color: click.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"
        StyledText {
            anchors.fill: parent
            anchors.leftMargin: 6 * Tokens.scale
            verticalAlignment: Text.AlignVCenter
            text: parent.text
            font: Tokens.font.body.small
        }
        MouseArea {
            id: click
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component WindowButton: Rectangle {
        required property string icon
        property bool danger
        signal clicked
        width: 38 * Tokens.scale
        height: 30 * Tokens.scale
        radius: Tokens.rounding.small
        color: buttonMouse.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"
        MaterialIcon {
            anchors.centerIn: parent
            text: parent.icon
            color: parent.danger ? Colours.palette.m3error : Colours.palette.m3onSurface
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
