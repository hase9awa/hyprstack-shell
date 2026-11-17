#!/usr/bin/env python3
"""Exercise motion presets in a separate compositor, bus and configuration.

python3 distribution/tests/test_animation_presets.py --prefix .work/animation-presets-prefix
Requires the matching built native plugin and a parent Wayland display.
"""
import argparse
import json
import os
import shlex
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
QML = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Io
import Hyprstack
import Hyprstack.Config
import Hyprstack.Blobs
import qs.components
import qs.modules.nexus
import qs.modules.nexus.pages
import qs.modules.drawers as DrawerModules
import qs.services
ShellRoot {
    id: root
    settings.watchFiles: false
    property real spatial: 0
    property real effect: 0
    property var samples: []
    property var effects: []
    property bool liquidTest: false
    property bool frameTest: false
    property bool revealTest: false
    property string frameSide: "top"
    property real frameAlpha: 1
    property real frameGap: 0
    property var liquidCaptures: []
    property var liquidCaptureFrames: []
    property bool captureDrips: false
    property bool captureStarted: false
    property var trackedDrip: null
    property bool trayTracing: false
    property var trayFrames: []
    property bool revealTracing: false
    property var revealFrames: []
    FrameAnimation {
        running: root.revealTracing
        onTriggered: {
            const parts=ShellState.componentsFor(Screens.screens[0]),panel=parts.panels.popouts;
            const reveal=root.findWhere(panel,i=>i.objectName==="popoutContentReveal" && i.active);
            const wrapper=parts.panels.popoutsWrapper;
            root.revealFrames.push({name:panel.currentName,x:wrapper.x,y:wrapper.y,dpr:wrapper.pixelRatio,
                serial:reveal?.serial??0,rows:reveal?.entries.map(e=>({scale:e.item?.scale??1,
                    opacity:e.item?.opacity??1,restingScale:e.effect.restingScale,playing:e.effect.playing}))??[]});
        }
    }
    FrameAnimation {
        running: root.trayTracing
        onTriggered: {
            const parts=ShellState.componentsFor(Screens.screens[0]),p=parts?.panels?.popoutsWrapper;
            const flow=root.findWhere(parts?.rootWindow.contentItem,i=>i.objectName==="popoutBackground")?.liquid;
            if(p) root.trayFrames.push({x:p.x,w:p.width,h:p.height,offset:p.offsetScale,visible:p.visible,
                has:p.content.hasCurrent,name:p.content.currentName,serial:flow?.serial??0,
                allocation:flow?.allocation??null,morph:flow?.morphSerial??0,splash:flow?.renderFrame.circles.length??0,dt:frameTime});
        }
    }
    FloatingWindow {
        id: inputUnderlay
        visible: false
        title: "Motion input underlay"
        implicitWidth: 1280
        implicitHeight: 1050
        color: "#234567"
        property int clicks: 0
        MouseArea { anchors.fill: parent; onClicked: ++inputUnderlay.clicks }
    }
    property bool panelTest: false
    property Item trackedPanel: null
    property var panelFrames: []
    property bool trackedFade: true
    property var workspaceCaptures: []
    property var workspaceFrames: []
    property bool workspaceClientsVisible: false
    property bool workspaceTracing: false
    property var workspaceBounds: []
    property bool workspaceDripTracing: false
    property string workspaceDripPath
    property var workspaceDripFrames: []
    property int workspaceStress: 0
    Timer {
        interval: 25
        repeat: true
        running: root.workspaceStress>0
        onTriggered: {
            Hypr.stepWorkspace(root.workspaceStress%4<2?1:-1,Hypr.monitorFor(Screens.screens[0]));
            --root.workspaceStress;
        }
    }
    FileView {
        id: workspaceDripFile
        path: root.workspaceDripPath ? root.workspaceDripPath+"/workspace-drip-frames.json" : ""
        blockWrites: true
    }
    FrameAnimation {
        running: root.workspaceDripTracing
        onTriggered: {
            const parts=ShellState.componentsFor(Screens.screens[0]);
            const liquid=root.find("workspaceActiveIndicator",parts?.bar)?.liquid;
            if(!liquid) return;
            const index=root.workspaceDripFrames.length;
            root.workspaceDripFrames.push({dt:frameTime,body:liquid.renderFrame.body,
                circles:JSON.parse(JSON.stringify(liquid.renderFrame.circles)),
                serial:liquid.serial,age:liquid.age,reshape:liquid.reshape,
                morph:liquid.morphSerial,bursts:liquid.morphBursts.map(b=>({seed:b.seed,age:b.age})),
                spawned:liquid.dripSerial,drips:liquid.drips.map(d=>({id:d.x0,detached:d.detached,
                    falling:!!d.drop,x:d.drop?.x??0,y:d.drop?.y.x??0,vy:d.drop?.y.v??0})),
                allocation:{x:liquid.allocation.x,y:liquid.allocation.y,
                    w:liquid.allocation.width,h:liquid.allocation.height}});
            if(index>=140 && index<176) {
                const path=root.workspaceDripPath+"/workspace-drips-"+index+".png";
                workspaceShot.createObject(root,{path:path});
            }
        }
    }
    FloatingWindow {
        visible: root.workspaceClientsVisible
        title: "Motion workspace fixture 2"
        implicitWidth: 640
        implicitHeight: 450
    }
    FloatingWindow {
        visible: root.workspaceClientsVisible
        title: "Motion workspace fixture 3"
        implicitWidth: 640
        implicitHeight: 450
    }
    FrameAnimation {
        running: root.workspaceTracing
        onTriggered: {
            const parts=ShellState.componentsFor(Screens.screens[0]);
            const indicator=root.find("workspaceActiveIndicator",parts?.bar);
            const list=root.findWhere(parts?.bar,i=>i.wsIds!==undefined);
            if(indicator&&list) root.workspaceBounds.push({ids:list.wsIds,
                ws:list.activeWsId,target:indicator.activeWs?.ws??-1,
                bottom:indicator.y+indicator.height+indicator.mask.anchors.margins,
                extent:list.height,width:indicator.width,height:indicator.height});
        }
    }
    Component {
        id: workspaceShot
        Process {
            required property string path
            command: ["grim","-o","MOTION-TEST",path]
            running: true
            onExited: destroy()
        }
    }
    FrameAnimation {
        running: root.workspaceCaptures.length>0
        onTriggered: {
            const parts=ShellState.componentsFor(Screens.screens[0]);
            const liquid=root.find("workspaceActiveIndicator",parts.bar)?.liquid;
            const age=liquid?.trackPulseMotion ? (liquid.morphBursts[0]?.age??0)/liquid.coreEnd : liquid?.age??0;
            if(!liquid?.active) return;
            while(root.workspaceCaptures.length && age>=root.workspaceCaptures[0].age) {
                const shot=root.workspaceCaptures[0];
                root.workspaceCaptures=root.workspaceCaptures.slice(1);
                root.workspaceFrames.push({label:shot.label,age:age,
                    frame:JSON.parse(JSON.stringify(liquid.renderFrame))});
                workspaceShot.createObject(root,{path:shot.path});
            }
        }
    }
    FrameAnimation {
        running: root.liquidCaptures.length > 0
        onTriggered: {
            if(root.captureDrips && !root.trackedDrip && liquidFixture.drips.length)
                root.trackedDrip=liquidFixture.drips[0];
            const cycle = root.trackedDrip;
            if(!root.captureDrips && liquidFixture.running) root.captureStarted=true;
            if (root.captureDrips ? !cycle : !root.captureStarted) return;
            const age = root.captureDrips ? (cycle.detached
                ? (cycle.drop ? .65+.35*Math.min(1,(cycle.drop.y.x-cycle.drop.y0)/cycle.fall) : 1)
                : cycle.m*.6) : liquidFixture.age;
            while (root.liquidCaptures.length && age >= root.liquidCaptures[0].age) {
                const shot = root.liquidCaptures[0];
                root.liquidCaptures = root.liquidCaptures.slice(1);
                root.liquidCaptureFrames.push({label:shot.label,age:age,progress:liquidFixture.progress,
                    frame:JSON.parse(JSON.stringify(liquidFixture.renderFrame)),rounding:liquidFixture.cornerRadius,
                    diagnostics:root.find("upstreamGoopLayer",fixtureGoo)?.diagnostics});
                captureRoot.grabToImage(result => result.saveToFile(shot.path));
            }
        }
    }
    FrameAnimation {
        running: root.trackedPanel !== null
        onTriggered: {
            const p=root.trackedPanel;
            root.panelFrames.push({offset:p.offsetScale,opacity:p.opacity,expectedOpacity:p.flowClipped?1:root.trackedFade?(1-p.offsetScale)*p.flowOpacity:1,visible:p.visible,
                masked:p.flowClipped??false,layerEnabled:p.layer.enabled,
                width:p.width,height:p.height,dt:frameTime});
        }
    }
    onSpatialChanged: samples.push(spatial)
    onEffectChanged: effects.push(effect)
    Component.onCompleted: { AnimationClock.activate(); Animations; }
    Binding { target: ShellState; property: "shellRoot"; value: root }
    Loader { active: root.panelTest; sourceComponent: DrawerModules.Drawers {} }
    MotionTestDialogs { id: testDialogs }
    NexusState { id: state; screen: Quickshell.screens[0]; isWindow: true }
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 800
        implicitHeight: 1000
        color: Colours.palette.m3surface
        contentItem.Tokens.screen: screen.name
        Item {
            id: captureRoot
            anchors.fill: parent
            AnimationSettings { id: page; visible: !root.liquidTest; anchors.fill: parent; anchors.margins: 24; nState: state }
            Rectangle {
                anchors.fill: parent
                visible: root.liquidTest
                color: "#141a1e"
                Rectangle { x:140;y:200;width:240;height:80;color:"#20282d";visible:!root.frameTest }
                Item { id: fixtureGoo; anchors.fill: parent }
                BlobGroup { id: fixtureFrameColour; color: "#b4e57b"; smoothing: 12 }
                BlobInvertedRect {
                    anchors.fill: parent
                    visible: root.frameTest
                    opacity: root.frameAlpha
                    group: fixtureFrameColour
                    borderLeft: 24; borderRight: 24; borderTop: 56; borderBottom: 24; radius: 32
                }
                Item {
                    id: fixtureFrameDensity
                    anchors.fill: parent
                    visible: root.frameTest
                    BlobGroup { id: fixtureFrameWhite; color: "white"; smoothing: 12 }
                    BlobInvertedRect {
                        anchors.fill: parent
                        group: fixtureFrameWhite
                        borderLeft: 24; borderRight: 24; borderTop: 56; borderBottom: 24; radius: 32
                    }
                }
                GoopFrameMask {
                    id: fixtureFrameMask
                    anchors.fill: parent
                    frameItem: fixtureFrameDensity
                    active: root.frameTest
                    innerRect: Qt.rect(24,56,parent.width-48,parent.height-80)
                }
                GoopLayer {
                    id: parityLayer
                    parent: fixtureGoo
                    visible: false
                    z: 1000
                    paintColor: "#b4e57b"
                    cornerRadius: 26
                    fieldRect: Qt.rect(0,0,captureRoot.width,captureRoot.height)
                }
                Rectangle {
                    id: clipFixture
                    x: root.frameTest ? (root.frameSide==="left" ? 24+root.frameGap : root.frameSide==="right" ? parent.width-24-width-root.frameGap : 300) : 140
                    y: root.frameTest ? (root.frameSide==="top" ? 56+root.frameGap : root.frameSide==="bottom" ? parent.height-24-height-root.frameGap : 420) : 200
                    width: root.frameTest ? 200 : 240
                    height: root.frameTest ? 140 : 80
                    clip: !root.frameTest
                    color: "transparent"
                    Item {
                        id: liquidButton
                        x: root.frameTest ? 0 : 20
                        y: root.frameTest ? 0 : 14
                        width: 200; height: root.frameTest ? 140 : 52
                        GoopSurface {
                            id: liquidFixture
                            anchors.fill: parent
                            paintColor: "#b4e57b"; cornerRadius: 26
                            anchorEdge: root.frameTest ? root.frameSide : "top"
                            escapeParent: fixtureGoo
                            frameMask: root.frameTest ? fixtureFrameMask : null
                        }
                        StateLayer { id: liquidInput; opacity: liquidFixture.contentOpacity }
                        Text {
                            id: liquidText
                            anchors.centerIn: parent
                            opacity: liquidFixture.contentOpacity
                            text: "GOOP"
                            font.pixelSize: 24
                            font.bold: true
                            color: "#102014"
                        }
                        Text {
                            anchors.fill: parent
                            visible: root.revealTest
                            text: "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
                            wrapMode: Text.WrapAnywhere
                            font.pixelSize: 10
                            font.bold: true
                            color: "#102014"
                        }
                    }
                }
            }
        }
    }
    Anim { id: spatialAnim; target: root; property: "spatial"; from: 0; to: 1; type: Anim.FastSpatial }
    Anim { id: effectAnim; target: root; property: "effect"; from: 0; to: 1; type: Anim.FastEffects }
    TestCase { id: input; when: false
        function clickItem(item) { mouseClick(item, item.width/2, item.height/2); }
    }
    function find(name, parent) {
        if (!parent) return null;
        if (parent.objectName === name) return parent;
        for (const child of parent.children ?? []) { const found=find(name,child); if(found)return found; }
        return null;
    }
    function findWhere(parent, predicate) {
        if (!parent) return null;
        if (predicate(parent)) return parent;
        for (const child of parent.children ?? []) { const found=findWhere(child,predicate); if(found)return found; }
        return null;
    }
    IpcHandler {
        target: "motionTest"
        function status(): string {
            const d = root.Tokens.anim.durations;
            return JSON.stringify({shell:Animations.shellPreset,window:Animations.windowPreset,
                durations:[d.small,d.normal,d.large,d.extraLarge,d.expressiveFastSpatial,
                    d.expressiveDefaultSpatial,d.expressiveSlowSpatial,d.expressiveFastEffects,
                    d.expressiveDefaultEffects,d.expressiveSlowEffects],scale:d.scale,
                selectedShell:root.find("shellAnimationPreset",page).active.value,
                selectedWindow:root.find("windowAnimationPreset",page).active.value,
                windowLabel:root.find("windowAnimationPreset",page).active.text,
                title:page.title,samples:root.samples,effects:root.effects,spatial:root.spatial,effect:root.effect,
                gameMode:GameMode.enabled,spatialRunning:spatialAnim.running,effectRunning:effectAnim.running});
        }
        function select(kind: string, preset: string): void {
            const row=root.find(kind+"AnimationPreset",page);
            row.selected(row.menuItems.find(item=>item.value===preset));
        }
        function choose(kind: string, preset: string): void {
            const row=root.find(kind+"AnimationPreset",page);
            const split=root.findWhere(row,item=>item.expandBtn !== undefined && item.menu !== undefined);
            const point=row.mapToItem(page.flickable.contentItem,0,0);
            page.flickable.contentY=Math.max(0,Math.min(point.y,page.flickable.contentHeight-page.flickable.height));
            input.clickItem(split.expandBtn);
            Qt.callLater(()=>input.clickItem(root.findWhere(split.menu,item=>item.modelData?.value===preset)));
        }
        function speed(scale: real): void { GlobalConfig.appearance.anim.durations.scale=scale; }
        function sample(): void { root.samples=[];root.effects=[];spatialAnim.restart();effectAnim.restart(); }
        function token(value: int): void { TokenConfig.appearance.animDurations.expressiveDefaultSpatial=value; }
        function game(value: bool): void { GameMode.enabled=value; }
        function language(value: string): void { GlobalConfig.general.language=value; }
        function click(name: string): void {
            const item=root.find(name,page);
            const point=item.mapToItem(page.flickable.contentItem,0,0);
            page.flickable.contentY=Math.max(0,Math.min(point.y,page.flickable.contentHeight-page.flickable.height));
            input.clickItem(item);
        }
        function capture(path: string): void { page.grabToImage(result=>result.saveToFile(path)); }
        function liquid(action: string, path: string): string {
            root.liquidTest=true;
            if(action==="open") liquidFixture.panelOpen=true;
            else if(action==="frameSetup") {
                const data=JSON.parse(path);
                root.frameTest=true;
                root.frameSide=data.side;
                root.frameAlpha=data.alpha;
                root.frameGap=data.gap;
                liquidButton.opacity=data.alpha;
                liquidFixture.allowHoverDrip=false;
                liquidInput.visible=false;
                liquidText.visible=false;
            }
            else if(action==="frameFilm") {
                root.captureDrips=false;
                root.captureStarted=false;
                root.liquidCaptureFrames=[];
                root.liquidCaptures=[.015,.06,.15,.25,.4,.57,.83,.97]
                    .map((age,i)=>({label:"frame-"+i,age:age,path:path+"-"+i+".png"}));
                liquidFixture.panelOpen=true;
            }
            else if(action==="frameDone") {
                root.frameTest=false;
                liquidFixture.visible=false;
            }
            else if(action==="film") {
                root.captureDrips=false;
                root.captureStarted=false;
                root.liquidCaptureFrames=[];
                root.liquidCaptures=[{label:"bulb",age:.06},{label:"neck",age:.25},{label:"spray",age:.57},{label:"fall",age:.83}]
                    .map(shot=>({label:shot.label,age:shot.age,path:path+"/liquid-"+shot.label+".png"}));
                liquidFixture.panelOpen=true;
            }
            else if(action==="revealFilm") {
                root.revealTest=true;
                root.captureDrips=false;
                root.captureStarted=false;
                root.liquidCaptureFrames=[];
                liquidFixture.allowHoverDrip=false;
                liquidButton.opacity=1;
                liquidInput.visible=false;
                liquidText.visible=false;
                root.liquidCaptures=[.025,.06,.13,.23,.4,.75]
                    .map((age,i)=>({label:"reveal-"+i,age:age,path:path+"/reveal-"+i+".png"}));
                liquidFixture.panelOpen=true;
            }
            else if(action==="revealDone") {
                root.revealTest=false;
                liquidFixture.allowHoverDrip=true;
                liquidInput.visible=true;
                liquidText.visible=true;
            }
            else if(action==="dripFilm") {
                root.captureDrips=true;
                root.trackedDrip=null;
                root.liquidCaptureFrames=[];
                root.liquidCaptures=[{label:"drip-bulb",age:.12},{label:"drip-neck",age:.5},
                    {label:"drip-fall",age:.7},{label:"drip-end",age:.9}]
                    .map(shot=>({label:shot.label,age:shot.age,path:path+"/liquid-"+shot.label+".png"}));
                input.mouseMove(liquidButton,liquidButton.width/2,liquidButton.height/2);
            }
            else if(action==="close") liquidFixture.panelOpen=false;
            else if(action==="press") input.clickItem(liquidInput);
            else if(action==="hover") input.mouseMove(liquidInput, 30, 20);
            else if(action==="leave") input.mouseMove(captureRoot,20,20);
            else if(action==="parity") {
                const snapshot=JSON.parse(path);
                liquidFixture.visible=false;
                liquidInput.visible=false;
                liquidText.visible=false;
                parityLayer.body=snapshot.frame.body;
                parityLayer.circles=snapshot.frame.circles;
                const panel=snapshot.frame.panel;
                parityLayer.panelRect=Qt.rect(panel.x,panel.y,panel.width,panel.height);
                parityLayer.cornerRadius=snapshot.rounding;
                parityLayer.visible=true;
            }
            else if(action.startsWith("debug-")) {
                root.find("goopThreshold",fixtureGoo).source=root.find(action==="debug-scene"?"goopSceneTexture":
                    action==="debug-horizontal"?"goopHorizontalTexture":"goopVerticalTexture",fixtureGoo);
            }
            else if(action==="translucent") { liquidButton.opacity=.65; liquidInput.disabled=true; }
            else if(action==="capture") captureRoot.grabToImage(result=>result.saveToFile(path));
            return JSON.stringify({running:liquidFixture.running,serial:liquidFixture.serial,age:liquidFixture.age,
                captures:root.liquidCaptureFrames,hovering:liquidFixture.hovering,dripping:liquidFixture.dripping,
                dripSerial:liquidFixture.dripSerial,active:liquidFixture.active,
                diagnostics:root.find("upstreamGoopLayer",fixtureGoo)?.diagnostics});
        }
        function workspace(action: string): string {
            const screen=Screens.screens[0],parts=ShellState.componentsFor(screen);
            const indicator=root.find("workspaceActiveIndicator",parts.bar);
            const liquid=indicator?.liquid;
            if(action==="hidden") {
                GlobalConfig.bar.workspaces.showUnoccupied=false;
                GlobalConfig.bar.workspaces.showWindows=true;
                root.workspaceClientsVisible=true;
                host.visible=true;
                Hypr.focusWorkspace(Hypr.workspaceBase(Hypr.monitorFor(screen))+1,Hypr.monitorFor(screen));
            }
            else if(action==="hidden-done") { root.workspaceClientsVisible=false;host.visible=false; }
            else if(action==="trace") { root.workspaceBounds=[];root.workspaceTracing=true; }
            else if(action==="read") root.workspaceTracing=false;
            if(action==="next" || action==="previous") Hypr.stepWorkspace(action==="next"?1:-1,Hypr.monitorFor(screen));
            const origin=indicator?.mapToItem(parts.rootWindow.contentItem,0,0);
            return JSON.stringify({ready:!!liquid&&indicator.initialized&&indicator.activeWs!==null
                    &&indicator.width>0&&indicator.height>0&&indicator.visible&&liquid.goopy&&liquid.progress>.98,
                serial:liquid?.serial??0,pulses:liquid?.morphSerial??0,running:liquid?.active??false,ws:Hypr.monitorFor(screen)?.activeWorkspace?.id,
                progress:liquid?.progress,panelOpen:liquid?.panelOpen,trackPulseMotion:liquid?.trackPulseMotion,
                active:liquid?.active??false,age:liquid?.age??1,origin:origin,rotation:indicator?.rotation??0,
                bounds:{width:indicator?.width,height:indicator?.height,y:indicator?.y,fluid:indicator?.fluidMotion},frames:root.workspaceFrames,
                trace:action==="read"?root.workspaceBounds:[],base:Hypr.workspaceBase(Hypr.monitorFor(screen)),
                colour:liquid?.paintColor.toString(),barBottom:parts.bar.mapToItem(parts.rootWindow.contentItem,0,parts.bar.height).y});
        }
        function workspaceFilm(path: string): void {
            root.workspaceCaptures=[{label:"neck",age:.15},{label:"spray",age:.35}]
                .map(shot=>({label:shot.label,age:shot.age,path:path+"/workspace-"+shot.label+".png"}));
            root.workspaceFrames=[];
            Hypr.stepWorkspace(1,Hypr.monitorFor(Screens.screens[0]));
        }
        function workspaceDrips(action: string, path: string): string {
            const parts=ShellState.componentsFor(Screens.screens[0]);
            const indicator=root.find("workspaceActiveIndicator",parts?.bar);
            if(action==="start") {
                root.workspaceDripFrames=[];root.workspaceDripPath=path;
                input.mouseMove(indicator,indicator.width/2,indicator.height/2);
                root.workspaceDripTracing=true;
            } else if(action==="stress") root.workspaceStress=40;
            else if(action==="stop") {
                root.workspaceDripTracing=false;
                workspaceDripFile.setText(JSON.stringify(root.workspaceDripFrames));
            }
            return JSON.stringify({hovering:indicator?.liquid.hovering,spawned:indicator?.liquid.dripSerial,
                count:root.workspaceDripFrames.length,stress:root.workspaceStress});
        }
        function trace(name: string): string {
            if(name==="read") return JSON.stringify(root.panelFrames);
            const parts=ShellState.componentsFor(Screens.screens[0]);
            root.trackedPanel=name ? (name==="popout"?parts.panels.popoutsWrapper:parts.panels[name]):null;
            root.trackedFade=name!=="popout";
            root.panelFrames=[];
            return "ok";
        }
        function dialogs(action: string, name: string): string {
            if(action==="compile") return testDialogs.compileAll();
            if(action==="rect") return JSON.stringify(testDialogs.rect(name));
            if(action==="open") testDialogs.open(name);
            else if(action==="close") testDialogs.close();
            else testDialogs.interact(action);
            return JSON.stringify(testDialogs.status());
        }
        function geometry(action: string): string {
            const parts=ShellState.componentsFor(Screens.screens[0]),panels=parts.panels;
            if(action==="special")Hypr.toggleSpecial("special");
            else if(action==="clients")root.workspaceClientsVisible=true;
            else if(action==="toast")Toaster.toast("RU","Layout fixture","keyboard",Toast.Info,10000,true);
            else if(action==="osd-left" || action==="osd-right") {
                GlobalConfig.osd.side=action==="osd-left"?OsdSide.Left:OsdSide.Right;
                ShellState.forScreen(Screens.screens[0]).osd=true;
            }
            else if(action==="odd") {testDialogs.window.dialogWidth=481;testDialogs.window.dialogHeight=239;}
            const special=root.findWhere(parts.bar,i=>i.activeSpecialId!==undefined);
            const marker=special?root.find("workspaceActiveIndicator",special):null;
            const normal=root.find("workspaceActiveIndicator",parts.bar);
            const flow=testDialogs.liquid(),rect=flow?.contentGeometry();
            return JSON.stringify({dialog:rect,dpr:testDialogs.window?.pixelRatio??1,
                masked:flow?.maskingContent??false,layer:flow?.contentTarget.layer.enabled??false,
                special:special?{ids:special.wsIds,active:special.activeSpecialId,target:marker?.activeWs?.ws,
                    initialized:marker?.initialized,colour:marker?.color.toString(),paint:marker?.liquid.paintColor.toString()}:null,
                normalLiquid:normal?.liquid.paintVisible??false,
                osd:panels?{left:panels.osd.onLeft,x:panels.osdWrapper.x+panels.osd.x,
                    width:panels.osd.width,viewport:panels.width}:null,
                toast:panels?{right:panels.width-panels.toasts.x-panels.toasts.width,
                    bottom:panels.height-panels.toasts.y-panels.toasts.height,
                    padding:panels.Tokens.padding.medium,height:panels.toasts.height}:null});
        }
        function underlay(action: string): int {
            if(action==="open") inputUnderlay.visible=true;
            return inputUnderlay.clicks;
        }
        function tray(action: string): string {
            const parts=ShellState.componentsFor(Screens.screens[0]);
            if(!parts?.bar) return JSON.stringify({ready:false});
            GlobalConfig.bar.tray.compact=false;
            const bar=parts.bar.content;
            const t=root.findWhere(bar,i=>i.items!==undefined && i.expandIcon!==undefined);
            const items=t?Array.from({length:t.items.count},(_,i)=>t.items.itemAt(i)):[];
            const fixtures=items.filter(i=>i.modelData.tooltipTitle.startsWith("motion-tray-"));
            const icon=fixtures.find(i=>i.modelData.tooltipTitle.endsWith(action));
            if(icon) {
                const p=icon.mapToItem(bar,icon.width/2,icon.height/2);
                bar.checkPopout(p.x);
            } else if(action==="gap") bar.missPopout();
            else if(action==="close") {root.trayTracing=false;parts.panels.popouts.close();}
            else if(action==="trace") {root.trayFrames=[];root.trayTracing=true;}
            const p=parts.panels.popoutsWrapper,flow=root.findWhere(parts.rootWindow.contentItem,i=>i.objectName==="popoutBackground")?.liquid;
            return JSON.stringify({ready:fixtures.length===2 && fixtures.every(i=>i.modelData.hasMenu),count:items.length,ids:items.map(i=>({id:i.modelData.id,title:i.modelData.tooltipTitle})),
                has:p.content.hasCurrent,offset:p.offsetScale,height:p.height,
                populated:p.content.current?.populated??false,serial:flow?.serial??0,morph:flow?.morphSerial??0,frames:root.trayFrames});
        }
        function systemIcon(action: string): string {
            const parts=ShellState.componentsFor(Screens.screens[0]),bar=parts.bar.content;
            const entry=bar.entryItems.find(i=>i.entryId==="statusIcons");
            const icons=entry?.item?.items.children.filter(i=>i.name && i.visible) ?? [];
            const icon=icons.find(i=>i.name===action);
            if(icon){const p=icon.mapToItem(bar,icon.width/2,icon.height/2);bar.checkPopout(p.x);}
            else if(action==="gap")bar.missPopout();
            else if(action==="trace"){root.revealFrames=[];root.revealTracing=true;}
            else if(action==="read")root.revealTracing=false;
            const flow=root.findWhere(parts.rootWindow.contentItem,i=>i.objectName==="popoutBackground")?.liquid;
            return JSON.stringify({icons:icons.map(i=>i.name),has:parts.panels.popouts.hasCurrent,
                revealFrames:action==="read"?root.revealFrames:[],
                offset:parts.panels.popoutsWrapper.offsetScale,serial:flow?.serial??0,
                morph:flow?.morphSerial??0,circles:flow?.renderFrame.circles.length??0});
        }
        function quickActions(action: string): string {
            const parts=ShellState.componentsFor(Screens.screens[0]),bar=parts?.bar?.content;
            if(action==="enable") {
                const entries=GlobalConfig.bar.entries;
                const vpn=entries.values.find(item=>item.id==="vpn");
                if(vpn)vpn.enabled=true;else entries.insert({id:"vpn",enabled:true});
                GlobalConfig.bar.showNotifications=true;
                GlobalConfig.sidebar.enabled=true;
                GlobalConfig.bar.popouts.vpn=GlobalConfig.bar.popouts.notifications=true;
            } else if(action==="disable") {
                GlobalConfig.bar.popouts.vpn=GlobalConfig.bar.popouts.notifications=false;
                parts.panels.popouts.close();
            }
            const entries=bar?.entryItems??[],entry=entries.find(i=>i.entryId===action);
            if(entry?.item){const p=entry.item.mapToItem(bar,entry.item.width/2,entry.item.height/2);bar.checkPopout(p.x);}
            if(action==="click-notifications" || action==="click-vpn") {
                const button=entries.find(i=>i.entryId===action.slice(6))?.item;
                if(button)input.clickItem(button);
            } else if(action==="close-settings" && ManagedVPN.window) ManagedVPN.window.visible=false;
            const current=parts?.panels?.popouts?.current;
            const flow=root.findWhere(parts?.rootWindow?.contentItem,i=>i.objectName==="popoutBackground")?.liquid;
            return JSON.stringify({entries:entries.map(i=>i.entryId),name:parts?.panels?.popouts.currentName,
                has:parts?.panels?.popouts.hasCurrent,card:current?.objectName,width:current?.width,height:current?.height,
                serial:flow?.serial,morph:flow?.morphSerial,circles:flow?.renderFrame.circles.length,
                offset:parts?.panels?.popoutsWrapper.offsetScale,settingsOpen:ManagedVPN.window!==null,
                sidebar:ShellState.forScreen(Screens.screens[0]).sidebar,
                dnd:Notifs.dnd,unread:Notifs.unreadCount});
        }
        function panels(action: string): string {
            if(action==="start") {GlobalConfig.dashboard.showOnHover=false;root.panelTest=true;host.visible=false;}
            const screen=Screens.screens[0];
            const parts=ShellState.componentsFor(screen);
            if(!parts?.panels)return JSON.stringify({ready:false});
            parts.interactionWrapper.enabled=false;
            for(const child of parts.interactionWrapper.data) {
                if(child.stop !== undefined && child.restart !== undefined) child.stop();
                if(child.hovered !== undefined && child.enabled !== undefined) child.enabled=false;
            }
            if(["dashboard","launcher","sidebar","session","utilities","osd"].includes(action))ShellState.forScreen(screen)[action]=true;
            else if(action==="popout") {
                parts.panels.popouts.currentCenter=parts.panels.width/2;
                parts.panels.popouts.currentName="audio";
                parts.panels.popouts.hasCurrent=true;
            }
            else if(action==="switch") {
                const next=parts.panels.popouts.currentName==="audio"?"kblayout":"audio";
                parts.panels.popouts.currentCenter=parts.panels.width*(next==="audio"?.6:.4);
                parts.panels.popouts.currentName=next;
            }
            else if(action==="close") {
                ShellState.closeDrawers();
                ShellState.forScreen(screen).utilities=false;
                ShellState.forScreen(screen).osd=false;
            }
            else if(action==="tab") input.clickItem(root.find("dashboardTab_1",parts.panels.dashboard));
            else if(action==="hover") {
                const tab=root.find("dashboardTab_0",parts.panels.dashboard);
                input.mouseMove(tab,10,10);
            }
            let active=0, serial=0; const emitters=[],masks=[];
            function count(item) {
                if(item.startOpening !== undefined) {
                    serial+=item.serial; if(item.running)active++;
                    if(item.running)emitters.push({parent:item.parent.objectName,width:item.width,height:item.height,age:item.age,serial:item.serial,open:item.panelOpen});
                    if(item.automaticOpening && item.contentTarget)masks.push({goopy:item.goopy,
                        clipped:item.contentTarget.flowClipped??false,layer:item.contentTarget.layer.enabled});
                }
                for(const child of item.children??[])count(child);
            }
            count(parts.rootWindow.contentItem);
            const bg=root.find("popoutBackground",parts.rootWindow.contentItem);
            const flow=bg?root.findWhere(bg,item=>item.startOpening!==undefined):null;
            return JSON.stringify({flowing:flow?.reshaping??false,bgLive:flow?.paintVisible??false,bodyWidth:flow?.renderFrame.body.w??0,ready:true,active:active,serial:serial,emitters:emitters,masks:masks,dashboard:parts.panels.dashboard.visible,
                launcher:parts.panels.launcher.visible,sidebar:parts.panels.sidebar.visible,
                session:parts.panels.session.visible,utilities:parts.panels.utilities.visible,
                osd:parts.panels.osd.visible,popout:parts.panels.popoutsWrapper.visible,
                popstate:{name:parts.panels.popouts.currentName,has:parts.panels.popouts.hasCurrent,
                    width:parts.panels.popoutsWrapper.width,height:parts.panels.popoutsWrapper.height,
                    offset:parts.panels.popoutsWrapper.offsetScale,active:parts.panels.popouts.content.active,
                    loader:parts.panels.popouts.content.status,iw:parts.panels.popouts.nonAnimWidth,ih:parts.panels.popouts.nonAnimHeight}});
        }
    }
}'''


def main(args):
    if not args.private_bus:
        subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--private-bus",
                    "--prefix", str(args.prefix.resolve()), *(["--goop-only"] if args.goop_only else []),
                    *(["--render-probe"] if args.render_probe else []),
                    *(["--frame-probe"] if args.frame_probe else []),
                    *(["--panels-only"] if args.panels_only else []),
                    *(["--portal-probe"] if args.portal_probe else []),
                    *(["--geometry-probe"] if args.geometry_probe else []),
                    *(["--workspace-drip-probe"] if args.workspace_drip_probe else []),
                    *(["--ui-probe"] if args.ui_probe else []),
                    *(["--quick-actions-probe"] if args.quick_actions_probe else [])], check=True)
        return
    # Hyprland's long instance signature leaves little room in a Unix socket
    # path. Keep the event socket comfortably below Qt's platform limit.
    base = Path(tempfile.mkdtemp(prefix="hs-m-"))
    print("Artifacts:", base, flush=True)
    pointer = base / "pointer"
    tray_fixture = base / "motion-tray"
    if args.ui_probe:
        protocol = ROOT / "distribution/tests/virtual-pointer.xml"
        for mode, name in (("client-header", "virtual-pointer.h"), ("private-code", "virtual-pointer.c")):
            subprocess.run(["wayland-scanner", mode, str(protocol), str(base / name)], check=True)
        flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "wayland-client"], text=True))
        subprocess.run(["cc", "-I" + str(base), str(ROOT / "distribution/tests/wayland_test_pointer.c"),
            str(base / "virtual-pointer.c"), *flags, "-o", str(pointer)], check=True)
        flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Widgets", "Qt6DBus"], text=True))
        subprocess.run(["c++", "-std=c++20", "-fPIC", str(ROOT / "distribution/tests/motion_tray.cpp"),
            *flags, "-o", str(tray_fixture)], check=True)
    runtime, config, shell = base / "r", base / "config", base / "shell"
    runtime.mkdir(mode=0o700)
    (base/"home").mkdir()
    (base/"home/fixture.txt").write_text("disposable motion fixture")
    shell.mkdir()
    shutil.copytree(ROOT / "shell/assets/hyprland/config", config / "hypr")
    prefs = config / "hyprstack"
    prefs.mkdir()
    (prefs / "shell.json").write_text(json.dumps({"general":{"language":"en"},
        "appearance":{"themeSync":{"enabled":False}},"services":{"weatherEnabled":False}}))
    (prefs / "layouts.json").write_text('{"mode":"scrolling"}')
    (prefs / "hypr-user.lua").write_text(
        'dofile(' + json.dumps(str(ROOT / "shell/assets/hyprland/layouts.lua")) + ')\n'
        'hl.monitor({output="",mode="1280x1050@60",position="auto",scale=1})\n'
        'hl.config({input={follow_mouse=0},misc={disable_autoreload=true}})\n')
    entry = base / "hyprland.lua"
    entry.write_text('local on=hl.on; hl.on=function(name,fn) if name~="hyprland.start" then return on(name,fn) end end\n'
        'dofile(' + json.dumps(str(config / "hypr/hyprland.lua")) + ')\nhl.on=on\n')
    for name in ("assets", "components", "modules", "services", "utils"):
        (shell / name).symlink_to(ROOT / "shell" / name)
    (shell / "shell.qml").write_text(QML)
    (shell / "MotionTestDialogs.qml").symlink_to(ROOT / "distribution/tests/MotionTestDialogs.qml")
    data = args.prefix.resolve() / "share/hyprstack"
    from PIL import Image
    Image.new("RGB",(400,200),"#478b7e").save(base/"fixture.png")
    parent = Path(os.environ["WAYLAND_DISPLAY"])
    if not parent.is_absolute(): parent = Path(os.environ["XDG_RUNTIME_DIR"]) / parent
    env = dict(os.environ, HOME=str(base / "home"), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(config),
        XDG_DATA_HOME=str(base / "data"), XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"),
        MOTION_TEST_IMAGE=str(base/"fixture.png"),
        WAYLAND_DISPLAY=str(parent), AQ_DRM_DEVICES="/dev/null", HYPRSTACK_NESTED="1", QT_QPA_PLATFORM="wayland",
        QML_IMPORT_PATH=str(data / "qml"), QML2_IMPORT_PATH=str(data / "qml"), HYPRSTACK_LIB_DIR=str(data / "lib"),
        HYPRSTACK_TITLEBAR_PLUGIN=str(data / "native/hyprstack-bars.so"), HYPRSTACK_DATA_DIR=str(data))
    for key in ("DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"): env.pop(key, None)
    processes = []

    def spawn(name, command):
        with (base / (name + ".log")).open("w") as log:
            p = subprocess.Popen(command, env=env, stdout=log, stderr=log, start_new_session=True)
        processes.append(p)
        return p

    def run(command):
        p = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
        assert p.returncode == 0, (command, p.stdout, p.stderr)
        return p.stdout.strip()

    def wait(check, label, timeout=15):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            try:
                value = check()
                if value: return value
            except (AssertionError, ValueError, FileNotFoundError) as error:
                last = str(error)[:500]
            time.sleep(.06)
        raise AssertionError(("Timeout: " + label, last, (base / "shell.log").read_text()[-5000:] if (base / "shell.log").exists() else ""))

    def image_ready(path):
        from PIL import Image
        try:
            with Image.open(path) as image: image.verify()
            return True
        except (OSError, SyntaxError): return False

    def ipc(name, *values):
        return run(["qs", "-p", str(shell), "ipc", "call", "motionTest", name, *map(str, values)])

    def status(): return json.loads(ipc("status"))
    def animations(): return {v["name"]:v for v in json.loads(run(["hyprctl", "-j", "animations"]))[0]}
    def evaluate(code): return run(["hyprctl", "eval", code])

    def check_quick_actions():
        ipc("quickActions","enable")
        wait(lambda:all(name in json.loads(ipc("quickActions","status"))["entries"]
             for name in ("vpn","notifications")),"quick action icons")
        for preset in ("default","goop"):
            ipc("select","shell",preset)
            ipc("quickActions","vpn")
            wait(lambda:json.loads(ipc("quickActions","status")).get("card")=="vpnQuickActions","VPN hover content")
            wait(lambda:json.loads(ipc("quickActions","status"))["offset"]==0,"VPN hover opens")
            before=json.loads(ipc("quickActions","status"))
            for name,card in (("notifications","notificationQuickActions"),("vpn","vpnQuickActions")):
                ipc("quickActions",name)
                wait(lambda:json.loads(ipc("quickActions","status")).get("card")==card,name+" hover content")
                time.sleep(.2)
                info=json.loads(ipc("quickActions","status"))
                assert info["has"] and info["width"]>0 and info["height"]>0,info
                assert not info["settingsOpen"] and info["dnd"]==before["dnd"] and info["unread"]==before["unread"],info
                if preset=="goop":
                    assert info["offset"]==0 and info["serial"]==before["serial"],info
                    assert info["morph"]>before["morph"] and info["circles"]>0,info
                run(["grim","-o","MOTION-TEST",str(base/("quick-"+preset+"-"+name+".png"))])
            print("PASS real VPN and notification hover menus, no actions on hover and continuous transitions",preset,flush=True)
        ipc("quickActions","notifications")
        wait(lambda:json.loads(ipc("quickActions","status")).get("card")=="notificationQuickActions","notification menu before click")
        ipc("quickActions","click-notifications")
        wait(lambda:json.loads(ipc("quickActions","status"))["sidebar"] and not json.loads(ipc("quickActions","status"))["has"],
             "full notification center replaces hover menu")
        ipc("quickActions","notifications");time.sleep(.25)
        assert not json.loads(ipc("quickActions","status"))["has"],"Notification hover reopened over the full center"
        ipc("quickActions","click-notifications")
        wait(lambda:not json.loads(ipc("quickActions","status"))["sidebar"],"close notification center")
        ipc("quickActions","vpn")
        wait(lambda:json.loads(ipc("quickActions","status"))["has"],"VPN menu before click")
        ipc("quickActions","click-vpn")
        wait(lambda:json.loads(ipc("quickActions","status"))["settingsOpen"] and not json.loads(ipc("quickActions","status"))["has"],
             "VPN icon replaces hover with settings")
        ipc("quickActions","close-settings")
        print("PASS main icons close the hover menu and open the full settings/notification center",flush=True)
        ipc("quickActions","disable")
        time.sleep(.8)
        for name in ("vpn","notifications"):
            ipc("quickActions",name);time.sleep(.2)
            assert not json.loads(ipc("quickActions","status"))["has"],name+" ignored disabled popout setting"
        ipc("quickActions","enable")

    def check_content_reveal():
        from PIL import Image
        ipc("liquid","close","");time.sleep(.6)
        ipc("liquid","revealFilm",str(base))
        wait(lambda:image_ready(base/"reveal-5.png"),"content revealed with the fluid")
        shots=json.loads(ipc("liquid","status",""))["captures"]
        (base/"content-reveal.json").write_text(json.dumps(shots))
        def ink(path):
            image=Image.open(path).convert("RGB")
            return sum(max(abs(c-e) for c,e in zip(pixel,(16,32,20)))<3
                for pixel in image.crop((160,214,360,266)).get_flattened_data())
        counts=[ink(base/("reveal-"+str(i)+".png")) for i in range(6)]
        assert shots[1]['frame']['content']<.1,("not an early opening frame",shots[1]['progress'])
        assert 10<counts[1]<counts[-1]*.85,("content did not appear immediately through a spatial mask",counts)
        assert counts[2]>counts[1] and counts[-1]>counts[2],("content did not follow the fluid expansion",counts)
        ipc("liquid","close","");time.sleep(.6);ipc("liquid","revealDone","")
        print("PASS opaque content is visible in early fluid and expands with its mask",counts,flush=True)

    def check_frame_connection():
        from PIL import Image
        ipc("liquid","prepare","");ipc("select","shell","goop");ipc("liquid","leave","")
        time.sleep(.6)
        for side,alpha,gap in [(s,1,0) for s in ("top","bottom","left","right")]+[("top",.65,0),("right",.65,48)]:
            ipc("liquid","close","");time.sleep(.6)
            ipc("liquid","frameSetup",json.dumps({"side":side,"alpha":alpha,"gap":gap}))
            time.sleep(.2)
            stem=base/("frame-"+side+"-"+str(alpha)+"-"+str(gap))
            ipc("liquid","frameFilm",str(stem))
            wait(lambda:image_ready(Path(str(stem)+"-7.png")),"attached "+side+" flow")
            shots=json.loads(ipc("liquid","status",""))["captures"]
            Path(str(stem)+".json").write_text(json.dumps(shots))
            expected=tuple(round(alpha*c+(1-alpha)*b) for c,b in zip((180,229,123),(20,26,30)))
            for i,shot in enumerate(shots):
                image=Image.open(str(stem)+"-"+str(i)+".png").convert("RGB")
                data=image.load();w,h=image.size
                def green(x,y):
                    r,g,b=data[x,y];return g>70 and g>r*1.1 and g>b*1.2
                # The body and native desktop frame must be one visible
                # component, including the upstream launch/pinch phases.
                connected=set();pending=[(10,10)]
                while pending:
                    x,y=pending.pop()
                    if (x,y) in connected or not (0<=x<w and 0<=y<h) or not green(x,y): continue
                    connected.add((x,y));pending.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
                b=shot['frame']['body'];cx,cy=round(b['cx']),round(b['cy'])
                if b['w']>=4 and b['h']>=4:
                    assert (cx,cy) in connected,(side,alpha,gap,i,"body detached from frame",b,len(connected))
                if b['w']>40 and b['h']>40:
                    x,y=(cx,56) if side=="top" else (cx,h-24) if side=="bottom" else (24,cy) if side=="left" else (w-24,cy)
                    assert max(abs(c-e) for c,e in zip(data[x,y],expected))<=2,(side,alpha,gap,i,"dark seam at native-frame join",data[x,y],expected)
                if i>=3 and b['w']>60 and b['h']>60:
                    vertical=side in ("top","bottom")
                    center=b['cx'] if vertical else b['cy'];breadth=b['w'] if vertical else b['h']
                    points=[]
                    for cross in [round(center-breadth/2+6),round(center+breadth/2-6)]:
                        for d in (2,4,6):
                            x,y=(cross,56+d) if side=="top" else (cross,h-24-d) if side=="bottom" else (24+d,cross) if side=="left" else (w-24-d,cross)
                            points.append(green(x,y))
                    assert sum(points)>=len(points)*.9,(side,alpha,gap,i,"rounded source corners separate the panel from its frame",points)
                # A frame shared with the field must never introduce a
                # second coat of colour at its joins, including alpha=.65.
                assert all(max(c-e for c,e in zip(pixel,expected))<=2 for pixel in image.get_flattened_data()),(side,alpha,gap,i,"frame join glows")
            print("PASS continuous native-frame flow and flat material",side,alpha,"gap",gap,flush=True)
        ipc("liquid","close","");time.sleep(.6);ipc("liquid","frameDone","")

    try:
        spawn("compositor", ["Hyprland", "-c", str(entry)])
        socket = wait(lambda: next((runtime / "hypr").glob("*/.socket.sock"), None), "compositor")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = socket.parent.name
        wait(lambda:(socket.parent/".socket2.sock").exists(),"compositor event socket")
        env["WAYLAND_DISPLAY"] = str(wait(lambda: next((p for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")), None), "display"))
        wait(lambda: json.loads(run(["hyprctl", "-j", "monitors"])), "monitor")
        run(["hyprctl", "output", "create", "headless", "MOTION-TEST"])
        evaluate('hl.monitor({output="MOTION-TEST",mode="1280x1050@60",position="0x0",scale=1})')
        for monitor in json.loads(run(["hyprctl", "-j", "monitors"])):
            if monitor["name"] != "MOTION-TEST":
                evaluate('hl.monitor({output='+json.dumps(monitor["name"])+',disabled=true})')
        wait(lambda: [m["name"] for m in json.loads(run(["hyprctl", "-j", "monitors"]))] == ["MOTION-TEST"], "isolated headless output")
        process = spawn("shell", ["qs", "-p", str(shell), "--no-color"])
        wait(status, "settings page")
        errors = run(["hyprctl", "configerrors"])
        assert not errors, errors
        baseline = animations()
        assert status()["durations"] == [200,400,600,1000,350,500,650,150,200,300], status()
        assert evaluate('assert(hl.plugin.hyprbars.motion_preset)') == "ok"
        print("PASS original shell tokens, native plugin and settings page", flush=True)
        if args.quick_actions_probe:
            ipc("panels","start")
            wait(lambda:json.loads(ipc("panels","status"))["ready"],"quick action drawers")
            check_quick_actions()
            text=(base/"shell.log").read_text()
            assert not any(word in text for word in ("TypeError:","ReferenceError:","Binding loop","Failed to load configuration")),text[-12000:]
            return
        if args.workspace_drip_probe:
            ipc("select","shell","goop")
            ipc("panels","start")
            wait(lambda:json.loads(ipc("panels","status"))["ready"],"workspace drawers")
            wait(lambda:json.loads(ipc("workspace","status"))["ready"],"workspace indicator")
            time.sleep(.8)
            info=json.loads(ipc("workspaceDrips","start",str(base)))
            wait(lambda:json.loads(ipc("workspaceDrips","status",""))["hovering"],"workspace hover handler")
            time.sleep(2.2)
            assert json.loads(ipc("workspaceDrips","status",""))["spawned"]>0,"No hover drops"
            for direction in ("next","next","previous","next","previous","previous","next","previous"):
                ipc("workspace",direction);time.sleep(.13)
            ipc("workspaceDrips","stress","")
            wait(lambda:json.loads(ipc("workspaceDrips","status",""))["stress"]==0,"rapid wheel simulation")
            time.sleep(2)
            ipc("workspaceDrips","stop","")
            frames=json.loads((base/"workspace-drip-frames.json").read_text())
            assert len(frames)>180 and any(f["circles"] for f in frames),"Missing animation trace"
            assert all(len(f["circles"])<=256 for f in frames),"Particle pool overflow"
            assert frames[-1]["morph"]>=12 and all(f["serial"]==0 for f in frames),"Workspace splash restarted the shared clock"
            assert all(f["allocation"]==frames[2]["allocation"] for f in frames[3:]),"Moving drops reallocated their render target"
            for previous,current in zip(frames,frames[1:]):
                bursts={b["seed"]:b for b in current["bursts"]}
                for burst in previous["bursts"]:
                    if burst["seed"] in bursts:
                        assert bursts[burst["seed"]]["age"]>=burst["age"],"A live splash rewound during reversal"
                drops={d["id"]:d for d in current["drips"] if d["falling"]}
                for drop in previous["drips"]:
                    if drop["falling"] and drop["id"] in drops:
                        assert abs(drops[drop["id"]]["x"]-drop["x"])<.001,"A detached hover drop followed the indicator"
                        assert drops[drop["id"]]["y"]>=drop["y"]-.001,"A falling hover drop moved upwards"
            print("PASS workspace hover, moving drops and rapid reversal captured",len(frames),flush=True)
            return
        if args.geometry_probe:
            ipc("select","shell","goop")
            for name in ("askpass","polkit"):
                ipc("dialogs","open",name)
                wait(lambda:json.loads(ipc("dialogs","status",""))["ready"],"password fixture")
                ipc("geometry","odd")
                wait(lambda:not json.loads(ipc("dialogs","status",""))["running"],"password appearance completes")
                time.sleep(.6)
                info=json.loads(ipc("geometry","status"));r=info["dialog"];dpr=info["dpr"]
                assert not info["layer"] and not info["masked"],info
                assert all(abs(r[k]*dpr-round(r[k]*dpr))<.001 for k in ("x","y","width","height")),info
                if name=="polkit":
                    ipc("dialogs","type","")
                    wait(lambda:json.loads(ipc("dialogs","status",""))["passwordShapes"]==7,"M3 password shapes")
                    ipc("dialogs","reveal","")
                    wait(lambda:json.loads(ipc("dialogs","status",""))["passwordShapes"]==0,"password reveal")
                    ipc("dialogs","reveal","")
                    wait(lambda:json.loads(ipc("dialogs","status",""))["passwordShapes"]==7,"hide password again")
                    password=json.loads(ipc("dialogs","status",""))
                    assert not password["nativeTextVisible"] and password["nativeTextAlpha"]==0,password
                    time.sleep(.6)
                run(["grim",str(base/(name+"-crisp.png"))])
                if name=="polkit":
                    ipc("dialogs","challenge","")
                    wait(lambda:json.loads(ipc("dialogs","status",""))["passwordShapes"]==0,"visible challenge uses text")
                ipc("dialogs","close","")
            print("PASS odd-sized password dialogs have native text and physical-pixel geometry",flush=True)
            ipc("panels","start")
            wait(lambda:json.loads(ipc("panels","status"))["ready"],"drawers")
            ipc("geometry","clients")
            clients=wait(lambda:[c for c in json.loads(run(["hyprctl","-j","clients"])) if c["title"].startswith("Motion workspace fixture")],"workspace fixture")
            client=next(c for c in clients if c["title"].startswith("Motion workspace fixture"))
            evaluate('hl.dispatch(hl.dsp.window.move({workspace="special:special",window='
                +json.dumps("address:"+client["address"])+',follow=false}))')
            ipc("geometry","special")
            wait(lambda:json.loads(ipc("geometry","status"))["special"] is not None,"special workspace UI")
            time.sleep(1)
            info=json.loads(ipc("geometry","status"));s=info["special"]
            assert s["initialized"] and s["active"] in s["ids"] and s["target"]==s["active"],info
            assert s["colour"]==s["paint"] and not info["normalLiquid"],info
            run(["grim",str(base/"special-workspace.png")])
            ipc("geometry","special");time.sleep(1)
            assert json.loads(ipc("geometry","status"))["normalLiquid"],"normal liquid indicator did not resume"
            ipc("geometry","toast");time.sleep(.3)
            info=json.loads(ipc("geometry","status"));t=info["toast"]
            assert t["height"]>0 and abs(t["right"]-t["padding"])<.1 and abs(t["bottom"]-t["padding"])<.1,info
            run(["grim",str(base/"keyboard-toast-corner.png")])
            print("PASS Win+S resolves the special workspace and restores the regular indicator",flush=True)
            print("PASS keyboard toast remains in the lower-right corner with retained hidden panels",flush=True)
            for preset in ("default","goop"):
                ipc("select","shell",preset)
                for side in ("left","right","left","right"):
                    ipc("geometry","osd-"+side);time.sleep(.7)
                    osd=json.loads(ipc("geometry","status"))["osd"]
                    assert 0<osd["width"]<osd["viewport"]/2,osd
                    assert abs(osd["x"] if side=="left" else osd["x"]+osd["width"]-osd["viewport"])<.1,osd
            print("PASS OSD changes sides with both original and liquid reveal without stretching",flush=True)
            text=(base/"shell.log").read_text()
            assert not any(w in text for w in ("TypeError:","ReferenceError:","Binding loop","AddressSanitizer")),text[-5000:]
            return
        if args.portal_probe:
            for preset in ("goop","default"):
                ipc("select","shell",preset)
                for index,delay in enumerate((.015,.06,.15,.3,.7,1.4)*2):
                    ipc("dialogs","open","chooser")
                    handle="/org/freedesktop/portal/desktop/request/motion/c"+str(index)
                    caller=spawn("chooser-"+preset+str(index),["gdbus","call","--session",
                        "--dest","org.freedesktop.impl.portal.desktop.hyprstack",
                        "--object-path","/org/freedesktop/portal/desktop",
                        "--method","org.freedesktop.impl.portal.AppChooser.ChooseApplication",
                        handle,"org.example.Motion","''","[]",
                        "{'content_type': <'x-scheme-handler/magnet'>, 'uri': <'magnet:?xt=urn:btih:0000000000000000000000000000000000000000'>}"])
                    wait(lambda:json.loads(ipc("dialogs","status",""))["visible"],"empty magnet chooser")
                    if delay>1:ipc("dialogs","hover","")
                    time.sleep(delay)
                    ipc("dialogs","cancel","")
                    caller.wait(timeout=5)
                    assert caller.returncode==0,(base/("chooser-"+preset+str(index)+".log")).read_text()
                    reply=(base/("chooser-"+preset+str(index)+".log")).read_text()
                    assert "uint32 1" in reply,reply
                    wait(lambda:json.loads(ipc("dialogs","status",""))["pendingChoosers"]==0,"chooser cancellation completion")
                    time.sleep(.12)
                    assert process.poll() is None,"Shell crashed after chooser cancellation"
                    print("PASS empty magnet chooser cancellation",preset,index,delay,flush=True)
                ipc("dialogs","open","files")
                wait(lambda:json.loads(ipc("dialogs","status",""))["ready"],"file dialog survives chooser cancellation")
                ipc("dialogs","close","")
            print("PASS real AppChooser cancellation leaves the shell and subsequent file dialogs alive",flush=True)
            return
        if args.ui_probe:
            ipc("select","shell","goop")
            assert not ipc("dialogs","compile","")
            for name in ("files","askpass","polkit","share","screenshot"):
                info=json.loads(ipc("dialogs","open",name))
                assert not info["error"],info
                wait(lambda:json.loads(ipc("dialogs","status",""))["ready"],name+" fluid surface")
                wait(lambda:json.loads(ipc("dialogs","status",""))["serial"]>0,name+" original opening")
                wait(lambda:not json.loads(ipc("dialogs","status",""))["running"],name+" settles")
                info=json.loads(ipc("dialogs","status",""))
                assert info["registered"] and info["nativeWhenSettled"] and not info["layer"] and info["visible"],info
                assert info["frames"] and all(f["opacity"]==1 and f["layer"] for f in info["frames"]),info
                assert all(f["w"]>=0 and f["h"]>=0 for f in info["frames"]),info
                assert any(f["progress"]<.4 and f["w"]>0 for f in info["frames"]),info
                if name=="files": assert "fixture.txt" in info["files"],info
                if name in ("askpass","polkit"):
                    ipc("dialogs","type","")
                    assert json.loads(ipc("dialogs","status",""))["canSubmit"],name+" input blocked"
                ipc("dialogs","hover","")
                wait(lambda:json.loads(ipc("dialogs","status",""))["dripping"]>0,name+" hover drips")
                (base/(name+"-dialog.json")).write_text(ipc("dialogs","status",""))
                run(["grim",str(base/(name+"-dialog.png"))])
                if name in ("askpass","polkit","files"):
                    if name=="files": ipc("dialogs","cancel","")
                    else:
                        pos=json.loads(ipc("dialogs","rect",name+"Cancel"))
                        run([str(pointer),str(round(pos["x"])),str(round(pos["y"])),"1280","1050"])
                        wait(lambda:json.loads(ipc("dialogs","status",""))["cancelled"]==1,name+" pointer cancel")
                    assert json.loads(ipc("dialogs","status",""))["cancelled"]==1,name+" cancel"
                ipc("select","shell","default")
                assert not json.loads(ipc("dialogs","status",""))["layer"],name+" default mask restoration"
                ipc("dialogs","close","")
                ipc("select","shell","goop")
                print("PASS fluid dialog, immediate content, hover drips and lifecycle",name,flush=True)
            ipc("panels","start")
            wait(lambda:json.loads(ipc("panels","status"))["ready"],"tray shell")
            for _ in range(5):ipc("workspace","next");time.sleep(.025)
            for cycle in range(5):
                for action in ("previous","previous","previous","next","next","next"):
                    ipc("workspace",action);time.sleep(.025)
                    ws=json.loads(ipc("workspace","status"))
                    assert ws["bounds"]["fluid"] and ws["bounds"]["height"]>=ws["bounds"]["width"]>0,ws
            time.sleep(1)
            run(["grim",str(base/"workspace-rapid-reversal.png")])
            print("PASS rapid leftward workspace changes and reversals preserve a full capsule",flush=True)
            scenario=json.loads(ipc("workspace","hidden"))
            wait(lambda:len(json.loads(run(["hyprctl","-j","clients"])))>=3,"occupied workspace fixtures")
            for client in json.loads(run(["hyprctl","-j","clients"])):
                title=client["title"]
                number=int(title.rsplit(" ",1)[-1]) if title.startswith("Motion workspace fixture ") else 1
                evaluate("hl.dispatch(hl.dsp.window.move({workspace="
                    +json.dumps(str(scenario["base"]+number))+",window="
                    +json.dumps("address:"+client["address"])+",follow=false}))")
            time.sleep(.8)
            ipc("workspace","trace")
            for _ in range(4):
                for action in ("next",)*5+("previous",)*5:
                    ipc("workspace",action);time.sleep(.055)
            time.sleep(.6)
            hidden=json.loads(ipc("workspace","read"))["trace"]
            (base/"workspace-hidden-trace.json").write_text(json.dumps(hidden))
            assert len(hidden)>100 and len({len(f["ids"]) for f in hidden})>=3,hidden[-5:]
            clipped=[f for f in hidden if f["bottom"]>f["extent"]+.25]
            assert not clipped,clipped[:5]
            assert all(f["height"]>=f["width"]>0 for f in hidden),hidden[-5:]
            run(["grim",str(base/"workspace-hidden-return.png")])
            ipc("workspace","hidden-done")
            print("PASS occupied-to-hidden workspace reversals retain the filled capsule inside its clip on every frame",flush=True)
            icons=json.loads(ipc("systemIcon","status"))["icons"]
            targets=[n for n in ("audio","kblayout","network","bluetooth") if n in icons]
            assert len(targets)>=2,icons
            ipc("systemIcon",targets[0]);time.sleep(1)
            before=json.loads(ipc("systemIcon","status"))
            ipc("systemIcon","trace")
            for target in targets[1:]+targets[:1]:
                ipc("systemIcon","gap");time.sleep(.02);ipc("systemIcon",target);time.sleep(.2)
                info=json.loads(ipc("systemIcon","status"))
                assert info["has"] and info["offset"]==0 and info["serial"]==before["serial"],info
                assert info["morph"]>before["morph"] and info["circles"]>0,info
            ipc("systemIcon",next(name for name in targets if name!="network"))
            time.sleep(.7)
            reveals=json.loads(ipc("systemIcon","read"))["revealFrames"]
            (base/"content-reveal-frames.json").write_text(json.dumps(reveals))
            rows=[row for f in reveals for row in f["rows"]]
            assert rows and any(.65<r["scale"]<.95 for r in rows),reveals[-5:]
            assert any(not r["playing"] and abs(r["scale"]-r["restingScale"])<.001 for r in rows),reveals[-5:]
            assert all(abs(f["x"]*f["dpr"]-round(f["x"]*f["dpr"]))<.001 for f in reveals),reveals[-5:]
            print("PASS shared row entrances settle at their original scale and popout text aligns to physical pixels",flush=True)
            print("PASS system-icon transitions preserve the surface and emit upstream splash",flush=True)
            ipc("panels","close");time.sleep(.6)
            spawn("tray-small",[str(tray_fixture),"small"])
            spawn("tray-large",[str(tray_fixture),"large"])
            wait(lambda:json.loads(ipc("tray","status"))["ready"],"real StatusNotifier icons")
            for size in ("small","large","small"):
                wait(lambda:json.loads(ipc("tray",size))["populated"],size+" DBusMenu")
                time.sleep(1)
            tray_before=json.loads(ipc("tray","trace"))
            serial=tray_before["serial"]
            for size in ("large","small")*5:
                ipc("tray","gap");time.sleep(.02);ipc("tray",size);time.sleep(.055)
            time.sleep(.4)
            info=json.loads(ipc("tray","status"))
            (base/"tray-morph.json").write_text(json.dumps(info))
            assert info["frames"] and all(f["has"] and f["visible"] and f["offset"]==0 for f in info["frames"]),info
            assert info["serial"]==serial,info
            assert info["morph"]>tray_before["morph"],info
            assert any(f["splash"]>10 for f in info["frames"]),info
            frames=info["frames"]
            assert all(abs(b["h"]-a["h"])<100 for a,b in zip(frames,frames[1:])),info
            run(["grim",str(base/"tray-morph.png")])
            ipc("select","shell","default")
            wait(lambda:json.loads(ipc("tray","small"))["populated"],"original tray menu")
            ipc("select","shell","goop")
            wait(lambda:json.loads(ipc("tray","small"))["populated"],"fluid tray menu restored")
            time.sleep(.5)
            last=frames[-1]
            click_x=round(last["x"]+last["w"]*.5)
            click_y=round(60+last["h"]*.5)
            ipc("tray","close")
            time.sleep(.6)
            ipc("underlay","open")
            time.sleep(.5)
            run([str(pointer),str(click_x),str(click_y),"1280","1050"])
            wait(lambda:int(ipc("underlay","status"))>0,"browser-area click after popout close")
            print("PASS the closed popout releases its input region to the underlying application",flush=True)
            text=(base/"shell.log").read_text()
            assert not any(word in text for word in ("TypeError:","ReferenceError:","Binding loop","Failed to load configuration","Failed to find shader")),text[-9000:]
            print("PASS real tray apps retain one continuous liquid surface across icon gaps and repeated resize reversals",flush=True)
            return
        if args.frame_probe:
            check_frame_connection()
            text=(base/"shell.log").read_text()
            assert not any(word in text for word in ("TypeError:","ReferenceError:","Binding loop","Failed to load configuration","Failed to find shader")),text[-8000:]
            return
        if args.render_probe:
            ipc("liquid","prepare","");ipc("select","shell","goop");ipc("liquid","leave","")
            ipc("liquid","film",str(base))
            wait(lambda:image_ready(base/"liquid-fall.png"),"original goopUI poses")
            snapshots=json.loads(ipc("liquid","status",""))["captures"]
            (base/"parity-frames.json").write_text(json.dumps(snapshots))
            for snapshot in snapshots:
                ipc("liquid","parity",json.dumps(snapshot));time.sleep(.2)
                target=base/("qt-"+snapshot['label']+".png")
                ipc("liquid","capture",str(target));wait(lambda:image_ready(target),"static original frame")
            ipc("panels","start")
            wait(lambda:json.loads(ipc("panels","status"))["ready"],"drawer construction")
            time.sleep(.2)
            (base/"binding-errors.json").write_text(json.dumps([line for line in (base/"shell.log").read_text().splitlines()
                if any(word in line for word in ("Binding loop","TypeError:","ReferenceError:"))]))
            print("PASS static original goopUI poses rendered for browser comparison",flush=True)
            return

        if not args.goop_only:
            durations = {"default":500,"goop":460,"fluent":300,"snappy":210,"cinematic":520,"reduced":0}
            for preset, duration in durations.items():
                ipc("select", "shell", preset)
                wait(lambda: status()["selectedShell"] == preset and status()["durations"][5] == duration, preset)
                assert status()["window"] == "default"
                ipc("sample")
                time.sleep(.8)
                result = status()
                assert result["spatial"] == 1 and result["effect"] == 1, (preset, result)
                if preset != "reduced":
                    assert result["samples"] and result["effects"], (preset, result)
                    assert all(0 <= x <= 1.2 for x in result["samples"]), (preset, result)
                    settled = next(i for i, value in enumerate(result["samples"]) if value >= .98)
                    assert min(result["samples"][settled:]) >= .95, (preset, result)
                assert all(0 <= x <= 1 for x in result["effects"]), result
                if preset == "goop": assert max(result["samples"]) > 1.05, result
                if preset == "reduced": assert not animations()["layersIn"]["enabled"]
            print("PASS all shell profiles, Goop spring overshoot and bounded effects", flush=True)

            styles = {"default":"popin 94%","spring":"popin 88%","glide":"slide", "snappy":"popin 97%","cinematic":"popin 82%","reduced":""}
            for preset, style in styles.items():
                ipc("select", "window", preset)
                wait(lambda: status()["selectedWindow"] == preset, preset)
                wait(lambda: animations()["windowsIn"]["enabled"] == (preset != "reduced")
                     and (preset == "reduced" or animations()["windowsIn"]["style"] == style), preset+" applied")
                assert status()["shell"] == "reduced"
                camera = json.loads(run(["hyprctl", "repl", 'return hl.plugin.hyprbars.workspace_camera("status")']))
                assert camera["enabled"]
                assert not animations()["workspaces"]["enabled"], "Native camera must own workspace movement"
                evaluate('hyprstack_layouts.toggle()')
                time.sleep(.55)
                assert animations()["workspaces"]["enabled"] == (preset not in ("default","reduced"))
                evaluate('hyprstack_layouts.toggle()')
                time.sleep(.55)
            print("PASS all window profiles in scrolling and stacking, camera ownership", flush=True)

            ipc("select", "shell", "goop")
            ipc("select", "window", "spring")
            ipc("speed", 1.5)
            assert status()["durations"][5] == 690
            ipc("game", "true")
            wait(lambda: json.loads(run(["hyprctl", "-j", "getoption", "animations:enabled"]))["bool"] is False, "game mode")
            assert status()["window"] == "spring"
            ipc("game", "false")
            wait(lambda: animations()["windowsIn"]["style"] == "popin 88%", "game mode restoration")
            ipc("language", "ru_RU")
            wait(lambda: status()["title"] == "Анимации" and status()["windowLabel"] == "Пружина", "Russian labels")
            time.sleep(1.5)
            ipc("capture", str(base / "settings-ru.png"))
            wait(lambda: image_ready(base / "settings-ru.png"), "screenshot")
            wait(lambda: json.loads((prefs / "shell.json").read_text())["appearance"]["anim"]["windowPreset"] == "spring", "saved presets")
            process.terminate(); process.wait(timeout=5)
            process = spawn("shell-restarted", ["qs", "-p", str(shell), "--no-color"])
            wait(lambda: status()["shell"] == "goop" and status()["window"] == "spring" and status()["scale"] == 1.5, "restart persistence")
            print("PASS speed, independent persistence, restart, game mode and Russian UI", flush=True)

            saved = json.loads((prefs / "shell.json").read_text())
            saved["appearance"]["anim"].update(shellPreset="fluent", windowPreset="glide")
            (prefs / "shell.json").write_text(json.dumps(saved))
            wait(lambda: status()["selectedShell"] == "fluent" and status()["selectedWindow"] == "glide"
                 and status()["durations"][5] == 450, "external config changes")
            wait(lambda: animations()["windowsIn"]["style"] == "slide", "external window preset")
            print("PASS live external configuration reload", flush=True)

            ipc("choose", "window", "cinematic")
            wait(lambda: status()["selectedWindow"] == "cinematic", "dropdown mouse selection")

            ipc("click", "resetAnimationPresets")
            wait(lambda: status()["shell"] == "default" and status()["window"] == "default" and status()["scale"] == 1, "reset button")
            for leaf in ("windowsIn", "windowsOut", "windowsMove", "layersIn", "layersOut", "fadeLayers", "fadeIn", "fadeSwitch", "fadeDim", "border"):
                assert animations()[leaf] == baseline[leaf], (leaf, animations()[leaf], baseline[leaf])
            ipc("token", 725)
            assert status()["durations"][5] == 725
            ipc("select", "shell", "goop")
            assert status()["durations"][5] == 460
            ipc("select", "shell", "default")
            assert status()["durations"][5] == 725, "Custom default motion token was overwritten"

        if not args.panels_only:
            ipc("liquid", "prepare", "")
            ipc("select", "shell", "goop")
            time.sleep(1.4)
            ipc("liquid", "capture", str(base / "liquid-before.png"))
            wait(lambda: image_ready(base / "liquid-before.png"), "liquid baseline")
            for action in ("hover", "press"):
                ipc("liquid", action, "")
                time.sleep(.15)
                assert json.loads(ipc("liquid", "status", ""))["serial"] == 0, "Pointer input started a splash"
            ipc("liquid", "film", str(base))
            wait(lambda: all(image_ready(base/("liquid-"+label+".png")) for label in ("bulb","neck","spray","fall")),
                 "opening frames captured by the animation clock")
            liquid_frames=json.loads(ipc("liquid","status",""))
            (base/"liquid-frames.json").write_text(json.dumps(liquid_frames))
            from PIL import Image
            image = Image.open(base / "liquid-spray.png").convert("RGB")
            escaped = sum(g > 100 and g > r * 1.1 and g > b * 1.2
                          for y in range(image.height) for x in range(image.width)
                          if not (140 <= x < 380 and 200 <= y < 280)
                          for r,g,b in [image.getpixel((x,y))])
            assert escaped > 0, ("Opening splash was clipped",escaped)
            pixels={(x,y) for y in range(150,400) for x in range(80,460)
                    for r,g,b in [image.getpixel((x,y))] if g>100 and g>r*1.1 and g>b*1.2}
            while pixels:
                component=set();pending=[next(iter(pixels))]
                while pending:
                    point=pending.pop()
                    if point not in pixels:continue
                    pixels.remove(point);component.add(point);x,y=point
                    pending.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
                if len(component)<4 or any(160<=x<360 and 214<=y<266 for x,y in component):continue
                w=max(x for x,y in component)-min(x for x,y in component)+1
                h=max(y for x,y in component)-min(y for x,y in component)+1
                assert max(w,h)/min(w,h)<8 and len(component)/(w*h)>.15, ("Stray rectangular shader streak",w,h,len(component))
            neck = Image.open(base / "liquid-neck.png").convert("RGB")
            green = {(x,y) for y in range(160,340) for x in range(100,420)
                     for r,g,b in [neck.getpixel((x,y))] if g>100 and g>r*1.1 and g>b*1.2}
            neck_body=next(c['frame']['body'] for c in liquid_frames['captures'] if c['label']=='neck')
            connected=set(); pending=[(round(neck_body['cx']),round(neck_body['cy']))]
            while pending:
                point=pending.pop()
                if point not in green or point in connected: continue
                connected.add(point);x,y=point
                pending.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
            assert len(connected)>1000 and len(connected)>=len(green)*.95, "Original goopUI neck is disconnected from the live body"
            time.sleep(.5)
            ipc("liquid", "capture", str(base/"liquid-rest.png"))
            wait(lambda:image_ready(base / "liquid-rest.png"),"settled body")
            before = Image.open(base / "liquid-rest.png").convert("RGB")
            bulb=Image.open(base/"liquid-bulb.png").convert("RGB")
            def mass(im):
                return sum(g>100 and g>r*1.1 and g>b*1.2 for r,g,b in im.crop((140,200,380,285)).getdata())
            assert 0<mass(bulb)<mass(before)*.65, "The whole panel did not emerge from a small liquid bulb"
            glyphs=[(x,y)for y in range(224,256)for x in range(210,310)
                    if max(before.getpixel((x,y)))<70]
            assert len(glyphs)>100
            assert sum(max(image.getpixel(p))<90 for p in glyphs)>len(glyphs)*.95, "Escaping liquid covered the label"
            time.sleep(.7)
            assert not json.loads(ipc("liquid", "status", ""))["running"]
            ipc("liquid", "close", "")
            for action in ("hover", "press"):
                ipc("liquid", action, "")
                time.sleep(.1)
            assert json.loads(ipc("liquid", "status", ""))["serial"] == 1
            time.sleep(.5)
            ipc("liquid", "translucent", "")
            ipc("liquid", "open", "")
            time.sleep(.30)
            ipc("liquid", "capture", str(base / "liquid-flat.png"))
            wait(lambda: image_ready(base / "liquid-flat.png"), "flat liquid colour")
            flat=Image.open(base / "liquid-flat.png").convert("RGB")
            # Sample fully covered pixels on the protrusions, including the neck
            # intersections. One translucent draw must have the same colour there.
            def liquid_pixel(x,y):
                r,g,b=flat.getpixel((x,y));return g>100 and g>r*1.1 and g>b*1.2
            solid=[(x,y,flat.getpixel((x,y))) for y in range(210,310) for x in range(145,375)
                   if not (206<=x<=314 and 220<=y<=260) and all(liquid_pixel(x+dx,y+dy) for dx,dy in ((0,0),(-2,0),(2,0),(0,-2),(0,2)))]
            assert len(solid)>15, ("No solid liquid pixels",len(solid))
            flat_interiors=0
            for x,y,pixel in solid:
                background=(32,40,45) if 140<=x<380 and 200<=y<280 else (20,26,30)
                expected=tuple(round(.65*c+.35*b) for c,b in zip((180,229,123),background))
                assert max(c-e for c,e in zip(pixel,expected))<=2, ("Glow or overlapping alpha",x,y,expected,pixel)
                flat_interiors+=max(abs(c-e) for c,e in zip(pixel,expected))<=2
            # Thin pinching necks add a few partially covered antialiasing pixels.
            # Their interiors still share exactly one flat material with the host.
            assert flat_interiors>=len(solid)*.99, ("Liquid interior is shaded",flat_interiors,len(solid))
            ipc("liquid", "close", "")
            print("PASS opening-only liquid, connected necks, readable labels and flat translucent colour",flush=True)
            ipc("liquid","leave","")
            time.sleep(1.6)
            ipc("liquid","open","")
            wait(lambda:not json.loads(ipc("liquid","status",""))["running"],"opening before stationary hover")
            before_drips=json.loads(ipc("liquid","status",""))["dripSerial"]
            ipc("liquid","dripFilm",str(base))
            wait(lambda:json.loads(ipc("liquid","status",""))["hovering"],"real pointer hover")
            wait(lambda:all(image_ready(base/("liquid-"+label+".png")) for label in
                 ("drip-bulb","drip-neck","drip-fall","drip-end")),"hover drip frames")
            wait(lambda:json.loads(ipc("liquid","status",""))["dripSerial"]>=before_drips+4,
                 "continuous drips while the cursor stays still")
            (base/"hover-drips.json").write_text(ipc("liquid","status",""))
            ipc("liquid","leave","")
            stopped_drips=json.loads(ipc("liquid","status",""))["dripSerial"]
            wait(lambda:not json.loads(ipc("liquid","status",""))["active"],"hover drip tail settles")
            assert json.loads(ipc("liquid","status",""))["dripSerial"]==stopped_drips,"Drips kept spawning after pointer leave"
            ipc("liquid","close","")
            print("PASS stationary hover emits continuous drips; leaving drains the tail and stops the frame clock",flush=True)
            check_content_reveal()
            check_frame_connection()
        else:
            ipc("select","shell","goop")
        ipc("panels","start")
        wait(lambda:json.loads(ipc("panels","status"))["ready"],"real drawer surfaces")
        wait(lambda:json.loads(ipc("workspace","status"))["ready"],"workspace indicator")
        # Restarting Qt's settings fixture can refocus the nested Wayland
        # backend. Relative workspace dispatch must target the captured output.
        evaluate('hl.dispatch(hl.dsp.focus({monitor="MOTION-TEST"}))')
        wait(lambda:json.loads(run(["hyprctl","-j","activeworkspace"]))["monitor"]=="MOTION-TEST",
             "captured output focused")
        workspace_before=json.loads(ipc("workspace","status"))["pulses"]
        ipc("speed",4)
        ipc("workspaceFilm",str(base))
        def workspace_splashed():
            info=json.loads(ipc("workspace","status"))
            assert info["pulses"]>workspace_before,info
            return info
        wait(workspace_splashed,"workspace switch splash")
        wait(lambda:all(image_ready(base/("workspace-"+label+".png")) for label in ("neck","spray")),"workspace frames from animation clock")
        (base/"workspace.json").write_text(ipc("workspace","status"))
        ws_state=json.loads(ipc("workspace","status"))
        from PIL import Image
        rgb=tuple(bytes.fromhex(ws_state["colour"].lstrip('#'))[:3])
        ws_image=Image.open(base/"workspace-spray.png").convert("RGB")
        escaped_workspace=sum(max(abs(a-b) for a,b in zip(ws_image.getpixel((x,y)),rgb))<8
            for y in range(int(ws_state["barBottom"])+3,min(ws_image.height,int(ws_state["barBottom"])+180))
            for x in range(min(ws_image.width,600)))
        assert escaped_workspace>4,("Workspace splash is clipped by the taskbar",escaped_workspace,ws_state)
        wait(lambda:not json.loads(ipc("workspace","status"))["running"],"workspace splash settles")
        ipc("speed",1)
        print("PASS workspace switching emits liquid from the real rotated indicator",flush=True)
        assert len(json.loads(ipc("panels","status"))["masks"])>=7,"Missing drawer content masks"
        ipc("game","true")
        wait(lambda:all(not m['clipped'] and not m['layer'] for m in json.loads(ipc("panels","status"))["masks"]),"game mode restores original content rendering")
        ipc("game","false")
        for preset in ("default","reduced"):
            ipc("select","shell",preset)
            wait(lambda:all(not m['clipped'] and not m['layer'] for m in json.loads(ipc("panels","status"))["masks"]),preset+" content rendering")
        ipc("select","shell","goop")
        wait(lambda:all(m['clipped'] and m['layer'] for m in json.loads(ipc("panels","status"))["masks"]),"fluid content mask restored")
        print("PASS content layers restore in default, reduced and game mode",flush=True)
        for mode in ("scrolling","stacking"):
            if mode=="stacking":evaluate('hyprstack_layouts.toggle()');time.sleep(.6)
            for panel in ("dashboard","launcher","sidebar","session","utilities","osd","popout"):
                ipc("trace",panel)
                ipc("panels",panel)
                wait(lambda:json.loads(ipc("panels","status"))[panel],mode+" "+panel)
                wait(lambda:json.loads(ipc("panels","status"))["active"]>0,mode+" panel splash")
                if mode == "scrolling" and panel == "dashboard":
                    for label, delay in (("bulb",.03),("neck",.13),("spray",.22),("settle",.35)):
                        time.sleep(delay)
                        run(["grim","-o","MOTION-TEST",str(base / ("dashboard-"+label+".png"))])
                wait(lambda:json.loads(ipc("panels","status"))["active"]==0,"opening settles")
                opening=json.loads(ipc("trace","read"))
                assert opening and all(-.000001<=f["offset"]<=1.000001 for f in opening), (mode,panel,"unbounded travel",opening)
                assert all(opening[i+1]["offset"]<=opening[i]["offset"]+.000001 for i in range(len(opening)-1)), (mode,panel,"opening reversed")
                assert all(abs(f["opacity"]-f["expectedOpacity"])<.000001 for f in opening), (mode,panel,"opacity overridden")
                assert opening[-1]["visible"] and opening[-1]["offset"]==0, (mode,panel,"panel disappeared")
                if panel == "dashboard":
                    before_serial=json.loads(ipc("panels","status"))["serial"]
                    for action in ("tab","hover"):
                        ipc("panels",action)
                        time.sleep(.25)
                    assert json.loads(ipc("panels","status"))["serial"]==before_serial, "Tabs or hovering started a splash"
                ipc("trace",panel)
                ipc("panels","close")
                closing_serial=json.loads(ipc("panels","status"))["serial"]
                time.sleep(.15)
                assert json.loads(ipc("panels","status"))["serial"]==closing_serial, "Closing emitted new liquid"
                wait(lambda:not json.loads(ipc("panels","status"))[panel],"drawer close")
                time.sleep(1.35)
                assert json.loads(ipc("panels","status"))["active"]==0,"Liquid kept animating while idle"
                closing=json.loads(ipc("trace","read"))
                assert all(-.000001<=f["offset"]<=1.000001 for f in closing), (mode,panel,"closing overshoot")
                assert all(closing[i+1]["offset"]>=closing[i]["offset"]-.000001 for i in range(len(closing)-1)), (mode,panel,"closing reversed")
                assert all(abs(f["opacity"]-f["expectedOpacity"])<.000001 for f in closing), (mode,panel,"closing opacity overridden")
                assert not closing[-1]["visible"] and closing[-1]["offset"]==1, (mode,panel,"did not finish closing")
                ipc("trace","")
                print("PASS bounded, persistent panel",mode,panel,flush=True)
        ipc("panels","popout")
        wait(lambda:json.loads(ipc("panels","status"))["popstate"]["offset"]==0,"steady popout before morph")
        for _ in range(4):
            ipc("panels","switch");time.sleep(.055)
            info=json.loads(ipc("panels","status"))
            assert info["flowing"] and info["bgLive"] and info["bodyWidth"]>5, ("Menu did not flow into its neighbour",info)
            assert info["popstate"]["has"] and info["popstate"]["offset"]==0, ("Menu surface was closed during morph",info)
            time.sleep(.3)
        ipc("panels","close")
        wait(lambda:not json.loads(ipc("panels","status"))["popout"],"morph close")
        print("PASS neighbouring menus retain one liquid surface while resizing and changing content",flush=True)
        for panel in ("dashboard","sidebar","popout"):
            ipc("trace",panel)
            for _ in range(3):
                ipc("panels",panel);time.sleep(.09)
                ipc("panels","close");time.sleep(.045)
            ipc("panels",panel)
            wait(lambda:json.loads(ipc("panels","status"))[panel],"reopened "+panel)
            time.sleep(1.3)
            frames=json.loads(ipc("trace","read"))
            assert frames and all(-.000001<=f["offset"]<=1.000001 for f in frames), (panel,"interrupted overshoot")
            assert all(abs(f["opacity"]-f["expectedOpacity"])<.000001 for f in frames), (panel,"interrupted opacity")
            assert all(f["visible"] for f in frames if f["offset"]<.99999), (panel,"interrupted disappearance")
            assert frames[-1]["visible"] and frames[-1]["offset"]==0, (panel,"reopen did not settle")
            (base/("motion-"+panel+"-reversal.json")).write_text(json.dumps(frames))
            ipc("panels","close")
            wait(lambda:not json.loads(ipc("panels","status"))[panel],"final close")
            ipc("trace","")
        print("PASS interrupted openings and rapid reversals keep panels visible and bounded",flush=True)
        print("PASS liquid on real panels in both layouts and zero active emitters after settling",flush=True)
        for log in ("shell.log", "shell-restarted.log"):
            if not (base / log).exists(): continue
            text = (base / log).read_text()
            assert not any(word in text for word in ("TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration")), text[-12000:]
        assert not run(["hyprctl", "configerrors"])
        if not args.goop_only:
            print("PASS clickable reset, exact default restoration and custom-token preservation", flush=True)
    finally:
        for p in reversed(processes):
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGTERM)
                try: p.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(p.pid, signal.SIGKILL)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--private-bus", action="store_true")
    parser.add_argument("--goop-only", action="store_true")
    parser.add_argument("--render-probe", action="store_true")
    parser.add_argument("--frame-probe", action="store_true")
    parser.add_argument("--panels-only", action="store_true")
    parser.add_argument("--ui-probe", action="store_true")
    parser.add_argument("--portal-probe", action="store_true")
    parser.add_argument("--geometry-probe", action="store_true")
    parser.add_argument("--workspace-drip-probe", action="store_true")
    parser.add_argument("--quick-actions-probe", action="store_true")
    main(parser.parse_args())
