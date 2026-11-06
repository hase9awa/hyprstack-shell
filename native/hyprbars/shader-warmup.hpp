// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <array>
#include <set>

// Hyprland compiles surface/decor variants synchronously on their first draw.
// Prepare the ordinary RGBX/RGBA window variants during each output's first
// frame, before an application launch can stall an otherwise idle desktop.
// No timer, extra frame or persistent GL context is needed.
namespace HyprstackShaders {
static CHyprSignalListener listener;
static std::set<MONITORID> prepared;

static Render::ShaderFeatureFlags colourFeatures(const NColorManagement::PImageDescription& source,
                                                 const NColorManagement::PImageDescription& target,
                                                 PHLMONITOR monitor) {
    using namespace Render;
    if (!source->needsCM(target)) return 0;
    const auto settings = g_pHyprRenderer->getCMSettings(g_pHyprRenderer->context(), source, target, nullptr, true,
        monitor->m_sdrMinLuminance, monitor->m_sdrMaxLuminance);
    ShaderFeatureFlags flags = SH_FEAT_CM;
    if (target->value().icc.present) flags |= SH_FEAT_ICC;
    else {
        if (settings.needsTonemap) {
            flags |= SH_FEAT_TONEMAP;
            if (settings.tonemapMode == 3) flags |= SH_FEAT_ALT_TONEMAP;
        }
        if (settings.needsSDRmod) flags |= SH_FEAT_SDR_MOD;
    }
    return flags;
}

static void install() {
    prepared.clear();
    listener = Event::bus()->m_events.render.stage.listen([](Event::SRenderStageEvent event) {
            const auto stage = event.stage;
        using namespace Render;
        const auto& gl = GL::g_pHyprOpenGL;
        const auto& data = g_pHyprRenderer->context().m_data;
        const auto monitor = data.pMonitor.lock();
        if (stage != RENDER_BEGIN || !gl || !gl->m_shadersInitialized || !monitor || prepared.contains(monitor->m_id)) return;
        const auto work = g_pHyprRenderer->workBufferImageDescription(g_pHyprRenderer->context());
        if (!work || !data.currentFB) return;
        prepared.insert(monitor->m_id);
        gl->makeEGLCurrent();
        const ShaderFeatureFlags mirror = monitor->needsUnmodifiedCopy() && data.currentFB->getMirrorTexture() ? SH_FEAT_MIRROR : 0;
        const auto srgb = NColorManagement::getDefaultImageDescription();
        const auto surface = colourFeatures(srgb, work, monitor) | mirror;
        for (const auto flags : std::array<ShaderFeatureFlags, 4>{0, SH_FEAT_RGBA, SH_FEAT_ROUNDING, SH_FEAT_RGBA | SH_FEAT_ROUNDING})
            gl->getShaderVariant(SH_FRAG_SURFACE, surface | flags);
        gl->getShaderVariant(SH_FRAG_BORDER1, colourFeatures(work, srgb, monitor) | SH_FEAT_ROUNDING | mirror);
        gl->getShaderVariant(SH_FRAG_SHADOW,
            (work->value().transferFunction != NColorManagement::CM_TRANSFER_FUNCTION_EXT_LINEAR ? SH_FEAT_CM : 0) | mirror);
        if (std::ranges::all_of(State::monitorState()->monitors(), [](const auto& m) { return prepared.contains(m->m_id); }))
            listener.reset();
    });
}
static void remove() { listener.reset(); prepared.clear(); }
} // namespace HyprstackShaders
