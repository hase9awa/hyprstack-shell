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
import qs.utils

DialogWindow {
    id: root

    required property AppChooserRequest request
    // Offering only the handlers the portal found is the better default, but
    // it does miss applications that simply never claimed the type.
    property bool showAll
    readonly property var candidates: {
        if (!root.showAll)
            return root.request.choices;
        return [...DesktopEntries.applications.values].filter(e => !e.noDisplay)
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(e => root.idFor(e.id));
    }
    readonly property string selected: candidates[list.currentIndex] ?? ""
    readonly property var selectedEntry: entryFor(selected)
    // Desktop entry ids reach the portal with their suffix, while the entries
    // themselves are named without it.
    readonly property bool suffixed: request.choices.length > 0 && request.choices[0].endsWith(".desktop")
    // What the application is about to be opened with, most telling first.
    readonly property string subject: request.fileName || request.uri || request.contentType
    readonly property url subjectIcon: {
        const type = root.request.contentType;
        if (!type)
            return "";
        // Themes carry an icon for the exact type only for a handful of them,
        // so fall back to the family and then to a plain document.
        return Quickshell.iconPath(type.replace("/", "-"), true)
            || Quickshell.iconPath(`${type.split("/")[0]}-x-generic`, true)
            || Quickshell.iconPath("application-x-zerosize");
    }

    function entryFor(id: string): var {
        // Walking the model rather than calling byId keeps the lookup bound
        // to it: entries are scanned asynchronously and can land after the
        // dialog has already been built. An entry is named after its file
        // without the suffix, but a file called "a.desktop.desktop" leaves
        // one behind, so an exact match wins over a stripped one.
        const entries = DesktopEntries.applications.values;
        return entries.find(e => e.id === id)
            ?? entries.find(e => `${e.id}.desktop` === id)
            ?? null;
    }

    // Spell a pick of the shell's own the way the portal spells the ones it
    // offered: the same spelling comes back later as last_choice. The portal
    // names an application by its file, which is the entry id plus the
    // suffix, so the suffix is added rather than swapped in.
    function idFor(id: string): string {
        return root.suffixed ? `${id}.desktop` : id;
    }

    function selectDefault(): void {
        const at = root.candidates.indexOf(root.request.lastChoice);
        list.currentIndex = at >= 0 ? at : (root.candidates.length > 0 ? 0 : -1);
    }

    function submit(): void {
        if (!root.selected)
            return;

        // The association outlives this window, which the portal tears down
        // the moment it is answered, so hand it to a detached process. An
        // entry is named after its file without the suffix, so adding it
        // back names the file even when the id carries one of its own.
        if (defaultSwitch.checked && root.selectedEntry && root.request.contentType)
            Quickshell.execDetached(["xdg-mime", "default", `${root.selectedEntry.id}.desktop`,
                root.request.contentType]);

        root.request.choose(root.selected);
    }

    name: "appchooser"
    visible: !request.answered
    implicitWidth: Math.min(440 * Tokens.scale, (screen?.width ?? 528) - 48 * Tokens.scale)
    implicitHeight: Math.min(contents.implicitHeight + Tokens.padding.large * 2,
        (screen?.height ?? 720) - 48 * Tokens.scale)
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
                model: root.candidates

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
                    readonly property var entry: root.entryFor(app.modelData)
                    readonly property url appIcon: {
                        const icon = app.entry?.icon ? Quickshell.iconPath(app.entry.icon, true) : "";
                        return icon || Icons.getAppIcon(app.modelData, "application-x-executable");
                    }

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
                            source: app.appIcon
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            // The entry model fills in a moment after start, so
                            // name the application by its id until it does.
                            text: app.entry?.name || app.modelData
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
                // Without a type there is no association to record.
                visible: root.request.contentType.length > 0
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Tr.tr("Make it the default for this type")
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledSwitch {
                    id: defaultSwitch

                    objectName: "appChooserDefault"
                    // The file name is only known once the entry resolves.
                    disabled: !root.selectedEntry
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconTextButton {
                    objectName: "appChooserAll"
                    type: root.showAll ? IconTextButton.Filled : IconTextButton.Tonal
                    verticalPadding: Tokens.padding.extraSmall
                    text: Tr.tr("All applications")
                    icon: "apps"
                    activeFocusOnTab: true
                    onClicked: {
                        // Hold on to the pick across the swap, since the same
                        // application is usually in both lists.
                        const keep = root.selected;
                        root.showAll = !root.showAll;
                        const at = root.candidates.indexOf(keep);
                        if (at >= 0)
                            list.currentIndex = at;
                        else
                            root.selectDefault();
                        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onSpacePressed: clicked()
                }

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
