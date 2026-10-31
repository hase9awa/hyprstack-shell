// Middle-click autoscroll for ordinary client surfaces. No timer runs at rest.
#pragma once

#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <nlohmann/json.hpp>
#include <cmath>
#include <set>
#include "autoscroll-motion.hpp"

namespace HyprstackAutoscroll {
class Controller {
  public:
    Controller() {
        m_button = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent e, Event::SCallbackInfo& info) {
            if (e.state == WL_POINTER_BUTTON_STATE_RELEASED && m_buttons.erase(e.button)) {
                info.cancelled = true;
                if (e.button == 274 && m_pending) {
                    // Buffer a short click until release, then deliver the
                    // complete pair. Tabs, links and middle-paste keep working.
                    if (valid()) {
                        const auto now = static_cast<uint32_t>(Time::millis(Time::steadyNow()));
                        g_pSeatManager->sendPointerButton(now - 1, e.button, WL_POINTER_BUTTON_STATE_PRESSED);
                        g_pSeatManager->sendPointerButton(now, e.button, WL_POINTER_BUTTON_STATE_RELEASED);
                        g_pSeatManager->sendPointerFrame();
                    }
                    stop();
                } else if (e.button == 274 && m_dragged) stop();
                m_held = false;
                return;
            }
            if (info.cancelled || e.state != WL_POINTER_BUTTON_STATE_PRESSED) return;
            if (m_active) {
                stop();
                m_buttons.insert(e.button);
                info.cancelled = true;
            } else if (e.button == 274 && prepare()) {
                m_buttons.insert(e.button);
                m_held = true;
                info.cancelled = true;
            } else if (m_pending) stop();
        });
        m_move = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D point, Event::SCallbackInfo& info) {
            if (!m_active && !m_pending) return;
            if (!valid()) { stop(); return; }
            m_delta = point - m_origin;
            if (m_pending) {
                if (m_delta.size() <= DEAD_ZONE) return;
                activate();
            }
            info.cancelled = true;
            if (m_held && m_delta.size() > DEAD_ZONE) m_dragged = true;
            updateTimer();
        });
        m_key = Event::bus()->m_events.input.keyboard.key.listen([this](IKeyboard::SKeyEvent e, Event::SCallbackInfo& info) {
            if (e.state == WL_KEYBOARD_KEY_STATE_RELEASED && m_keys.erase(e.keycode)) {
                info.cancelled = true;
                return;
            }
            if ((!m_active && !m_pending) || e.state != WL_KEYBOARD_KEY_STATE_PRESSED) return;
            const bool wasActive = m_active;
            stop();
            if (wasActive && e.keycode == 1) { m_keys.insert(e.keycode); info.cancelled = true; }
        });
        m_axis = Event::bus()->m_events.input.mouse.axis.listen([this](IPointer::SAxisEvent, Event::SCallbackInfo&) { stop(); });
        m_focus = g_pSeatManager->m_events.pointerFocusChange.listen([this] {
            if ((m_active || m_pending) && g_pSeatManager->m_state.pointerFocus != m_surface) stop();
        });
        m_keyboardFocus = g_pSeatManager->m_events.keyboardFocusChange.listen([this] {
            if ((m_active || m_pending) && Desktop::focusState()->window() != m_window) stop();
        });
        m_close = Event::bus()->m_events.window.close.listen([this](PHLWINDOW window) { if (window == m_window) stop(); });
        m_reload = Event::bus()->m_events.config.preReload.listen([this] { stop(); });
        m_lock = g_pSessionLockManager->m_events.lock.listen([this] { stop(); });
        m_timer = makeShared<CEventLoopTimer>(std::nullopt, [this](SP<CEventLoopTimer>, void*) { tick(); }, nullptr);
        g_pEventLoopManager->addTimer(m_timer);
    }
    ~Controller() {
        stop();
        if (g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_timer);
    }
    void enable(bool enabled) { m_enabled = enabled; if (!enabled) stop(); }
    void stop() {
        if (!m_active && !m_pending) return;
        const bool hadCursorOverride = m_active;
        if (m_active && g_pSeatManager->m_state.pointerFocus == m_surface) {
            const auto now = static_cast<uint32_t>(Time::millis(Time::steadyNow()));
            axis(now, WL_POINTER_AXIS_VERTICAL_SCROLL, 0);
            axis(now, WL_POINTER_AXIS_HORIZONTAL_SCROLL, 0);
            g_pSeatManager->sendPointerFrame();
        }
        m_active = m_pending = m_held = m_dragged = false;
        m_delta = {}; m_velocity = {}; m_remainder = {};
        m_window.reset(); m_surface.reset();
        m_timer->updateTimeout(std::nullopt);
        if (hadCursorOverride)
            Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
        g_pInputManager->simulateMouseMovement();
    }
    nlohmann::json status() const {
        return {{"enabled",m_enabled},{"active",m_active},{"pending",m_pending},{"timerArmed",m_timer->armed()},
            {"velocityX",m_velocity.x},{"velocityY",m_velocity.y},
            {"targetVelocityX",velocity(m_delta.x)},{"targetVelocityY",velocity(m_delta.y)},
            {"intervalMs",intervalSeconds()*1000.0},{"frames",m_frames}};
    }

  private:
    double intervalSeconds() const {
        const auto window = m_window.lock();
        const auto monitor = window ? window->m_monitor.lock() : nullptr;
        const double hz = monitor ? monitor->m_refreshRate : 60.0;
        return intervalFor(hz);
    }
    void armFrame() {
        m_timer->updateTimeout(std::chrono::duration_cast<Time::steady_dur>(std::chrono::duration<double>(intervalSeconds())));
    }
    static void axis(uint32_t now, wl_pointer_axis direction, double value) {
        g_pSeatManager->sendPointerAxis(now,direction,value,0,0,WL_POINTER_AXIS_SOURCE_CONTINUOUS,
            WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
    }
    bool valid() const {
        const auto window = m_window.lock();
        return (m_active || m_pending) && window && window->mapped() && !window->isHidden() && !m_surface.expired() &&
            !g_pSessionLockManager->isSessionLocked() && !g_pInputManager->isConstrained() &&
            g_pSeatManager->m_state.pointerFocus == m_surface && Desktop::focusState()->window() == window;
    }
    bool prepare() {
        if (!m_enabled || g_pSessionLockManager->isSessionLocked() || g_pInputManager->isConstrained() ||
            g_layoutManager->dragController()->target()) return false;
        const auto keyboard = g_pSeatManager->m_keyboard.lock();
        if (keyboard && (keyboard->getModifiers() & (Input::HL_MODIFIER_SHIFT|Input::HL_MODIFIER_CTRL|Input::HL_MODIFIER_ALT|Input::HL_MODIFIER_META))) return false;
        const auto surface = g_pSeatManager->m_state.pointerFocus.lock();
        const auto owner = surface ? Desktop::View::CWLSurface::fromResource(surface) : nullptr;
        const auto window = owner ? dynamicPointerCast<Desktop::View::CWindow>(owner->view()) : nullptr;
        // Menus, panel widgets, the desktop and lock surfaces keep their input.
        if (!window || !window->mapped() || window->isHidden()) return false;
        const auto point = g_pInputManager->getMouseCoordsInternal();
        if (!CBox{window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT),
            window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)}.containsPoint(point)) return false;
        Desktop::focusState()->fullWindowFocus(window,Desktop::FOCUS_REASON_CLICK,surface);
        m_window = window; m_surface = surface; m_origin = point; m_delta = {};
        m_pending = true; m_dragged = false;
        m_timer->updateTimeout(std::chrono::milliseconds(180));
        return true;
    }
    void activate() {
        m_pending = false; m_active = true;
        m_velocity = {}; m_remainder = {}; m_frames = 0;
        m_previousTick = Time::steadyNow();
        m_timer->updateTimeout(std::nullopt);
        Pointer::Cursor::overrideController->setOverride("all-scroll",Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
    }
    void updateTimer() {
        if (velocity(m_delta.x) == 0 && velocity(m_delta.y) == 0) {
            if (m_velocity != Vector2D{}) {
                const auto now = static_cast<uint32_t>(Time::millis(Time::steadyNow()));
                axis(now,WL_POINTER_AXIS_VERTICAL_SCROLL,0);
                axis(now,WL_POINTER_AXIS_HORIZONTAL_SCROLL,0);
                g_pSeatManager->sendPointerFrame();
            }
            m_velocity = {}; m_remainder = {};
            m_timer->updateTimeout(std::nullopt);
        } else if (!m_timer->armed()) {
            m_previousTick = Time::steadyNow();
            armFrame();
        }
    }
    void tick() {
        if (!valid()) { stop(); return; }
        if (m_pending) { activate(); updateTimer(); return; }
        // Cancelling client motion leaves Hyprland's last delivered position
        // unchanged. Returning exactly there can skip the motion callback.
        m_delta = g_pInputManager->getMouseCoordsInternal() - m_origin;
        const auto now = Time::steadyNow();
        const auto elapsed = std::clamp(std::chrono::duration<double>(now-m_previousTick).count(),0.0,0.05);
        m_previousTick = now;
        const double targetX = velocity(m_delta.x), targetY = velocity(m_delta.y);
        const bool stopX = targetX == 0 && m_velocity.x != 0;
        const bool stopY = targetY == 0 && m_velocity.y != 0;
        const double x = advance(targetX,elapsed,m_velocity.x,m_remainder.x);
        const double y = advance(targetY,elapsed,m_velocity.y,m_remainder.y);
        const auto ms = static_cast<uint32_t>(Time::millis(now));
        if (x != 0) axis(ms,WL_POINTER_AXIS_HORIZONTAL_SCROLL,x);
        if (y != 0) axis(ms,WL_POINTER_AXIS_VERTICAL_SCROLL,y);
        if (stopX) axis(ms,WL_POINTER_AXIS_HORIZONTAL_SCROLL,0);
        if (stopY) axis(ms,WL_POINTER_AXIS_VERTICAL_SCROLL,0);
        if (x != 0 || y != 0 || stopX || stopY) { g_pSeatManager->sendPointerFrame(); ++m_frames; }
        if (targetX != 0 || targetY != 0) armFrame();
        else updateTimer();
    }
    bool m_enabled = true, m_active = false, m_pending = false, m_held = false, m_dragged = false;
    PHLWINDOWREF m_window;
    WP<CWLSurfaceResource> m_surface;
    Vector2D m_origin, m_delta, m_velocity, m_remainder;
    uint64_t m_frames = 0;
    Time::steady_tp m_previousTick;
    std::set<uint32_t> m_buttons, m_keys;
    CHyprSignalListener m_button,m_move,m_key,m_axis,m_focus,m_keyboardFocus,m_close,m_reload,m_lock;
    SP<CEventLoopTimer> m_timer;
};
static UP<Controller> controller;
static int luaScroll(lua_State* L) {
    const std::string action = luaL_checkstring(L,1);
    if (action == "enable") controller->enable(lua_toboolean(L,2));
    else if (action == "stop") controller->stop();
    else if (action == "status") {
        const auto value = controller->status().dump();
        lua_pushlstring(L,value.data(),value.size()); return 1;
    } else return luaL_error(L,"Unknown autoscroll action");
    lua_pushboolean(L,true); return 1;
}
static void install(HANDLE handle) {
    controller = makeUnique<Controller>();
    HyprlandAPI::addLuaFunction(handle,"hyprbars","autoscroll",luaScroll);
}
static void remove() { controller.reset(); }
}
