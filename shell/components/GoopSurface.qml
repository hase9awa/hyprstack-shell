pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Hyprstack.Blobs
import Hyprstack.Config
import qs.services
import "../utils/vendor/goopui/core.js" as Upstream

Item {
    id: root
    property color paintColor: Colours.palette.m3primaryContainer
    property real cornerRadius: 0
    property real topLeftRadius: cornerRadius
    property real topRightRadius: cornerRadius
    property real bottomLeftRadius: cornerRadius
    property real bottomRightRadius: cornerRadius
    property bool panelOpen: false
    property bool automaticOpening: true
    property bool allowHoverDrip: true
    property Item hoverTarget: parent
    property string anchorEdge: "top"
    property Item escapeParent: null
    property real layerZ: 900
    property bool preserveHost: false
    property GoopFrameMask frameMask: null
    property bool keepFrameJoin: true
    property bool stableField: false
    property bool floating: false
    property var geometryRevision: 0
    property bool nativeContentWhenSettled: false
    property bool tearingDown: false
    property bool splashOnContentChange: false
    property bool trackPulseMotion: false
    property var morphBursts: []
    property int morphSerial: 0
    readonly property bool morphing: morphBursts.length>0
    property Item contentTarget: automaticOpening && !preserveHost ? hoverTarget : null
    property bool controlsContentMotion: false
    property var contentMaskSurface: root
    readonly property GoopLayer liquid: renderer.item
    readonly property var maskTexture: liquid?.maskTexture ?? null
    readonly property rect maskRect: allocation
    readonly property size maskSize: liquid?.fieldSize ?? Qt.size(1,1)
    readonly property Component contentEffect: contentReveal
    readonly property Item overlay: escapeParent ?? (QsWindow.window as QsWindow)?.contentItem ?? root
    readonly property bool goopy: GlobalConfig.appearance.anim.shellPreset === "goop"
        && GlobalConfig.appearance.anim.durations.scale>0 && !GameMode.enabled
    // ShaderEffectSource retains a window reference even when invisible.
    // Release those references before Quickshell deletes a dialog's backer.
    readonly property bool shaderLive: goopy && !tearingDown && (!floating || panelOpen)
    readonly property bool maskingContent: shaderLive && (!nativeContentWhenSettled || running
        || reshaping || morphing || progress < 0.999 || pendingOpening)
    property real externalProgress: -1
    property string contentKey
    property real presence: panelOpen ? 1 : 0
    property real age: 1
    property real reshape: 1
    property int serial: 0
    property int revision: 0
    property bool pendingOpening: false
    property int dripSerial: 0
    property var dripModel: null
    property rect allocation: Qt.rect(0,0,0,0)
    property size contentAllocation: Qt.size(0,0)
    readonly property bool running: flight.running
    readonly property bool reshaping: reshapeAnim.running
    readonly property bool hovering: hover.hovered
    readonly property bool hoverRequested: goopy && visible && allowHoverDrip && panelOpen
        && presence>0.98 && hovering
    readonly property bool dripping: { revision; return dripModel?.active ?? false; }
    readonly property var drips: { revision; return dripModel?.field.drips ?? []; }
    readonly property real progress: Math.max(0,Math.min(1,presence))
    readonly property real coreRate: Upstream.GoopCore.qtFlowDuration*1000
        /Math.max(1,Tokens.anim.durations.expressiveDefaultSpatial)
    readonly property real coreEnd: automaticOpening ? Upstream.GoopCore.qtAnimationEnd
        : Upstream.GoopCore.emergeMomentumEnd("open")
    readonly property bool active: shaderLive && visible && (running || reshaping || morphing || hoverRequested || dripping
        || (progress>0 && progress<1))
    readonly property var renderFrame: {
        revision;
        geometryRevision;
        parent?.x; parent?.y;
        width; height; externalProgress; progress;
        if(!goopy || !overlay || width<=0 || height<=0)
            return {body:{cx:0,cy:0,w:0,h:0},circles:[],content:1,panel:{x:0,y:0,width:1,height:1}};
        const geometry=targetGeometry();
        const f=frameMask?.innerRect;
        const band=!f?0:geometry.side==="bottom"?f.y:geometry.side==="top"?frameMask.height-f.y-f.height:
            geometry.side==="right"?f.x:frameMask.width-f.x-f.width;
        const result=Upstream.GoopCore.qtPanelFrame(geometry.rect,geometry.side,
            automaticOpening?progress:1,running?age*coreEnd:coreEnd,serial,
            !automaticOpening,reshaping?reshape*Upstream.GoopCore.emergeMomentumEnd("open"):-1,
            dripModel?.circles() ?? [],frameMask?.active ? {
                innerRect:{x:frameMask.innerRect.x,y:frameMask.innerRect.y,
                    width:frameMask.innerRect.width,height:frameMask.innerRect.height},
                overlap:Upstream.GoopCore.qtFilterParams.blur*3,keepJoined:keepFrameJoin,radius:cornerRadius,
                originInset:Math.min(Upstream.GoopCore.qtFilterParams.blur,Math.max(0,band/2)),
            }:floating ? {innerRect:geometry.rect,overlap:0,keepJoined:false,
                radius:cornerRadius,floating:true}:undefined);
        for(const burst of morphBursts)
            result.circles=result.circles.concat(Upstream.GoopCore.qtMorphCircles(
                burst.side,burst.age,burst.seed,burst.samples));
        return result;
    }
    readonly property var pose: {
        const b=renderFrame.body;
        return {x:b.cx-b.w/2,y:b.cy-b.h/2,width:b.w,height:b.h,radius:cornerRadius};
    }
    readonly property var frame: renderFrame.circles
    readonly property real contentOpacity: 1
    readonly property bool paintVisible: shaderLive && visible
        && (progress>0 || running || dripping || (!automaticOpening && panelOpen))

    enabled: false

    Binding {
        target: root.contentTarget?.layer ?? null
        property: "effect"
        when: root.maskingContent && root.contentTarget!==null
        value: root.contentEffect
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root.contentTarget?.layer ?? null
        property: "enabled"
        when: root.maskingContent && root.contentTarget!==null
        value: true
        restoreMode: Binding.RestoreBindingOrValue
    }
    // Retain native-resolution text textures while a tray menu changes size.
    // A matching logical sourceRect avoids stretching its glyphs.
    Binding {
        target: root.contentTarget?.layer ?? null
        property: "sourceRect"
        when: root.goopy && root.stableField && root.contentTarget!==null
        value: Qt.rect(0,0,Math.max(1,root.contentAllocation.width),Math.max(1,root.contentAllocation.height))
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root.contentTarget?.layer ?? null
        property: "textureSize"
        when: root.goopy && root.stableField && root.contentTarget!==null
        value: Qt.size(Math.max(1,Math.ceil(root.contentAllocation.width*Screen.devicePixelRatio)),
            Math.max(1,Math.ceil(root.contentAllocation.height*Screen.devicePixelRatio)))
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root.contentTarget
        property: "flowClipped"
        when: root.goopy && root.contentTarget!==null && root.controlsContentMotion
        value: true
        restoreMode: Binding.RestoreBindingOrValue
    }
    Component {
        id: contentReveal
        GoopContentEffect {
            maskSource: root.contentMaskSurface.maskTexture
            fieldRect: root.contentMaskSurface.maskRect
            maskExtent: Qt.vector2d(root.contentMaskSurface.maskSize.width,root.contentMaskSurface.maskSize.height)
            contentRect: root.contentGeometry()
            sourceScale: root.stableField && root.contentTarget ? Qt.vector2d(
                root.contentTarget.width/Math.max(1,root.contentAllocation.width),
                root.contentTarget.height/Math.max(1,root.contentAllocation.height)) : Qt.vector2d(1,1)
            contrast: Upstream.GoopCore.qtFilterParams.contrast
            threshold: Upstream.GoopCore.qtFilterParams.threshold
        }
    }
    onRenderFrameChanged: Qt.callLater(reserveField)
    onOverlayChanged: Qt.callLater(reserveField)
    onGoopyChanged: if(!goopy) Qt.callLater(clearIfInactive)
    onPresenceChanged: if(!panelOpen && presence<=0) Qt.callLater(clearIfClosed)
    onPanelOpenChanged: {
        if(panelOpen && (automaticOpening || pendingOpening)) Qt.callLater(startOpening);
        else if(!panelOpen) { pendingOpening=false;dripModel?.field.setFed(false); }
    }
    onWidthChanged: if(pendingOpening) Qt.callLater(startOpening)
    onHeightChanged: if(pendingOpening) Qt.callLater(startOpening)
    onVisibleChanged: {
        ++revision;
        if (visible) {
            Qt.callLater(reserveField);
            if (pendingOpening) Qt.callLater(startOpening);
        }
    }
    onContentKeyChanged: {
        if(!panelOpen || !goopy) return;
        if(!reshapeAnim.running) reshapeAnim.start();
        if(splashOnContentChange && progress>.98) Qt.callLater(startMorph);
    }
    Component.onDestruction: {
        tearingDown=true;
        flight.stop();
        reshapeAnim.stop();
        dripModel?.destroy();
    }

    Behavior on presence {
        NumberAnimation {
            duration: root.goopy ? root.Tokens.anim.durations.expressiveDefaultSpatial : 0
            // Upstream emergePose supplies the spatial easing.
            easing.type: Easing.Linear
        }
    }

    NumberAnimation {
        id: flight
        target: root
        property: "age"
        from: 0
        to: 1
        duration: root.coreEnd/root.coreRate*1000
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: reshapeAnim
        target: root
        property: "reshape"
        from: 0
        to: 1
        duration: root.splashOnContentChange ? Upstream.GoopCore.emergeMomentumEnd("open")/root.coreRate*1000
            : root.Tokens.anim.durations.expressiveFastSpatial
        easing.type: Easing.Linear
    }

    HoverHandler {
        id: hover
        parent: root.hoverTarget
        enabled: root.goopy && root.allowHoverDrip && root.panelOpen && root.progress>0.98
    }

    function clear(): void {
        flight.stop();
        reshapeAnim.stop();
        dripModel?.clear();
        morphBursts=[];
        allocation=Qt.rect(0,0,0,0);
        contentAllocation=Qt.size(0,0);
        ++revision;
    }

    function clearIfInactive(): void {
        if(!goopy) clear();
    }

    function clearIfClosed(): void {
        if(!panelOpen && presence<=0) clear();
    }

    function startOpening(): void {
        if(!goopy) return;
        if(!panelOpen || !visible || width<=0 || height<=0) {pendingOpening=true;return;}
        pendingOpening=false;
        if(running) return;
        ++serial;
        age=0;
        flight.start();
    }

    function pulse(): void {
        // Each moving source owns its release history. A new workspace
        // switch must not restart or translate a drop already in flight.
        if(trackPulseMotion) {
            // Smooth wheels can dispatch several switches inside one beat.
            // Coalesce the new emission while every live drop keeps moving.
            if(!morphBursts.some(burst=>burst.age<.065*coreRate)) startMorph();
        }
        else if(running) reshapeAnim.restart();
        else startOpening();
    }

    function startMorph(): void {
        if(!goopy || !panelOpen || progress<=.98 || width<=0 || height<=0) return;
        const geometry=targetGeometry();
        morphBursts=morphBursts.concat([{age:0,side:geometry.side,seed:++morphSerial,
            samples:[{time:0,rect:geometry.rect}]}]);
    }

    function targetGeometry(): var {
        // Remove only the wrapper's slide. The original goopUI engine draws
        // the liquid body and its neck in the settled menu's coordinate space.
        const o=externalProgress>=0?1-Math.max(0,Math.min(1,externalProgress)):0;
        let dx=0,dy=0,nx=0,ny=0;
        if(anchorEdge==="top") {dy=(height+5)*o;ny=1;}
        else if(anchorEdge==="bottom") {dy=-(height+5)*o;ny=-1;}
        else if(anchorEdge==="left") {dx=(width+5)*o;nx=1;}
        else {dx=-(width+5)*o;nx=-1;}
        const a=mapToItem(overlay,dx,dy),b=mapToItem(overlay,dx+width,dy+height);
        const p=mapToItem(overlay,0,0),n=mapToItem(overlay,nx,ny);
        const vx=n.x-p.x,vy=n.y-p.y;
        const side=Math.abs(vx)>Math.abs(vy)?(vx>0?"right":"left"):(vy>0?"bottom":"top");
        return {rect:{x:Math.min(a.x,b.x),y:Math.min(a.y,b.y),
            width:Math.max(.01,Math.abs(b.x-a.x)),height:Math.max(.01,Math.abs(b.y-a.y))},side:side};
    }

    function contentGeometry(): rect {
        revision;contentMaskSurface.revision;contentMaskSurface.renderFrame;
        const host=contentTarget,space=contentMaskSurface.overlay;
        if(!host || !space) return Qt.rect(0,0,0,0);
        host.x;host.y;host.width;host.height;
        const a=host.mapToItem(space,0,0),b=host.mapToItem(space,host.width,host.height);
        return Qt.rect(Math.min(a.x,b.x),Math.min(a.y,b.y),Math.abs(b.x-a.x),Math.abs(b.y-a.y));
    }

    function reserveField(): void {
        if(!goopy || !overlay || !paintVisible) return;
        if(stableField) {
            if(contentTarget) contentAllocation=Qt.size(Math.max(contentAllocation.width,
                Math.ceil(contentTarget.width/64)*64),overlay.height);
            allocation=Qt.rect(0,0,overlay.width,overlay.height);
            return;
        }
        const p=renderFrame.panel,b=renderFrame.body;
        let left=Math.min(p.x,b.cx-b.w/2),top=Math.min(p.y,b.cy-b.h/2);
        let right=Math.max(p.x+p.width,b.cx+b.w/2),bottom=Math.max(p.y+p.height,b.cy+b.h/2);
        const skin=renderFrame.bodyShape;
        if(skin) {
            const bend=Math.abs(skin.lean);
            if(skin.side==="top" || skin.side==="bottom") {
                left=Math.min(left,b.cx-b.w/2-bend);right=Math.max(right,b.cx+b.w/2+bend);
            } else {
                top=Math.min(top,b.cy-b.h/2-bend);bottom=Math.max(bottom,b.cy+b.h/2+bend);
            }
        }
        for(const c of renderFrame.circles) {
            left=Math.min(left,c.x-c.r*c.sx);right=Math.max(right,c.x+c.r*c.sx);
            top=Math.min(top,c.y-c.r*c.sy);bottom=Math.max(bottom,c.y+c.r*c.sy);
        }
        const pad=Math.ceil(Upstream.GoopCore.qtFilterParams.blur*3)+4;
        left=Math.max(0,Math.floor((left-pad)/64)*64);
        top=Math.max(0,Math.floor((top-pad)/64)*64);
        right=Math.min(overlay.width,Math.ceil((right+pad)/64)*64);
        bottom=Math.min(overlay.height,Math.ceil((bottom+pad)/64)*64);
        // Grow the texture in blocks; retain its allocation through the
        // transition instead of reallocating an FBO for every moving drop.
        const valid=allocation.width>0 && allocation.height>0;
        const x=valid?Math.min(left,allocation.x):left,y=valid?Math.min(top,allocation.y):top;
        const r=valid?Math.max(right,allocation.x+allocation.width):right;
        const d=valid?Math.max(bottom,allocation.y+allocation.height):bottom;
        allocation=Qt.rect(x,y,Math.max(1,r-x),Math.max(1,d-y));
    }

    function sourceOpacity(): real {
        const ancestors=[];
        for(let item=overlay;item;item=item.parent) ancestors.push(item);
        let value=1,item=root.parent;
        for(let i=0;item && !ancestors.includes(item) && i<40;++i,item=item.parent) value*=item.opacity;
        return value;
    }

    Loader {
        id: renderer
        active: root.shaderLive
        sourceComponent: GoopLayer {
            objectName: "upstreamGoopLayer"
            live: root.shaderLive
            parent: root.overlay
            z: root.layerZ
            visible: root.paintVisible
            opacity: root.sourceOpacity()
            paintColor: root.paintColor
            body: root.renderFrame.body
            bodyShape: root.renderFrame.bodyShape ?? null
            circles: root.renderFrame.circles
            panelRect: Qt.rect(root.renderFrame.panel.x,root.renderFrame.panel.y,
                root.renderFrame.panel.width,root.renderFrame.panel.height)
            fieldRect: root.allocation
            cornerRadius: root.cornerRadius
            cutoutHost: root.preserveHost
            frameMask: root.frameMask
            blur: Upstream.GoopCore.qtFilterParams.blur
            contrast: Upstream.GoopCore.qtFilterParams.contrast
            threshold: Upstream.GoopCore.qtFilterParams.threshold
            circleCapacity: root.splashOnContentChange || root.trackPulseMotion ? 256 : 128
        }
    }

    FrameAnimation {
        running: root.active
        onTriggered: {
            const dt=Upstream.GoopCore.clampDt(frameTime)*root.coreRate;
            if(root.morphing) {
                const geometry=root.targetGeometry();
                const survivors=[];
                for(const burst of root.morphBursts) {
                    burst.age+=dt;
                    if(burst.age>=Upstream.GoopCore.emergeMomentumEnd("open")) continue;
                    burst.samples.push({time:burst.age,rect:geometry.rect});
                    survivors.push(burst);
                }
                if(survivors.length!==root.morphBursts.length) root.morphBursts=survivors;
            }
            if(!root.dripModel) root.dripModel=Upstream.GoopCore.createQtDrips();
            root.dripModel.step(dt,
                root.hoverRequested && !root.running,root.renderFrame.dripBody ?? root.renderFrame.body);
            root.dripSerial=root.dripModel.spawned;
            ++root.revision;
            root.reserveField();
        }
    }
}
