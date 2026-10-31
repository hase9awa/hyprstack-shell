// Click transactions and native drag gestures for the pinned Hyprland 0.57 API.
#pragma once

#include "titlebar-actions.hpp"
#include "scrolling-opening.hpp"
#include "stacking-snap.hpp"
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/render/decorations/DecorationPositioner.hpp>

class CStackingInput {
  public:
    CStackingInput() {
        m_workspaceMove = Event::bus()->m_events.window.moveToWorkspace.listen([this](PHLWINDOW window, PHLWORKSPACE destination) {
            if (enabled() || !validMapped(window) || window->isFloating() || (window->m_state & Desktop::View::WINDOW_STATE_PINNED) || !destination || (destination->type() == Workspace::eWorkspaceType::SPECIAL)) return;
            const auto target = window->layoutTarget();
            // window.layout reads the destination workspace here, but the
            // native target still belongs to its original scrolling space.
            const auto space = target ? target->space() : nullptr;
            const auto algorithm = space ? space->algorithm() : nullptr;
            const auto scrolling = algorithm ? dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get()) : nullptr;
            const auto data = scrolling ? scrolling->dataFor(target, true) : nullptr;
            const auto column = data ? data->column.lock() : nullptr;
            if (!column) return;
            if (std::ranges::none_of(m_transfers, [&](const auto& entry) { return entry.window.lock() == window; }))
                m_transfers.push_back({window, column->getColumnWidth()});
            if (m_transferTimer) g_pEventLoopManager->removeTimer(m_transferTimer);
            m_transferTimer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(1), [this](SP<CEventLoopTimer>, void*) {
                for (const auto& entry : m_transfers) {
                    const auto window = entry.window.lock();
                    if (enabled() || !validMapped(window) || window->isFloating() || !window->m_workspace || (window->m_workspace->type() == Workspace::eWorkspaceType::SPECIAL)) continue;
                    const auto target = window->layoutTarget();
                    const auto space = target ? target->space() : nullptr;
                    const auto algorithm = space ? space->algorithm() : nullptr;
                    const auto scrolling = algorithm ? dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get()) : nullptr;
                    const auto data = scrolling ? scrolling->dataFor(target, true) : nullptr;
                    const auto column = data ? data->column.lock() : nullptr;
                    if (!column || std::abs(column->getColumnWidth() - entry.width) < 0.0001) continue;
                    column->setColumnWidth(entry.width);
                    scrolling->recalculate();
                }
                m_transfers.clear();
            }, nullptr);
            g_pEventLoopManager->addTimer(m_transferTimer);
        });
        // Run before newTarget() changes the camera. A native maximized tile
        // otherwise hides its neighbour as soon as the viewport goal changes.
        m_openEarly = Event::bus()->m_events.window.openEarly.listen([this](PHLWINDOW incoming) {
            m_openingWindow.reset();
            m_openingAnchor.reset();
            if (enabled() || !incoming || incoming->isFloating() || !incoming->m_workspace) return;
            m_openingWindow = incoming;
            const auto focused = Desktop::focusState()->window();
            if (focused && focused != incoming && validMapped(focused) && !focused->isFloating() &&
                focused->m_workspace == incoming->m_workspace)
                m_openingAnchor = focused;
            for (const auto& window : Desktop::windowState()->windows())
                if (window != incoming && window->m_workspace == incoming->m_workspace) {
                    if (!m_openingAnchor && validMapped(window) && !window->isFloating() &&
                        window->presentation().visibleOnMonitor(incoming->m_monitor.lock()))
                        m_openingAnchor = window;
                    normalizeTiledMaximize(window);
                }
        });
        m_openLate = Event::bus()->m_events.window.openLate.listen([this](PHLWINDOW incoming) {
            const auto anchor = m_openingAnchor.lock();
            const bool ours = m_openingWindow.lock() == incoming;
            m_openingWindow.reset();
            m_openingAnchor.reset();
            if (!ours || enabled() || !incoming || !validMapped(incoming) || incoming->isFloating() ||
                !anchor || !validMapped(anchor) || anchor->m_workspace != incoming->m_workspace ||
                Fullscreen::controller()->getFullscreenModes(incoming).internal == Fullscreen::FSMODE_FULLSCREEN)
                return;
            // animateIn() starts a pop-in at the final viewport position. Move
            // the new tile from the same camera offset as its existing neighbour
            // instead; otherwise it instantly obscures half of the old image.
            const auto cameraDelta = anchor->positionAnimation()->value() - anchor->positionAnimation()->goal();
            if (cameraDelta.size() < 1) return;
            const auto destination = incoming->positionAnimation()->goal();
            incoming->sizeAnimation()->setValueAndWarp(incoming->sizeAnimation()->goal());
            incoming->positionAnimation()->setValueAndWarp(destination + cameraDelta);
            incoming->move(destination);
            incoming->presentation().updateDecorations();
        });
        // Read the very same geometry as renderWindow(), for each output's
        // frame. Animation callbacks can otherwise cache an earlier tick.
        m_render = Event::bus()->m_events.render.stage.listen([](Event::SRenderStageEvent event) {
            const auto stage = event.stage;
            if (stage != RENDER_PRE_WINDOW) return;
            const auto window = g_pHyprRenderer->context().m_data.currentWindow.lock();
            if (!validMapped(window) || window->isHidden()) return;
            if (window->sizeAnimation()->isBeingAnimated())
                g_pDecorationPositioner->forceRecalcFor(window);
            g_pDecorationPositioner->onWindowUpdate(window);
        });
        m_button = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent event, Event::SCallbackInfo&) {
            if ((event.button != 272 && event.button != 273) || !enabled()) return;
            if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
                if (event.button != 272) return;
                m_pressedFocus = Desktop::focusState()->window();
                m_pressTime = Time::steadyNow();
                m_pressValid = true;
                const auto pos = g_pInputManager->getMouseCoordsInternal();
                const auto window = Desktop::viewState()->hitTest().windowAt(pos,
                    Desktop::View::ALLOW_FLOATING | Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
                const auto monitor = Desktop::focusState()->monitor();
                bool panel = false;
                if (monitor) {
                    Vector2D local;
                    PHLLS layer;
                    for (size_t index : {2U, 3U})
                        panel = panel || bool(Desktop::viewState()->hitTest().layerSurfaceAt(pos,
                            &monitor->m_layerSurfaceLayers[index], &local, &layer));
                }
                if (!window && !panel) Desktop::focusState()->fullWindowFocus(nullptr, Desktop::FOCUS_REASON_CLICK);
            } else {
                const auto drag = g_layoutManager->dragController().get();
                const auto target = drag->target();
                const auto window = target ? target->window() : m_dragWindow.lock();
                if (!window || !window->mapped()) { HyprstackSnap::clear(); return; }
                const bool moved = target ? drag->dragThresholdReached() : m_dragMoved;
                const auto mode = target ? drag->mode() : m_dragMode;
                const auto pos = g_pInputManager->getMouseCoordsInternal();
                if (!moved || mode == MBIND_INVALID) { HyprstackSnap::clear(); return; }
                const auto snap = mode == MBIND_MOVE ? HyprstackSnap::drop() : HyprstackSnap::Drop{};
                HyprstackSnap::clear();
                m_dragWindow.reset();
                m_dragMode = MBIND_INVALID;
                if (m_releaseTimer) g_pEventLoopManager->removeTimer(m_releaseTimer);
                m_releaseTimer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(1),
                    [this, weak = PHLWINDOWREF(window), pos, mode, snap](SP<CEventLoopTimer>, void*) {
                        const auto window = weak.lock();
                        if (!enabled() || !window || !window->mapped() || g_layoutManager->dragController()->target()) return;
                        const auto monitor = window->m_monitor.lock();
                        if (mode == MBIND_MOVE && HyprstackSnap::apply(window,snap)) return;
                        // Snap only after an actual move ends at this output's top edge.
                        if (mode == MBIND_MOVE && monitor && pos.y <= monitor->m_position.y + 6 &&
                            pos.y >= monitor->m_position.y && pos.x >= monitor->m_position.x &&
                            pos.x < monitor->m_position.x + monitor->m_size.x)
                            runDecorationAction(window, "maximize-snap");
                        else runDecorationAction(window, "remember-stacking");
                    }, nullptr);
                g_pEventLoopManager->addTimer(m_releaseTimer);
            }
        });
        m_move = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D pos, Event::SCallbackInfo&) {
            if (!enabled()) { m_dragWindow.reset(); HyprstackSnap::clear(); return; }
            const auto drag = g_layoutManager->dragController().get();
            const auto target = drag->target();
            const auto window = target ? target->window() : nullptr;
            if (!window || !window->mapped()) { HyprstackSnap::clear(); return; }
            const auto mode = drag->mode();
            if (m_dragWindow.lock() != window || m_dragMode != mode) {
                m_dragWindow = window;
                m_dragMode = mode;
                m_dragMoved = false;
                const bool maximized = Fullscreen::controller()->getFullscreenModes(window).client == Fullscreen::FSMODE_MAXIMIZED;
                const auto previous = window->layoutBox();
                if (mode == MBIND_MOVE && !maximized) runDecorationAction(window,"drag-restore");
                const bool snapped = (previous.size()-window->layoutBox().size()).size() > 1;
                if (mode != MBIND_MOVE) {
                    HyprstackSnap::clear();
                    runDecorationAction(window, "resize-start");
                } else if (maximized || snapped) {
                    // Rebase Hyprland's drag snapshot after restoring the normal
                    // box, so the next motion cannot put its maximized size back.
                    const double fraction = std::clamp((pos.x - previous.x) / previous.w, 0.0, 1.0);
                    const bool exclusive = drag->exclusiveDeviceGrab();
                    g_layoutManager->endDragTarget();
                    if (maximized) runDecorationAction(window, "maximize-unset");
                    auto normal = window->layoutBox();
                    normal.x = pos.x - normal.w * fraction;
                    std::string app = window->metadata().appID();
                    std::ranges::transform(app, app.begin(), [](unsigned char c) { return std::tolower(c); });
                    const bool csd = app.find("thorium") != std::string::npos || app.find("chromium") != std::string::npos ||
                        app.find("chrome") != std::string::npos || app.find("telegram") != std::string::npos ||
                        app.find("ayugram") != std::string::npos || app == "firefox" || app == "librewolf" ||
                        app.starts_with("zen") || app == "discord" || app.starts_with("org.gnome.");
                    normal.y = pos.y + (csd ? -16 : 16);
                    target->setPositionGlobal(normal);
                    g_layoutManager->beginDragTarget(target, MBIND_MOVE, std::nullopt, exclusive);
                    runDecorationAction(window, "drag-start");
                } else {
                    runDecorationAction(window, "drag-start");
                }
            }
            m_dragMoved = drag->dragThresholdReached();
            if (m_dragMoved && mode == MBIND_MOVE) HyprstackSnap::update(window,pos);
        });
        m_rules = Event::bus()->m_events.window.updateRules.listen([](PHLWINDOW window) { suppressTelegram(window); });
        m_reload = Event::bus()->m_events.config.reloaded.listen([] {
            for (const auto& window : Desktop::windowState()->windows()) suppressTelegram(window);
        });
        for (const auto& window : Desktop::windowState()->windows()) suppressTelegram(window);
    }

    ~CStackingInput() {
        if (m_releaseTimer && g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_releaseTimer);
        if (m_transferTimer && g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_transferTimer);
    }

    bool taskFocused(const std::string& address, const std::string& id) {
        const bool recent = m_pressValid && std::chrono::duration<double>(Time::steadyNow() - m_pressTime).count() < 1.5;
        const auto window = recent ? m_pressedFocus.lock() : Desktop::focusState()->window();
        m_pressValid = false;
        return window && std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())) == address &&
            std::format("{:x}", window->metadata().stableID()) == id;
    }

  private:
    static bool enabled() { return g_pGlobalState && g_pGlobalState->config.enabled->value(); }

    static void suppressTelegram(PHLWINDOW window) {
        if (!window) return;
        std::string app = window->metadata().appID();
        std::ranges::transform(app, app.begin(), [](unsigned char c) { return std::tolower(c); });
        if (app.find("telegram") != std::string::npos || app.find("ayugram") != std::string::npos)
            window->m_ruleApplicator->focusOnActivate() = false;
    }

    CHyprSignalListener m_button, m_move, m_rules, m_reload, m_render, m_openEarly, m_openLate, m_workspaceMove;
    PHLWINDOWREF m_pressedFocus, m_dragWindow, m_openingWindow, m_openingAnchor;
    Time::steady_tp m_pressTime = Time::steadyNow();
    bool m_pressValid = false, m_dragMoved = false;
    eMouseBindMode m_dragMode = MBIND_INVALID;
    SP<CEventLoopTimer> m_releaseTimer;
    struct STransfer { PHLWINDOWREF window; float width; };
    std::vector<STransfer> m_transfers;
    SP<CEventLoopTimer> m_transferTimer;
};

static UP<CStackingInput> stackingInput;
static int clearFocusLua(lua_State*) {
    Desktop::focusState()->fullWindowFocus(nullptr, Desktop::FOCUS_REASON_CLICK);
    return 0;
}
static int taskFocusedLua(lua_State* L) {
    const std::string address = luaL_checkstring(L, 1), id = luaL_checkstring(L, 2);
    lua_pushboolean(L, stackingInput && stackingInput->taskFocused(address, id));
    return 1;
}
