pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Portals
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

StyledWindow {
    id: root

    required property AppChooserRequest request
    readonly property string selected: request.choices[list.currentIndex] ?? ""
    // What the application is about to be opened with, most telling first.
    readonly property string subject: request.fileName || request.uri || request.contentType
    readonly property url subjectIcon: {
        const type = root.request.contentType;
        return type ? Quickshell.iconPath(type.replace("/", "-"), true) : "";
    }

    function selectDefault(): void {
        const choices = root.request.choices;
        const at = choices.indexOf(root.request.lastChoice);
        list.currentIndex = at >= 0 ? at : (choices.length > 0 ? 0 : -1);
    }

    function submit(): void {
        if (root.selected)
            root.request.choose(root.selected);
    }

    name: "appchooser"
    Config.screen: screen?.name ?? ""
    Tokens.screen: screen?.name ?? ""
    visible: !request.answered
    implicitWidth: Math.min(420 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    implicitHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: visible && request.modal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Component.onCompleted: selectDefault()

    Connections {
        target: root.request

        // The portal offers more applications once one is installed while
        // the dialog is still open.
        function onChoicesChanged(): void { root.selectDefault(); }
    }

    StyledRect {
        objectName: "appChooserSurface"
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
                        visible: !root.subjectIcon
                        text: "open_in_new"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }

                    CachingIconImage {
                        anchors.centerIn: parent
                        implicitSize: 28 * Tokens.scale
                        source: root.subjectIcon
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        objectName: "appChooserTitle"
                        Layout.fillWidth: true
                        text: Tr.tr("Open with")
                        font: Tokens.font.title.medium
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: text.length > 0
                        text: root.subject
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        elide: Text.ElideMiddle
                    }
                }
            }

            VerticalFadeListView {
                id: list

                objectName: "appChooserList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(contentHeight, 320 * Tokens.scale)
                visible: count > 0
                clip: true
                focus: true
                spacing: Tokens.spacing.extraSmall
                model: root.request.choices

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: list
                }

                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                Keys.onEscapePressed: event => {
                    root.request.reject();
                    event.accepted = true;
                }

                delegate: StyledRect {
                    id: app

                    required property int index
                    required property string modelData
                    readonly property bool selected: app.index === list.currentIndex
                    // Portals name applications by desktop entry id, which
                    // may or may not carry the suffix.
                    readonly property var entry: DesktopEntries.applications.values.find(e => e.id === app.modelData
                        || e.id === `${app.modelData}.desktop`) ?? null

                    width: list.width
                    implicitHeight: appInner.implicitHeight + Tokens.padding.medium * 2

                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3secondaryContainer, selected ? 1 : 0)

                    StateLayer {
                        color: app.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        onClicked: list.currentIndex = app.index
                        onDoubleClicked: {
                            list.currentIndex = app.index;
                            root.submit();
                        }
                    }

                    RowLayout {
                        id: appInner

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        anchors.leftMargin: Tokens.padding.large
                        anchors.rightMargin: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        CachingIconImage {
                            implicitSize: 24 * Tokens.scale
                            source: Quickshell.iconPath(app.entry?.icon ?? "", true) // qmllint disable missing-property
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: app.entry?.name ?? app.modelData // qmllint disable missing-property
                            color: app.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            elide: Text.ElideRight
                        }

                        MaterialIcon {
                            visible: app.modelData === root.request.lastChoice
                            text: "history"
                            color: app.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
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
                text: Tr.tr("No applications available")
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item { Layout.fillWidth: true }

                TextButton {
                    objectName: "appChooserCancel"
                    text: Tr.trCtx("Cancel", "button")
                    type: TextButton.Tonal
                    activeFocusOnTab: true
                    onClicked: root.request.reject()
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

                TextButton {
                    objectName: "appChooserOpen"
                    text: Tr.trCtx("Open", "button")
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
