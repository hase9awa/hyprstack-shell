// Native target selection and click handling; the shell draws the hint as
// part of its shared frame, with the same shape and animation as its drawers.
#pragma once
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <array>
#include <map>

namespace HyprstackTilingHover {
using Json = nlohmann::json;
enum Side { LEFT, RIGHT, TOP, BOTTOM };
struct ShellGeometry {
    CBox area;
    double depth = 34, length = 52, padding = 12;
    std::vector<CBox> blocked;
};

class Controller {
  public:
    Controller() {
        m_move = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D point, Event::SCallbackInfo& info) {
            if (info.cancelled) { clear(true); return; }
            update(point);
            if (m_hovered) info.cancelled = true;
        });
        m_button = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent event, Event::SCallbackInfo& info) {
            if (event.button == 272 && event.state == WL_POINTER_BUTTON_STATE_RELEASED && m_pressed) {
                const auto window = m_pressedWindow.lock();
                const bool activate = !info.cancelled && window == m_window && valid(window, m_monitor.lock()) &&
                    !blocked(m_monitor.lock(), m_box) && m_box.containsPoint(g_pInputManager->getMouseCoordsInternal());
                m_pressed = false; m_pressedWindow.reset();
                info.cancelled = true;
                clear();
                if (activate) Desktop::focusState()->fullWindowFocus(window, Desktop::FOCUS_REASON_DISPATCH_FOCUSWINDOW);
                return;
            }
            if (info.cancelled) { clear(true); return; }
            if (event.state != WL_POINTER_BUTTON_STATE_PRESSED) return;
            update(g_pInputManager->getMouseCoordsInternal());
            if (event.button == 272 && m_hovered) {
                m_pressed = true; m_pressedWindow = m_window; info.cancelled = true;
            } else clear();
        });
        m_render = Event::bus()->m_events.render.stage.listen([this](Event::SRenderStageEvent event) {
            const auto stage = event.stage;
            if (stage != RENDER_POST_WINDOWS || !m_window) return;
            const auto monitor = m_monitor.lock();
            if (!valid(m_window.lock(), monitor) || blocked(monitor,m_box) || overPanel(monitor,m_box.middle())) clear(true);
        });
        m_key = Event::bus()->m_events.input.keyboard.key.listen([this](IKeyboard::SKeyEvent event, Event::SCallbackInfo&) {
            if (event.state == WL_KEYBOARD_KEY_STATE_PRESSED) clear();
        });
        m_focus = Event::bus()->m_events.window.active.listen([this](PHLWINDOW, Desktop::eFocusReason) { clear(); });
        m_close = Event::bus()->m_events.window.close.listen([this](PHLWINDOW window) { if (window == m_window) clear(); });
        m_floating = Event::bus()->m_events.window.floating.listen([this](PHLWINDOW window) { if (window == m_window) clear(); });
        m_workspace = Event::bus()->m_events.workspace.active.listen([this](PHLWORKSPACE) { clear(); });
        m_reload = Event::bus()->m_events.config.preReload.listen([this] { clear(true); m_shells.clear(); });
        m_lock = g_pSessionLockManager->m_events.lock.listen([this] { clear(true); });
    }
    ~Controller() { clear(true); }
    void focusOnHover(bool enabled) {
        m_focusOnHover = enabled;
        if (enabled) clear(true);
    }
    void configure(const std::string& monitor, const Json& value) {
        ShellGeometry geometry;
        const auto area = value.at("area");
        geometry.area = {area.at("x"),area.at("y"),area.at("width"),area.at("height")};
        geometry.depth = std::clamp(value.value("depth",34.0),16.0,100.0);
        geometry.length = std::clamp(value.value("length",52.0),24.0,160.0);
        geometry.padding = std::clamp(value.value("padding",12.0),0.0,80.0);
        for (const auto& region : value.at("blocked"))
            geometry.blocked.emplace_back(region.at("x"),region.at("y"),region.at("width"),region.at("height"));
        m_shells[monitor] = std::move(geometry);
        if (m_monitor && m_monitor->m_name == monitor && blocked(m_monitor.lock(),m_box)) clear(true);
        else publish();
    }
    Json status() const {
        const auto window = m_window.lock();
        return {{"focusOnHover",m_focusOnHover},{"visible",bool(window)},{"hovered",m_hovered},{"instant",m_instant},
            {"address",window ? std::format("0x{:x}",reinterpret_cast<uintptr_t>(window.get())) : ""},
            {"monitor",m_monitor ? m_monitor->m_name : ""},{"side",std::array{"left","right","top","bottom"}[m_side]},
            {"box",{{"x",m_box.x},{"y",m_box.y},{"width",m_box.w},{"height",m_box.h}}},
            {"renderer","shell"},{"timerArmed",false},{"configuredMonitors",m_shells.size()}};
    }

  private:
    void publish() const { if (IPC::Socket2::sock()) IPC::Socket2::sock()->postEvent({"hyprstack_tiling_hover",status().dump()}); }
    bool available(PHLMONITOR monitor) const {
        if (m_focusOnHover || !monitor || !m_shells.contains(monitor->m_name) ||
            g_pSessionLockManager->isSessionLocked() || g_pInputManager->isConstrained() ||
            g_layoutManager->dragController()->target() || !g_pInputManager->m_currentlyHeldButtons.empty() ||
            monitor->m_activeSpecialWorkspace || (HyprstackOverview::scene && HyprstackOverview::scene->runningFor(monitor))) return false;
        const auto keyboard = g_pSeatManager->m_keyboard.lock();
        if (keyboard && (keyboard->getModifiers() & (Input::HL_MODIFIER_SHIFT|Input::HL_MODIFIER_CTRL|Input::HL_MODIFIER_ALT|Input::HL_MODIFIER_META))) return false;
        return monitor->m_activeWorkspace && !Fullscreen::controller()->hasFullscreen(monitor->m_activeWorkspace);
    }
    static SP<Layout::Tiled::SScrollingTargetData> dataFor(PHLWINDOW window) {
        if (!window || !window->mapped() || window->isHidden() || window->isFloating() || !window->m_workspace ||
            !window->m_workspace->space() || !window->layoutTarget()) return nullptr;
        const auto algorithm = window->m_workspace->space()->algorithm();
        const auto scrolling = algorithm ? dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get()) : nullptr;
        return scrolling ? scrolling->dataFor(window->layoutTarget(),true) : nullptr;
    }
    bool valid(PHLWINDOW window, PHLMONITOR monitor) const {
        if (!available(monitor) || !window || window == Desktop::focusState()->window() ||
            window->m_monitor != monitor || window->m_workspace != monitor->m_activeWorkspace) return false;
        const auto data = dataFor(window);
        const auto column = data ? data->column.lock() : nullptr;
        const auto tape = column ? column->scrollingData.lock() : nullptr;
        return tape && !tape->visible(column,true);
    }
    static Side sideFor(PHLWINDOW window) {
        const auto data = dataFor(window);
        const auto tape = data->column->scrollingData.lock();
        const auto area = window->m_workspace->space()->workArea();
        const auto box = window->layoutBox();
        if (tape->controller->isPrimaryHorizontal()) return box.middle().x < area.middle().x ? LEFT : RIGHT;
        return box.middle().y < area.middle().y ? TOP : BOTTOM;
    }
    bool blocked(PHLMONITOR monitor, const CBox& box) const {
        if (!monitor || !m_shells.contains(monitor->m_name)) return true;
        for (const auto& obstacle : m_shells.at(monitor->m_name).blocked)
            if (box.overlaps(obstacle)) return true;
        return false;
    }
    static bool overPanel(PHLMONITOR monitor, Vector2D point) {
        if (!monitor) return true;
        Vector2D local; PHLLS layer;
        for (size_t index : {2U,3U}) {
            if (!Desktop::viewState()->hitTest().layerSurfaceAt(point,&monitor->m_layerSurfaceLayers[index],&local,&layer)) continue;
            // Geometry from this same shell includes both visible panels and
            // closed edge triggers. It also owns the hint's frame surface.
            if (layer && layer->m_namespace == "hyprstack-drawers") continue;
            return true;
        }
        return false;
    }
    std::optional<CBox> place(PHLMONITOR monitor, Side side, Vector2D point, PHLWINDOW target) const {
        const auto& shell = m_shells.at(monitor->m_name);
        const bool horizontal = side == LEFT || side == RIGHT;
        const auto area = shell.area;
        const auto row = target->layoutBox();
        const double start = std::max(horizontal ? area.y : area.x,horizontal ? row.y : row.x) + shell.padding;
        const double end = std::min(horizontal ? area.y+area.h : area.x+area.w,horizontal ? row.y+row.h : row.x+row.w) - shell.padding - shell.length;
        if (end < start) return std::nullopt;
        const double desired = std::clamp((horizontal ? point.y : point.x)-shell.length/2,start,end);
        std::vector<double> positions{desired};
        for (const auto& obstacle : shell.blocked) {
            positions.push_back(std::clamp((horizontal ? obstacle.y : obstacle.x)-shell.length-shell.padding,start,end));
            positions.push_back(std::clamp((horizontal ? obstacle.y+obstacle.h : obstacle.x+obstacle.w)+shell.padding,start,end));
        }
        std::optional<CBox> result;
        double nearest = INFINITY;
        for (const auto position : positions) {
            CBox box = horizontal ? CBox{side == LEFT ? area.x : area.x+area.w-shell.depth,position,shell.depth,shell.length} :
                CBox{position,side == TOP ? area.y : area.y+area.h-shell.depth,shell.length,shell.depth};
            if (blocked(monitor,box.copy().expand(shell.padding)) || overPanel(monitor,box.middle())) continue;
            if (const double distance = std::abs(position-desired); distance < nearest) { nearest = distance; result = box; }
        }
        return result;
    }
    void update(Vector2D point) {
        PHLMONITOR monitor;
        for (const auto& candidate : State::monitorState()->monitors())
            if (candidate->logicalBox().containsPoint(point)) { monitor = candidate; break; }
        if (!available(monitor) || blocked(monitor,{point,Vector2D{1,1}}) || overPanel(monitor,point)) { clear(true); return; }
        if (monitor == m_monitor && valid(m_window.lock(),monitor) && !blocked(monitor,m_box) &&
            m_box.copy().expand(m_shells.at(monitor->m_name).padding).containsPoint(point)) {
            hover(m_box.containsPoint(point)); return;
        }
        const auto hit = Desktop::viewState()->hitTest().windowAt(point,
            Desktop::View::ALLOW_FLOATING | Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
        if (hit && (hit->isFloating() || hit->hasPopupAt(point))) { clear(); return; }
        PHLWINDOW target = valid(hit,monitor) ? hit : nullptr;
        if (!target) {
            const auto area = monitor->logicalBox();
            double nearest = INFINITY;
            for (const auto& window : Desktop::windowState()->windows()) {
                if (!valid(window,monitor)) continue;
                const auto side = sideFor(window);
                const auto box = window->layoutBox();
                const bool horizontal = side == LEFT || side == RIGHT;
                const bool atEdge = side == LEFT ? point.x < area.x+16 : side == RIGHT ? point.x >= area.x+area.w-16 :
                    side == TOP ? point.y < area.y+16 : point.y >= area.y+area.h-16;
                const bool inRow = horizontal ? point.y >= box.y && point.y < box.y+box.h : point.x >= box.x && point.x < box.x+box.w;
                const double distance = horizontal ? std::abs(box.middle().x-point.x) : std::abs(box.middle().y-point.y);
                if (atEdge && inRow && distance < nearest) { target = window; nearest = distance; }
            }
        }
        if (!target) { clear(); return; }
        if (target != m_window || monitor != m_monitor) {
            const auto side = sideFor(target);
            const auto box = place(monitor,side,point,target);
            if (!box) { clear(); return; }
            clear(true);
            m_window = target; m_monitor = monitor; m_side = side; m_box = *box; m_instant = false;
            publish();
        }
        hover(m_box.containsPoint(point));
    }
    void hover(bool hovered) {
        if (m_hovered == hovered) return;
        m_hovered = hovered;
        if (hovered) Pointer::Cursor::overrideController->setOverride("pointer",Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
        else Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
        publish();
    }
    void clear(bool instant = false) {
        if (!m_window && !m_hovered) return;
        if (m_hovered) Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
        m_hovered = false; m_instant = instant;
        m_window.reset(); m_monitor.reset();
        publish();
    }
    bool m_focusOnHover = false, m_hovered = false, m_pressed = false, m_instant = false;
    Side m_side = LEFT;
    CBox m_box;
    PHLWINDOWREF m_window, m_pressedWindow;
    PHLMONITORREF m_monitor;
    std::map<std::string,ShellGeometry> m_shells;
    CHyprSignalListener m_move,m_button,m_render,m_key,m_focus,m_close,m_floating,m_workspace,m_reload,m_lock;
};
static UP<Controller> controller;
static int luaHover(lua_State* L) {
    const std::string action = luaL_checkstring(L,1);
    if (action == "focus_on_hover") controller->focusOnHover(lua_toboolean(L,2));
    else if (action == "shell") {
        try { controller->configure(luaL_checkstring(L,2),Json::parse(luaL_checkstring(L,3))); }
        catch (const std::exception& e) { return luaL_error(L,"Tiling hint geometry: %s",e.what()); }
    } else if (action == "theme") { /* Colours belong to the shared shell surface. */ }
    else if (action == "status") {
        const auto value = controller->status().dump(); lua_pushlstring(L,value.data(),value.size()); return 1;
    } else return luaL_error(L,"Unknown tiling hover action");
    lua_pushboolean(L,true); return 1;
}
static void install(HANDLE handle) {
    controller = makeUnique<Controller>();
    HyprlandAPI::addLuaFunction(handle,"hyprbars","tiling_hover",luaHover);
}
static void remove() { controller.reset(); }
}
