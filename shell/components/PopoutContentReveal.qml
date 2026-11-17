pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config

// Let each newly loaded row enter with the same fade and soft scale as Wi-Fi.
// Temporary bindings restore the row's own opacity and scale afterwards.
Item {
    id: root

    required property Item target
    property bool active: false
    property int revision: 0
    property var entries: []
    property real deadline: 0
    property int serial: 0
    readonly property int count: entries.length
    objectName: "popoutContentReveal"

    function rowsFor(item: Item): var {
        if (!item)
            return [];
        if (item.positionViewAtIndex !== undefined && item.contentItem)
            return item.contentItem.children.filter(c => c.visible && c.width > 0 && c.height > 1);
        if (item.push !== undefined && item.currentItem)
            return rowsFor(item.currentItem);
        const children = item.children.filter(c => c.visible && c.width > 0 && c.height > 0);
        if (children.length === 1 && children[0].spacing !== undefined)
            return rowsFor(children[0]);
        let rows = [];
        for (const child of children) {
            if (child.positionViewAtIndex !== undefined && child.contentItem)
                rows = rows.concat(rowsFor(child));
            else
                rows.push(child);
        }
        return rows;
    }

    function finish(): void {
        scan.stop();
        for (const entry of entries)
            entry.effect.finish();
        entries = [];
    }

    function restart(): void {
        finish();
        if (!active || !target)
            return;
        ++serial;
        deadline = Date.now() + 500;
        collect();
        scan.start();
    }

    function collect(): void {
        if (!active || !target)
            return;
        const added = [];
        for (const row of rowsFor(target)) {
            if (entries.some(e => e.item === row))
                continue;
            const effect = appearance.createObject(root, {
                target: row, restingOpacity: row.opacity, restingScale: row.scale,
                delay: Math.min((entries.length + added.length) * 16, 80)
            });
            added.push({item: row, effect: effect});
        }
        if (added.length)
            entries = entries.concat(added);
    }

    onActiveChanged: active ? Qt.callLater(restart) : finish()
    onTargetChanged: Qt.callLater(restart)
    onRevisionChanged: Qt.callLater(restart)
    Component.onCompleted: Qt.callLater(restart)

    Connections {
        target: root.target
        ignoreUnknownSignals: true
        function onCurrentItemChanged(): void { Qt.callLater(root.restart); }
    }

    Timer {
        id: scan
        interval: 16
        repeat: true
        onTriggered: {
            root.collect();
            if (Date.now() >= root.deadline)
                stop();
        }
    }

    Component {
        id: appearance
        Item {
            id: entry
            required property Item target
            required property real restingOpacity
            required property real restingScale
            required property int delay
            property real fade: 0
            property real growth: 0
            property bool playing: true

            function finish(): void {
                motion.stop();
                playing = false;
                destroy();
            }

            Binding {
                target: entry.target
                property: "opacity"
                when: entry.playing && entry.target !== null
                value: entry.restingOpacity * entry.fade
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: entry.target
                property: "scale"
                when: entry.playing && entry.target !== null
                value: entry.restingScale * (0.7 + 0.3 * entry.growth)
                restoreMode: Binding.RestoreBindingOrValue
            }
            SequentialAnimation {
                id: motion
                running: true
                PauseAnimation { duration: entry.delay }
                ParallelAnimation {
                    Anim { target: entry; property: "fade"; from: 0; to: 1; type: Anim.DefaultEffects }
                    Anim { target: entry; property: "growth"; from: 0; to: 1 }
                }
                onFinished: entry.playing = false
            }
        }
    }
}
