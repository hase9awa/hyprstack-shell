import QtQuick
import Hyprstack.Config

NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial
    // Visibility and size gates must never cross their endpoints. Goop keeps
    // its spring on accents; the actual panel follows a bounded travel curve.
    property bool bounded: false

    duration: {
        if (type < Anim.StandardSmall || type > Anim.SlowEffects)
            return Tokens.anim.durations.normal;

        if (type === Anim.FastSpatial)
            return Tokens.anim.durations.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return Tokens.anim.durations.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return Tokens.anim.durations.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return Tokens.anim.durations.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return Tokens.anim.durations.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return Tokens.anim.durations.expressiveSlowEffects;

        const types = ["small", "normal", "large", "extraLarge"];
        const idx = type % 4; // 0-7 are the 4 standard types
        return Tokens.anim.durations[types[idx]];
    }
    easing: {
        if (bounded && GlobalConfig.appearance.anim.shellPreset === "goop")
            return Tokens.anim.expressiveDefaultEffects;
        if (type === Anim.FastSpatial)
            return Tokens.anim.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return Tokens.anim.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return Tokens.anim.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return Tokens.anim.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return Tokens.anim.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return Tokens.anim.expressiveSlowEffects;

        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return Tokens.anim.emphasized;
        return Tokens.anim.standard;
    }
}
