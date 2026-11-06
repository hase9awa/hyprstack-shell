pragma Singleton

import QtQuick
import Quickshell
import Hyprstack
import Hyprstack.Config

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // The folders the desktop keeps for the user, under the names this
    // system gave them: XDG writes them in the user's own language, so
    // these are not "Downloads" and "Pictures" everywhere.
    readonly property string desktop: Quickshell.env("XDG_DESKTOP_DIR") || CUtils.userDirectory("desktop")
    readonly property string documents: Quickshell.env("XDG_DOCUMENTS_DIR") || CUtils.userDirectory("documents")
    readonly property string downloads: Quickshell.env("XDG_DOWNLOAD_DIR") || CUtils.userDirectory("downloads")
    readonly property string music: Quickshell.env("XDG_MUSIC_DIR") || CUtils.userDirectory("music")
    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || CUtils.userDirectory("pictures")
    readonly property string videos: Quickshell.env("XDG_VIDEOS_DIR") || CUtils.userDirectory("videos")

    readonly property string data: `${Quickshell.env("XDG_DATA_HOME") || `${home}/.local/share`}/hyprstack`
    readonly property string state: `${Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`}/hyprstack`
    readonly property string cache: `${Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`}/hyprstack`
    readonly property string config: `${Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`}/hyprstack`

    readonly property string imagecache: `${cache}/imagecache`
    readonly property string notifimagecache: `${imagecache}/notifs`
    readonly property string wallsdir: Quickshell.env("HYPRSTACK_WALLPAPERS_DIR") || absolutePath(GlobalConfig.paths.wallpaperDir)
    readonly property string recsdir: Quickshell.env("HYPRSTACK_RECORDINGS_DIR") || `${videos}/Recordings`
    readonly property string shotsdir: Quickshell.env("HYPRSTACK_SCREENSHOTS_DIR") || `${pictures}/Screenshots`
    readonly property string libdir: Quickshell.env("HYPRSTACK_LIB_DIR") || "/usr/lib/hyprstack"

    function toLocalFile(path: url): string {
        path = Qt.resolvedUrl(path);
        return path.toString() ? CUtils.toLocalFile(path) : "";
    }

    function fileUrl(path: string): string {
        return path.startsWith("/") ? "file://" + path.split("/").map(encodeURIComponent).join("/") : path;
    }

    function absolutePath(path: string): string {
        return toLocalFile(path.replace(/~|(\$({?)HOME(}?))+/, home));
    }

    function shortenHome(path: string): string {
        return path.replace(home, "~");
    }
}
