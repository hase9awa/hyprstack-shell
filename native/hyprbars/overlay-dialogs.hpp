#pragma once

#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/output/Monitor.hpp>

namespace HyprstackOverlayDialogs {
static CHyprSignalListener opened, focus, backgroundRender;

static void restoreBackground(const PHLLS& layer) {
    if (!layer || !layer->mapped() || layer->m_layer != ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND
        || layer->m_namespace != "hyprstack-background") return;
    const auto& alpha = layer->alpha()[Desktop::View::LS_ALPHA_FADE];
    if (alpha->goal() > 0.F) return;
    alpha->setValueAndWarp(1.F);
    if (const auto monitor = layer->m_monitor.lock()) {
        monitor->m_blurFBDirty = true;
        g_pHyprRenderer->damageMonitor(monitor);
    }
}

static void restoreBackgrounds(const PHLMONITOR& monitor) {
    if (!monitor) return;
    for (const auto& layer : monitor->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND])
        restoreBackground(layer.lock());
}

static void permit(const PHLLS& layer) {
    if (layer && layer->mapped() && layer->m_layer == ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY)
        layer->m_flags |= Desktop::View::LAYER_FLAG_ABOVE_FULLSCREEN;
}

static void install() {
    // Scrolling clears ABOVE_FULLSCREEN while deactivating a floating media
    // viewer. This can happen inside the new layer's takeKeyboardFocus(),
    // before onMap() decides whether to start its visibility animation.
    focus = Event::bus()->m_events.input.keyboard.focus.listen([](SP<CWLSurfaceResource> surface) {
        const auto owner = surface ? Desktop::View::CWLSurface::fromResource(surface) : nullptr;
        permit(owner ? dynamicPointerCast<Desktop::View::CLayerSurface>(owner->view()) : nullptr);
    });
    opened = Event::bus()->m_events.layer.opened.listen([](PHLLS layer) {
        // 0.57 skips animateIn() for a new background while fullscreen is
        // active, then never restores it. Its stacking level stays behind
        // windows; it must not gain ABOVE_FULLSCREEN or keyboard focus.
        restoreBackground(layer);
        if (!layer || layer->m_layer != ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY) return;
        permit(layer);
        const auto& alpha = layer->alpha()[Desktop::View::LS_ALPHA_FADE];
        // An overlay that missed animateIn() otherwise stays invisible while
        // its exclusive keyboard focus blocks every application underneath.
        // Preserve normal entry animations and leave TOP panels untouched.
        if (alpha->goal() > 0.F) return;
        alpha->setValueAndWarp(1.F);
        if (const auto monitor = layer->m_monitor.lock()) g_pHyprRenderer->damageMonitor(monitor);
        g_pInputManager->simulateMouseMovement();
    });
    // A live wallpaper toggle can change the layer from bottom to background
    // during fullscreen, which also resets its fade to zero in onCommit().
    backgroundRender = Event::bus()->m_events.render.stage.listen([](Event::SRenderStageEvent event) {
        if (event.stage == RENDER_PRE) restoreBackgrounds(event.monitor);
    });
    // Recover an already hidden desktop when the native module is reloaded.
    for (const auto& monitor : State::monitorState()->monitors()) restoreBackgrounds(monitor);
}

static void remove() {
    opened.reset();
    focus.reset();
    backgroundRender.reset();
}
} // namespace HyprstackOverlayDialogs
