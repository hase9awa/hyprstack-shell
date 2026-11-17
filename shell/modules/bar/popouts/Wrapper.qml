pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Hyprstack.Config
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.windowinfo

Item {
    id: root
    property real flowOpacity: 1
    property bool flowClipped: false
    readonly property real visualOffsetScale: flowClipped ? 0 : offsetScale
    opacity: flowOpacity

    required property ShellScreen screen
    required property real offsetScale

    readonly property alias content: content
    readonly property alias winfo: winfo
    readonly property alias nexus: nexus

    readonly property real nonAnimWidth: children.find(c => c.shouldBeActive)?.implicitWidth ?? content.implicitWidth
    readonly property real nonAnimHeight: children.find(c => c.shouldBeActive)?.implicitHeight ?? content.implicitHeight
    readonly property Item current: (content.item as Content)?.current ?? null
    readonly property bool isDetached: detachedMode.length > 0

    property alias currentName: popoutState.currentName
    property alias hasCurrent: popoutState.hasCurrent
    property alias taskButton: popoutState.taskButton
    property alias trayItem: popoutState.trayItem
    readonly property int trayRevision: popoutState.trayRevision
    property real currentCenter

    property string detachedMode
    property string queuedMode

    // Dummy object so Tokens attached prop resolves to global config
    // Anim configs are not per-monitor
    readonly property QtObject dummy: QtObject {}
    property bool slowMotion: false
    readonly property string motionRole: `expressive${slowMotion ? "Slow" : "Default"}Spatial`
    readonly property int animLength: dummy.Tokens.anim.durations[motionRole]
    readonly property int geometryDuration: Math.round(animLength*.65)
    property real flowingWidth: nonAnimWidth
    property real flowingHeight: nonAnimHeight
    readonly property var animCurve: GlobalConfig.appearance.anim.shellPreset === "goop"
        ? dummy.Tokens.anim.expressiveDefaultEffects : dummy.Tokens.anim[motionRole]

    function setAnims(detach: bool): void {
        slowMotion = detach;
    }

    function detach(mode: string): void {
        setAnims(true);
        if (mode === "winfo") {
            detachedMode = mode;
        } else {
            queuedMode = mode;
            detachedMode = "any";
        }
        setAnims(false);
        focus = true;
    }

    function close(): void {
        hasCurrent = false;
        detachedMode = "";
    }

    implicitWidth: flowClipped ? flowingWidth : nonAnimWidth
    implicitHeight: flowClipped ? flowingHeight : nonAnimHeight

    Behavior on flowingWidth {
        enabled: root.flowClipped && root.offsetScale<1
        SmoothedAnimation { velocity: -1; duration: root.geometryDuration; maximumEasingTime: root.geometryDuration/3 }
    }
    Behavior on flowingHeight {
        enabled: root.flowClipped && root.offsetScale<1
        SmoothedAnimation { velocity: -1; duration: root.geometryDuration; maximumEasingTime: root.geometryDuration/3 }
    }

    focus: hasCurrent
    Keys.onEscapePressed: {
        // Forward escape to password popout if active, otherwise close
        if (currentName === "wirelesspassword" && content.item) {
            const passwordPopout = (content.item as Content)?.children.find(c => c.name === "wirelesspassword");
            if (passwordPopout && passwordPopout.item) {
                passwordPopout.item.closeDialog();
                return;
            }
        }
        close();
    }

    Keys.onPressed: event => {
        // Don't intercept keys when password popout is active - let it handle them
        if (currentName === "wirelesspassword") {
            event.accepted = false;
        }
    }

    PopoutState {
        id: popoutState

        screen: root.screen

        onDetachRequested: mode => root.detach(mode)
    }

    HyprlandFocusGrab {
        active: root.isDetached
        windows: [QsWindow.window]
        onCleared: root.close()
    }

    Binding {
        when: root.isDetached || (root.hasCurrent && root.currentName === "wirelesspassword")

        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    Comp {
        id: content

        shouldBeActive: !root.detachedMode && (root.hasCurrent || (root.currentName === "tasks" && root.offsetScale < 1))
        spatialOnly: root.currentName === "tasks"
        anchors.fill: parent

        sourceComponent: Content {
            popouts: popoutState
        }
    }

    Comp {
        id: winfo

        shouldBeActive: root.detachedMode === "winfo"
        anchors.centerIn: parent

        sourceComponent: WindowInfo {
            screen: root.screen
            client: Hypr.activeToplevelFor(root.screen)
        }
    }

    Comp {
        id: nexus

        shouldBeActive: root.detachedMode === "any"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            radius: Tokens.rounding.extraLarge
            implicitWidth: nexusInner.implicitWidth
            implicitHeight: nexusInner.implicitHeight

            Nexus {
                id: nexusInner

                anchors.fill: parent
                nState.screen: root.screen
                nState.animatingContainer: nexus.opacity < 1
                nState.currentPageIdx: ["appearance", "network", "bluetooth", "audio"].indexOf(root.queuedMode)
                onClose: root.close()
            }
        }
    }

    Behavior on implicitWidth {
        enabled: !root.flowClipped
        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    Behavior on implicitHeight {
        enabled: root.offsetScale < 1 && !root.flowClipped

        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    component Comp: Loader {
        id: comp

        property bool shouldBeActive
        property bool spatialOnly

        active: false
        opacity: 0

        // Makes the loader load on the same frame shouldBeActive becomes true, which ensures size is set
        states: State {
            name: "active"
            when: comp.shouldBeActive

            PropertyChanges {
                comp.opacity: 1
                comp.active: true
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                        duration: comp.spatialOnly ? 0 : GlobalConfig.appearance.anim.shellPreset === "goop"
                            ? root.animLength : comp.Tokens.anim.durations.expressiveDefaultEffects
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                        duration: comp.spatialOnly ? 0 : GlobalConfig.appearance.anim.shellPreset === "goop"
                            ? root.animLength : comp.Tokens.anim.durations.expressiveDefaultEffects
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }
}
