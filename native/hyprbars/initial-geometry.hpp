// Give scrolling clients their tile size before they allocate their first buffer.
#pragma once

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include "globals.hpp"
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/workspace/WorkspaceRuleManager.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/managers/XWaylandManager.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>

namespace HyprstackInitialGeometry {
static CFunctionHook* sizeHook = nullptr;

static std::string withoutSilent(std::string value) {
    if (value.ends_with(" silent")) value.resize(value.size() - 7);
    return value;
}

static std::optional<Vector2D> tileSize(PHLWINDOW window) {
    if (!window || !g_pGlobalState || g_pGlobalState->config.enabled->value() || window->m_isMapped || window->m_isFloating ||
        window->m_ruleApplicator->static_.floating.value_or(false) || window->parent() || g_pXWaylandManager->shouldBeFloated(window, true))
        return std::nullopt;

    const auto& rules = window->m_ruleApplicator->static_;
    auto monitor = Desktop::focusState()->monitor();
    if (!rules.monitor.empty()) {
        const auto selected = State::monitorState()->query().selector(withoutSilent(rules.monitor)).run();
        if (selected) monitor = selected;
    }
    if (!monitor) return std::nullopt;
    auto workspace = monitor->m_activeWorkspace;
    if (!rules.workspace.empty()) {
        const auto selected = State::workspaceState()->query().string(withoutSilent(rules.workspace)).run();
        if (selected) {
            workspace = selected;
            if (selected->m_monitor) monitor = selected->m_monitor.lock();
        }
    }
    if (!workspace || !workspace->m_space) return std::nullopt;
    const auto algorithm = workspace->m_space->algorithm();
    const auto scrolling = algorithm ? dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get()) : nullptr;
    if (!scrolling) return std::nullopt;

    const auto workspaceRule = Config::workspaceRuleMgr()->getWorkspaceRuleFor(workspace);
    static const auto directionValue = CConfigValue<Config::STRING>("scrolling:direction");
    std::string direction = *directionValue;
    if (workspaceRule && workspaceRule->m_layoutopts.contains("direction")) direction = workspaceRule->m_layoutopts.at("direction");
    const bool horizontal = direction != "up" && direction != "down";
    const bool reversed = direction == "left" || direction == "up";
    static const auto widthValue = CConfigValue<Config::FLOAT>("scrolling:column_width");
    const double width = std::clamp<double>(rules.scrollingWidth.value_or(*widthValue), .05, 1.0);

    // New application windows become a new column after the focused column,
    // or at the end when focus belongs to another workspace.
    size_t columns = 0, insertion = 0;
    const auto focused = Desktop::focusState()->window();
    for (const auto& target : workspace->m_space->targets()) {
        const auto data = target ? scrolling->dataFor(target.lock(), true) : nullptr;
        const auto column = data ? data->column.lock() : nullptr;
        const auto tape = column ? column->scrollingData.lock() : nullptr;
        if (!tape) continue;
        columns = tape->columns.size();
        insertion = columns;
        const auto active = focused ? scrolling->dataFor(focused->layoutTarget(), true) : nullptr;
        const auto activeColumn = active ? active->column.lock() : nullptr;
        if (activeColumn) {
            const auto index = tape->idx(activeColumn);
            if (index >= 0) insertion = index + 1;
        }
        break;
    }
    bool before = insertion > 0, after = insertion < columns;
    if (reversed) std::swap(before, after);
    static const auto gapsValue = CConfigValue<Config::IComplexConfigValue>("general:gaps_in");
    const auto gaps = workspaceRule && workspaceRule->m_gapsIn ? *workspaceRule->m_gapsIn : *static_cast<Config::CCssGapData*>(gapsValue.ptr());
    Vector2D size = workspace->m_space->workArea().size();
    static const auto fullscreenOnOne = CConfigValue<Config::INTEGER>("scrolling:fullscreen_on_one_column");
    const double fraction = !columns && *fullscreenOnOne ? 1.0 : width;
    if (horizontal) size.x = size.x * fraction - (before ? gaps.m_left : 0) - (after ? gaps.m_right : 0);
    else size.y = size.y * fraction - (before ? gaps.m_top : 0) - (after ? gaps.m_bottom : 0);
    const double border = window->getRealBorderSize();
    size -= Vector2D{2 * border, 2 * border};
    if (workspace->m_isSpecialWorkspace) {
        static const auto scale = CConfigValue<Config::FLOAT>("dwindle:special_scale_factor");
        size = size * *scale;
    }
    return Vector2D{std::max(1.0, std::round(size.x)), std::max(1.0, std::round(size.y))};
}

using SetSizeFunction = uint32_t (*)(CXDGToplevelResource*, const Vector2D&);
static uint32_t setSize(CXDGToplevelResource* toplevel, const Vector2D& size) {
    const auto original = reinterpret_cast<SetSizeFunction>(sizeHook->m_original);
    // Only replace the missing initial hint. Later configure events, floating
    // dialogs, fullscreen requests and other layouts retain their own sizing.
    if (size != Vector2D{} || !toplevel->m_owner || !toplevel->m_owner->m_initialCommit ||
        toplevel->m_state.requestsFullscreen.value_or(false))
        return original(toplevel, size);
    const auto predicted = tileSize(toplevel->m_window.lock());
    if (!predicted) return original(toplevel, size);
    // The tiling decoration policy sets this on map already. Announce it in
    // the same first configure so Chromium does not first paint a normal CSD.
    toplevel->setMaximized(true);
    return original(toplevel, *predicted);
}

static void install(HANDLE handle) {
    const auto matches = HyprlandAPI::findFunctionsByName(handle, "setSize");
    const auto found = std::ranges::find_if(matches, [](const auto& match) {
        return match.demangled.starts_with("CXDGToplevelResource::setSize(");
    });
    if (found == matches.end()) throw std::runtime_error("[hyprstack] Missing initial toplevel size hook");
    sizeHook = HyprlandAPI::createFunctionHook(handle, found->address, reinterpret_cast<void*>(&setSize));
    if (!sizeHook || !sizeHook->hook()) {
        if (sizeHook) HyprlandAPI::removeFunctionHook(handle, sizeHook);
        sizeHook = nullptr;
        throw std::runtime_error("[hyprstack] Cannot hook initial toplevel size");
    }
}

static void remove(HANDLE handle) {
    if (sizeHook) HyprlandAPI::removeFunctionHook(handle, sizeHook);
    sizeHook = nullptr;
}
} // namespace HyprstackInitialGeometry
