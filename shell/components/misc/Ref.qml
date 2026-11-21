import QtQuick

QtObject {
    required property QtObject service
    property QtObject heldService

    function sync(): void {
        if (heldService === service)
            return;
        if (heldService)
            heldService.refCount--;
        heldService = service;
        if (heldService)
            heldService.refCount++;
    }

    onServiceChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (heldService) heldService.refCount--
}
