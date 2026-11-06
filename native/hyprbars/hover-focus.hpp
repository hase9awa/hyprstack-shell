// Focus follows the pointer, but only once the pointer has settled on a
// window. Crossing a monitor on the way somewhere, or passing over what
// happens to lie between, leaves the focus — and the scrolling camera that
// follows it — where they were.
#pragma once

#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>

namespace HyprstackHoverFocus {
// How long the pointer has to stay on a window before the focus follows it.
// The setting carries the number; this is what it starts at, long enough
// that a pointer on its way through a window never carries the focus off
// with it. The compositor itself only knows distance, not dwelling.
constexpr int DEFAULT_DWELL = 200;
constexpr int MAX_DWELL = 1000;

class Controller {
  public:
    Controller() {
        m_move = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D point, Event::SCallbackInfo& info) {
            if (info.cancelled) { disarm(); return; }
            update(point);
        });
        // A click focuses on its own, and a key says the user is busy with
        // the window they already have: both end the wait.
        m_button = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent, Event::SCallbackInfo&) { disarm(); });
        m_key = Event::bus()->m_events.input.keyboard.key.listen([this](IKeyboard::SKeyEvent, Event::SCallbackInfo&) { disarm(); });
        m_close = Event::bus()->m_events.window.close.listen([this](PHLWINDOW window) { if (window == m_candidate) disarm(); });
        m_reload = Event::bus()->m_events.config.preReload.listen([this] { disarm(); });
        m_lock = g_pSessionLockManager->m_events.lock.listen([this] { disarm(); });
        m_timer = makeShared<CEventLoopTimer>(std::nullopt, [this](SP<CEventLoopTimer>, void*) { fire(); }, nullptr);
        g_pEventLoopManager->addTimer(m_timer);
    }
    ~Controller() {
        disarm();
        if (g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_timer);
    }
    Controller(const Controller&) = delete;
    Controller& operator=(const Controller&) = delete;

    void enable(bool enabled) {
        if (m_enabled == enabled) return;
        m_enabled = enabled;
        if (!enabled) disarm();
    }

    void setDwell(int milliseconds) {
        m_dwell = std::chrono::milliseconds(std::clamp(milliseconds, 0, MAX_DWELL));
    }

    nlohmann::json status() const {
        const auto window = m_candidate.lock();
        return {{"enabled", m_enabled}, {"waiting", bool(window)}, {"timerArmed", m_timer->armed()},
            {"dwellMs", m_dwell.count()},
            {"candidate", window ? std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())) : ""}};
    }

  private:
    // Everything that means the pointer is not simply resting on a window:
    // a held button is a drag, a constrained pointer belongs to the client,
    // and a locked session has no windows to speak of.
    bool eligible() const {
        return m_enabled && !g_pSessionLockManager->isSessionLocked() && !g_pInputManager->isConstrained() &&
            g_pInputManager->m_currentlyHeldButtons.empty() && !g_layoutManager->dragController()->target();
    }
    PHLWINDOW windowAt(Vector2D point) const {
        if (!eligible()) return nullptr;
        const auto window = Desktop::viewState()->hitTest().windowAt(point,
            Desktop::View::ALLOW_FLOATING | Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
        if (!window || !window->mapped() || window->isHidden()) return nullptr;
        return window;
    }
    void update(Vector2D point) {
        const auto window = windowAt(point);
        if (!window || window == Desktop::focusState()->window()) { disarm(); return; }
        // Moving about inside the same window goes on counting towards the
        // same wait; a different one starts it over.
        if (window == m_candidate) return;
        m_candidate = window;
        m_timer->updateTimeout(m_dwell);
    }
    void fire() {
        const auto window = m_candidate.lock();
        disarm();
        if (!window || window == Desktop::focusState()->window()) return;
        // The pointer has had the whole wait to leave: hand the focus over
        // only to what is still underneath it.
        if (windowAt(g_pInputManager->getMouseCoordsInternal()) != window) return;
        Desktop::focusState()->fullWindowFocus(window, Desktop::FOCUS_REASON_FFM);
    }
    void disarm() {
        if (!m_candidate && !m_timer->armed()) return;
        m_candidate.reset();
        m_timer->updateTimeout(std::nullopt);
    }

    bool m_enabled = false;
    std::chrono::milliseconds m_dwell { DEFAULT_DWELL };
    PHLWINDOWREF m_candidate;
    SP<CEventLoopTimer> m_timer;
    CHyprSignalListener m_move, m_button, m_key, m_close, m_reload, m_lock;
};

static UP<Controller> controller;
static int luaHoverFocus(lua_State* L) {
    if (lua_isstring(L, 1) && std::string(luaL_checkstring(L, 1)) == "status") {
        const auto value = controller->status().dump();
        lua_pushlstring(L, value.data(), value.size());
        return 1;
    }
    controller->enable(lua_toboolean(L, 1));
    if (lua_isnumber(L, 2))
        controller->setDwell(static_cast<int>(lua_tointeger(L, 2)));
    lua_pushboolean(L, true);
    return 1;
}
static void install(HANDLE handle) {
    controller = makeUnique<Controller>();
    HyprlandAPI::addLuaFunction(handle, "hyprbars", "hover_focus", luaHoverFocus);
}
static void remove() { controller.reset(); }
} // namespace HyprstackHoverFocus
