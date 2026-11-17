pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Shared fluid surface for shell-owned dialogs. The background can splash
// outside the dialog; its content uses the very same liquid silhouette.
Item {
    id: root

    property color color: "transparent"
    property real radius: 0
    property alias border: background.border
    default property alias contents: content.data
    readonly property alias liquid: liquid

    StyledRect {
        id: background
        anchors.fill: parent
        color: root.color
        radius: root.radius
        visible: !liquid.goopy
    }

    StyledClippingRect {
        id: content
        anchors.fill: parent
        radius: liquid.maskingContent ? 0 : root.radius
    }

    GoopSurface {
        id: liquid
        objectName: "dialogGoopSurface"
        anchors.fill: parent
        paintColor: root.color
        cornerRadius: root.radius
        hoverTarget: root
        contentTarget: content
        floating: true
        nativeContentWhenSettled: true
        geometryRevision: Qt.rect(root.parent?.x ?? 0, root.parent?.y ?? 0,
            root.parent?.width ?? 0, root.parent?.height ?? 0)
        externalProgress: 1
        layerZ: -1
        panelOpen: root.visible && ((QsWindow.window as QsWindow)?.visible ?? false)
            && ((QsWindow.window as QsWindow)?.backingWindowVisible ?? false)
    }
}
