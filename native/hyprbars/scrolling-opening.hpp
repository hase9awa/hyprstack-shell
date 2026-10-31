// Keep full-width scrolling columns independent of exclusive maximize state.
#pragma once

#include "barDeco.hpp"
#include "globals.hpp"
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>

static bool normalizeTiledMaximize(PHLWINDOW window) {
    if (!window || !window->mapped() || window->isFloating() || (window->m_state & Desktop::View::WINDOW_STATE_PINNED) ||
        g_pGlobalState->config.enabled->value() || !window->m_workspace || !window->m_workspace->space() ||
        Fullscreen::controller()->getFullscreenModes(window).internal != Fullscreen::FSMODE_MAXIMIZED)
        return false;

    const auto algorithm = window->m_workspace->space()->algorithm();
    const auto scrolling = algorithm ? dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get()) : nullptr;
    if (!scrolling) return false;
    const auto data = scrolling->dataFor(window->layoutTarget(), true);
    if (!data || !data->column) return false;

    // Remove only maximize, preserving a real video fullscreen request. Keep
    // the current image; both layout changes happen before the next frame.
    Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_NONE, Fullscreen::FSMODE_NONE);
    const auto monitor = window->m_monitor.lock();
    data->column->setColumnWidth(monitor && monitor->m_size.y > monitor->m_size.x ? .5F : 1.F);
    scrolling->recalculate();
    for (const auto& bar : g_pGlobalState->bars)
        if (bar && bar->getOwner() == window) bar->syncNativePolicy();
    window->sendWindowSize(true);
    return true;
}
