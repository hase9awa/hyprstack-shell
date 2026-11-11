import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Hyprstack
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import qs.services
import qs.utils

PageBase {
    id: root

    title: Tr.tr("Updates")

    readonly property string statusText: {
        switch (Updates.phase) {
        case "checking": return Tr.tr("Checking for updates…");
        case "downloading": return Tr.tr("Downloading the release…");
        case "building": return Tr.tr("Building the update… This may take several minutes.");
        case "starting":
        case "waiting": return Tr.tr("Waiting for the session to end…");
        case "installing": return Tr.tr("Installing the update…");
        case "done": return Tr.tr("Hyprstack was updated successfully");
        case "error": return Tr.tr("Update failed");
        }
        if (Updates.ready) return Tr.tr("The update is ready to install");
        if (Updates.available) return Tr.tr("A new version is available");
        if (Updates.report.no_releases) return Tr.tr("No releases have been published yet");
        if (Updates.report.checked_at) return Tr.tr("You are using the latest version");
        return Tr.tr("Check for a new Hyprstack release");
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Hyprstack version")
        }

        InfoRow {
            first: true
            label: Tr.tr("Installed version")
            value: CUtils.version
        }

        InfoRow {
            label: Tr.tr("Latest release")
            value: Updates.latestVersion || "—"
        }

        InfoRow {
            label: Tr.tr("Last checked")
            value: Updates.report.checked_at
                ? Qt.formatDateTime(new Date(Updates.report.checked_at * 1000), Qt.DefaultLocaleShortDate) : "—"
        }

        InfoRow {
            last: true
            label: root.statusText
            icon: Updates.busy ? "hourglass_top" : Updates.available ? "system_update" : "info"
        }

        StyledProgressBar {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: Updates.busy
            indeterminate: true
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: !!Updates.error
            text: Tr.tr("Unable to update Hyprstack: %1").arg(Updates.error)
            textFormat: Text.PlainText
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        SectionHeader { text: Tr.tr("Actions") }

        RowButton {
            objectName: "updatesCheck"
            first: true
            icon: "refresh"
            text: Tr.tr("Check for updates")
            disabled: Updates.busy
            onClicked: Updates.run("check")
        }

        RowButton {
            objectName: "updatesPrepare"
            icon: "download"
            text: Updates.ready ? Tr.tr("Prepare the update again") : Tr.tr("Download and prepare update")
            subtext: Tr.tr("You can keep working while the release downloads and builds.")
            disabled: Updates.busy || !Updates.available || !Updates.canInstall
            onClicked: Updates.run("prepare")
        }

        RowButton {
            objectName: "updatesInstall"
            last: true
            icon: "system_update"
            text: Tr.tr("Install update…")
            subtext: Tr.tr("Save your work. Installation ends the Hyprland session.")
            disabled: Updates.busy || !Updates.ready || !Updates.canInstall
            onClicked: installDialog.open()
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: !Updates.canInstall && !!Updates.report.install_reason
            text: Updates.report.install_reason === "nix"
                ? Tr.tr("On NixOS, update the hyprstack flake input and rebuild your NixOS or Home Manager configuration.")
                : Updates.report.install_reason === "systemd"
                    ? Tr.tr("Installation from Settings requires a systemd user session. Use update.sh from a TTY on this system.")
                    : Tr.tr("This installation is managed by your package manager or configuration. Update it there.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        RowButton {
            first: true
            last: true
            visible: !!Updates.report.log_exists && (Updates.ready || !!Updates.error)
            icon: "description"
            text: Tr.tr("Open update log")
            onClicked: Qt.openUrlExternally(Paths.fileUrl(Updates.report.log_path))
        }

        SectionHeader { text: Tr.tr("Automatic checks") }

        ToggleRow {
            first: true
            text: Tr.tr("Check for updates automatically")
            subtext: Tr.tr("Check stable releases at startup and every six hours.")
            checked: GlobalConfig.services.checkUpdates
            onToggled: GlobalConfig.services.checkUpdates = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Notify about new releases")
            subtext: Tr.tr("Show a small notification once for each new version.")
            checked: GlobalConfig.services.updateNotifications
            onToggled: GlobalConfig.services.updateNotifications = checked
        }

        SectionHeader {
            visible: !!Updates.report.release_url
            text: Tr.tr("Release notes")
        }

        RowButton {
            first: true
            last: true
            visible: !!Updates.report.release_url
            icon: "open_in_new"
            text: Tr.tr("Open release on GitHub")
            onClicked: Qt.openUrlExternally(Updates.report.release_url)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: !!Updates.report.notes
            text: Updates.report.notes ?? ""
            textFormat: Text.PlainText
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }
    }

    // Keep session termination behind a separate, explicit confirmation.
    readonly property Dialog installDialog: Dialog {
        id: installDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(root.width - root.Tokens.padding.large * 2, 480 * root.Tokens.scale)
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        modal: true
        title: Tr.tr("Install update and log out?")
        padding: root.Tokens.padding.large
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        header: null
        footer: null
        background: StyledRect {
            color: Colours.palette.m3surfaceContainerHigh
            radius: root.Tokens.rounding.large
        }
        contentItem: ColumnLayout {
            spacing: root.Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: installDialog.title
                font: root.Tokens.font.title.medium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Save your work and close your applications. Hyprland will exit, then the prepared update will be installed with a backup. Wait for installation to finish before logging in again.")
                font: root.Tokens.font.body.medium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.Tokens.spacing.small
                Item { Layout.fillWidth: true }
                TextButton {
                    Tokens.screen: root.Tokens.screen
                    type: TextButton.Text
                    text: Tr.trCtx("Cancel", "button")
                    onClicked: installDialog.close()
                }
                TextButton {
                    Tokens.screen: root.Tokens.screen
                    text: Tr.tr("Install and log out")
                    disabled: Updates.busy || !Updates.ready
                    onClicked: {
                        installDialog.close();
                        Updates.run("install");
                    }
                }
            }
        }
    }
}
