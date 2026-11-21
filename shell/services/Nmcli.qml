pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack
import Hyprstack.I18n

Singleton {
    id: root

    property var deviceStatus: null
    property var wirelessInterfaces: []
    property var ethernetInterfaces: []
    property bool isConnected: false
    readonly property bool connecting: wirelessInterfaces.some(i => isConnectingState(i.state))
    property string activeInterface: ""
    property string activeConnection: ""
    property bool wifiEnabled: true
    readonly property bool scanning: rescanProc.running
    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(n => n.active) ?? null
    property list<string> savedConnections: []
    property list<string> savedConnectionSsids: []
    // Map of saved Wi-Fi SSID (lowercased) -> security type
    property var savedConnectionSecurity: ({})

    property bool savedRefreshActive: false
    property bool savedRefreshPending: false
    property var savedRefreshCallbacks: []
    property var pendingConnection: null
    property var wirelessDeviceDetails: null
    property var ethernetDeviceDetails: null
    property string ethernetDataUsage: ""
    // Link speed of the active ethernet interface (from sysfs), e.g. "1 Gbps".
    property string ethernetSpeed: ""
    readonly property list<EthernetDevice> ethernetDevices: []
    readonly property EthernetDevice activeEthernet: ethernetDevices.find(d => d.connected) ?? null
    // True when at least one wired device has a carrier (cable plugged in).
    // nmcli reports "unavailable" for ethernet NICs with no link, so we treat
    // anything other than that as a usable connection.
    readonly property bool hasAvailableEthernet: ethernetDevices.some(d => d.state !== "unavailable")
    property list<var> activeProcesses: []

    // Constants
    readonly property string deviceTypeWifi: "wifi"
    readonly property string deviceTypeEthernet: "ethernet"
    readonly property string connectionTypeWireless: "802-11-wireless"
    readonly property string nmcliCommandDevice: "device"
    readonly property string nmcliCommandConnection: "connection"
    readonly property string nmcliCommandWifi: "wifi"
    readonly property string nmcliCommandRadio: "radio"
    readonly property string deviceStatusFields: "DEVICE,TYPE,STATE,CONNECTION"
    readonly property string connectionListFields: "NAME,TYPE"
    readonly property string wirelessSsidField: "802-11-wireless.ssid"
    readonly property string networkListFields: "SSID,SIGNAL,SECURITY"
    readonly property string networkDetailFields: "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY"
    readonly property string securityKeyMgmt: "802-11-wireless-security.key-mgmt"
    readonly property string securityPsk: "802-11-wireless-security.psk"
    readonly property string keyMgmtWpaPsk: "wpa-psk"
    readonly property string connectionParamType: "type"
    readonly property string connectionParamConName: "con-name"
    readonly property string connectionParamIfname: "ifname"
    readonly property string connectionParamSsid: "ssid"
    readonly property string connectionParamPassword: "password"
    readonly property string connectionParamHidden: "802-11-wireless.hidden"

    signal connectionFailed(string ssid)

    function detectPasswordRequired(error: string): bool {
        return !!error && !/connection activated|successfully/i.test(error)
            && /\b(secrets?|password|passphrase)\b|802-11-wireless-security\.psk/i.test(error);
    }

    // In terse output nmcli escapes both colons and backslashes, including in SSIDs.
    function terseFields(line: string): var {
        const fields = [];
        let field = "";
        for (let i = 0; i < line.length; ++i) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length)
                field += line[++i];
            else if (ch === ":") {
                fields.push(field);
                field = "";
            } else
                field += ch;
        }
        fields.push(field);
        return fields;
    }

    function parseNetworkOutput(output: string): list<var> {
        if (!output || output.length === 0) {
            return [];
        }

        const allNetworks = output.split("\n").filter(line => line.length > 0).map(line => {
            const net = terseFields(line);
            return {
                active: net[0] === "yes",
                strength: parseInt(net[1] || "0", 10) || 0,
                frequency: parseInt(net[2] || "0", 10) || 0,
                ssid: net[3] ?? "",
                bssid: net[4] ?? "",
                security: (net[5] ?? "").trim()
            };
        }).filter(n => n.ssid && n.ssid.length > 0);

        return allNetworks;
    }

    function deduplicateNetworks(networks: list<var>): list<var> {
        if (!networks || networks.length === 0) {
            return [];
        }

        const networkMap = new Map();
        for (const network of networks) {
            const existing = networkMap.get(network.ssid);
            if (!existing) {
                networkMap.set(network.ssid, network);
            } else {
                if (network.active && !existing.active) {
                    networkMap.set(network.ssid, network);
                } else if (!network.active && !existing.active) {
                    if (network.strength > existing.strength) {
                        networkMap.set(network.ssid, network);
                    }
                }
            }
        }

        return Array.from(networkMap.values());
    }

    function isConnectionCommand(command: list<string>): bool {
        return command[0] === "nmcli" && ((command[1] === "device" && command[2] === "wifi" && command[3] === "connect")
            || (command[1] === "connection" && command[2] === "up"));
    }

    function parseDeviceStatusOutput(output: string, filterType: string): list<var> {
        if (!output || output.length === 0) {
            return [];
        }

        const interfaces = [];
        const lines = output.trim().split("\n");

        for (const line of lines) {
            const parts = terseFields(line);
            if (parts.length >= 2) {
                const deviceType = parts[1];
                let shouldInclude = false;

                if (filterType === root.deviceTypeWifi && deviceType === root.deviceTypeWifi) {
                    shouldInclude = true;
                } else if (filterType === root.deviceTypeEthernet && deviceType === root.deviceTypeEthernet) {
                    shouldInclude = true;
                } else if (filterType === "both" && (deviceType === root.deviceTypeWifi || deviceType === root.deviceTypeEthernet)) {
                    shouldInclude = true;
                }

                if (shouldInclude) {
                    interfaces.push({
                        device: parts[0] || "",
                        type: parts[1] || "",
                        state: parts[2] || "",
                        connection: parts[3] || ""
                    });
                }
            }
        }

        return interfaces;
    }

    function isConnectedState(state: string): bool {
        if (!state || state.length === 0) {
            return false;
        }

        return state === "100 (connected)" || state === "connected" || state.startsWith("connected");
    }

    function isConnectingState(state: string): bool {
        return !!state && state.startsWith("connecting");
    }

    function connectingSsid(): string {
        const iface = root.wirelessInterfaces.find(i => isConnectingState(i.state));
        return iface ? iface.connection : "";
    }

    function executeCommand(args: list<string>, callback: var): void {
        const proc = commandProc.createObject(root);
        proc.cmdArgs = ["nmcli", ...args];
        proc.callback = callback;

        activeProcesses.push(proc);

        Qt.callLater(() => {
            proc.exec(proc.cmdArgs);
        });
    }

    function getDeviceStatus(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            if (callback)
                callback(result.output);
        });
    }

    function getWirelessInterfaces(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            const interfaces = parseDeviceStatusOutput(result.output, root.deviceTypeWifi);
            root.wirelessInterfaces = interfaces;
            if (callback)
                callback(interfaces);
        });
    }

    function getEthernetInterfaces(callback: var): void {
        getDeviceStatus(output => {
            updateEthernetInterfaces(output);
            if (callback)
                callback(root.ethernetInterfaces);
        });
    }

    function updateEthernetInterfaces(output: string): void {
        const devices = parseDeviceStatusOutput(output, root.deviceTypeEthernet);
        // A physical NIC has a sysfs device link. Keep the full list if sysfs is unavailable.
        const physical = devices.length && CUtils.isDirectory("/sys/class/net")
            ? devices.filter(d => CUtils.isDirectory(`/sys/class/net/${d.device}/device`)) : devices;
        root.ethernetInterfaces = physical;
        syncEthernetDevices(physical.map(d => ({
            interface: d.device, type: d.type, state: d.state, connection: d.connection,
            connected: isConnectedState(d.state)
        })));
    }

    // Sync a list of ethernet devices to the existing device list. Same logic as getNetworks
    function syncEthernetDevices(devices: list<var>): void {
        const rDevices = root.ethernetDevices;

        const newMap = new Map();
        for (const d of devices)
            newMap.set(d.interface, d);

        for (let i = rDevices.length - 1; i >= 0; i--) {
            if (!newMap.has(rDevices[i].iface)) {
                const removed = rDevices.splice(i, 1)[0];
                removed.destroy();
            }
        }

        const existingMap = new Map();
        for (const rd of rDevices)
            existingMap.set(rd.iface, rd);

        for (const [iface, data] of newMap) {
            const match = existingMap.get(iface);
            if (match)
                match.lastIpcObject = data;
            else
                rDevices.push(ethComp.createObject(root, {
                    lastIpcObject: data
                }));
        }
    }

    function connectEthernet(connectionName: string, interfaceName: string, callback: var): void {
        if (connectionName && connectionName.length > 0) {
            executeCommand([root.nmcliCommandConnection, "up", connectionName], result => {
                if (result.success) {
                    Qt.callLater(() => {
                        getEthernetInterfaces(() => {});
                        if (interfaceName && interfaceName.length > 0) {
                            Qt.callLater(() => {
                                getEthernetDeviceDetails(interfaceName, () => {});
                            }, 1000);
                        }
                    }, 500);
                }
                if (callback)
                    callback(result);
            });
        } else if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "connect", interfaceName], result => {
                if (result.success) {
                    Qt.callLater(() => {
                        getEthernetInterfaces(() => {});
                        Qt.callLater(() => {
                            getEthernetDeviceDetails(interfaceName, () => {});
                        }, 1000);
                    }, 500);
                }
                if (callback)
                    callback(result);
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection name or interface specified",
                    exitCode: -1
                });
        }
    }

    function disconnectEthernet(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection name specified",
                    exitCode: -1
                });
            return;
        }

        executeCommand([root.nmcliCommandConnection, "down", connectionName], result => {
            if (result.success) {
                root.ethernetDeviceDetails = null;
                Qt.callLater(() => {
                    getEthernetInterfaces(() => {});
                }, 500);
            }
            if (callback)
                callback(result);
        });
    }

    function getAllInterfaces(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            const interfaces = parseDeviceStatusOutput(result.output, "both");
            if (callback)
                callback(interfaces);
        });
    }

    function isInterfaceConnected(interfaceName: string, callback: var): void {
        executeCommand([root.nmcliCommandDevice, "status"], result => {
            const lines = result.output.trim().split("\n");
            for (const line of lines) {
                const parts = line.split(/\s+/);
                if (parts.length >= 3 && parts[0] === interfaceName) {
                    const connected = isConnectedState(parts[2]);
                    if (callback)
                        callback(connected);
                    return;
                }
            }
            if (callback)
                callback(false);
        });
    }

    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        if (isSecure) {
            connectWireless(ssid, "", bssid, result => {
                if (result.success) {
                    if (callback)
                        callback({
                            success: true,
                            usedSavedPassword: true,
                            output: result.output,
                            error: "",
                            exitCode: 0
                        });
                } else if (result.needsPassword) {
                    if (callback)
                        callback({
                            success: false,
                            needsPassword: true,
                            output: result.output,
                            error: result.error,
                            exitCode: result.exitCode
                        });
                } else {
                    if (callback)
                        callback(result);
                }
            });
        } else {
            connectWireless(ssid, "", bssid, callback);
        }
    }

    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        connectWireless(ssid, password, bssid, callback);
    }

    function connectWireless(ssid: string, password: string, bssid: string, callback: var): void {
        connectionRetry.stop();
        connectionRetry.attempt = null;
        const request = {ssid: ssid, bssid: bssid || "", callback: callback};
        pendingConnection = request;
        const finish = result => root.finishConnection(request, result);
        const command = [root.nmcliCommandDevice, root.nmcliCommandWifi, "connect", ssid];
        if (password)
            command.push(root.connectionParamPassword, password);
        if (bssid)
            command.push("bssid", bssid.toUpperCase());
        let retries = 0;
        function attempt() {
            root.executeCommand(command, result => {
                if (root.pendingConnection !== request)
                    return;
                if (result.needsPassword && password) {
                    root.retrySavedPassword(request, password, result);
                } else if (!result.success && !result.needsPassword && !password && callback && retries < 2) {
                    ++retries;
                    connectionRetry.attempt = attempt;
                    connectionRetry.restart();
                } else {
                    finish(result);
                }
            });
        }
        attempt();
    }

    function finishConnection(request: var, result: var): void {
        if (!request || request !== pendingConnection)
            return;
        pendingConnection = null;
        connectionRetry.stop();
        connectionRetry.attempt = null;
        if (result.success && !hasSavedProfile(request.ssid))
            loadSavedConnections();
        else if (!result.success && !result.needsPassword)
            connectionFailed(request.ssid);
        if (request.callback)
            request.callback(result);
    }

    function retrySavedPassword(request: var, password: string, failure: var): void {
        // nmcli can reuse a saved profile whose PSK is stale. Update only the
        // matching wireless profile and keep its routes, DNS and other settings.
        executeCommand(["-t", "-f", `connection.uuid,${wirelessSsidField},${securityKeyMgmt}`,
                        "connection", "show", "id", request.ssid], result => {
            if (pendingConnection !== request) return;
            const fields = new Map(result.output.split("\n").map(line => terseFields(line)));
            const uuid = fields.get("connection.uuid");
            if (!result.success || !uuid || fields.get(wirelessSsidField) !== request.ssid
                || !["wpa-psk", "sae"].includes(fields.get(securityKeyMgmt))) {
                finishConnection(request, failure);
                return;
            }
            executeCommand(["connection", "modify", "uuid", uuid, securityPsk, password], changed => {
                if (pendingConnection !== request) return;
                if (!changed.success) {
                    finishConnection(request, changed);
                    return;
                }
                const up = ["connection", "up", "uuid", uuid];
                if (request.bssid) up.push("ap", request.bssid);
                executeCommand(up, activated => finishConnection(request, activated));
            });
        });
    }

    function checkAndDeleteConnection(ssid: string, callback: var): void {
        executeCommand([root.nmcliCommandConnection, "show", ssid], result => {
            if (result.success) {
                executeCommand([root.nmcliCommandConnection, "delete", ssid], () => {
                    if (callback)
                        callback();
                });
            } else {
                if (callback)
                    callback();
            }
        });
    }

    function activateConnection(connectionName: string, callback: var): void {
        executeCommand([root.nmcliCommandConnection, "up", connectionName], result => {
            if (callback)
                callback(result);
        });
    }

    function loadSavedConnections(callback: var): void {
        if (callback)
            savedRefreshCallbacks.push(callback);
        if (savedRefreshActive) {
            savedRefreshPending = true;
            return;
        }
        savedRefreshActive = true;
        readSavedConnections();
    }

    function readSavedConnections(): void {
        const names = [];
        const wireless = [];
        const ssids = [];
        const security = Object.create(null);
        let index = 0;

        function finish() {
            if (!root.savedRefreshPending) {
                root.savedConnections = names;
                root.savedConnectionSecurity = security;
                root.savedConnectionSsids = ssids;
            }
            if (root.savedRefreshPending) {
                root.savedRefreshPending = false;
                root.readSavedConnections();
                return;
            }
            const callbacks = root.savedRefreshCallbacks;
            root.savedRefreshCallbacks = [];
            root.savedRefreshActive = false;
            for (const callback of callbacks)
                callback(ssids);
        }

        function readNext() {
            if (index === wireless.length) {
                finish();
                return;
            }
            root.executeCommand(["-t", "-f", `${root.wirelessSsidField},${root.securityKeyMgmt}`,
                                 root.nmcliCommandConnection, "show", wireless[index++]], result => {
                if (result.success) {
                    let ssid = "", keyMgmt = "";
                    for (const line of result.output.split("\n")) {
                        const [key, value] = root.terseFields(line);
                        if (key === root.wirelessSsidField)
                            ssid = value;
                        else if (key === root.securityKeyMgmt)
                            keyMgmt = value;
                    }
                    if (ssid) {
                        const key = ssid.toLowerCase();
                        if (!(key in security))
                            ssids.push(ssid);
                        security[key] = keyMgmt;
                    }
                }
                readNext();
            });
        }

        executeCommand(["-t", "-f", root.connectionListFields, root.nmcliCommandConnection, "show"], result => {
            if (result.success) {
                for (const line of result.output.split("\n")) {
                    const [name, type] = root.terseFields(line);
                    if (!name || !type)
                        continue;
                    names.push(name);
                    if (type === root.connectionTypeWireless)
                        wireless.push(name);
                }
            }
            readNext();
        });
    }

    function securityLabel(keyMgmt: string): string {
        switch ((keyMgmt || "").trim().toLowerCase()) {
        case "":
        case "none":
            return Tr.trCtx("Open", "wifi security type");
        case "sae":
            return "WPA3";
        case "wpa-psk":
            return "WPA2";
        case "wpa-eap":
        case "wpa-eap-suite-b-192":
            return Tr.tr("Enterprise");
        case "owe":
            return Tr.tr("Enhanced Open");
        case "ieee8021x":
            return "802.1X";
        default:
            return keyMgmt.trim();
        }
    }

    // Cached security label for a saved SSID, or "" if unknown (e.g. not loaded).
    function savedSecurityFor(ssid: string): string {
        if (!ssid || ssid.length === 0)
            return "";
        return root.savedConnectionSecurity[ssid.toLowerCase()] || "";
    }

    function hasSavedProfile(ssid: string): bool {
        if (!ssid || ssid.length === 0) {
            return false;
        }
        const ssidLower = ssid.toLowerCase().trim();

        if (root.active && root.active.ssid) {
            const activeSsidLower = root.active.ssid.toLowerCase().trim();
            if (activeSsidLower === ssidLower) {
                return true;
            }
        }

        const hasSsid = root.savedConnectionSsids.some(savedSsid => savedSsid && savedSsid.toLowerCase().trim() === ssidLower);

        if (hasSsid) {
            return true;
        }

        const hasConnectionName = root.savedConnections.some(connName => connName && connName.toLowerCase().trim() === ssidLower);

        return hasConnectionName;
    }

    // Adds and connects to an SSID by name. When hidden is true the profile is
    // created with 802-11-wireless.hidden=yes so NetworkManager actively probes
    // for it.
    function addHiddenNetwork(ssid: string, password: string, security: string, hidden: bool, callback: var): void {
        if (!ssid || ssid.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No SSID specified",
                    exitCode: -1
                });
            return;
        }

        const isSecure = security && security !== "none";

        // Remove any stale profile with the same name first so we don't collide.
        checkAndDeleteConnection(ssid, () => {
            let cmd = [root.nmcliCommandConnection, "add", root.connectionParamType, root.deviceTypeWifi, root.connectionParamConName, ssid, root.connectionParamIfname, "*", root.connectionParamSsid, ssid, root.connectionParamHidden, hidden ? "yes" : "no"];

            if (isSecure) {
                cmd.push(root.securityKeyMgmt, root.keyMgmtWpaPsk, root.securityPsk, password);
            }

            executeCommand(cmd, result => {
                if (result.success) {
                    loadSavedConnections();
                    activateConnection(ssid, callback);
                } else {
                    const hasDuplicateWarning = result.error && (result.error.includes("another connection with the name") || result.error.includes("Reference the connection by its uuid"));

                    if (hasDuplicateWarning) {
                        loadSavedConnections();
                        activateConnection(ssid, callback);
                    } else if (callback) {
                        callback(result);
                    }
                }
            });
        });
    }

    // Reads whether a saved connection auto-connects.
    function getAutoconnect(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback(true);
            return;
        }
        executeCommand(["-t", "-f", "connection.autoconnect", root.nmcliCommandConnection, "show", connectionName], result => {
            let auto = true;
            if (result.success) {
                const line = result.output.trim();
                const idx = line.indexOf(":");
                if (idx >= 0)
                    auto = line.slice(idx + 1).trim() !== "no";
            }
            if (callback)
                callback(auto);
        });
    }

    // Toggles auto-connect for a saved connection. When turned OFF, also makes
    // NetworkManager ask for the password on the next manual connect instead of
    // silently reusing the stored one (psk-flags 2 = "not saved, always ask");
    // turning it back ON restores psk-flags 0 so the next password is saved.
    function setAutoconnect(connectionName: string, enabled: bool, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection specified",
                    exitCode: -1
                });
            return;
        }

        let cmd = [root.nmcliCommandConnection, "modify", connectionName, "connection.autoconnect", enabled ? "yes" : "no"];

        if (enabled) {
            cmd.push("802-11-wireless-security.psk-flags", "0");
        } else {
            cmd.push("802-11-wireless-security.psk-flags", "2");
            cmd.push("802-11-wireless-security.psk", "");
        }

        executeCommand(cmd, result => {
            // For open networks the security fields don't exist; nmcli then
            // errors. Retry with just the autoconnect change so it still works.
            if (!result.success && result.error && (result.error.includes("802-11-wireless-security") || result.error.includes("is not a valid property") || result.error.includes("Error: invalid"))) {
                executeCommand([root.nmcliCommandConnection, "modify", connectionName, "connection.autoconnect", enabled ? "yes" : "no"], retryResult => {
                    if (callback)
                        callback(retryResult);
                });
                return;
            }
            if (callback)
                callback(result);
        });
    }

    function forgetNetwork(ssid: string, callback: var): void {
        if (!ssid || ssid.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No SSID specified",
                    exitCode: -1
                });
            return;
        }

        const connectionName = root.savedConnections.find(conn => conn && conn.toLowerCase().trim() === ssid.toLowerCase().trim()) || ssid;

        executeCommand([root.nmcliCommandConnection, "delete", connectionName], result => {
            if (result.success) {
                Qt.callLater(() => {
                    loadSavedConnections();
                }, 500);
            }
            if (callback)
                callback(result);
        });
    }

    function disconnect(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "disconnect", interfaceName], result => {
                if (callback)
                    callback(result.success ? result.output : "");
            });
        } else {
            executeCommand([root.nmcliCommandDevice, "disconnect", root.deviceTypeWifi], result => {
                if (callback)
                    callback(result.success ? result.output : "");
            });
        }
    }

    function disconnectFromNetwork(): void {
        if (active && active.ssid) {
            executeCommand([root.nmcliCommandConnection, "down", active.ssid], result => {
                if (result.success) {
                    getNetworks(() => {});
                }
            });
        } else {
            executeCommand([root.nmcliCommandDevice, "disconnect", root.deviceTypeWifi], result => {
                if (result.success) {
                    getNetworks(() => {});
                }
            });
        }
    }

    function getDeviceDetails(interfaceName: string, callback: var): void {
        executeCommand([root.nmcliCommandDevice, "show", interfaceName], result => {
            if (callback)
                callback(result.output);
        });
    }

    function refreshStatus(callback: var): void {
        getDeviceStatus(output => {
            const lines = output.trim().split("\n");
            let connected = false;
            let activeIf = "";
            let activeConn = "";

            for (const line of lines) {
                const parts = terseFields(line);
                if (parts.length >= 4) {
                    const state = parts[2] || "";
                    if (isConnectedState(state)) {
                        connected = true;
                        activeIf = parts[0] || "";
                        activeConn = parts[3] || "";
                        break;
                    }
                }
            }

            root.isConnected = connected;
            root.activeInterface = activeIf;
            root.activeConnection = activeConn;

            if (callback)
                callback({
                    connected,
                    interface: activeIf,
                    connection: activeConn
                });
        });
    }

    function bringInterfaceUp(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "connect", interfaceName], result => {
                if (callback) {
                    callback(result);
                }
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No interface specified",
                    exitCode: -1
                });
        }
    }

    function bringInterfaceDown(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "disconnect", interfaceName], result => {
                if (callback) {
                    callback(result);
                }
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No interface specified",
                    exitCode: -1
                });
        }
    }

    function scanWirelessNetworks(interfaceName: string, callback: var): void {
        let cmd = [root.nmcliCommandDevice, root.nmcliCommandWifi, "rescan"];
        if (interfaceName && interfaceName.length > 0) {
            cmd.push(root.connectionParamIfname, interfaceName);
        }
        executeCommand(cmd, result => {
            if (callback) {
                callback(result);
            }
        });
    }

    function rescanWifi(): void {
        rescanProc.running = true;
    }

    function enableWifi(enabled: bool, callback: var): void {
        const cmd = enabled ? "on" : "off";
        executeCommand([root.nmcliCommandRadio, root.nmcliCommandWifi, cmd], result => {
            if (result.success) {
                getWifiStatus(status => {
                    root.wifiEnabled = status;
                    if (callback)
                        callback(result);
                });
            } else {
                if (callback)
                    callback(result);
            }
        });
    }

    function toggleWifi(callback: var): void {
        const newState = !root.wifiEnabled;
        enableWifi(newState, callback);
    }

    function getWifiStatus(callback: var): void {
        executeCommand([root.nmcliCommandRadio, root.nmcliCommandWifi], result => {
            if (result.success) {
                const enabled = result.output.trim() === "enabled";
                root.wifiEnabled = enabled;
                if (callback)
                    callback(enabled);
            } else {
                if (callback)
                    callback(root.wifiEnabled);
            }
        });
    }

    function findNetwork(ssid: string): var {
        return networks.find(n => n.ssid === ssid) ?? null;
    }

    function getNetworks(callback: var): void {
        executeCommand(["-g", root.networkDetailFields, "d", "w"], result => {
            if (!result.success) {
                if (callback)
                    callback([]);
                return;
            }

            const allNetworks = parseNetworkOutput(result.output);
            const networks = deduplicateNetworks(allNetworks);
            const rNetworks = root.networks;

            const newMap = new Map();
            for (const n of networks)
                newMap.set(`${n.frequency}:${n.ssid}:${n.bssid}`, n);

            for (let i = rNetworks.length - 1; i >= 0; i--) {
                const rn = rNetworks[i];
                const key = `${rn.frequency}:${rn.ssid}:${rn.bssid}`;
                if (!newMap.has(key)) {
                    rNetworks.splice(i, 1);
                    rn.destroy();
                }
            }

            const existingMap = new Map();
            for (const rn of rNetworks)
                existingMap.set(`${rn.frequency}:${rn.ssid}:${rn.bssid}`, rn);

            for (const [key, network] of newMap) {
                const match = existingMap.get(key);
                if (match) {
                    match.lastIpcObject = network;
                } else {
                    rNetworks.push(apComp.createObject(root, {
                        lastIpcObject: network
                    }));
                }
            }

            if (callback)
                callback(root.networks);
        });
    }

    function getWirelessSSIDs(interfaceName: string, callback: var): void {
        let cmd = ["-t", "-f", root.networkListFields, root.nmcliCommandDevice, root.nmcliCommandWifi, "list"];
        if (interfaceName && interfaceName.length > 0) {
            cmd.push(root.connectionParamIfname, interfaceName);
        }
        executeCommand(cmd, result => {
            if (!result.success) {
                if (callback)
                    callback([]);
                return;
            }

            const ssids = [];
            const lines = result.output.trim().split("\n");
            const seenSSIDs = new Set();

            for (const line of lines) {
                if (!line || line.length === 0)
                    continue;

                const parts = terseFields(line);
                if (parts.length >= 1) {
                    const ssid = parts[0].trim();
                    if (ssid && ssid.length > 0 && !seenSSIDs.has(ssid)) {
                        seenSSIDs.add(ssid);
                        const signalStr = parts.length >= 2 ? parts[1].trim() : "";
                        const signal = signalStr ? parseInt(signalStr, 10) : 0;
                        const security = parts.length >= 3 ? parts[2].trim() : "";
                        ssids.push({
                            ssid: ssid,
                            signal: signalStr,
                            signalValue: isNaN(signal) ? 0 : signal,
                            security: security
                        });
                    }
                }
            }

            ssids.sort((a, b) => {
                return b.signalValue - a.signalValue;
            });

            if (callback)
                callback(ssids);
        });
    }

    function cidrToSubnetMask(cidr: string): string {
        const cidrNum = parseInt(cidr, 10);
        if (isNaN(cidrNum) || cidrNum < 0 || cidrNum > 32) {
            return "";
        }

        const mask = cidrNum === 0 ? 0 : (0xffffffff << (32 - cidrNum)) >>> 0;
        const octet1 = (mask >>> 24) & 0xff;
        const octet2 = (mask >>> 16) & 0xff;
        const octet3 = (mask >>> 8) & 0xff;
        const octet4 = mask & 0xff;

        return `${octet1}.${octet2}.${octet3}.${octet4}`;
    }

    function getWirelessDeviceDetails(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            const activeInterface = root.wirelessInterfaces.find(iface => {
                return isConnectedState(iface.state);
            });
            if (activeInterface && activeInterface.device) {
                interfaceName = activeInterface.device;
            } else {
                if (callback)
                    callback(null);
                return;
            }
        }

        executeCommand(["device", "show", interfaceName], result => {
            if (!result.success || !result.output) {
                root.wirelessDeviceDetails = null;
                if (callback)
                    callback(null);
                return;
            }

            const details = parseDeviceDetails(result.output, false);
            root.wirelessDeviceDetails = details;
            if (callback)
                callback(details);
        });
    }

    // Reads the IPv4 configuration (method, address, gateway, DNS, autoconnect)
    // of a connection profile for the ethernet detail page.
    function getIpv4Config(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback(null);
            return;
        }

        executeCommand(["-t", "-f", "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,connection.autoconnect", root.nmcliCommandConnection, "show", connectionName], result => {
            if (!result.success) {
                if (callback)
                    callback(null);
                return;
            }

            const cfg = {
                method: "auto",
                address: "",
                gateway: "",
                dns: "",
                ignoreAutoDns: false,
                autoconnect: true
            };

            const lines = result.output.trim().split("\n");
            for (const line of lines) {
                const idx = line.indexOf(":");
                if (idx < 0)
                    continue;
                const key = line.slice(0, idx).trim();
                const value = line.slice(idx + 1).trim();

                if (key === "ipv4.ignore-auto-dns")
                    cfg.ignoreAutoDns = value === "yes";
                else if (key === "connection.autoconnect")
                    cfg.autoconnect = value !== "no";

                if (value === "" || value === "--")
                    continue;

                if (key === "ipv4.method")
                    cfg.method = value;
                else if (key === "ipv4.addresses")
                    cfg.address = value.split(",")[0].trim();
                else if (key === "ipv4.gateway")
                    cfg.gateway = value;
                else if (key === "ipv4.dns")
                    cfg.dns = value.replace(/;\s*$/, "").split(/[;,]/).map(d => d.trim()).filter(d => d.length > 0).join(", ");
            }

            // Distinguish "automatic + custom DNS only" from plain DHCP.
            if (cfg.method === "auto" && cfg.ignoreAutoDns)
                cfg.method = "auto-dns";

            if (callback)
                callback(cfg);
        });
    }

    // Writes an IPv4 configuration to a connection profile and reactivates it so
    // the change takes effect immediately.
    function setIpv4Config(connectionName: string, config: var, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection specified",
                    exitCode: -1
                });
            return;
        }

        const dnsList = (config.dns ?? "").split(",").map(d => d.trim()).filter(d => d.length > 0).join(" ");
        let cmd = [root.nmcliCommandConnection, "modify", connectionName];

        if (config.method === "manual") {
            cmd.push("ipv4.method", "manual");
            cmd.push("ipv4.addresses", config.address ?? "");
            cmd.push("ipv4.gateway", config.gateway ?? "");
            cmd.push("ipv4.dns", dnsList);
            cmd.push("ipv4.ignore-auto-dns", "yes");
        } else if (config.method === "auto-dns") {
            // DHCP addressing, custom DNS only.
            cmd.push("ipv4.method", "auto");
            cmd.push("ipv4.addresses", "");
            cmd.push("ipv4.gateway", "");
            cmd.push("ipv4.dns", dnsList);
            cmd.push("ipv4.ignore-auto-dns", "yes");
        } else {
            // Full DHCP: clear manual fields and re-enable auto DNS.
            cmd.push("ipv4.method", "auto");
            cmd.push("ipv4.addresses", "");
            cmd.push("ipv4.gateway", "");
            cmd.push("ipv4.dns", "");
            cmd.push("ipv4.ignore-auto-dns", "no");
        }

        executeCommand(cmd, result => {
            if (!result.success) {
                if (callback)
                    callback(result);
                return;
            }
            // Reactivate so changes take effect immediately.
            executeCommand([root.nmcliCommandConnection, "up", connectionName], upResult => {
                Qt.callLater(() => {
                    refreshOnConnectionChange();
                });
                if (callback)
                    callback(upResult);
            });
        });
    }

    // Reads cumulative since-boot byte counters from sysfs for an interface and
    // returns a human-readable total via the callback.
    // Reads the negotiated link speed (Mbit/s) from sysfs and stores a
    // human-readable form in ethernetSpeed. nmcli `device show` doesn't expose
    // link speed, so sysfs is the root-free source.
    function getEthernetSpeed(interfaceName: string): void {
        if (!interfaceName || interfaceName.length === 0) {
            root.ethernetSpeed = "";
            return;
        }
        speedProc.command = ["cat", `/sys/class/net/${interfaceName}/speed`];
        speedProc.running = true;
    }

    function getEthernetDataUsage(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            if (callback)
                callback("");
            return;
        }
        dataUsageProc.iface = interfaceName;
        dataUsageProc.cb = callback;
        dataUsageProc.command = ["cat", `/sys/class/net/${interfaceName}/statistics/rx_bytes`, `/sys/class/net/${interfaceName}/statistics/tx_bytes`];
        dataUsageProc.running = true;
    }

    function getEthernetDeviceDetails(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            const activeInterface = root.ethernetInterfaces.find(iface => {
                return isConnectedState(iface.state);
            });
            if (activeInterface && activeInterface.device) {
                interfaceName = activeInterface.device;
            } else {
                if (callback)
                    callback(null);
                return;
            }
        }

        executeCommand(["device", "show", interfaceName], result => {
            if (!result.success || !result.output) {
                // Transient failure (e.g. nmcli busy during a toggle). Keep the
                // previous details so dependent UI (gateway, IP/DNS) doesn't
                // blink out and back.
                if (callback)
                    callback(root.ethernetDeviceDetails);
                return;
            }

            const details = parseDeviceDetails(result.output, true);
            root.ethernetDeviceDetails = details;
            if (callback)
                callback(details);
        });
    }

    function parseDeviceDetails(output: string, isEthernet: bool): var {
        const details = {
            ipAddress: "",
            gateway: "",
            dns: [],
            subnet: "",
            macAddress: "",
            speed: ""
        };

        if (!output || output.length === 0) {
            return details;
        }

        const lines = output.trim().split("\n");

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const parts = line.split(":");
            if (parts.length >= 2) {
                const key = parts[0].trim();
                const value = parts.slice(1).join(":").trim();

                if (key.startsWith("IP4.ADDRESS")) {
                    const ipParts = value.split("/");
                    details.ipAddress = ipParts[0] || "";
                    if (ipParts[1]) {
                        details.subnet = cidrToSubnetMask(ipParts[1]);
                    } else {
                        details.subnet = "";
                    }
                } else if (key === "IP4.GATEWAY") {
                    if (value !== "--") {
                        details.gateway = value;
                    }
                } else if (key.startsWith("IP4.DNS")) {
                    if (value !== "--" && value.length > 0) {
                        details.dns.push(value);
                    }
                } else if (key === "GENERAL.HWADDR") {
                    details.macAddress = value;
                }
            }
        }

        return details;
    }

    function refreshOnConnectionChange(): void {
        getWifiStatus();
        getNetworks();
        getDeviceStatus(output => {
            root.wirelessInterfaces = parseDeviceStatusOutput(output, root.deviceTypeWifi);
            updateEthernetInterfaces(output);
            const wireless = root.wirelessInterfaces.find(iface => isConnectedState(iface.state));
            if (wireless)
                getWirelessDeviceDetails(wireless.device);
            else
                root.wirelessDeviceDetails = null;
            if (root.activeEthernet)
                getEthernetDeviceDetails(root.activeEthernet.iface);
            else
                root.ethernetDeviceDetails = null;
        });
    }

    Component.onCompleted: {
        refreshOnConnectionChange();
        loadSavedConnections();
    }

    Component {
        id: commandProc

        CommandProcess {}
    }

    Component {
        id: apComp

        AccessPoint {}
    }

    Component {
        id: ethComp

        EthernetDevice {}
    }

    Timer {
        id: connectionRetry
        property var attempt: null
        interval: 1000
        onTriggered: {
            const next = attempt;
            attempt = null;
            if (next) next();
        }
    }

    Process {
        id: dataUsageProc

        property string iface
        property var cb

        stdout: StdioCollector {
            onStreamFinished: {
                const nums = text.trim().split("\n").map(n => parseInt(n.trim(), 10)).filter(n => !isNaN(n));
                if (nums.length < 2) {
                    if (dataUsageProc.cb)
                        dataUsageProc.cb("");
                    return;
                }
                const human = Units.formatBytes(nums[0] + nums[1]);
                root.ethernetDataUsage = human;
                if (dataUsageProc.cb)
                    dataUsageProc.cb(human);
            }
        }
    }

    Process {
        id: speedProc

        stdout: StdioCollector {
            onStreamFinished: {
                const mbit = parseInt(text.trim(), 10);
                // Disconnected/virtual interfaces report -1 or nothing.
                if (isNaN(mbit) || mbit <= 0) {
                    root.ethernetSpeed = "";
                } else if (mbit >= 1000) {
                    const gbps = mbit / 1000;
                    // TRANSLATORS: %1 = a number
                    root.ethernetSpeed = Tr.tr("%1 Gbps").arg(Number.isInteger(gbps) ? gbps : gbps.toFixed(1));
                } else {
                    // TRANSLATORS: %1 = a number
                    root.ethernetSpeed = Tr.tr("%1 Mbps").arg(mbit);
                }
            }
        }
    }

    Process {
        id: rescanProc

        command: ["nmcli", "dev", root.nmcliCommandWifi, "list", "--rescan", "yes"]
        onExited: root.getNetworks() // qmllint disable signal-handler-parameters
    }

    Process {
        id: monitorProc

        running: true
        command: ["nmcli", "monitor"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: monitorRefresh.start()
        }
        onExited: monitorRestartTimer.start() // qmllint disable signal-handler-parameters
    }

    Timer {
        id: monitorRefresh
        interval: 150
        onTriggered: root.refreshOnConnectionChange()
    }

    Timer {
        id: monitorRestartTimer

        interval: 2000
        onTriggered: {
            monitorProc.running = true;
        }
    }

    LoggingCategory {
        id: lc

        name: "hyprstack.qml.services.nmcli"
        defaultLogLevel: LoggingCategory.Info
    }

    component CommandProcess: Process {
        id: proc

        property var callback: null
        property list<string> cmdArgs: []
        property bool callbackCalled: false
        property int exitCode: 127

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {
            id: stderrCollector

            onStreamFinished: {
                if (proc.callback && !proc.callbackCalled && root.isConnectionCommand(proc.cmdArgs)
                    && root.detectPasswordRequired(text)) {
                    proc.callbackCalled = true;
                    proc.callback({success: false, output: stdoutCollector.text, error: text, exitCode: -1, needsPassword: true});
                }
            }
        }

        onExited: code => exitCode = code
        // A missing executable emits runningChanged without exited.
        onRunningChanged: if (!running) Qt.callLater(finish)

        function finish(): void {
            const index = root.activeProcesses.indexOf(proc);
            if (index < 0)
                return;
            root.activeProcesses.splice(index, 1);
            proc.destroy();
            if (callbackCalled || !callback)
                return;

            const output = stdoutCollector.text ?? "";
            const error = stderrCollector.text ?? "";
            const connection = root.isConnectionCommand(cmdArgs);
            callbackCalled = true;
            callback({success: exitCode === 0, output: output, error: error, exitCode: exitCode,
                needsPassword: connection && root.detectPasswordRequired(error)});
        }
    }

    component AccessPoint: QtObject {
        required property var lastIpcObject
        readonly property string ssid: lastIpcObject.ssid
        readonly property string bssid: lastIpcObject.bssid
        readonly property int strength: lastIpcObject.strength
        readonly property int frequency: lastIpcObject.frequency
        readonly property bool active: lastIpcObject.active
        readonly property string security: lastIpcObject.security
        readonly property bool isSecure: security.length > 0
    }

    component EthernetDevice: QtObject {
        required property var lastIpcObject
        readonly property string iface: lastIpcObject.interface
        readonly property string type: lastIpcObject.type
        readonly property string state: lastIpcObject.state
        readonly property string connection: lastIpcObject.connection
        readonly property bool connected: lastIpcObject.connected
        readonly property string ipAddress: lastIpcObject.ipAddress ?? ""
        readonly property string gateway: lastIpcObject.gateway ?? ""
        readonly property var dns: lastIpcObject.dns ?? []
        readonly property string subnet: lastIpcObject.subnet ?? ""
        readonly property string macAddress: lastIpcObject.macAddress ?? ""
        readonly property string speed: lastIpcObject.speed ?? ""
    }
}
