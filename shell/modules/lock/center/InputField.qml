pragma ComponentBehavior: Bound

import QtQuick
import Hyprstack.Config
import Hyprstack.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.lock

Item {
    id: root

    required property real centerScale
    required property Pam pam
    readonly property alias placeholder: placeholder
    readonly property alias placeholderWidth: nonAnimPlaceholder.width
    property string buffer
    property bool showPassword

    clip: true

    Connections {
        function onBufferChanged(): void {
            if (root.pam.buffer.length === 0) {
                placeholder.animate = true;
                root.showPassword = false;
            }

            root.buffer = root.pam.buffer;
        }

        target: root.pam
    }

    TextMetrics {
        id: nonAnimPlaceholder

        text: {
            if (root.pam.passwd.active)
                return Tr.tr("Loading...");
            if (root.pam.howdy.active)
                return Tr.tr("Scanning face...");
            if (root.pam.state === Pam.MaxTries)
                return Tr.tr("Max tries reached");
            return Tr.tr("Enter your password");
        }
        font: placeholder.font
    }

    StyledText {
        id: placeholder

        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1

        text: nonAnimPlaceholder.text

        animate: true
        color: root.pam.passwd.active ? Colours.palette.m3secondary : Colours.palette.m3outline
        font: Tokens.font.body.builders.medium.scale(root.centerScale).width(110).build()

        opacity: root.buffer ? 0 : 1

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    PasswordCharacters {
        id: charList

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: implicitWidth > root.width ? -(implicitWidth - root.width) / 2 : 0

        buffer: root.buffer
        revealed: root.showPassword
        characterSize: Tokens.font.body.medium.pointSize
    }
}
