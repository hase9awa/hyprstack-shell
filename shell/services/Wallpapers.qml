pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import Hyprstack.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        // The CLI only knows the environment variable and its own default, so
        // the folder shown in the settings is passed to it explicitly.
        Quickshell.execDetached(["hyprstack", "wallpaper", "-r", Paths.wallsdir, ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["hyprstack", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;
        pendingPreviewClear = false;

        if (Colours.scheme === "dynamic")
            requestPreviewColours();
        else
            Colours.showPreview = false;
    }

    function requestPreviewColours(): void {
        if (!showPreview || Colours.scheme !== "dynamic" || getPreviewColoursProc.running)
            return;
        getPreviewColoursProc.requestedPath = previewPath;
        getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.actualCurrent = text().trim();
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = "";
            root.previewColourLock = false;
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    Process {
        id: getPreviewColoursProc

        property string requestedPath
        command: ["hyprstack", "wallpaper", "-p", requestedPath, ...root.smartArg]
        onExited: if (requestedPath !== root.previewPath) Qt.callLater(root.requestPreviewColours)
        stdout: StdioCollector {
            onStreamFinished: {
                // A cancelled preview must not replace the selected static
                // theme when its asynchronous colour extraction finishes.
                if (!root.showPreview || Colours.scheme !== "dynamic" || getPreviewColoursProc.requestedPath !== root.previewPath)
                    return;
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
