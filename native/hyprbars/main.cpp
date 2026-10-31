#define WLR_USE_UNSTABLE

#include <unistd.h>

#include <any>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleEffectContainer.hpp>
#include <hyprland/src/config/lua/bindings/LuaBindingsInternal.hpp>
#include <hyprland/src/config/lua/types/LuaConfigColor.hpp>
#include <hyprland/src/state/MonitorState.hpp>


#include <algorithm>

#include "barDeco.hpp"
#include "globals.hpp"
#include "task-animation.hpp"
#include "scrolling-opening.hpp"
#include "initial-geometry.hpp"
#include "client-surface.hpp" // HYPRSTACK_CLIENT_SURFACE
#include <set>
#include <hyprland/src/devices/IKeyboard.hpp>
#include <hyprland/src/layout/target/WindowTarget.hpp>
#include "floating-dialogs.hpp"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include "stacking-input.hpp" // HYPRSTACK_STACKING_INPUT
#include "overview-scene.hpp" // HYPRSTACK_OVERVIEW_SCENE
#include "autoscroll.hpp"
#include "tiling-hover.hpp"
#include "shader-warmup.hpp"

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

// HYPRSTACK_SOLO_SUPER: any chord or pointer action cancels the bare modifier.
static std::set<uint32_t> superPressedKeys;
static bool superUsed = true;
static bool superHeld() { return superPressedKeys.contains(125) || superPressedKeys.contains(126); }
static int soloSuperLua(lua_State* L) { lua_pushboolean(L, !superUsed); return 1; }

static void onNewWindow(PHLWINDOW window) {
    if (!window->backend().traits().suggestsNoBorder) {
        if (std::ranges::any_of(window->presentation().decorations(), [](const auto& d) { return d->getDisplayName() == "Hyprbar"; }))
            return;

        auto bar = makeShared<CHyprBar>(window);
        g_pGlobalState->bars.emplace_back(bar);
        bar->m_self = bar;
        HyprlandAPI::addWindowDecoration(PHANDLE, window, std::move(bar));
    }
}

static void onPreConfigReload() {
    g_pGlobalState->buttons.clear();
}

static void onConfigReloaded() {
    for (auto& b : g_pGlobalState->bars) {
        if (!b)
            continue;

        b->onConfigReloaded();
    }
}

static void onUpdateWindowRules(PHLWINDOW window) {
    const auto BARIT = std::find_if(g_pGlobalState->bars.begin(), g_pGlobalState->bars.end(), [window](const auto& bar) { return bar->getOwner() == window; });

    if (BARIT == g_pGlobalState->bars.end())
        return;

    (*BARIT)->updateRules();
    window->presentation().updateDecorations();
}

// HYPRSTACK_TASK_TRANSFORMER: client geometry is never part of a task animation.
// HYPRSTACK_TASK_BUTTON_TARGET: enter the real task rectangle behind the bar.
int animateLuaWindow(lua_State* L) {
    const std::string address = luaL_checkstring(L, 1), id = luaL_checkstring(L, 2), operation = luaL_checkstring(L, 3);
    PHLWINDOW window;
    for (const auto& w : Desktop::windowState()->windows()) {
        if (w->mapped() && std::format("0x{:x}", reinterpret_cast<uintptr_t>(w.get())) == address &&
            std::format("{:x}", w->metadata().stableID()) == id) { window = w; break; }
    }
    if (!window) { lua_pushboolean(L, false); return 1; }
    if (operation == "telegram-webview-parent") {
        const auto parent = telegramWebviewParent(window);
        if (parent) {
            const auto parentAddress = std::format("0x{:x}", reinterpret_cast<uintptr_t>(parent.get()));
            lua_pushlstring(L, parentAddress.data(), parentAddress.size());
        } else lua_pushboolean(L, false);
        return 1;
    }
    if (operation == "center") {
        lua_pushboolean(L, centerFloatingWindow(window, lua_toboolean(L, 4)));
        return 1;
    }
    if (operation == "normalize-tiled-maximize") {
        lua_pushboolean(L, normalizeTiledMaximize(window));
        return 1;
    }
    if (operation == "client-state") {
        for (auto& bar : g_pGlobalState->bars)
            if (bar && bar->getOwner() == window) bar->syncNativePolicy();
        window->sendWindowSize(true);
        return 0;
    }
    if (operation == "decorations") {
        for (auto& bar : g_pGlobalState->bars)
            if (bar && bar->getOwner() == window) bar->onConfigReloaded();
        return 0;
    }
    if (operation == "clear-maximize-echo") {
        window->fullscreenPolicy().clearExpectedMaximizeEcho();
        return 0;
    }
    if (operation == "busy") {
        const auto task = CTaskAnimation::find(window);
        lua_pushboolean(L, task && task->busy());
        return 1;
    }
    if (operation == "workspace-opacity") {
        window->presentation().alpha(Desktop::View::WINDOW_ALPHA_MOVE_TO_WORKSPACE)->setValueAndWarp(1.F);
        window->presentation().alpha(Desktop::View::WINDOW_ALPHA_MOVE_FROM_WORKSPACE)->setValueAndWarp(1.F);
        return 0;
    }
    if (operation == "clear") { CTaskAnimation::clear(window); return 0; }
    const Vector2D pos{luaL_checknumber(L, 4), luaL_checknumber(L, 5)};
    const Vector2D size{std::max(1.0, luaL_checknumber(L, 6)), std::max(1.0, luaL_checknumber(L, 7))};
    const CBox target{pos, size};
    if (operation == "geometry") {
        // One target update avoids the center-preserving intermediate resize.
        window->layoutTarget()->setPositionGlobal(target);
        lua_pushboolean(L, true);
        return 1;
    }
    const auto monitor = window->m_monitor.lock();
    const double panelTop = luaL_optnumber(L, 8, pos.y - 4.0);
    const auto previous = CTaskAnimation::find(window);
    const bool reversing = previous != nullptr;
    const CBox current = previous ? previous->current() : window->getFullWindowBoundingBox();
    CTaskAnimation::clear(window);
    if (operation == "from") {
        window->effects().transformers()->emplace<CTaskAnimation>(window, reversing ? current : target, window->getFullWindowBoundingBox(), panelTop);
    } else if (operation == "to") {
        window->effects().transformers()->emplace<CTaskAnimation>(window, current, target, panelTop);
    } else if (operation == "reset") {
        window->positionAnimation()->setValueAndWarp(pos);
        window->sizeAnimation()->setValueAndWarp(size);
    }
    g_pHyprRenderer->damageWindow(window);
    return 0;
}

int clearLuaButtons(lua_State*) {
    g_pGlobalState->buttons.clear();
    for (auto& bar : g_pGlobalState->bars) {
        if (bar) bar->m_bButtonsDirty = true;
    }
    return 0;
}

int newLuaButton(lua_State* L) {
    if (!lua_istable(L, 1))
        return Config::Lua::Bindings::Internal::configError(L, "add_button: expected a table { bg_color, fg_color, size, icon, action }");

    SHyprButton button;

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "bg_color");

        Config::Lua::CLuaConfigColor parser(0);
        auto                         err = parser.parse(L);
        if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
            return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse bg_color");

        button.bgcol = parser.parsed();
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "fg_color");

        Config::Lua::CLuaConfigColor parser(0);
        auto                         err = parser.parse(L);
        if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
            return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse fg_color");

        button.userfg = true;
        button.fgcol = parser.parsed();
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "size");

        if (!lua_isnumber(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: size must be an integer");

        button.size = lua_tointeger(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "icon");

        if (!lua_isstring(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: icon must be a string");

        button.icon = lua_tostring(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "action");

        if (!lua_isstring(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: action must be a string");

        button.cmd = lua_tostring(L, -1);
    }

    g_pGlobalState->buttons.push_back(std::move(button));

    for (auto& b : g_pGlobalState->bars) {
        b->m_bButtonsDirty = true;
    }

    return 0;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[hyprbars] Failure in initialization: Version mismatch (headers ver is not equal to running hyprland ver)",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[hb] Version mismatch");
    }

    installClientSurfacePolicy(PHANDLE);
    HyprstackOverview::install(PHANDLE);
    HyprstackShaders::install();

    g_pGlobalState                    = makeUnique<SGlobalState>();
    g_pGlobalState->nobarRuleIdx      = Desktop::Rule::windowEffects()->registerEffect("hyprbars:no_bar");
    g_pGlobalState->barColorRuleIdx   = Desktop::Rule::windowEffects()->registerEffect("hyprbars:bar_color");
    g_pGlobalState->titleColorRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:title_color");

    static auto P  = Event::bus()->m_events.window.open.listen([&](PHLWINDOW w) { onNewWindow(w); });
    static auto P3 = Event::bus()->m_events.window.updateRules.listen([&](PHLWINDOW w) { onUpdateWindowRules(w); });

    g_pGlobalState->config.barColor            = makeShared<Config::Values::CColorValue>("plugin:hyprbars:bar_color", "Change the bar color", 0x88333333);
    g_pGlobalState->config.textColor           = makeShared<Config::Values::CColorValue>("plugin:hyprbars:col.text", "Change the text color", 0xffffffff);
    g_pGlobalState->config.inactiveButtonColor = makeShared<Config::Values::CColorValue>(
        "plugin:hyprbars:inactive_button_color", "Change the inactive button's color. 0x00000000 means unset", 0x00000000);
    g_pGlobalState->config.barHeight       = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_height", "Change the bar's height", 15);
    g_pGlobalState->config.barTextSize     = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_text_size", "Change the bar's text size", 10);
    g_pGlobalState->config.barTextWeight   = makeShared<Config::Values::CFontWeightValue>("plugin:hyprbars:bar_text_weight", "Bar's title text weight (e.g. \"bold\" or an integer 100-1000)", 400);
    g_pGlobalState->config.barTitleEnabled = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_title_enabled", "Whether to enable titles in the bar", true);
    g_pGlobalState->config.barBlur         = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_blur", "Whether to enable blur of the bar", false);
    g_pGlobalState->config.barTextFont     = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_font", "Bar's text font", "Sans");
    g_pGlobalState->config.barTextAlign    = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_align", "Bar's text alignment", "center");
    g_pGlobalState->config.barPartOfWindow =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_part_of_window", "Whether the bar is a part of the window (reserves space)", true);
    g_pGlobalState->config.barPrecedenceOverBorder =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_precedence_over_border", "Whether the bar is before, or after the border", false);
    g_pGlobalState->config.barButtonsAlignment = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_buttons_alignment", "Alignment of the bar buttons", "right");
    g_pGlobalState->config.barPadding          = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_padding", "Padding of the bar", 7);
    g_pGlobalState->config.barButtonPadding    = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_button_padding", "Padding of the bar buttons", 5);
    g_pGlobalState->config.enabled             = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:enabled", "Whether bars are enabled", true);
    g_pGlobalState->config.iconOnHover         = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:icon_on_hover", "Whether to use an icon on hover of the buttons", false);
    g_pGlobalState->config.onDoubleClick       = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_double_click", "Action to execute on double click of the bar", "");

    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.textColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.inactiveButtonColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barHeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextSize);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextWeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTitleEnabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barBlur);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextFont);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextAlign);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPartOfWindow);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPrecedenceOverBorder);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barButtonsAlignment);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPadding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barButtonPadding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.enabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.iconOnHover);
    g_pGlobalState->config.onMinimize = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_minimize", "Addressed native minimize action", "");
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onMinimize);
    g_pGlobalState->config.onMaximize = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_maximize", "Addressed native maximize action", "");
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onMaximize);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onDoubleClick);

        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "add_button", ::newLuaButton);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "clear_buttons", ::clearLuaButtons);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "animate_window", ::animateLuaWindow);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "solo_super", ::soloSuperLua);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "clear_focus", ::clearFocusLua);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "task_focused", ::taskFocusedLua);
    static auto superKey = Event::bus()->m_events.input.keyboard.key.listen([](IKeyboard::SKeyEvent event, Event::SCallbackInfo&) {
        if (event.state == WL_KEYBOARD_KEY_STATE_PRESSED) {
            if (event.keycode == 125 || event.keycode == 126) superUsed = !superPressedKeys.empty();
            else if (superHeld()) superUsed = true;
            superPressedKeys.insert(event.keycode);
        } else superPressedKeys.erase(event.keycode);
    });
    static auto superButton = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) {
        if (event.state == WL_POINTER_BUTTON_STATE_PRESSED && superHeld()) superUsed = true;
    });
    static auto superWheel = Event::bus()->m_events.input.mouse.axis.listen([](IPointer::SAxisEvent, Event::SCallbackInfo&) {
        if (superHeld()) superUsed = true;
    });
    static auto P4 = Event::bus()->m_events.config.preReload.listen([&] { onPreConfigReload(); });
    static auto P5 = Event::bus()->m_events.config.reloaded.listen([&] { onConfigReloaded(); });

    stackingInput = makeUnique<CStackingInput>();
    HyprstackSnap::install(PHANDLE); // HYPRSTACK_SNAP_ZONES
    HyprstackAutoscroll::install(PHANDLE);
    HyprstackTilingHover::install(PHANDLE);
    HyprstackInitialGeometry::install(PHANDLE);

    // add deco to existing windows
    for (auto& w : Desktop::windowState()->windows()) {
        if (w->isHidden() || !w->mapped())
            continue;

        onNewWindow(w);
    }

    HyprlandAPI::reloadConfig();

    return {"hyprstack-hyprbars", "Hyprstack window decorations and navigation.", "hyprwm / Hyprstack", "1.3.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    HyprstackInitialGeometry::remove(PHANDLE);
    HyprstackTilingHover::remove();
    HyprstackShaders::remove();
    HyprstackAutoscroll::remove();
    HyprstackOverview::remove(PHANDLE);
    removeClientSurfacePolicy(PHANDLE);
    HyprstackSnap::remove();
    stackingInput.reset();
    for (const auto& window : Desktop::windowState()->windows()) CTaskAnimation::clear(window);
    for (auto& m : State::monitorState()->monitors())
        m->m_scheduledRecalc = true;

    g_pHyprRenderer->context().m_pass.removeAllOfType("CBarPassElement");

    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->barColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->titleColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->nobarRuleIdx);
}
