// Keep borrowed windows above the source desktop throughout their native flight.
#pragma once
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/SceneResources.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <algorithm>
#include <stdexcept>
#include <vector>

namespace HyprstackSecondaryReturn {
using WindowRender = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLWINDOW, PHLMONITOR,
    const Render::SWindowRenderPresentation&, const Time::steady_tp&, bool, Render::eRenderPassMode, bool, bool);
static CFunctionHook* renderHook = nullptr;
struct Flight { PHLWINDOWREF window; PHLMONITORREF source; };
static bool desktopContext(const Render::CRenderContext& ctx) {
    return !ctx.m_renderingSnapshot && (!ctx.sceneResources() || !ctx.sceneResources()->isolated());
}

class Controller {
  public:
    Controller() {
        m_stage = Event::bus()->m_events.render.stage.listen([this](Event::SRenderStageEvent event) {
            if (event.stage != RENDER_POST_WINDOWS || !event.context) return;
            auto& ctx = event.context->get();
            if (!desktopContext(ctx)) return;
            const auto flights = m_flights;
            for (const auto& flight : flights) {
                const auto window = flight.window.lock();
                if (!active(flight) || flight.source != event.monitor ||
                    !window->getFullWindowBoundingBox().overlaps(event.monitor->logicalBox())) continue;
                // Draw once above desktop windows, below shell panels. Keep
                // Hyprland's own geometry, opacity and animation clocks intact.
                Hyprutils::Utils::CScopeGuard restore([&] { m_drawing = false; });
                m_drawing = true;
                reinterpret_cast<WindowRender>(renderHook->m_original)(g_pHyprRenderer.get(), ctx, window,
                    event.monitor, window->presentation().renderPresentation(), Time::steadyNow(), true,
                    Render::RENDER_PASS_ALL, false, false);
            }
        });
        m_timer = makeShared<CEventLoopTimer>(std::nullopt, [this](SP<CEventLoopTimer>, void*) { tick(); }, nullptr);
        g_pEventLoopManager->addTimer(m_timer);
    }
    ~Controller() {
        if (g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_timer);
        for (const auto& flight : m_flights)
            if (const auto source = flight.source.lock()) g_pHyprRenderer->damageMonitor(source);
    }
    void add(PHLWINDOW window) {
        std::erase_if(m_flights, [&](const auto& flight) { return flight.window == window; });
        m_flights.push_back({window, window->m_monitor});
        m_timer->updateTimeout(std::chrono::milliseconds(1));
    }
    bool deferred(PHLWINDOW window, PHLMONITOR monitor) const {
        return !m_drawing && std::ranges::any_of(m_flights, [&](const auto& flight) {
            return flight.window == window && flight.source == monitor && active(flight);
        });
    }
  private:
    static bool active(const Flight& flight) {
        const auto window = flight.window.lock();
        return flight.source && window && window->mapped() && window->m_workspace &&
            window->m_workspace->type() != Workspace::eWorkspaceType::SPECIAL &&
            (window->positionAnimation()->isBeingAnimated() || window->sizeAnimation()->isBeingAnimated() ||
             (window->presentation().movingFromMonitor() &&
              window->presentation().alpha(Desktop::View::WINDOW_ALPHA_MOVE_TO_WORKSPACE)->isBeingAnimated()));
    }
    void tick() {
        int interval = 16;
        std::erase_if(m_flights, [&](const auto& flight) {
            if (const auto source = flight.source.lock()) {
                g_pHyprRenderer->damageMonitor(source);
                interval = std::min(interval, std::max(1, static_cast<int>(1000 / source->m_refreshRate)));
            }
            return !active(flight);
        });
        m_timer->updateTimeout(m_flights.empty() ? std::nullopt : std::optional{std::chrono::milliseconds(interval)});
    }
    bool m_drawing = false;
    std::vector<Flight> m_flights;
    CHyprSignalListener m_stage;
    SP<CEventLoopTimer> m_timer;
};
static UP<Controller> controller;

static void renderWindow(Render::IHyprRenderer* renderer, Render::CRenderContext& ctx, PHLWINDOW window,
    PHLMONITOR monitor, const Render::SWindowRenderPresentation& presentation, const Time::steady_tp& now,
    bool decorate, Render::eRenderPassMode pass, bool ignorePosition, bool standalone) {
    if (!standalone && desktopContext(ctx) && controller && controller->deferred(window, monitor)) return;
    reinterpret_cast<WindowRender>(renderHook->m_original)(renderer, ctx, window, monitor, presentation,
        now, decorate, pass, ignorePosition, standalone);
}
static int registerReturn(lua_State* L) {
    if (!controller) return 0;
    const std::string address = luaL_checkstring(L, 1), identity = luaL_checkstring(L, 2);
    for (const auto& window : Desktop::windowState()->windows()) {
        if (!window->mapped() || !window->m_monitor || !window->m_workspace ||
            window->m_workspace->addressableName() != "special:hyprstack-secondary" ||
            std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())) != address ||
            std::format("{:x}", window->metadata().stableID()) != identity) continue;
        controller->add(window);
        return 0;
    }
    return 0;
}
static void install(HANDLE handle) {
    const auto matches = HyprlandAPI::findFunctionsByName(handle, "renderWindow");
    const auto found = std::ranges::find_if(matches, [](const auto& match) {
        return match.demangled.starts_with("Render::IHyprRenderer::renderWindow(");
    });
    if (found == matches.end()) throw std::runtime_error("[hyprstack] Missing window render hook");
    renderHook = HyprlandAPI::createFunctionHook(handle, found->address, reinterpret_cast<void*>(&renderWindow));
    if (!renderHook || !renderHook->hook()) {
        if (renderHook) HyprlandAPI::removeFunctionHook(handle, renderHook);
        renderHook = nullptr;
        throw std::runtime_error("[hyprstack] Cannot hook returning window rendering");
    }
    controller = makeUnique<Controller>();
    HyprlandAPI::addLuaFunction(handle, "hyprbars", "secondary_return", registerReturn);
}
static void remove(HANDLE handle) {
    if (renderHook) HyprlandAPI::removeFunctionHook(handle, renderHook);
    renderHook = nullptr;
    controller.reset();
}
}
