pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack

Singleton {
    id: root

    readonly property list<string> validImageTypes: ["jpeg", "png", "webp", "tiff", "svg"]
    readonly property list<string> validImageExtensions: ["jpg", "jpeg", "png", "webp", "tif", "tiff", "svg"]
    property string profilePicture

    function refreshProfilePicture(): void {
        profilePicture = CUtils.fileInfo(pictureFile.path).exists ? pictureFile.path : "";
    }

    Component.onCompleted: refreshProfilePicture()

    FileView {
        id: pictureFile
        path: Paths.home + "/.face"
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: {
            root.profilePicture = "";
            Qt.callLater(root.refreshProfilePicture);
        }
    }

    function isValidImageByName(name: string): bool {
        return validImageExtensions.some(t => name.endsWith(`.${t}`));
    }
}
