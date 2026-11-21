pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import qs.components
import qs.components.images
import qs.services

StyledRect {
    id: root

    color: Colours.palette.m3surfaceContainer

    property string source: Wallpapers.current
    property CachingImage current

    readonly property CachingImage spare: current === first ? second : first

    onSourceChanged: Qt.callLater(syncSource)
    Component.onCompleted: Qt.callLater(syncSource)

    function syncSource(): void {
        fade.stop();
        if (!source) {
            current = null;
            first.path = second.path = "";
            return;
        }
        if (current)
            current.opacity = 1;
        spare.opacity = 0;
        spare.path = current?.path === source ? "" : source;
    }

    function showLayer(layer: CachingImage): void {
        if (layer === current || layer.path !== source)
            return;
        current = layer;
        fade.start();
    }

    component Layer: CachingImage {
        id: layer
        anchors.fill: parent
        opacity: 0
        z: root.current === layer ? 1 : 0
        cache: false
        onStatusChanged: {
            if (status === Image.Ready)
                root.showLayer(layer);
            else if (status === Image.Error && root.current !== layer)
                path = "";
        }
    }

    Layer { id: first }
    Layer { id: second }

    Anim {
        id: fade
        target: root.current
        property: "opacity"
        type: Anim.SlowEffects
        from: 0
        to: 1
        onFinished: root.spare.path = ""
    }
}
