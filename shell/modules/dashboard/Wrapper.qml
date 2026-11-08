pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.filedialog
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    required property bool atBottom
    readonly property FileDialog facePicker: FileDialog {
        title: Tr.tr("Select a profile picture")
        filterLabel: Tr.tr("Image files")
        filters: Images.validImageExtensions
        onAccepted: paths => {
            const path = paths[0];
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "hyprstack-shell", "-u", "low", "-h", `STRING:image-path:${path}`, Tr.tr("Profile picture changed"), Tr.tr("Profile picture changed to %1").arg(Paths.shortenHome(path))]);
            else
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "hyprstack-shell", "-u", "critical", Tr.tr("Unable to change profile picture"), Tr.tr("Failed to change profile picture to %1").arg(Paths.shortenHome(path))]);
        }
    }

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property real nonAnimWidth: (content.item as Content)?.nonAnimWidth ?? 0
    readonly property bool resizing: shouldBeActive && contentPrepared
        && (Math.abs(height - nonAnimHeight) > 0.5 || Math.abs(width - nonAnimWidth) > 0.5)
    readonly property bool shouldBeActive: screenState.dashboard && Config.dashboard.enabled
    property bool contentPrepared: false
    property bool retainContent: false
    property bool preparingGraphics: false
    property double lastClosedAt: Date.now()
    readonly property real contentHeight: content.implicitHeight
    // Retain the previous hit area until the pointer enters the resized panel
    // or leaves both areas. A small pointer movement must not close a tab.
    property real hoverHeight: 0
    property real hoverWidth: 0
    readonly property real interactionHeight: Math.max(height, hoverHeight)
    readonly property real interactionWidth: Math.max(width, hoverWidth)
    property real offsetScale: shouldBeActive && contentPrepared ? 0 : 1

    function prepareContent(): void {
        if (contentPrepared || preparingGraphics || content.status !== Loader.Ready
            || !(content.item as Content)?.readyToOpen)
            return;
        // Build text, shapes and shader pipelines offscreen while the drawer
        // is closed. Start its slide only after the first render is ready.
        preparingGraphics = true;
        if (!content.item.grabToImage(() => {
            root.preparingGraphics = false;
            root.contentPrepared = content.status === Loader.Ready;
        })) {
            preparingGraphics = false;
            contentPrepared = true;
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            implicitHeight = Qt.binding(() => contentHeight);
            // After idle, the GPU and the scenegraph's text/shape resources
            // can be cold even though the QML objects remain loaded. Finish
            // one offscreen draw before advancing the visible slide.
            if (Math.abs(Date.now() - lastClosedAt) > 2000) {
                contentPrepared = false;
                Qt.callLater(prepareContent);
            }
        } else {
            lastClosedAt = Date.now();
            hoverHeight = 0;
            hoverWidth = 0;
            implicitHeight = implicitHeight;
        }
    }

    visible: offsetScale < 1
    y: atBottom ? (parent?.height ?? 0) - height + (implicitHeight + 5) * offsetScale
        : (-implicitHeight - 5) * offsetScale
    implicitHeight: contentHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Timer {
        interval: 500
        running: root.Config.dashboard.enabled && !root.retainContent
        onTriggered: root.retainContent = true
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        height: root.height

        asynchronous: true
        active: Config.dashboard.enabled && (root.shouldBeActive || root.visible || root.retainContent)
        onActiveChanged: if (!active) root.contentPrepared = false
        onLoaded: Qt.callLater(() => {
            if (content.status === Loader.Ready) {
                root.retainContent = true;
                root.prepareContent();
            }
        })

        sourceComponent: Content {
            screenState: root.screenState
            facePicker: root.facePicker
        }
    }

    Connections {
        target: content.item
        function onReadyToOpenChanged(): void { root.prepareContent(); }
    }
}
