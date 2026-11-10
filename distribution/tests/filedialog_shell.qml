// Disposable file-dialog test display; never used by the desktop session.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import qs.components.filedialog
import qs.services

ShellRoot {
    id: root
    settings.watchFiles: false
    property list<string> acceptedPaths: []
    property bool cancelled: false
    Component.onCompleted: { AnimationClock.activate(); Dialogs; }

    FloatingWindow {
        id: underlay
        title: "File dialog test underlay"
        implicitWidth: 1000
        implicitHeight: 650
        visible: true
        color: "#234567"
    }

    FileDialog {
        id: chooser
        onAccepted: paths => root.acceptedPaths = paths
        onRejected: root.cancelled = true
    }

    function items(item: var): var {
        let result = [item];
        for (const child of item.children ?? [])
            result = result.concat(root.items(child));
        return result;
    }
    function dialog(): var { return Dialogs.dialogs.find(d => d.name === "filechooser") ?? null; }
    function find(name: string): var {
        const win = dialog();
        return win ? items(win.contentItem).find(item => item.objectName === name) ?? null : null;
    }

    IpcHandler {
        target: "fileDialogTest"
        function start(mode: int, path: string, multiple: bool): void {
            root.acceptedPaths = [];
            root.cancelled = false;
            chooser.mode = mode;
            chooser.cwd = path.split("/");
            chooser.multiple = multiple;
            chooser.suggestedName = "saved file.txt";
            chooser.filters = ["*"];
            chooser.open();
        }
        function status(): string {
            const win = root.dialog();
            const folder = root.find("fileDialogContents");
            const view = root.find("fileDialogEntries");
            return JSON.stringify({open: !!win, accepted: root.acceptedPaths, cancelled: root.cancelled,
                path: win?.currentPath ?? "", error: win?.errorMessage ?? "", hidden: win?.showHidden ?? false,
                selected: folder?.selectedPaths ?? [], saveName: win?.saveName ?? "",
                current: view?.currentItem?.modelData?.path ?? "",
                viewMode: FileDialogSettings.viewMode, sortBy: FileDialogSettings.sortBy,
                reverse: FileDialogSettings.reverse, preferencesLoaded: FileDialogSettings.loaded,
                entries: view ? [...view.model.entries].map(e => e.name) : [],
                files: view ? [...view.model.entries].filter(e => !e.isDir).map(e => e.name) : [],
                icons: win ? root.items(win.contentItem).filter(i => i.objectName === "fileDialogImage")
                    .map(i => ({source: i.source.toString(), status: i.status, visible: i.visible})) : []});
        }
        function rect(name: string): string {
            const item = root.find(name);
            if (!item) return "null";
            const pos = item.mapToItem(null, item.width / 2, item.height / 2);
            return JSON.stringify({x:pos.x, y:pos.y});
        }
    }
}
