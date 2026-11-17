import QtQuick
import Quickshell

QtObject {
    required property ShellScreen screen
    property string currentName
    property bool hasCurrent
    property Item taskButton
    property var trayItem: null
    property int trayRevision: 0
    onTrayItemChanged: ++trayRevision

    signal detachRequested(mode: string)
}
