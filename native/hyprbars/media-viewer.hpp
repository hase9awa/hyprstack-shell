// Telegram's translucent fullscreen viewer needs its chat as a backdrop.
// Its first mapped buffer can still contain the small, undimmed preview.
#pragma once

#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/SceneResources.hpp>
#include <chrono>
#include <cmath>
#include <algorithm>
#include <unordered_map>

namespace HyprstackMediaViewer {
using Clock = std::chrono::steady_clock;
struct Entry {
    PHLWINDOWREF viewer, backdrop;
    Clock::time_point deadline;
    bool ready = false, closing = false;
};
static std::unordered_map<uint64_t, Entry> entries;
static CHyprSignalListener render, closed;
static SP<CEventLoopTimer> deadlineTimer;

static void damage(const PHLWINDOW& window) {
    if (const auto monitor = window ? window->m_monitor.lock() : nullptr)
        g_pHyprRenderer->damageMonitor(monitor);
}

static void reveal(Entry& entry) {
    if (entry.ready) return;
    entry.ready = true;
    damage(entry.viewer.lock());
}

static bool holding(const PHLWINDOW& viewer) {
    if (!viewer) return false;
    const auto found = entries.find(viewer->metadata().stableID());
    return found != entries.end() && !found->second.ready;
}

static PHLWINDOW backdropFor(const PHLWINDOW& viewer) {
    if (!viewer || !viewer->mapped() || !Fullscreen::controller()->isFullscreen(viewer)) return nullptr;
    const auto found = entries.find(viewer->metadata().stableID());
    if (found == entries.end()) return nullptr;
    const auto parent = found->second.backdrop.lock();
    return parent && parent->mapped() && !parent->isHidden() && parent->m_workspace == viewer->m_workspace ? parent : nullptr;
}

static bool isBackdrop(const PHLWINDOW& window) {
    return std::ranges::any_of(entries, [&](const auto& item) {
        return item.second.backdrop == window && backdropFor(item.second.viewer.lock()) == window;
    });
}

static bool bufferReady(const PHLWINDOW& window) {
    const auto surface = window->resource();
    if (!surface || !surface->m_current.texture) return false;
    const auto geometry = window->backend().geometry().box;
    const auto goal = window->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    const auto size = surface->m_current.size;
    return goal.x > 0 && goal.y > 0 && std::abs(geometry.w - goal.x) <= 1 && std::abs(geometry.h - goal.y) <= 1
        && size.x >= geometry.x + geometry.w && size.y >= geometry.y + geometry.h;
}

static void scheduleDeadline() {
    std::optional<Clock::time_point> next;
    for (const auto& [_, entry] : entries)
        if (!entry.ready && !entry.closing && (!next || entry.deadline < *next)) next = entry.deadline;
    deadlineTimer->updateTimeout(next ? std::optional{std::max(*next - Clock::now(), Clock::duration{1})} : std::nullopt);
}

static void track(const PHLWINDOW& viewer, const PHLWINDOW& backdrop) {
    if (!viewer || !backdrop || viewer == backdrop || !viewer->mapped() || !backdrop->mapped()
        || viewer->backend().pid() != backdrop->backend().pid()
        || viewer->metadata().appID() != backdrop->metadata().appID()) return;
    const auto id = viewer->metadata().stableID();
    if (entries.contains(id) && !entries.at(id).closing) return;
    entries.insert_or_assign(id, Entry{viewer, backdrop, Clock::now() + std::chrono::milliseconds(250)});
    scheduleDeadline();
}

static void install() {
    deadlineTimer = makeShared<CEventLoopTimer>(std::nullopt, [](SP<CEventLoopTimer>, void*) {
        for (auto& [_, entry] : entries)
            if (!entry.ready && !entry.closing && Clock::now() >= entry.deadline) reveal(entry);
        scheduleDeadline();
    }, nullptr);
    g_pEventLoopManager->addTimer(deadlineTimer);
    render = Event::bus()->m_events.render.stage.listen([](Event::SRenderStageEvent event) {
        if (event.stage != RENDER_PRE_WINDOWS || !event.context) return;
        const auto& ctx = event.context->get();
        if (ctx.m_renderingSnapshot || (ctx.sceneResources() && ctx.sceneResources()->isolated())) return;
        // Closing snapshots are made synchronously after window.close; keep
        // an unready image held until that capture has finished.
        std::erase_if(entries, [](const auto& item) { return item.second.closing || !item.second.viewer; });
        for (auto& [_, entry] : entries) {
            const auto viewer = entry.viewer.lock();
            if (!viewer || !viewer->mapped() || viewer->m_monitor != event.monitor) continue;
            const bool fullscreen = Fullscreen::controller()->isFullscreen(viewer);
            if (entry.ready) continue;
            if (!fullscreen || bufferReady(viewer) || Clock::now() >= entry.deadline) {
                reveal(entry);
            }
        }
    });
    closed = Event::bus()->m_events.window.close.listen([](PHLWINDOW window) {
        const auto found = entries.find(window->metadata().stableID());
        if (found == entries.end()) return;
        found->second.closing = true;
        scheduleDeadline();
    });
}

static void remove() {
    render.reset(); closed.reset();
    for (auto& [_, entry] : entries) damage(entry.viewer.lock());
    entries.clear();
    if (deadlineTimer && g_pEventLoopManager) g_pEventLoopManager->removeTimer(deadlineTimer);
    deadlineTimer.reset();
}
} // namespace HyprstackMediaViewer
