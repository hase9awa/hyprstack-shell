// Only loaded by test_upgrade.py in its disposable compositor.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
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
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Damage probe: compositor/header ABI mismatch");
    HyprlandAPI::addLuaFunction(handle, "upgrade_probe", "damage", damage);
    return {"upgrade-damage-probe", "Disposable surface damage verification", "Hyprstack tests", "1"};
}
APICALL EXPORT void PLUGIN_EXIT() {}
