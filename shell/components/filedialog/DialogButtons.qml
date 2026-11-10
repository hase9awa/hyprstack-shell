pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import "Filters.js" as Filters

StyledRect {
    id: root

    required property var dialog
    required property FolderContents folder

    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

        spacing: Tokens.spacing.small

        Loader {
            asynchronous: true
            visible: active
            active: root.dialog.mode === FileDialog.Save

            sourceComponent: StyledText {
                text: Tr.trCtx("Name:", "file name field")
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.rightMargin: Tokens.spacing.medium

            asynchronous: true
            visible: active
            active: root.dialog.mode === FileDialog.Save

            sourceComponent: StyledTextField {
                objectName: "fileDialogName"
                text: root.dialog.saveName
                placeholderText: Tr.tr("File name")
                onTextChanged: root.dialog.saveName = text
                onAccepted: root.dialog.submit()
            }
        }

        StyledText {
            visible: root.dialog.mode !== FileDialog.SelectFolder
            text: Tr.trCtx("Filter:", "file filter")
        }

        StyledRect {
            id: filterBox

            readonly property bool switchable: root.dialog.groups.length > 1

            Layout.fillWidth: root.dialog.mode !== FileDialog.Save
            Layout.fillHeight: true
            Layout.rightMargin: Tokens.spacing.medium

            visible: root.dialog.mode !== FileDialog.SelectFolder
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: filterRow.implicitWidth + Tokens.padding.medium * 2

            StateLayer {
                radius: parent.radius
                disabled: !filterBox.switchable
                // Portals rarely offer more than a handful of sets, so the
                // box steps through them instead of growing a menu.
                onClicked: root.dialog.currentFilter = (root.dialog.currentFilter + 1) % root.dialog.groups.length
            }

            RowLayout {
                id: filterRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium

                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    text: {
                        const group = root.dialog.activeGroup;
                        if (!group)
                            return "";
                        const patterns = (group.patterns ?? []).map(f => Filters.display(f)).join(Tr.trCtx(", ", "file filter separator"));
                        // TRANSLATORS: %1 = filter label, %2 = file patterns
                        return Tr.trCtx("%1 (%2)", "file filter label and patterns").arg(group.label).arg(patterns);
                    }
                    elide: Text.ElideRight
                }

                Loader {
                    asynchronous: true
                    active: filterBox.switchable
                    visible: active

                    sourceComponent: MaterialIcon {
                        text: "swap_horiz"
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        StyledRect {
            objectName: "fileDialogAccept"
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: acceptText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: acceptText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                disabled: !root.dialog.selectionValid
                onClicked: root.dialog.submit()
            }

            StyledText {
                id: acceptText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: root.dialog.overwriting ? Tr.trCtx("Replace", "button") : root.dialog.acceptLabel
                color: root.dialog.selectionValid ? Colours.palette.m3onSurface : Colours.palette.m3outline
            }
        }

        StyledRect {
            objectName: "fileDialogCancel"
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: cancelText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: cancelText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: {
                    root.dialog.rejected();
                }
            }

            StyledText {
                id: cancelText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: Tr.trCtx("Cancel", "button")
            }
        }
    }
}
