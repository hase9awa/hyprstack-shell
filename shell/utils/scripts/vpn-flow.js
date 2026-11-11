.pragma library

// The primary button always names the next explicit user action. Opening the
// window or preparing a profile never changes an existing VPN connection.
function primaryAction(state) {
    if (state.busy) return "busy";
    if (state.connected) return "disconnect";
    if (state.otherConnected) return "disconnect-other";
    if (!state.hasProfile) return state.profileCount > 0 ? "select" : "import";
    if (state.installed === false) return "install";
    if (state.mode !== "proxy" && !state.canTun) return "authorize";
    return "connect";
}
