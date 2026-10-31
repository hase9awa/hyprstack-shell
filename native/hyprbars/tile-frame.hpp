// Square shared tile edges, concentric accent arcs at the desktop frame.
#pragma once
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/render/ElementRenderer.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <nlohmann/json.hpp>
#include <map>
#include <array>

bool hyprstackOverviewRendering();
namespace HyprstackTileFrame {
static std::map<std::string, double> radii;
static CFunctionHook* borderHook = nullptr;
using BorderDraw = void (*)(void*, Render::CRenderContext&, WP<CBorderPassElement>, const CRegion&);

static void drawBorder(void* renderer, Render::CRenderContext& ctx, WP<CBorderPassElement> element, const CRegion& damage) {
    const auto original = reinterpret_cast<BorderDraw>(borderHook->m_original);
    const auto window = element ? element->m_data.window.lock() : nullptr;
    const auto monitor = g_pHyprRenderer->context().m_data.pMonitor.lock();
    if (!window || !monitor || !window->mapped() || window->isFloating() || (window->m_state & Desktop::View::WINDOW_STATE_PINNED) ||
        !window->m_workspace || !window->m_workspace->space() || (window->m_workspace->type() == Workspace::eWorkspaceType::SPECIAL) ||
        !radii.contains(monitor->m_name) || radii.at(monitor->m_name) <= 0 || hyprstackOverviewRendering() ||
        Fullscreen::controller()->getFullscreenModes(window).internal != Fullscreen::FSMODE_NONE) {
        original(renderer, ctx, element, damage); return;
    }
    const auto area = window->m_workspace->space()->workArea();
    const double border = window->presentation().borderSize();
    const CBox outer{window->positionAnimation()->goal()-Vector2D{border,border},
        window->sizeAnimation()->goal()+Vector2D{2*border,2*border}};
    const bool left = std::abs(outer.x-area.x) <= 1, right = std::abs(outer.x+outer.w-area.x-area.w) <= 1;
    const bool top = std::abs(outer.y-area.y) <= 1, bottom = std::abs(outer.y+outer.h-area.y-area.h) <= 1;
    const std::array<bool,4> corners{left&&top, right&&top, left&&bottom, right&&bottom};
    if (std::ranges::none_of(corners, [](bool value) { return value; })) {
        auto data=element->m_data;
        data.round=data.outerRound=0;
        const auto part=makeShared<CBorderPassElement>(data);
        original(renderer, ctx, part, damage); return;
    }
    auto& render = g_pHyprRenderer->context().m_data;
    const auto savedDamage = render.damage.copy();
    auto bounds = element->m_data.box.copy().expand(std::round(border*monitor->m_scale));
    render.renderModif.applyToBox(bounds);
    const auto midpoint = bounds.middle().round();
    const std::array<CBox,4> quarters{{
        {bounds.x,bounds.y,midpoint.x-bounds.x,midpoint.y-bounds.y},
        {midpoint.x,bounds.y,bounds.x+bounds.w-midpoint.x,midpoint.y-bounds.y},
        {bounds.x,midpoint.y,midpoint.x-bounds.x,bounds.y+bounds.h-midpoint.y},
        {midpoint.x,midpoint.y,bounds.x+bounds.w-midpoint.x,bounds.y+bounds.h-midpoint.y}}};
    const int radius = std::round(radii.at(monitor->m_name)*monitor->m_scale);
    const int thickness = std::round(border*monitor->m_scale);
    for (size_t i=0; i<quarters.size(); ++i) {
        render.damage = savedDamage.copy().intersect(quarters[i]);
        if (render.damage.empty()) continue;
        auto data = element->m_data;
        data.round = corners[i] ? std::max(1,radius-thickness) : 0;
        data.outerRound = corners[i] ? radius : 0;
        data.roundingPower = 2.F;
        const auto part = makeShared<CBorderPassElement>(data);
        original(renderer, ctx, part, damage);
    }
    render.damage = savedDamage;
}

static int luaFrame(lua_State* L) {
    const std::string monitor = luaL_checkstring(L,1);
    if (monitor == "status") {
        const auto value = nlohmann::json(radii).dump();
        lua_pushlstring(L,value.data(),value.size()); return 1;
    }
    if (monitor == "settle") {
        // A gap toggle changes both the tile mask and the shared edge geometry.
        // Commit those together instead of animating square corners past the
        // already rounded desktop frame.
        for (const auto& output : State::monitorState()->monitors())
            g_layoutManager->recalculateMonitor(output);
        for (const auto& window : Desktop::windowState()->windows()) {
            if (!window->mapped() || window->isFloating() || window->isHidden()) continue;
            window->positionAnimation()->warp();
            window->sizeAnimation()->warp();
            window->sendWindowSize(true);
        }
        for (const auto& output : State::monitorState()->monitors())
            g_pHyprRenderer->damageMonitor(output);
        lua_pushboolean(L,true); return 1;
    }
    radii[monitor] = std::clamp(luaL_checknumber(L,2),0.0,100.0);
    for (const auto& output : State::monitorState()->monitors())
        if (output->m_name == monitor) g_pHyprRenderer->damageMonitor(output);
    lua_pushboolean(L,true); return 1;
}
static void remove(HANDLE handle) {
    if (borderHook) HyprlandAPI::removeFunctionHook(handle,borderHook);
    borderHook = nullptr; radii.clear();
}
static void install(HANDLE handle) {
    const auto matches = HyprlandAPI::findFunctionsByName(handle,"draw");
    const auto found = std::ranges::find_if(matches, [](const auto& function) {
        return function.demangled.starts_with("Render::GL::CGLElementRenderer::draw(") &&
            function.demangled.contains("CBorderPassElement");
    });
    if (found == matches.end()) throw std::runtime_error("[hyprstack] Missing pinned border renderer");
    borderHook = HyprlandAPI::createFunctionHook(handle,found->address,reinterpret_cast<void*>(&drawBorder));
    if (!borderHook || !borderHook->hook()) { remove(handle); throw std::runtime_error("[hyprstack] Cannot hook tile frame"); }
    HyprlandAPI::addLuaFunction(handle,"hyprbars","tile_frame",luaFrame);
}
}
