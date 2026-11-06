// One camera per output/workspace. Retargeting cannot give neighbouring windows
// different animation clocks or slide multiple workspaces into the same row.
#pragma once
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/managers/input/UnifiedWorkspaceSwipeGesture.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/protocols/ShortcutsInhibit.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <nlohmann/json.hpp>
#include <chrono>
#include <vector>

namespace HyprstackCamera {
using Clock = std::chrono::steady_clock;
using Json = nlohmann::json;
static constexpr double duration = .28;
static double phase(Clock::time_point start) { return std::clamp(std::chrono::duration<double>(Clock::now()-start).count()/duration, 0.0, 1.0); }
static double eased(double t) { return 1-std::pow(1-t, 3); }
static Layout::Tiled::CScrollingAlgorithm* scrollingLayout(PHLWORKSPACE workspace) {
    const auto algorithm = workspace && workspace->space() ? workspace->space()->algorithm() : nullptr;
    return algorithm ? dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get()) : nullptr;
}

struct Output {
    PHLMONITORREF monitor;
    double from = 0, to = 0;
    Clock::time_point start;
    double row() const { return from+(to-from)*eased(phase(start)); }
};
struct Member { PHLWINDOWREF window; Vector2D goal, size; };
struct Column {
    PHLWORKSPACEREF workspace;
    std::vector<Member> members;
    Vector2D from;
    Clock::time_point start;
    Vector2D offset() const { return from*(1-eased(phase(start))); }
};

class Cameras {
  public:
    Cameras() {
        m_active = Event::bus()->m_events.workspace.active.listen([this](PHLWORKSPACE workspace) {
            if (!m_enabled || !workspace || (workspace->type() == Workspace::eWorkspaceType::SPECIAL) || workspace->numberedID().value_or(0) <= 0) return;
            const auto monitor = workspace->m_monitor.lock();
            if (!monitor) return;
            auto& output = forOutput(monitor);
            const double current = output.row();
            output.from = m_paused ? workspace->numberedID().value_or(0) : current;
            output.to = workspace->numberedID().value_or(0);
            output.start = Clock::now();
            tick();
        });
        m_swipeBegin = Event::bus()->m_events.gesture.swipe.begin.listen([this](IPointer::SSwipeBeginEvent event, Event::SCallbackInfo& info) {
            resetSwipe();
            static auto disableInhibit = CConfigValue<Config::INTEGER>("binds:disable_keybind_grabbing");
            if (info.cancelled || !m_enabled || m_paused || !navigationFingers(event.fingers) ||
                g_pSessionLockManager->isSessionLocked() || g_pInputManager->getModsFromAllKBs() ||
                (PROTO::shortcutsInhibit->isInhibited() && !*disableInhibit)) return;
            const auto monitor = Desktop::focusState()->monitor();
            if (!monitor || monitor->m_activeSpecialWorkspace) return;
            m_swipeMonitor = monitor;
            m_swipeWorkspace = monitor->m_activeWorkspace;
            m_swipeFingers = event.fingers;
        });
        m_swipeUpdate = Event::bus()->m_events.gesture.swipe.update.listen([this](IPointer::SSwipeUpdateEvent event, Event::SCallbackInfo& info) {
            if (info.cancelled || !m_swipeMonitor || m_paused) return;
            m_swipeDelta += event.delta;
            if (m_swipeAxis == NONE && (std::abs(m_swipeDelta.x) >= 5 || std::abs(m_swipeDelta.y) >= 5)) {
                m_swipeAxis = std::abs(m_swipeDelta.x) > std::abs(m_swipeDelta.y) ? HORIZONTAL : VERTICAL;
                if (m_swipeFingers != (m_swipeAxis == HORIZONTAL ? m_columnFingers : m_workspaceFingers)) {
                    resetSwipe();
                    return;
                }
                if (const auto layout = scrollingLayout(m_swipeWorkspace.lock())) m_swipeStartOffset = layout->normalizedTapeOffset();
            }
            m_swipeUpdated = true;
        });
        // InputManager emits this before the native gesture's end handler. A
        // cancelled input must return to its starting viewport without inertia.
        m_swipeEnd = Event::bus()->m_events.gesture.swipe.end.listen([this](IPointer::SSwipeEndEvent event, Event::SCallbackInfo&) {
            if (event.cancelled && m_swipeAxis == HORIZONTAL) {
                if (const auto layout = scrollingLayout(m_swipeWorkspace.lock()))
                    layout->moveTapeNormalized(layout->normalizedTapeOffset() - m_swipeStartOffset);
            } else if (event.cancelled && m_swipeAxis == VERTICAL && g_pUnifiedWorkspaceSwipe->isGestureInProgress())
                g_pUnifiedWorkspaceSwipe->update(0);
            resetSwipe();
        });
        m_pre = Event::bus()->m_events.render.pre.listen([this](PHLMONITOR monitor) { update(monitor); });
        m_timer = makeShared<CEventLoopTimer>(std::nullopt, [this](SP<CEventLoopTimer>, void*) { tick(); }, nullptr);
        g_pEventLoopManager->addTimer(m_timer);
    }
    ~Cameras() { enable(false); if (g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_timer); }

    void enable(bool value) {
        if (value == m_enabled) return;
        settle();
        m_enabled = value;
        m_outputs.clear(); m_columns.clear();
        if (value) for (const auto& monitor : State::monitorState()->monitors()) forOutput(monitor);
    }
    void pause(bool value) {
        settle();
        // Overview can focus another column while the desktop camera is
        // suspended. Its settled viewport becomes the new baseline at handoff,
        // rather than starting another slide from the pre-overview positions.
        m_columns.clear();
        m_paused = value;
    }
    void gestureFingers(int columns, int workspaces) { m_columnFingers = columns; m_workspaceFingers = workspaces; }
    bool navigationFingers(size_t fingers) const { return fingers == m_columnFingers || fingers == m_workspaceFingers; }
    void settle() {
        resetSwipe();
        for (auto& output : m_outputs) {
            const auto monitor = output.monitor.lock();
            if (!monitor) continue;
            if (monitor->m_activeWorkspace) output.from = output.to = monitor->m_activeWorkspace->numberedID().value_or(0);
            for (const auto& weak : State::workspaceState()->workspaces()) {
                const auto workspace = weak.lock();
                if (!workspace || workspace->m_monitor != monitor || (workspace->type() == Workspace::eWorkspaceType::SPECIAL)) continue;
                workspace->m_forceRendering = false;
                workspace->m_renderOffset->setValueAndWarp({});
                workspace->m_alpha->setValueAndWarp(workspace == monitor->m_activeWorkspace ? 1.F : 0.F);
            }
            g_pHyprRenderer->damageMonitor(monitor);
        }
        for (auto& column : m_columns) {
            if (column.from.size() > .001) for (const auto& member : column.members)
                if (const auto window = member.window.lock(); window && window->mapped()) window->positionAnimation()->warp();
            column.from = {};
        }
        if (m_timer) m_timer->updateTimeout(std::nullopt);
    }
    Json status() const {
        Json result = {{"enabled", m_enabled}, {"paused", m_paused}, {"outputs", Json::array()}, {"columns", Json::array()}};
        for (const auto& output : m_outputs) if (const auto monitor = output.monitor.lock()) {
            Json entry = {{"monitor", monitor->m_name}, {"row", output.row()}, {"goal", output.to},
                {"stride", monitor->m_size.y}, {"workspaces", Json::array()}};
            for (const auto& weak : State::workspaceState()->workspaces()) if (const auto ws = weak.lock(); ws && ws->m_monitor == monitor && !(ws->type() == Workspace::eWorkspaceType::SPECIAL))
                entry["workspaces"].push_back({{"id", ws->numberedID().value_or(0)}, {"y", ws->m_renderOffset->value().y},
                    {"alpha", ws->m_alpha->value()}, {"rendered", ws->m_forceRendering}});
            result["outputs"].push_back(entry);
        }
        for (const auto& column : m_columns) if (const auto workspace = column.workspace.lock()) {
            const auto offset = column.offset();
            Json entry = {{"workspace", workspace->numberedID().value_or(0)}, {"offset", std::abs(offset.x) >= std::abs(offset.y) ? offset.x : offset.y},
                {"offsetX", offset.x}, {"offsetY", offset.y}, {"windows", Json::array()}};
            for (const auto& member : column.members) if (const auto w = member.window.lock(); w && w->mapped()) {
                const auto position = w->positionAnimation()->value(), goal = w->positionAnimation()->goal();
                entry["windows"].push_back({{"address", std::format("0x{:x}", reinterpret_cast<uintptr_t>(w.get()))},
                    {"x", position.x}, {"y", position.y}, {"goalX", goal.x}, {"goalY", goal.y}});
            }
            result["columns"].push_back(entry);
        }
        return result;
    }

  private:
    enum SwipeAxis { NONE, HORIZONTAL, VERTICAL };
    void resetSwipe() {
        m_swipeMonitor.reset(); m_swipeWorkspace.reset();
        m_swipeAxis = NONE; m_swipeDelta = {}; m_swipeUpdated = false;
    }
    Output& forOutput(PHLMONITOR monitor) {
        auto found = std::ranges::find_if(m_outputs, [&](const auto& output) { return output.monitor == monitor; });
        if (found != m_outputs.end()) return *found;
        const double row = monitor->m_activeWorkspace ? monitor->m_activeWorkspace->numberedID().value_or(0) : 1;
        m_outputs.push_back({monitor, row, row, Clock::now()});
        return m_outputs.back();
    }
    void update(PHLMONITOR monitor) {
        if (!m_enabled || m_paused || !monitor || !monitor->m_activeWorkspace || monitor->m_activeWorkspace->numberedID().value_or(0) <= 0) return;
        auto& output = forOutput(monitor);
        const bool swiping = m_swipeAxis == VERTICAL && m_swipeMonitor == monitor && g_pUnifiedWorkspaceSwipe->isGestureInProgress();
        if (swiping && m_swipeUpdated) {
            static auto gap = CConfigValue<Config::INTEGER>("general:gaps_workspaces");
            // Disabled native animations report an empty style and swipe on X.
            // Map either native axis to our vertical camera, once per input
            // update. Reading our own offset on idle frames would shrink it.
            const auto style = monitor->m_activeWorkspace->m_renderOffset->getStyle();
            const bool vertical = style == "slidevert" || style.starts_with("slidefadevert");
            const auto offset = monitor->m_activeWorkspace->m_renderOffset->value();
            output.from = output.to = monitor->m_activeWorkspace->numberedID().value_or(0) -
                (vertical ? offset.y : offset.x) / ((vertical ? monitor->m_size.y : monitor->m_size.x) + *gap);
            output.start = Clock::now();
            m_swipeUpdated = false;
        }
        // Internal workspace changes do not emit workspace.active.
        if (!swiping && output.to != monitor->m_activeWorkspace->numberedID().value_or(0)) {
            output.from = output.row(); output.to = monitor->m_activeWorkspace->numberedID().value_or(0); output.start = Clock::now();
        }
        const double row = output.row();
        const double stride = monitor->m_size.y;
        const bool moving = swiping || std::abs(row-output.to) > .00001;
        for (const auto& weak : State::workspaceState()->workspaces()) {
            const auto workspace = weak.lock();
            if (!workspace || workspace->m_monitor != monitor || (workspace->type() == Workspace::eWorkspaceType::SPECIAL) || workspace->numberedID().value_or(0) <= 0) continue;
            const double y = (workspace->numberedID().value_or(0)-row)*stride;
            const bool intersects = moving && std::abs(y) < stride;
            const Vector2D offset{0.0, moving ? y : 0.0};
            const float alpha = intersects || (!moving && workspace == monitor->m_activeWorkspace) ? 1.F : 0.F;
            // Rendering may continue after the workspace animation finishes.
            // Do not run animation-end/update callbacks on unchanged values.
            if (workspace->m_renderOffset->value() != offset || workspace->m_renderOffset->goal() != offset)
                workspace->m_renderOffset->setValueAndWarp(offset);
            if (workspace->m_alpha->value() != alpha || workspace->m_alpha->goal() != alpha)
                workspace->m_alpha->setValueAndWarp(alpha);
            workspace->m_forceRendering = intersects;
            updateColumns(workspace);
        }
        const bool columnsMoving = std::ranges::any_of(m_columns, [&](const auto& column) {
            return column.workspace && column.workspace->m_monitor == monitor && column.offset().size() > .001;
        });
        // render.pre precedes Monitor::m_renderingActive, so damage alone is
        // consumed by this frame without requesting the next one. Continue at
        // the output's presentation cadence, including the first idle wake-up.
        // The fallback timer is only needed to wake an output without a frame.
        if ((!swiping && moving) || columnsMoving)
            monitor->m_pendingFrame = true;
        tick();
    }
    void updateColumns(PHLWORKSPACE workspace) {
        auto found = std::ranges::find_if(m_columns, [&](const auto& column) { return column.workspace == workspace; });
        if (found == m_columns.end()) {
            m_columns.push_back({workspace, {}, {}, Clock::now()});
            found = std::prev(m_columns.end());
        }
        auto& column = *found;
        const bool dragging = m_swipeAxis == HORIZONTAL && m_swipeWorkspace == workspace;
        std::vector<Member> next;
        std::optional<Vector2D> shift;
        bool rigid = true;
        size_t matched = 0;
        for (const auto& window : Desktop::windowState()->windows()) {
            if (!window->mapped() || window->isFloating() || (window->m_state & Desktop::View::WINDOW_STATE_PINNED) || window->m_workspace != workspace) continue;
            Member member{window, window->positionAnimation()->goal(), window->sizeAnimation()->goal()};
            const auto old = std::ranges::find_if(column.members, [&](const auto& old) { return old.window == window; });
            if (old != column.members.end()) {
                ++matched;
                const auto delta = member.goal-old->goal;
                if ((member.size-old->size).size() > .5 || (shift && (delta-*shift).size() > .5)) rigid = false;
                if (!shift) shift = delta;
            }
            next.push_back(member);
        }
        if (dragging) {
            // scroll_move already changes the tape for every input event. Do
            // not put another easing animation between the fingers and windows.
            column.from = {};
            for (const auto& member : next) if (const auto window = member.window.lock()) window->positionAnimation()->warp();
        } else if (rigid && matched && shift && shift->size() > .5) {
            column.from = column.offset()-*shift;
            column.start = Clock::now();
        } else if (!rigid) column.from = {};
        column.members = std::move(next);
        if (column.from.size() < .001) return;
        const auto offset = column.offset();
        for (const auto& member : column.members) if (const auto window = member.window.lock()) {
            if (phase(column.start) >= 1) window->positionAnimation()->warp();
            else window->positionAnimation()->setValue(member.goal+offset);
        }
        if (phase(column.start) >= 1) column.from = {};
    }
    void tick() {
        if (!m_enabled || m_paused || !m_timer) return;
        bool moving = false;
        int interval = 16;
        std::erase_if(m_outputs, [](const auto& output) { return output.monitor.expired(); });
        std::erase_if(m_columns, [](const auto& column) { return column.workspace.expired(); });
        for (const auto& output : m_outputs) if (const auto monitor = output.monitor.lock()) {
            const bool columnsMoving = std::ranges::any_of(m_columns, [&](const auto& column) {
                return column.workspace && column.workspace->m_monitor == monitor && column.offset().size() > .001; });
            if (std::abs(output.row()-output.to) > .00001 || columnsMoving) {
                moving = true;
                interval = std::min(interval, std::max(1, static_cast<int>(1000/monitor->m_refreshRate)));
                g_pHyprRenderer->damageMonitor(monitor);
            }
        }
        m_timer->updateTimeout(moving ? std::optional{std::chrono::milliseconds(interval)} : std::nullopt);
    }

    bool m_enabled = false, m_paused = false;
    int m_columnFingers = 3, m_workspaceFingers = 3, m_swipeFingers = 0;
    SwipeAxis m_swipeAxis = NONE;
    Vector2D m_swipeDelta;
    PHLMONITORREF m_swipeMonitor;
    PHLWORKSPACEREF m_swipeWorkspace;
    bool m_swipeUpdated = false;
    double m_swipeStartOffset = 0;
    std::vector<Output> m_outputs;
    std::vector<Column> m_columns;
    CHyprSignalListener m_active, m_pre, m_swipeBegin, m_swipeUpdate, m_swipeEnd;
    SP<CEventLoopTimer> m_timer;
};

static UP<Cameras> cameras;
static int luaCamera(lua_State* L) {
    if (!cameras) return luaL_error(L, "Workspace camera is not loaded");
    const std::string action = luaL_checkstring(L,1);
    if (action == "enable") cameras->enable(lua_toboolean(L,2));
    else if (action == "gestures") cameras->gestureFingers(luaL_checkinteger(L,2),luaL_checkinteger(L,3));
    else if (action == "pause") cameras->pause(lua_toboolean(L,2));
    else if (action == "settle") cameras->settle();
    else if (action == "status") { lua_pushstring(L,cameras->status().dump().c_str()); return 1; }
    else return luaL_error(L, "Unknown workspace camera action");
    lua_pushboolean(L,true); return 1;
}
static void install(HANDLE handle) {
    cameras = makeUnique<Cameras>();
    HyprlandAPI::addLuaFunction(handle,"hyprbars","workspace_camera",luaCamera);
}
static void remove() { cameras.reset(); }
} // namespace HyprstackCamera
