pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property bool blurEnabled: true
    property bool windowShadows: true
    property bool uiShadows: true
    property int shadowSize: 18
    property real shadowOpacity: 0.35
    property int blurVariant: 0
    property int blurSize: 8
    property int blurPasses: 2
    property bool proportionalBlur: false
    property bool windowWobble: false
    property real wobbleIntensity: 0.2
    property int wobbleStiffness: 200
    property int wobbleDamping: 12
    property bool windowGlow: false
    property int glowSize: 10
    property real glowOpacity: 0.35
    property bool motionBlur: false
    property int motionBlurSamples: 7
    property var preferences: ({})
    readonly property bool uiShadowsEnabled: uiShadows && shadowSize > 0 && shadowOpacity > 0 && !GameMode.enabled
    property bool loaded: false

    function setBlurEnabled(enabled: bool): void {
        set("blur", enabled);
    }

    function set(option: string, value: var): void {
        if (!loaded) return;
        if (option === "blur") blurEnabled = !!value;
        else if (option === "windowShadows") windowShadows = !!value;
        else if (option === "uiShadows") uiShadows = !!value;
        else if (option === "shadowSize") shadowSize = Math.max(0, Math.min(60, Math.round(value)));
        else if (option === "shadowOpacity") shadowOpacity = Math.max(0, Math.min(1, value));
        else if (option === "blurVariant") blurVariant = bounded(value, 0, 10, 0);
        else if (option === "blurSize") blurSize = bounded(value, 0, 100, 8);
        else if (option === "blurPasses") blurPasses = bounded(value, 1, 10, 2);
        else if (option === "proportionalBlur") proportionalBlur = !!value;
        else if (option === "windowWobble") windowWobble = !!value;
        else if (option === "wobbleIntensity") wobbleIntensity = bounded(value, 0, 2, 0.2, false);
        else if (option === "wobbleStiffness") wobbleStiffness = bounded(value, 1, 1000, 200);
        else if (option === "wobbleDamping") wobbleDamping = bounded(value, 0, 100, 12);
        else if (option === "windowGlow") windowGlow = !!value;
        else if (option === "glowSize") glowSize = bounded(value, 0, 100, 10);
        else if (option === "glowOpacity") glowOpacity = bounded(value, 0, 1, 0.35, false);
        else if (option === "motionBlur") motionBlur = !!value;
        else if (option === "motionBlurSamples") motionBlurSamples = bounded(value, 1, 64, 7);
        else return;
        storage.setText(JSON.stringify(Object.assign({}, preferences, values())));
        apply();
    }

    function bounded(value: var, minimum: real, maximum: real, fallback: real, integer: var): real {
        const number = Number(value);
        if (!Number.isFinite(number)) return fallback;
        const result = Math.max(minimum, Math.min(maximum, number));
        return integer === false ? result : Math.round(result);
    }

    function values(): var {
        return {blur: blurEnabled, windowShadows: windowShadows, uiShadows: uiShadows,
            shadowSize: shadowSize, shadowOpacity: shadowOpacity, blurVariant: blurVariant,
            blurSize: blurSize, blurPasses: blurPasses, proportionalBlur: proportionalBlur,
            windowWobble: windowWobble, wobbleIntensity: wobbleIntensity,
            wobbleStiffness: wobbleStiffness, wobbleDamping: wobbleDamping,
            windowGlow: windowGlow, glowSize: glowSize, glowOpacity: glowOpacity,
            motionBlur: motionBlur, motionBlurSamples: motionBlurSamples};
    }

    function apply(): void {
        if (loaded && Hypr.usingLua) {
            Hypr.extras.message(`eval if hyprstack_layouts then hyprstack_layouts.shadows({windowShadows=${windowShadows && !GameMode.enabled},shadowSize=${shadowSize},shadowOpacity=${shadowOpacity}}) end`);
            Hypr.extras.message(`eval if hyprstack_layouts then hyprstack_layouts.window_effects(${JSON.stringify(JSON.stringify(values()))}, ${GameMode.enabled}) end`);
        }
    }

    FileView {
        id: storage
        path: `${Paths.config}/effects.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.preferences = data;
                root.blurEnabled = data.blur !== false;
                root.windowShadows = data.windowShadows !== false;
                root.uiShadows = data.uiShadows !== false;
                root.shadowSize = Math.max(0, Math.min(60, Math.round(data.shadowSize ?? 18)));
                root.shadowOpacity = Math.max(0, Math.min(1, data.shadowOpacity ?? 0.35));
                root.blurVariant = root.bounded(data.blurVariant ?? 0, 0, 10, 0);
                root.blurSize = root.bounded(data.blurSize ?? 8, 0, 100, 8);
                root.blurPasses = root.bounded(data.blurPasses ?? 2, 1, 10, 2);
                root.proportionalBlur = data.proportionalBlur === true;
                root.windowWobble = data.windowWobble === true;
                root.wobbleIntensity = root.bounded(data.wobbleIntensity ?? 0.2, 0, 2, 0.2, false);
                root.wobbleStiffness = root.bounded(data.wobbleStiffness ?? 200, 1, 1000, 200);
                root.wobbleDamping = root.bounded(data.wobbleDamping ?? 12, 0, 100, 12);
                root.windowGlow = data.windowGlow === true;
                root.glowSize = root.bounded(data.glowSize ?? 10, 0, 100, 10);
                root.glowOpacity = root.bounded(data.glowOpacity ?? 0.35, 0, 1, 0.35, false);
                root.motionBlur = data.motionBlur === true;
                root.motionBlurSamples = root.bounded(data.motionBlurSamples ?? 7, 1, 64, 7);
            } catch (error) {
                console.warn(`Unable to load effect preferences: ${error}`);
            }
            root.loaded = true;
            root.apply();
        }
        onLoadFailed: { root.loaded = true; root.apply(); }
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void { root.apply(); }
    }

    Connections {
        target: GameMode
        function onEnabledChanged(): void { root.apply(); }
    }
}
