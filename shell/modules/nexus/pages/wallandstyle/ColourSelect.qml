pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Colours")
    isSubPage: true
    objectName: "colourSchemesPage"

    property string mode: Colours.currentLight ? "light" : "dark"
    property bool showEditor
    property string editorMode: "dark"
    property var draft: ({dark: {}, light: {}})
    readonly property bool draftValid: themeName.text.trim().length > 0
        && ["dark", "light"].every(m => ["background", "foreground", "accent"].every(k => /^#?[0-9a-fA-F]{6}$/.test(draft[m][k] ?? "")))

    function beginCreate(): void {
        const theme = ThemeSchemes.currentTheme ?? ThemeSchemes.themes[0];
        if (!theme)
            return;
        const data = {};
        for (const mode of ["dark", "light"]) {
            const colours = (theme.variants.find(v => v.mode === mode && v.accent === Colours.accent)
                ?? theme.variants.find(v => v.mode === mode) ?? ThemeSchemes.themes[0].variants.find(v => v.mode === mode)).colours;
            data[mode] = {background: "#" + colours.surface, foreground: "#" + colours.onSurface, accent: "#" + colours.primary};
        }
        draft = data;
        showEditor = true;
        Qt.callLater(() => {
            root.flickable.contentY = Math.max(0, editorCard.y);
            themeName.forceActiveFocus();
        });
    }

    readonly property FileDialog importDialog: FileDialog {
        title: Tr.tr("Import a colour scheme")
        filterLabel: Tr.tr("Colour schemes")
        filters: ["json", "txt"]
        onAccepted: path => ThemeSchemes.importFile(Paths.toLocalFile(path), root.mode)
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        Flow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Tokens.spacing.small

            Repeater {
                model: [{id: "dark", label: Tr.tr("Dark")}, {id: "light", label: Tr.tr("Light")}]

                TextButton {
                    required property var modelData

                    objectName: "colourMode_" + modelData.id
                    text: modelData.label
                    type: TextButton.Tonal
                    isToggle: true
                    checked: root.mode === modelData.id
                    onClicked: root.mode = modelData.id
                }
            }

            IconTextButton {
                icon: "file_open"
                text: Tr.tr("Import")
                type: IconTextButton.Tonal
                disabled: ThemeSchemes.busy
                onClicked: root.importDialog.open()
            }

            IconButton {
                objectName: "createColourScheme"
                icon: "add"
                type: IconButton.Tonal
                disabled: ThemeSchemes.busy || !ThemeSchemes.themes.length
                onClicked: root.beginCreate()
                Accessible.name: Tr.tr("Create a colour scheme")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: Tr.tr("Choose a palette for the shell, window decorations and synchronized applications.")
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        Repeater {
            model: ThemeSchemes.themes

            StyledRect {
                id: card

                required property var modelData
                readonly property bool selected: (modelData.id === Colours.scheme || modelData.aliases.includes(Colours.scheme))
                    && root.mode === (Colours.currentLight ? "light" : "dark")
                readonly property var variants: modelData.variants.filter(v => v.mode === root.mode)
                readonly property var accents: {
                    const unique = [], colours = {};
                    for (const variant of variants) {
                        const key = variant.colours.primary;
                        if (colours[key]) {
                            colours[key].accentAliases.push(variant.accent);
                        } else {
                            const entry = {accent: variant.accent, accentLabel: variant.accentLabel,
                                flavour: variant.flavour, colours: variant.colours, accentAliases: [variant.accent]};
                            colours[key] = entry;
                            unique.push(entry);
                        }
                    }
                    return unique;
                }
                readonly property var variant: variants.find(v => selected && v.flavour === Colours.flavour) ?? variants[0] ?? null

                objectName: "colourScheme_" + modelData.id
                Layout.fillWidth: true
                visible: variant !== null
                implicitHeight: content.implicitHeight + Tokens.padding.medium * 2
                    + (accentList.visible ? accentList.implicitHeight + Tokens.spacing.small : 0)
                radius: Tokens.rounding.large
                color: Colours.layer(card.selected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh, 2)
                border.width: card.selected ? 2 : 0
                border.color: Colours.palette.m3primary

                HoverHandler {
                    id: cardHover

                    enabled: !ThemeSchemes.busy
                }

                StateLayer {
                    objectName: "applyColourScheme_" + card.modelData.id
                    manualHoverOverride: cardHover.hovered
                    disabled: ThemeSchemes.busy
                    onClicked: ThemeSchemes.apply(card.modelData.id, root.mode)
                }

                RowLayout {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.medium
                    height: implicitHeight
                    spacing: Tokens.spacing.medium

                    Rectangle {
                        Layout.preferredWidth: 92 * Tokens.scale
                        Layout.preferredHeight: 50 * Tokens.scale
                        radius: Tokens.rounding.small
                        color: "#" + (card.variant?.colours.surface ?? "000000")
                        border.width: 1
                        border.color: "#" + (card.variant?.colours.outlineVariant ?? "808080")

                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 8 * Tokens.scale
                            text: "Aa"
                            color: "#" + (card.variant?.colours.onSurface ?? "ffffff")
                            font: Tokens.font.body.medium
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 8 * Tokens.scale
                            spacing: 4 * Tokens.scale

                            Repeater {
                                model: ["primary", "term1", "term2", "term3", "term4", "term5", "term6"]
                                Rectangle {
                                    required property string modelData
                                    width: 7 * Tokens.scale
                                    height: 7 * Tokens.scale
                                    radius: width / 2
                                    color: "#" + (card.variant?.colours[modelData] ?? "ffffff")
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2 * Tokens.scale

                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.name
                            textFormat: Text.PlainText
                            Layout.minimumWidth: 0
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: (card.variant?.label ?? "") + " · " + Tr.tr(card.variant?.accentLabel ?? "Default")
                                + (card.modelData.custom ? " · " + Tr.tr("Custom") : "")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            Layout.minimumWidth: 0
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }

                    MaterialIcon {
                        visible: card.selected
                        text: "check_circle"
                        color: Colours.palette.m3primary
                    }
                }

                Flow {
                    id: accentList

                    objectName: "colourAccents_" + card.modelData.id
                    anchors.top: content.bottom
                    anchors.topMargin: Tokens.spacing.small
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    visible: card.accents.length > 1
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: card.accents

                        StyledRect {
                            id: swatch

                            required property var modelData
                            readonly property bool selected: card.selected && modelData.accentAliases.includes(Colours.accent)
                            readonly property string selectionAccent: selected ? Colours.accent : modelData.accent
                            objectName: "colourAccent_" + card.modelData.id + "_" + modelData.accent
                            width: accentContent.implicitWidth + Tokens.padding.small * 2
                            height: 32 * Tokens.scale
                            radius: Tokens.rounding.full
                            color: selected ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainer
                            border.width: selected ? 2 : 1
                            border.color: selected ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                            activeFocusOnTab: true
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: card.modelData.name + " · " + Tr.tr(modelData.accentLabel)
                            Accessible.checked: selected
                            Keys.onReturnPressed: ThemeSchemes.apply(card.modelData.id, root.mode, selectionAccent)
                            Keys.onSpacePressed: ThemeSchemes.apply(card.modelData.id, root.mode, selectionAccent)

                            StateLayer {
                                disabled: ThemeSchemes.busy
                                onClicked: ThemeSchemes.apply(card.modelData.id, root.mode, swatch.selectionAccent)
                            }

                            Row {
                                id: accentContent
                                anchors.centerIn: parent
                                spacing: Tokens.spacing.small

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14 * Tokens.scale
                                    height: width
                                    radius: width / 2
                                    color: "#" + swatch.modelData.colours.primary
                                }
                                StyledText {
                                    text: Tr.tr(swatch.modelData.accentLabel)
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            id: editorCard

            Layout.fillWidth: true
            visible: root.showEditor
            implicitHeight: editor.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: editor

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText { text: Tr.tr("Create a colour scheme"); font: Tokens.font.title.medium }

                StyledTextField {
                    id: themeName

                    objectName: "customThemeName"
                    Layout.fillWidth: true
                    placeholderText: Tr.tr("Theme name")
                    maximumLength: 80
                }

                RowLayout {
                    Repeater {
                        model: [{id: "dark", label: Tr.tr("Dark")}, {id: "light", label: Tr.tr("Light")}]
                        TextButton {
                            required property var modelData
                            text: modelData.label
                            type: TextButton.Tonal
                            isToggle: true
                            checked: root.editorMode === modelData.id
                            onClicked: root.editorMode = modelData.id
                        }
                    }
                }

                Repeater {
                    model: [{key: "background", label: Tr.tr("Background")},
                            {key: "foreground", label: Tr.tr("Text")}, {key: "accent", label: Tr.tr("Accent")}]

                    RowLayout {
                        id: colourRow
                        required property var modelData

                        Layout.fillWidth: true
                        StyledText { Layout.fillWidth: true; text: colourRow.modelData.label }
                        StyledTextField {
                            Layout.preferredWidth: 160 * Tokens.scale
                            text: root.draft[root.editorMode][colourRow.modelData.key] ?? ""
                            placeholderText: "#RRGGBB"
                            maximumLength: 7
                            validate: /^#?[0-9a-fA-F]{6}$/
                            emptyIsValid: false
                            onTextEdited: {
                                const draft = Object.assign({}, root.draft);
                                draft[root.editorMode] = Object.assign({}, draft[root.editorMode], {[colourRow.modelData.key]: text});
                                root.draft = draft;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    TextButton {
                        text: Tr.tr("Cancel")
                        type: TextButton.Text
                        onClicked: root.showEditor = false
                    }
                    TextButton {
                        objectName: "saveCustomTheme"
                        text: Tr.tr("Save & apply")
                        disabled: !root.draftValid || ThemeSchemes.busy
                        onClicked: {
                            ThemeSchemes.create(themeName.text.trim(), root.draft, root.mode);
                            root.showEditor = false;
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: ThemeSchemes.error !== ""
            text: ThemeSchemes.error
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Colours.palette.m3error
        }

        StyledText {
            Layout.fillWidth: true
            visible: ThemeSchemes.catalogueErrors.length > 0
            text: ThemeSchemes.catalogueErrors.join("\n")
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Colours.palette.m3error
        }
    }
}
