pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack.Components
import Hyprstack.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property Workspace activeWs
    required property Item mask

    property real start
    property real end
    property bool initialized: false
    property int lastWorkspace: 0
    objectName: "workspaceActiveIndicator"
    readonly property alias liquid: liquid
    readonly property bool fluidMotion: liquid.goopy
    property real targetStart: 0
    property real targetEnd: 0
    property real flowingStart: targetStart
    property real flowingEnd: targetEnd
    property bool backwards: false
    property bool liquidEffects: true
    property real geometryRevision: 0
    readonly property real leadingDuration: Math.round(Tokens.anim.durations.expressiveDefaultSpatial * 0.88)
    readonly property real trailingDuration: leadingDuration * (Config.bar.workspaces.activeTrail ? 1.5 : 1)
    // Independent interrupted edges must never collapse the filled capsule.
    readonly property real flowingHeight: Math.max(width, Math.abs(flowingEnd-flowingStart))

    function runAnim(): void {
        if (!activeWs)
            return;

        const newStart = activeWs.LazyListView.layoutY;
        const newHeight = activeWs.LazyListView.preferredHeight;
        if (!Number.isFinite(newStart) || !Number.isFinite(newHeight) || newHeight <= 0)
            return;
        if (fluidMotion) {
            // Retarget without stopping and restarting the easing on each
            // layout update. SmoothedAnimation preserves velocity on reversal.
            backwards = newStart+newHeight/2 < (flowingStart+flowingEnd)/2;
            targetStart = newStart;
            targetEnd = newStart+newHeight;
            lastWorkspace = activeWs.ws;
            initialized = true;
            return;
        }
        const goingUp = newStart < start;
        const leadingDuration = Tokens.anim.durations.expressiveDefaultSpatial;
        const trailingDuration = leadingDuration * (Config.bar.workspaces.activeTrail ? 1.5 : 1);

        startAnim.stop();
        endAnim.stop();
        startAnim.to = newStart;
        endAnim.to = newStart + activeWs.LazyListView.preferredHeight;
        startAnim.duration = goingUp ? leadingDuration : trailingDuration;
        endAnim.duration = goingUp ? trailingDuration : leadingDuration;
        startAnim.start();
        endAnim.start();
        lastWorkspace = activeWs.ws;
        initialized = true;
    }

    onActiveWsChanged: runAnim()
    onFluidMotionChanged: Qt.callLater(runAnim)
    Component.onCompleted: runAnim()
    onLiquidEffectsChanged: if (!liquidEffects) liquid?.clear()

    visible: initialized
    clip: true
    y: (fluidMotion ? (flowingStart+flowingEnd-flowingHeight)/2 : start) + mask.y
    implicitHeight: fluidMotion ? flowingHeight : end - start
    radius: Tokens.rounding.full
    color: Colours.palette.m3primary

    GoopSurface {
        id: liquid
        objectName: "workspaceLiquid"
        anchors.fill: parent
        visible: root.liquidEffects
        geometryRevision: root.geometryRevision
        paintColor: root.color
        cornerRadius: Math.min(width,height)/2
        externalProgress: 1
        panelOpen: root.visible && root.activeWs !== null
        automaticOpening: false
        preserveHost: true
        trackPulseMotion: true
        // A falling drop or a moving capsule must not resize its render target.
        stableField: true
        // The workspace list is rotated -90 degrees in the horizontal bar.
        anchorEdge: "right"
        hoverTarget: root
    }

    Anim on start {
        id: startAnim
        bounded: true
    }

    Behavior on flowingStart {
        enabled: root.fluidMotion && root.initialized
        SmoothedAnimation {
            velocity: -1
            duration: root.backwards ? root.leadingDuration : root.trailingDuration
            maximumEasingTime: root.leadingDuration/4
        }
    }

    Behavior on flowingEnd {
        enabled: root.fluidMotion && root.initialized
        SmoothedAnimation {
            velocity: -1
            duration: root.backwards ? root.trailingDuration : root.leadingDuration
            maximumEasingTime: root.leadingDuration/4
        }
    }

    Anim on end {
        id: endAnim
        bounded: true
    }

    Connections {
        function onLayoutYChanged(): void {
            root.runAnim();
        }

        function onPreferredHeightChanged(): void {
            root.runAnim();
        }

        target: root.activeWs?.LazyListView ?? null
    }

}
