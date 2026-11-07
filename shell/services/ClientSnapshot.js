function clientData(toplevel, clients, ready) {
    const ipc = toplevel?.lastIpcObject;
    if (!ipc)
        return null;
    if (!ready)
        return ipc;
    const current = clients[ipc.address];
    if (!current || (ipc.stableId && current.stableId && ipc.stableId !== current.stableId))
        return null;
    return current;
}

function hasFullscreen(workspaceId, clients, ready, toplevels) {
    const windows = ready ? Object.values(clients) : toplevels.map(t => t.lastIpcObject);
    return windows.some(w => w?.mapped && !w.hidden && w.workspace?.id === workspaceId && w.fullscreen > 1);
}
