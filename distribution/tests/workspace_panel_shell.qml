// Workspace bar integration fixture: private display and D-Bus only.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.Components
import qs.services
import qs.modules.drawers

ShellRoot {
    id: root
    settings.watchFiles: false
    Component.onCompleted: AnimationClock.activate()
    Binding { target: ShellState; property: "shellRoot"; value: root }
    Drawers {}
    FloatingWindow { title: "Workspace test client"; implicitWidth: 500; implicitHeight: 400; color: "#234567"; visible: true }
    function findItem(item: var, name: string): var {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const found = findItem(child, name); if (found) return found; }
        return null;
    }
    IpcHandler {
        target: "workspaceTest"
        function status(): string {
            return JSON.stringify(Quickshell.screens.map(screen => {
                const win = ShellState.componentsFor(screen)?.rootWindow;
                const bar = win?.bar?.content;
                const item = bar ? root.findItem(bar, "taskbarWorkspaces") : null;
                return {screen:screen.name, lua:Hypr.usingLua, layout:Hypr.layoutMode,
                    monitor:Hypr.monitorFor(screen)?.name, active:item?.activeWsId,
                    special:item?.onSpecial, raw:Hypr.monitorFor(screen)?.lastIpcObject.specialWorkspace,
                    fullscreen:win?.hasFullscreen, size:item ? [item.width,item.height] : [],
                    workspaceIds:item?.wsIds, entries:item?.workspaces.map(w => {
                        const pos = w.mapToItem(win.contentItem, w.width/2,w.LazyListView.visibleHeight/2);
                        return {id:w.ws,x:pos.x,y:pos.y,width:w.width,height:w.height};
                    })};
            }));
        }
    }
}
