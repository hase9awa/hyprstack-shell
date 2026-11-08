// Only loaded by test_upgrade.py in its disposable compositor.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <nlohmann/json.hpp>
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

static int damage(lua_State* L) {
    const std::string title = luaL_checkstring(L, 1);
    const auto windows = Desktop::windowState()->windows();
    const auto found = std::ranges::find_if(windows, [&](const auto& w) { return w->metadata().title() == title; });
    if (found == windows.end() || !(*found)->resource()) return luaL_error(L, "Test window is missing");
    const auto window = *found;
    auto& state = window->resource()->m_current;
    if (state.scale != 1 || state.viewport.hasSource || window->positionAnimation()->isBeingAnimated() ||
        window->sizeAnimation()->isBeingAnimated() || window->backend().geometry().box.pos() != Vector2D{})
        return luaL_error(L, "Test window has not settled at scale 1");
    // Restore the test client's damage exactly, including asynchronous buffers
    // for which accumulateBufferDamage() consumes the supplied region.
    const auto savedDamage = state.damage.copy(), savedBufferDamage = state.bufferDamage.copy();
    struct Restore {
        SSurfaceState& state;
        CRegion damage, bufferDamage;
        ~Restore() { state.damage = damage; state.bufferDamage = bufferDamage; }
    } restore{state, savedDamage, savedBufferDamage};
    nlohmann::json result;
    for (const auto& [name, box] : std::vector<std::pair<std::string, std::optional<CBox>>>{
        {"full", std::nullopt}, {"bounded", CBox{0, 0, 17, 13}}, {"empty", CBox{0, 0, 0, 0}}}) {
        state.damage.clear();
        state.bufferDamage = CBox{{}, state.bufferSize};
        auto region = window->wlSurface()->computeDamage(box);
        const auto extents = region.getExtents();
        result[name] = {extents.x, extents.y, extents.w, extents.h};
    }
    const auto serialized = result.dump();
    lua_pushlstring(L, serialized.data(), serialized.size());
    return 1;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
static int geometry(lua_State* L) {
    const std::string title = luaL_checkstring(L, 1);
    for (const auto& window : Desktop::windowState()->windows()) {
        if (window->metadata().title() != title) continue;
        const auto pos = window->positionAnimation()->value(), size = window->sizeAnimation()->value();
        const auto goalPos = window->positionAnimation()->goal(), goalSize = window->sizeAnimation()->goal();
        const auto value = nlohmann::json{{"current", {pos.x, pos.y, size.x, size.y}},
            {"goal", {goalPos.x, goalPos.y, goalSize.x, goalSize.y}},
            {"movingFromMonitor", window->presentation().movingFromMonitor()},
            {"borderSize", window->presentation().borderSize()}}.dump();
        lua_pushlstring(L, value.data(), value.size()); return 1;
    }
    return luaL_error(L, "Test window is missing");
}

static int drag(lua_State* L) {
    const std::string title = luaL_checkstring(L, 1);
    for (const auto& window : Desktop::windowState()->windows()) {
        if (window->metadata().title() != title) continue;
        const auto target = window->layoutTarget();
        if (!target || target->floating()) return luaL_error(L, "Test window must be tiled");
        const auto point = g_pInputManager->getMouseCoordsInternal();
        const auto before = target->position();
        const auto fraction = (point - before.pos()) / before.size();
        g_layoutManager->beginDragTarget(target, MBIND_MOVE);
        const auto pickedUp = target->position();
        const auto grabbed = (point - pickedUp.pos()) / pickedUp.size();
        const auto value = nlohmann::json{{"before", {fraction.x, fraction.y}}, {"after", {grabbed.x, grabbed.y}},
            {"floating", target->floating()}}.dump();
        g_layoutManager->endDragTarget();
        lua_pushlstring(L, value.data(), value.size()); return 1;
    }
    return luaL_error(L, "Test window is missing");
}

static SP<CXDGToplevelResource> toplevel(PHLWINDOW window) {
    const auto surface = window->resource();
    const auto role = surface ? dynamicPointerCast<CXDGSurfaceRole>(surface->m_role) : nullptr;
    const auto xdg = role ? role->m_xdgSurface.lock() : nullptr;
    return xdg ? xdg->m_toplevel.lock() : nullptr;
}

static int clientState(lua_State* L) {
    const std::string title = luaL_checkstring(L, 1);
    for (const auto& window : Desktop::windowState()->windows()) {
        if (window->metadata().title() != title) continue;
        const auto client = toplevel(window);
        if (!client) return luaL_error(L, "Test window must be an xdg toplevel");
        const auto value = nlohmann::json{{"maximized", std::ranges::find(client->m_pendingApply.states,
            XDG_TOPLEVEL_STATE_MAXIMIZED) != client->m_pendingApply.states.end()}}.dump();
        lua_pushlstring(L, value.data(), value.size()); return 1;
    }
    return luaL_error(L, "Test window is missing");
}

static int requestState(lua_State* L) {
    const std::string title = luaL_checkstring(L, 1), operation = luaL_checkstring(L, 2);
    const bool value = lua_toboolean(L, 3);
    if (operation != "maximize" && operation != "minimize") return luaL_error(L, "Unknown test request");
    for (const auto& window : Desktop::windowState()->windows()) {
        if (window->metadata().title() != title) continue;
        const auto client = toplevel(window);
        if (!client) return luaL_error(L, "Test window must be an xdg toplevel");
        // Run outside the IPC Lua evaluation, as an actual client request does.
        g_pEventLoopManager->doLater([weak = WP<CXDGToplevelResource>(client), operation, value] {
            const auto client = weak.lock();
            if (!client) return;
            if (operation == "maximize") client->m_state.requestsMaximize = value;
            else client->m_state.requestsMinimize = true;
            client->m_events.stateChanged.emit();
            client->m_state.requestsMaximize.reset();
            client->m_state.requestsMinimize.reset();
        });
        return 0;
    }
    return luaL_error(L, "Test window is missing");
}

static bool rectRequested = false;
static int rectDrawn = 0;
static CHyprSignalListener rectRender;
static int rectangle(lua_State* L) {
    const std::string action = luaL_checkstring(L, 1);
    if (action == "request") {
        rectDrawn = 0;
        rectRequested = true;
        if (const auto monitor = Desktop::focusState()->monitor()) g_pHyprRenderer->damageMonitor(monitor);
    }
    lua_pushinteger(L, rectDrawn);
    return 1;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Damage probe: compositor/header ABI mismatch");
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "damage", damage);
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "geometry", geometry);
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "drag", drag);
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "client_state", clientState);
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "request_state", requestState);
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "rectangle", rectangle);
    rectRender = Event::bus()->m_events.render.stage.listen([](Event::SRenderStageEvent event) {
        if (!rectRequested || event.stage != RENDER_POST_WINDOWS) return;
        rectRequested = false;
        auto& context = g_pHyprRenderer->context();
        // Use the real renderRect path, outside overview. Both implicit and
        // explicit damage must work, including the nullable blurred path.
        for (int index = 0; index < 3; ++index) {
            Render::GL::CHyprOpenGLImpl::SRectRenderData data;
            data.blur = index == 1;
            if (index == 2) data.damage = &context.m_data.damage;
            Render::GL::g_pHyprOpenGL->renderRect(context, CBox{30, 40, 160, 120}, CHyprColor{0.3, 0.5, 0.7, 0.7}, data);
            ++rectDrawn;
        }
    });
    return {"upgrade-damage-probe", "Disposable surface damage verification", "Hyprstack tests", "1"};
}
APICALL EXPORT void PLUGIN_EXIT() { rectRender.reset(); }
