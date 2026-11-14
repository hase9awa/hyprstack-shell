pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Hyprstack.Components
import Hyprstack.Config
import Hyprstack.I18n
import Hyprstack.Models
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Wallpapers")
    isSubPage: true

    // The folder dialog walks the wallpapers directory as segments, with the
    // home directory named rather than spelled out.
    function wallDirSegments(): list<string> {
        const dir = Paths.wallsdir;
        if (!dir || dir === Paths.home)
            return ["Home"];
        if (dir.startsWith(`${Paths.home}/`))
            return ["Home", ...dir.slice(Paths.home.length + 1).split("/")];
        return dir.split("/");
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "photo_library"
                text: Tr.tr("Browse")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: browseDialog.open()

                FileDialog {
                    id: browseDialog

                    title: Tr.tr("Select an image")
                    filterLabel: Tr.tr("Image files")
                    filters: Images.validImageExtensions
                    onAccepted: paths => {
                        Wallpapers.setWallpaper(paths[0]);
                        root.nState.closeSubPage();
                    }
                }
            }

            IconTextButton {
                icon: "shuffle"
                text: Tr.tr("Random")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                type: IconTextButton.Tonal
                onClicked: {
                    Wallpapers.setRandom();
                    root.nState.closeSubPage();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Local wallpapers")
                    font: Tokens.font.title.small
                    elide: Text.ElideMiddle
                }

                // The folder the grid and the random button both read from.
                StyledText {
                    Layout.fillWidth: true
                    text: Paths.shortenHome(Paths.wallsdir)
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                    elide: Text.ElideMiddle
                }
            }

            IconButton {
                icon: "folder"
                type: IconButton.Tonal
                Accessible.name: Tr.trCtx("Select folder", "button")
                onClicked: dirDialog.open()

                FileDialog {
                    id: dirDialog

                    mode: FileDialog.SelectFolder
                    title: Tr.tr("Select a folder with wallpapers")
                    cwd: root.wallDirSegments()
                    onAccepted: paths => {
                        if (paths[0] !== Paths.wallsdir)
                            GlobalConfig.paths.wallpaperDir = paths[0];
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            visible: Wallpapers.list.length > 0

            columns: Config.nexus.wallpapersPerRow
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.large

            Repeater {
                id: localWalls

                model: {
                    const walls = Wallpapers.list;
                    const baseDir = Paths.wallsdir;
                    const categories = {};
                    const list = [];
                    for (const w of walls) {
                        if (w.parentDir !== baseDir) {
                            const category = Wallpapers.getCategoryFor(w);
                            if (category && (!(category in categories) || categories[category].name.localeCompare(w.name) > 0))
                                categories[category] = w;
                        } else {
                            list.push(w);
                        }
                    }
                    list.push(...Object.values(categories));
                    list.sort((a, b) => ((a.parentDir === baseDir) - (b.parentDir === baseDir)) || a.name.localeCompare(b.name));
                    while (list.length < Config.nexus.wallpapersPerRow)
                        list.push(null);
                    return list;
                }

                WallItem {
                    required property FileSystemEntry modelData

                    // Empty placeholders for sizing
                    opacity: modelData ? 1 : 0
                    enabled: modelData

                    source: String(modelData?.path ?? "")
                    text: {
                        if (!modelData)
                            return "";

                        if (modelData.parentDir !== Paths.wallsdir) {
                            const category = Wallpapers.getCategoryFor(modelData);
                            return category.slice(0, 1).toUpperCase() + category.slice(1);
                        }
                        return modelData.name;
                    }
                    onClicked: {
                        if (modelData.parentDir !== Paths.wallsdir) {
                            root.nState.selectedWallpaperCategory = Wallpapers.getCategoryFor(modelData);
                            root.nState.openSubPage(2); // Category page
                        } else {
                            Wallpapers.setWallpaper(modelData.path);
                            root.nState.closeSubPage();
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true

            asynchronous: true
            active: Wallpapers.list.length === 0
            visible: active

            sourceComponent: StyledRect {
                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.extraLarge
                implicitHeight: noWallsLayout.implicitHeight + Tokens.padding.extraExtraLarge * 2

                ColumnLayout {
                    id: noWallsLayout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Tr.tr("No local wallpapers found")
                        color: Colours.palette.m3outline
                        font: Tokens.font.title.small
                    }

                    IconTextButton {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Tokens.spacing.medium
                        icon: "folder"
                        text: Tr.trCtx("Select folder", "button")
                        type: IconTextButton.Tonal
                        onClicked: dirDialog.open()
                    }
                }
            }
        }
    }
}
