// Native requests and titlebar buttons share the controller's current state.
#pragma once
#include <hyprland/src/config/lua/ConfigManager.hpp>

static bool runDecorationAction(PHLWINDOW window, const std::string& operation) {
    const auto manager = dynamic_cast<Config::Lua::CConfigManager*>(Config::mgr().get());
    if (!manager || !window || !window->mapped()) return false;
    const auto result = manager->eval(std::format(
        "if not hyprstack_layouts or hyprstack_layouts.mode() ~= 'stacking' then return false end; "
        "hyprstack_layouts.action('{}', '0x{:x}', '{:x}'); return true",
        operation, reinterpret_cast<uintptr_t>(window.get()), window->metadata().stableID()), true);
    return result && *result == "true";
}
