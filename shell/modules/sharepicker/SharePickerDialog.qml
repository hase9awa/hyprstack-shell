pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils

DialogWindow {
    id: root

    required property var sharePicker
    required property var request
    // The portal hands over whole outputs and the windows it can capture; a
    // rectangle is drawn on the screen itself rather than picked from a list.
    property bool showWindows
    readonly property var entries: {
        if (root.showWindows)
            return root.request.windows.map(window => ({
                        selection: `window:${window.handle}`,
                        // The class names the application and the title the
                        // document, which is the order they are read in.
                        name: window.class || window.title,
                        detail: window.class ? window.title : "",
                        icon: Icons.getAppIcon(window.class, "application-x-executable"),
                        symbol: "web_asset"
                    }));
        return Screens.screens.map(screen => ({
                    selection: `screen:${screen.name}`,
                    name: screen.name,
                    detail: `${screen.width}×${screen.height}`,
                    icon: "",
                    symbol: "monitor"
                }));
    }
    readonly property string selected: entries[list.currentIndex]?.selection ?? ""

    function submit(): void {
        if (!root.selected)
            return;
        root.sharePicker.submit(root.request, root.selected, tokenSwitch.checked);
    }

    function cancel(): void {
        root.sharePicker.cancel(root.request);
    }

    name: "sharepicker"
    visible: !request.picking
    dialogWidth: Math.min(440 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    dialogHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onEntriesChanged: if (list.currentIndex >= entries.length) list.currentIndex = entries.length - 1

    StyledRect {
        objectName: "sharePickerSurface"
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainer
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        ColumnLayout {
            id: contents

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.large

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 48 * Tokens.scale
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "screen_share"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        objectName: "sharePickerTitle"
                        Layout.fillWidth: true
                        text: Tr.tr("Share your screen")
                        font: Tokens.font.title.medium
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    StyledText {
                        Layout.fillWidth: true
                        // The portal does not say which application asked,
                        // only that one did.
                        text: Tr.tr("Choose what an application may capture")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconTextButton {
                    objectName: "sharePickerScreens"
                    type: root.showWindows ? IconTextButton.Tonal : IconTextButton.Filled
                    verticalPadding: Tokens.padding.extraSmall
                    text: Tr.trCtx("Screens", "share source")
                    icon: "monitor"
                    activeFocusOnTab: true
                    onClicked: {
                        root.showWindows = false;
                        list.currentIndex = 0;
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                IconTextButton {
                    objectName: "sharePickerWindows"
                    // Without the toplevel protocol the portal offers no
                    // windows at all, and there is nothing to switch to.
                    visible: root.request.windows.length > 0
                    type: root.showWindows ? IconTextButton.Filled : IconTextButton.Tonal
                    verticalPadding: Tokens.padding.extraSmall
                    text: Tr.trCtx("Windows", "share source")
                    icon: "web_asset"
                    activeFocusOnTab: true
                    onClicked: {
                        root.showWindows = true;
                        list.currentIndex = 0;
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                IconTextButton {
                    objectName: "sharePickerRegion"
                    type: IconTextButton.Tonal
                    verticalPadding: Tokens.padding.extraSmall
                    // The overlay the recorder already sends one to, so the
                    // gesture is a familiar one.
                    text: Tr.trCtx("Region", "share source")
                    icon: "screenshot_region"
                    activeFocusOnTab: true
                    onClicked: root.sharePicker.pickRegion(root.request, tokenSwitch.checked)
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            VerticalFadeListView {
                id: list

                objectName: "sharePickerList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(contentHeight, 320 * Tokens.scale)
                visible: count > 0
                clip: true
                focus: true
                spacing: Tokens.spacing.extraSmall
                model: root.entries

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: list
                }

                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                Keys.onEscapePressed: event => {
                    root.cancel();
                    event.accepted = true;
                }

                delegate: StyledRect {
                    id: entry

                    required property int index
                    required property var modelData
                    readonly property bool selected: entry.index === list.currentIndex

                    width: list.width
                    implicitHeight: entryInner.implicitHeight + Tokens.padding.medium * 2

                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3secondaryContainer, selected ? 1 : 0)

                    StateLayer {
                        color: entry.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        onClicked: list.currentIndex = entry.index
                        onDoubleClicked: {
                            list.currentIndex = entry.index;
                            root.submit();
                        }
                    }

                    RowLayout {
                        id: entryInner

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        anchors.leftMargin: Tokens.padding.large
                        anchors.rightMargin: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            visible: !entry.modelData.icon
                            text: entry.modelData.symbol
                            color: entry.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }

                        CachingIconImage {
                            visible: entry.modelData.icon
                            implicitSize: 24 * Tokens.scale
                            source: entry.modelData.icon
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: entry.modelData.name
                                color: entry.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: text.length > 0
                                text: entry.modelData.detail
                                color: entry.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.medium
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.medium
                Layout.bottomMargin: Tokens.spacing.medium
                visible: list.count === 0
                horizontalAlignment: Text.AlignHCenter
                text: root.showWindows ? Tr.tr("No windows to share") : Tr.tr("No screens to share")
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Tr.tr("Let it share this again without asking")
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledSwitch {
                    id: tokenSwitch

                    objectName: "sharePickerToken"
                    // The portal says whether it would rather hand one out
                    // than ask again, and the answer is still the user's.
                    checked: root.request.allowToken
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    objectName: "sharePickerCancel"
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.cancel()
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                TextButton {
                    objectName: "sharePickerShare"
                    text: Tr.trCtx("Share", "button")
                    disabled: !root.selected
                    activeFocusOnTab: !disabled
                    onClicked: root.submit()
                    Keys.onReturnPressed: root.submit()
                    Keys.onSpacePressed: root.submit()
                }
            }
        }
    }
}
