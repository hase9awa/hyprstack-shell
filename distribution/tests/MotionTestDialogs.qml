pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Hyprstack.Portals
import qs.components.filedialog
import qs.modules.sharepicker
import qs.modules.areapicker
import qs.modules.network as NetworkDialogs
import qs.modules.bluetooth as BluetoothDialogs
import qs.modules.portals as PortalDialogs
import qs.services

Item {
    id: root
    property var window: null
    property string kind
    property string error
    property int cancelled: 0
    property int submitted: 0
    property var frames: []
    property bool tracing: false
    PortalHost {
        id: portalHost
        AppChooserPortal { id: chooserPortal }
    }
    PortalDialogs.AppChooser { portal: chooserPortal }
    Connections {
        target: Dialogs
        function onDialogsChanged(): void {
            if(root.kind==="chooser")
                root.window=Dialogs.dialogs.find(w=>w.name==="appchooser")??null;
        }
    }

    QtObject {
        id: fake
        property bool isResponseRequired: true
        property bool isCompleted: false
        property bool isCancelled: false
        property bool responseVisible: false
        property string inputPrompt: "Password:"
        property string message: "Animation test"
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool failed: false
        property var identities: []
        property var selectedIdentity: null
        signal authenticationFailed
        function cancelAuthenticationRequest(): void { ++root.cancelled; }
        function cancel(request: var): void { ++root.cancelled; }
        function submit(request: var, value: var): void { ++root.submitted; }
    }
    FileDialog {
        id: files
        onRejected: ++root.cancelled
    }
    Connections {
        target: files
        function onItemChanged(): void {if(root.kind==="files")root.window=files.item;}
    }
    TestCase { id: input; when: false }

    function find(item, predicate) {
        if(predicate(item)) return item;
        for(const child of item.children ?? []) {
            const found=find(child,predicate);
            if(found) return found;
        }
        return null;
    }
    function liquid() { return window ? find(window.contentItem,i=>i.objectName==="dialogGoopSurface") : null; }
    function compileAll(): string {
        for(const path of ["network/SecretDialog","bluetooth/PairDialog","portals/AccessDialog",
            "portals/AppChooserDialog","portals/WallpaperDialog"]) {
            const comp=Qt.createComponent(Qt.resolvedUrl("modules/"+path+".qml"));
            if(comp.status!==Component.Ready) return comp.errorString();
        }
        return "";
    }
    function rect(name: string): var {
        const item=window?find(window.contentItem,i=>i.objectName===name):null;
        if(!item)return null;
        const p=item.mapToItem(window.contentItem,item.width/2,item.height/2);
        return {x:p.x,y:p.y};
    }
    function open(name: string): void {
        close();
        kind=name; cancelled=0; submitted=0; frames=[]; error="";
        if(name==="files") {
            files.open();
            window=files.item;
        } else if(name!=="chooser") {
            const paths={askpass:"askpass/AskpassDialog",polkit:"polkit/AuthDialog",
                share:"sharepicker/SharePickerDialog",screenshot:"areapicker/ScreenshotPreview"};
            const props=name==="askpass"?{askpass:fake,request:{prompt:"Animation test"}}:
                name==="polkit"?{flow:fake}:name==="share"?{sharePicker:fake,request:{windows:[],picking:false,restoreToken:"",allowToken:false}}:
                {path:Quickshell.env("MOTION_TEST_IMAGE")};
            props.screen=Quickshell.screens[0];props.visible=true;
            const comp=Qt.createComponent(Qt.resolvedUrl("modules/"+paths[name]+".qml"));
            if(comp.status!==Component.Ready) {error=comp.errorString();return;}
            window=comp.createObject(root,props);
            if(!window)error=comp.errorString();
        }
        tracing=true;
    }
    function close(): void {
        tracing=false;
        if(window) {
            if(kind==="chooser") window.request.reject();
            else if(kind==="files") files.close();
            else window.destroy();
        }
        window=null;
    }
    function interact(action: string): void {
        const flow=liquid();
        if(!flow) return;
        if(action==="hover") input.mouseMove(flow.hoverTarget,flow.width*.5,flow.height*.5);
        else if(action==="type") {
            const field=find(window.contentItem,i=>i.objectName===(kind==="polkit"?"polkitResponse":"askpassSecret"));
            if(field) {field.forceActiveFocus();field.text="fixture";}
        }
        else if(action==="reveal" && kind==="polkit") window.revealResponse=!window.revealResponse;
        else if(action==="challenge" && kind==="polkit") fake.responseVisible=true;
        else if(action==="cancel") window.closeRequested();
    }
    function status(): var {
        const flow=liquid();
        const entries=window && kind==="files"?find(window.contentItem,i=>i.objectName==="fileDialogEntries"):null;
        const shapes=window && kind==="polkit"?find(window.contentItem,i=>i.objectName==="polkitPasswordShapes"):null;
        const response=window && kind==="polkit"?find(window.contentItem,i=>i.objectName==="polkitResponse"):null;
        return {kind:kind,error:error,ready:!!flow,visible:window?.visible??false,
            opened:flow?.panelOpen??false,serial:flow?.serial??0,running:flow?.running??false,
            layer:flow?.contentTarget.layer.enabled??false,hovering:flow?.hovering??false,
            nativeWhenSettled:flow?.nativeContentWhenSettled??false,
            dripping:flow?.dripSerial??0,cancelled:cancelled,submitted:submitted,
            canSubmit:window?.canSubmit??false,focused:window?.inputFocused??false,
            passwordShapes:shapes?.visible?shapes.count:0,
            nativeTextVisible:response?.inputTextVisible??false,nativeTextAlpha:response?.color.a??0,
            files:entries?Array.from(entries.model.entries,e=>e.name):[],
            registered:window?Dialogs.dialogs.includes(window):false,frames:frames,
            pendingChoosers:chooserPortal.requests.length,portalReady:portalHost.registered};
    }
    FrameAnimation {
        running: root.tracing
        onTriggered: {
            const flow=root.liquid();
            if(flow?.running) root.frames.push({age:flow.age,progress:flow.progress,
                w:flow.renderFrame.body.w,h:flow.renderFrame.body.h,opacity:flow.contentOpacity,
                layer:flow.contentTarget.layer.enabled,dt:frameTime});
        }
    }
}
