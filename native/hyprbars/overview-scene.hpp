// Hyprstack's overview is a compositor scene, not a layer-shell application.
// Pinned to the same Hyprland 0.57 renderer ABI as the titlebar adaptation.
#pragma once
#include "tile-frame.hpp"

#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>
#include <hyprland/src/render/ElementRenderer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>
#include <hyprland/src/render/pass/ClearPassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/protocols/wlr-layer-shell-unstable-v1.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/render/decorations/DecorationPositioner.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <nlohmann/json.hpp>
#include <chrono>
#include <functional>
#include <set>
#include "overview-blur.hpp"
#include "workspace-camera.hpp"

namespace HyprstackOverview {
using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;
using WorkspaceRender = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLMONITOR, PHLWORKSPACE,
    const Time::steady_tp&, Render::eSceneMode, const Vector2D&, const float&);
using LayerRender = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool, bool);
using BackgroundRender = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLMONITOR);
using FadeoutRender = void (*)(Render::IHyprRenderer*, Render::CRenderContext&, PHLMONITOR, Desktop::eFadeoutPlane, PHLWORKSPACE);

static CFunctionHook* renderHook = nullptr;
static CFunctionHook* scanoutHook = nullptr;
static CFunctionHook* textureHook = nullptr;
static CFunctionHook* rectHook = nullptr;
static CFunctionHook* fadeoutHook = nullptr;
static LayerRender renderLayer = nullptr;
static BackgroundRender renderBackground = nullptr;

struct Camera {
    double x = 0, y = 0, zoom = 1;
    bool operator==(const Camera& other) const {
        return std::abs(x - other.x) < .01 && std::abs(y - other.y) < .01 && std::abs(zoom - other.zoom) < .0001;
    }
};
static Camera mix(Camera a, Camera b, double t) {
    return {a.x + (b.x-a.x)*t, a.y + (b.y-a.y)*t, a.zoom + (b.zoom-a.zoom)*t};
}
static CBox mix(CBox a, CBox b, double t) { return {a.pos()+(b.pos()-a.pos())*t, a.size()+(b.size()-a.size())*t}; }
static CBox box(const Json& value) { return {value.value("x", 0.0), value.value("y", 0.0), value.value("width", 1.0), value.value("height", 1.0)}; }
static Camera camera(const Json& value) { return {value.value("x", 0.0), value.value("y", 0.0), value.value("zoom", 1.0)}; }
static Json encode(CBox b) { return {{"x", b.x}, {"y", b.y}, {"width", b.w}, {"height", b.h}}; }

struct Window {
    PHLWINDOWREF window;
    std::string address, identity;
    int64_t workspace = 0;
    bool original = false;
    CBox world, worldFrom, from, to;
    Clock::time_point start, worldStart;
};
struct Row { int64_t workspace; CBox world; Vector2D origin; };
struct ClosedWindow {
    std::string address;
    SP<Render::IFramebuffer> snapshot;
    CBox frame;
    Camera camera;
    Clock::time_point start;
    size_t zIndex;
};

// Run after the real background surfaces, before any windows or shell panels.
// The blur is cached in a private framebuffer, never in a borrowed work buffer.
class BackgroundPass final : public IPassElement {
  public:
    explicit BackgroundPass(std::function<std::vector<UP<IPassElement>>()> draw) : m_draw(std::move(draw)) {}
    std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override { return m_draw(); }
    bool needsLiveBlur(Render::CRenderContext& ctx) override { return false; }
    bool needsPrecomputeBlur(Render::CRenderContext& ctx) override { return false; }
    bool disableSimplification(Render::CRenderContext& ctx) override { return true; }
    const char* passName() override { return "HyprstackOverviewBackground"; }
    ePassElementType type() override { return EK_CUSTOM; }
  private:
    std::function<std::vector<UP<IPassElement>>()> m_draw;
};

class Scene {
  public:
    Scene() {
        m_unmap = Event::bus()->m_events.window.close.listen([this](PHLWINDOW window) { captureClosingWindow(window); });
        m_render = Event::bus()->m_events.render.stage.listen([this](Event::SRenderStageEvent event) {
            const auto stage = event.stage;
            const auto monitor = m_monitor.lock();
            if (!monitor || g_pHyprRenderer->context().m_data.pMonitor != monitor) return;
            if (stage == RENDER_BEGIN && m_running) {
                // A fullscreen client must still go through the workspace scene.
                monitor->m_solitaryClient.reset();
                g_pHyprRenderer->context().m_data.noSimplify = true;
            } else if (stage == RENDER_POST) g_pHyprRenderer->context().m_data.noSimplify = false;
        });
        m_key = Event::bus()->m_events.input.keyboard.key.listen([this](IKeyboard::SKeyEvent event, Event::SCallbackInfo& info) {
            if (event.state == WL_KEYBOARD_KEY_STATE_RELEASED) {
                if (m_keys.erase(event.keycode)) info.cancelled = true;
                return;
            }
            if (!acceptsInput()) return;
            const auto keyboard = g_pSeatManager->m_keyboard.lock();
            const auto mods = keyboard ? keyboard->getModifiers() : Input::ModifierMask{Input::HL_MODIFIER_NONE};
            std::string action;
            switch (event.keycode) {
                case 1: action = "overviewCancel"; break;
                case 28: case 96: action = "overviewAccept"; break;
                case 15: action = mods & Input::HL_MODIFIER_SHIFT ? "overviewBackcycle" : "overviewCycle"; break;
                case 35: case 105: action = "overviewH"; break;
                case 36: case 108: action = "overviewJ"; break;
                case 37: case 103: action = "overviewK"; break;
                case 38: case 106: action = "overviewL"; break;
                case 24: if (mods & Input::HL_MODIFIER_META) action = "overview"; break;
                case 16: if (mods & Input::HL_MODIFIER_META) action = "overviewClose"; break;
                case 32: if (mods & Input::HL_MODIFIER_META) action = "launcher"; break;
            }
            if (!action.empty() || !(mods & Input::HL_MODIFIER_META)) {
                m_keys.insert(event.keycode);
                info.cancelled = true;
            }
            if (!action.empty()) dispatch(action);
        });
        m_move = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D point, Event::SCallbackInfo& info) {
            if (!acceptsInput() || !contains(point)) return;
            // Pointer motion belongs to the overview, never to an underlying
            // titlebar or client. Cursor movement itself is unaffected.
            info.cancelled = true;
        });
        m_button = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent event, Event::SCallbackInfo& info) {
            if (event.state == WL_POINTER_BUTTON_STATE_RELEASED && m_buttons.erase(event.button)) { info.cancelled = true; return; }
            const auto point = g_pInputManager->getMouseCoordsInternal();
            if (!acceptsInput() || !contains(point)) return;
            info.cancelled = true;
            if (event.state != WL_POINTER_BUTTON_STATE_PRESSED) return;
            m_buttons.insert(event.button);
            if (event.button != 272) { m_input = {{"action", "cancel"}}; dispatch("overviewPointer"); return; }
            const auto monitor = m_monitor.lock();
            const auto local = point - monitor->m_position;
            // Match the actual animated geometry, rather than final grid cells.
            const auto& order = Desktop::windowState()->windows();
            for (auto it = order.rbegin(); it != order.rend(); ++it) {
                const auto state = std::ranges::find_if(m_windows, [&](const auto& w) { return w.window == *it; });
                if (state == m_windows.end() || !valid(*state) || !visualFrame(*state).containsPoint(local)) continue;
                m_input = {{"action", "accept"}, {"address", state->address}, {"workspace", state->workspace}};
                dispatch("overviewPointer"); return;
            }
            if (!m_stacking) for (const auto& row : m_rows) {
                if (project(row.world).containsPoint(local)) {
                    m_input = {{"action", "accept"}, {"address", ""}, {"workspace", row.workspace}};
                    dispatch("overviewPointer"); return;
                }
            }
            m_input = {{"action", "cancel"}}; dispatch("overviewPointer");
        });
        m_axis = Event::bus()->m_events.input.mouse.axis.listen([this](IPointer::SAxisEvent event, Event::SCallbackInfo& info) {
            if (!acceptsInput() || !contains(g_pInputManager->getMouseCoordsInternal())) return;
            info.cancelled = true;
            if (!m_stacking && event.delta != 0) dispatch(event.delta > 0 ? "overviewJ" : "overviewK");
        });
        // Navigation while overview is open belongs to the scene. Letting the
        // same swipe reach scroll_move/workspace would move the hidden desktop.
        m_swipeBegin = Event::bus()->m_events.gesture.swipe.begin.listen([this](IPointer::SSwipeBeginEvent event, Event::SCallbackInfo& info) {
            m_swipeOwned = acceptsInput() && HyprstackCamera::cameras && HyprstackCamera::cameras->navigationFingers(event.fingers);
            m_swipeDelta = {};
            if (m_swipeOwned) info.cancelled = true;
        });
        m_swipeUpdate = Event::bus()->m_events.gesture.swipe.update.listen([this](IPointer::SSwipeUpdateEvent event, Event::SCallbackInfo& info) {
            if (!m_swipeOwned) return;
            info.cancelled = true;
            m_swipeDelta += event.delta;
        });
        m_swipeEnd = Event::bus()->m_events.gesture.swipe.end.listen([this](IPointer::SSwipeEndEvent event, Event::SCallbackInfo& info) {
            if (!std::exchange(m_swipeOwned, false)) return;
            info.cancelled = true;
            if (!acceptsInput() || event.cancelled || std::max(std::abs(m_swipeDelta.x), std::abs(m_swipeDelta.y)) < 40) return;
            if (std::abs(m_swipeDelta.x) > std::abs(m_swipeDelta.y)) dispatch(m_swipeDelta.x < 0 ? "overviewL" : "overviewH");
            else if (!m_stacking) dispatch(m_swipeDelta.y < 0 ? "overviewJ" : "overviewK");
        });
        m_timer = makeShared<CEventLoopTimer>(std::nullopt, [this](SP<CEventLoopTimer> timer, void*) {
            const auto monitor = m_monitor.lock();
            if (!m_running || !monitor) { reset(); return; }
            if (g_pSessionLockManager->isSessionLocked() ||
                (!m_closing && std::chrono::duration<double>(Clock::now()-m_heartbeat).count() > 1.5) ||
                (m_closing && phase() >= 1)) { reset(); return; }
            g_pHyprRenderer->damageMonitor(monitor);
            timer->updateTimeout(std::chrono::milliseconds(std::max(1, static_cast<int>(1000 / monitor->m_refreshRate))));
        }, nullptr);
        g_pEventLoopManager->addTimer(m_timer);
    }
    ~Scene() { reset(); if (g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_timer); }

    void reset() {
        if (const auto monitor = m_monitor.lock()) g_pHyprRenderer->damageMonitor(monitor);

        m_running = m_closing = false;
        m_windows.clear(); m_closed.clear(); m_rows.clear(); m_input = Json::object();
        m_backgroundDirty = true;
        m_backgroundCommits.clear(); m_backgroundSources.clear();
        // Keep consumed key/button releases paired even after closing.
        if (m_timer) m_timer->updateTimeout(std::nullopt);
    }
    bool runningFor(PHLMONITOR monitor) const { return m_running && m_monitor == monitor && !g_pSessionLockManager->isSessionLocked(); }
    void heartbeat() { m_heartbeat = Clock::now(); }
    Json takeInput() { auto input = m_input; m_input = Json::object(); return input; }
    static Json geometry() {
        Json result = Json::object();
        for (const auto& w : Desktop::windowState()->windows()) {
            if (!w->mapped()) continue;
            const auto pos = w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT) + w->presentation().floatingOffset();
            const auto size = w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            auto rect = encode({pos, size});
            const auto ext = w->getWindowExtentsUnified(Desktop::View::INPUT_EXTENTS | Desktop::View::RESERVED_EXTENTS);
            rect["extents"] = {{"left", ext.topLeft.x}, {"top", ext.topLeft.y}, {"right", ext.bottomRight.x}, {"bottom", ext.bottomRight.y}};
            result[std::format("0x{:x}", reinterpret_cast<uintptr_t>(w.get()))] = rect;
        }
        return result;
    }

    void update(const Json& data) {
        PHLMONITOR monitor;
        for (const auto& m : State::monitorState()->monitors()) if (m->m_name == data.at("monitor").get<std::string>()) monitor = m;
        if (!monitor || g_pSessionLockManager->isSessionLocked()) return;
        const bool fresh = !m_running || m_closing || m_monitor != monitor;
        if (fresh) reset();
        m_monitor = monitor;
        m_stacking = data.value("mode", "scrolling") == "stacking";
        m_selected = data.value("selected", ""); m_workspace = data.value("workspace", int64_t{1});
        const auto wallpaper = data.value("wallpaper", "");
        if (wallpaper != m_wallpaper) { m_wallpaper = wallpaper; m_backgroundDirty = true; }
        const auto colour = data.value("colour", Json::array({0.5, 0.6, 0.9}));
        m_colour = CHyprColor(colour[0].get<float>(), colour[1].get<float>(), colour[2].get<float>(), 1);
        if (fresh) {
            m_home = camera(data.value("originCamera", Json::object()));
            m_cameraFrom = m_cameraTo = m_home;
            m_started = m_cameraStarted = Clock::now(); m_duration = .28;
            m_originalWorkspace = data.value("originalWorkspace", m_workspace);


            m_running = true; m_closing = false;
        }
        heartbeat();
        const auto nextCamera = camera(data.value("camera", Json::object()));
        if (!m_stacking && !(m_cameraTo == nextCamera)) {
            m_cameraFrom = currentCamera(); m_cameraTo = nextCamera; m_cameraStarted = Clock::now();
        }
        m_rows.clear();
        for (const auto& row : data.value("worldRows", Json::array()))
            m_rows.push_back({row.at("workspace"), box(row), {row.value("originX", 0.0), row.value("originY", row.value("y", 0.0))}});
        std::vector<Window> next;
        for (const auto& entry : data.at("windows")) {
            PHLWINDOW window;
            const auto address = entry.at("address").get<std::string>(), identity = entry.at("identity").get<std::string>();
            for (const auto& w : Desktop::windowState()->windows())
                if (w->mapped() && std::format("0x{:x}", reinterpret_cast<uintptr_t>(w.get())) == address && std::format("{:x}", w->metadata().stableID()) == identity) { window = w; break; }
            if (!window) continue;
            auto previous = std::ranges::find_if(m_windows, [&](const auto& w) { return w.address == address && w.identity == identity; });
            const CBox destination = box(entry.at("frame"));
            Window state;
            if (previous != m_windows.end()) state = *previous;
            else {
                state.window = window; state.address = address; state.identity = identity;
                state.original = entry.value("workspace", int64_t{0}) == m_originalWorkspace && !entry.value("minimized", false);
                state.from = nativeBox(window, false); state.to = destination; state.start = Clock::now();
                state.world = state.worldFrom = box(entry.at("world")); state.worldStart = Clock::now();
            }
            state.workspace = entry.value("workspace", int64_t{0});
            const auto nextWorld = box(entry.at("world"));
            if (!sameBox(state.world, nextWorld)) {
                state.worldFrom = worldFrame(state); state.world = nextWorld; state.worldStart = Clock::now();
            }
            if (m_stacking && (std::abs(state.to.x-destination.x) > .5 || std::abs(state.to.y-destination.y) > .5 || std::abs(state.to.w-destination.w) > .5 || std::abs(state.to.h-destination.h) > .5)) {
                state.from = frame(state); state.to = destination; state.start = Clock::now();
            }
            next.push_back(state);
        }
        m_windows = std::move(next);
        m_timer->updateTimeout(std::chrono::milliseconds(1));
        g_pHyprRenderer->damageMonitor(monitor);
    }

    void close(bool accept) {
        if (!m_running || m_closing) return;
        const auto monitor = m_monitor.lock(); if (!monitor) { reset(); return; }
        const auto renderedCamera = currentCamera();
        if (accept) {
            // Focus has already calculated the destination viewport. Finish its
            // underlying layout animation behind the overview so the single
            // overview camera can meet the exact desktop geometry at its end.
            for (const auto& state : m_windows) if (valid(state)) {
                const auto w = state.window.lock();
                w->positionAnimation()->setValueAndWarp(w->positionAnimation()->goal());
                w->sizeAnimation()->setValueAndWarp(w->sizeAnimation()->goal());
                w->presentation().updateDecorations();
            }
            // Outgoing workspace fades/slides must also have ended at handoff.
            for (const auto& weak : State::workspaceState()->workspaces()) {
                const auto ws = weak.lock();
                if (!ws || ws->m_monitor != monitor) continue;
                ws->m_renderOffset->setValueAndWarp(ws->m_renderOffset->goal());
                ws->m_alpha->setValueAndWarp(ws->m_alpha->goal());
            }
        }
        m_cameraFrom = renderedCamera; m_cameraTo = m_home;
        if (accept && !m_stacking) {
            const auto selected = std::ranges::find_if(m_windows, [&](const auto& w) { return w.address == m_selected; });
            const auto row = std::ranges::find_if(m_rows, [&](const auto& r) { return r.workspace == m_workspace; });
            m_cameraTo.y = row != m_rows.end() ? -row->origin.y : m_home.y;
            m_cameraTo.x = row != m_rows.end() ? -row->origin.x : m_home.x;
            m_cameraTo.zoom = 1;
            if (selected != m_windows.end() && valid(*selected)) {
                const auto destination = nativeBox(selected->window.lock(), true);
                m_cameraTo.x = destination.x - selected->world.x;
                m_cameraTo.y = destination.y - selected->world.y;
            }
        }
        for (auto& state : m_windows) {
            const auto window = state.window.lock(); if (!valid(state)) continue;
            state.from = frame(state, &renderedCamera); state.to = nativeBox(window, true); state.start = Clock::now();
            state.original = window->m_workspace == monitor->m_activeWorkspace && !window->isHidden();
        }
        m_closing = true; m_started = m_cameraStarted = Clock::now();
        m_timer->updateTimeout(std::chrono::milliseconds(1));
    }

    Json status() const {
        Json result = {{"active", m_running && !m_closing}, {"closing", m_closing}, {"renderer", "native"}, {"frames", Json::array()}};
        if (!m_running) return result;
        const auto cam = currentCamera();
        result["camera"] = {{"x", cam.x}, {"y", cam.y}, {"zoom", cam.zoom}};
        result["progress"] = phase();
        result["wallpaper"] = m_wallpaper;
        result["backgroundBlurred"] = m_background && !m_backgroundDirty;
        result["backgroundBlur"] = "gaussian";
        result["backgroundError"] = m_blur.error();
        result["rows"] = Json::array();
        result["closingWindows"] = Json::array();
        for (const auto& closed : m_closed) {
            auto rect = encode(closedFrame(closed, cam)); rect["address"] = closed.address;
            rect["alpha"] = closedAlpha(closed); rect["hasContent"] = static_cast<bool>(closed.snapshot);
            result["closingWindows"].push_back(rect);
        }
        for (const auto& row : m_rows) { auto rect = encode(row.world); rect["workspace"] = row.workspace; result["rows"].push_back(rect); }
        for (const auto& window : m_windows) if (valid(window)) {
            auto rect = encode(frame(window, &cam)); rect["address"] = window.address;
            rect["visual"] = encode(visualFrame(window, &cam));
            rect["hasContent"] = window.window->wlSurface() && window.window->wlSurface()->resource() && window.window->wlSurface()->resource()->m_current.texture;
            result["frames"].push_back(rect);
        }
        return result;
    }

    void render(Render::IHyprRenderer* renderer, PHLMONITOR monitor, const Time::steady_tp& now) {
        renderer->context().m_data.noSimplify = true;
        const auto renderCamera = currentCamera();
        watchBackground(monitor);
        renderBackground(renderer, renderer->context(), monitor);
        const auto layers = [&](int layer) {
            for (const auto& weak : monitor->m_layerSurfaceLayers[layer]) renderLayer(renderer, renderer->context(), weak.lock(), monitor, now, false, false, false);
        };
        // One full-screen wallpaper joins every workspace seamlessly. Only the
        // windows belong to the ribbon; there are no separate wallpaper cards.
        layers(ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND);
        renderer->addPassElement(g_pHyprRenderer->context(), makeUnique<BackgroundPass>([this] { return backgroundPass(); }));
        layers(ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM);
        std::erase_if(m_closed, [&](const auto& w) { return closedAlpha(w) <= 0; });
        // Preserve native stacking order during the transition. Grid windows
        // do not overlap once settled, and tiled columns share one camera.
        size_t zIndex = 0, closedIndex = 0;
        for (const auto& real : Desktop::windowState()->windows()) {
            while (closedIndex < m_closed.size() && m_closed[closedIndex].zIndex <= zIndex)
                closedPass(renderer, m_closed[closedIndex++], renderCamera, monitor);
            ++zIndex;
            const auto state = std::ranges::find_if(m_windows, [&](const auto& w) { return w.window == real; });
            if (state == m_windows.end() || !valid(*state)) continue;
            const auto destination = frame(*state, &renderCamera), source = nativeBox(real, false);
            if (destination.x+destination.w < 0 || destination.y+destination.h < 0 || destination.x > monitor->m_size.x || destination.y > monitor->m_size.y) continue;
            const double scale = destination.w / std::max(1.0, source.w);
            const auto wsOffset = real->m_workspace && !(real->m_state & Desktop::View::WINDOW_STATE_PINNED) ? real->m_workspace->m_renderOffset->value() : Vector2D{};
            hints(renderer, scale, destination.pos() - (source.pos()+wsOffset)*scale, monitor);
            const float opacity = m_closing && !state->original ? 1-phase() : m_stacking && !state->original ? phase() : 1;
            windowPass(renderer, real, monitor, now, opacity);
            hints(renderer, 1, {}, monitor);
            if (state->address == m_selected && acceptsInput()) outline(renderer, *state, renderCamera, monitor);
        }
        while (closedIndex < m_closed.size()) closedPass(renderer, m_closed[closedIndex++], renderCamera, monitor);
        layers(ZWLR_LAYER_SHELL_V1_LAYER_TOP); layers(ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY);
    }

  private:
    static bool valid(const Window& state) { return state.window && state.window->mapped() && std::format("{:x}", state.window->metadata().stableID()) == state.identity; }
    static bool sameBox(CBox a, CBox b) { return std::abs(a.x-b.x)<.5 && std::abs(a.y-b.y)<.5 && std::abs(a.w-b.w)<.5 && std::abs(a.h-b.h)<.5; }
    bool acceptsInput() const { return m_running && !m_closing && !g_pSessionLockManager->isSessionLocked(); }
    bool contains(Vector2D point) const { const auto m=m_monitor.lock(); return m && CBox{m->m_position, m->m_size}.containsPoint(point); }
    static void dispatch(const std::string& action) { Config::Actions::global("hyprstack:"+action); }
    double phase() const { return ease(std::chrono::duration<double>(Clock::now()-m_started).count()/m_duration); }
    static double ease(double t) { t=std::clamp(t,0.0,1.0); return 1-std::pow(1-t,3); }
    Camera currentCamera() const { return mix(m_cameraFrom,m_cameraTo,ease(std::chrono::duration<double>(Clock::now()-m_cameraStarted).count()/m_duration)); }
    CBox project(CBox b, const Camera* fixed = nullptr) const { const auto c=fixed ? *fixed : currentCamera(); return {{c.x+b.x*c.zoom,c.y+b.y*c.zoom}, b.size()*c.zoom}; }
    CBox worldFrame(const Window& w) const { return mix(w.worldFrom,w.world,ease(std::chrono::duration<double>(Clock::now()-w.worldStart).count()/m_duration)); }
    CBox frame(const Window& w, const Camera* fixed = nullptr) const {
        // Tiling keeps one rigid world during both entry and exit. Sending
        // every hidden workspace to its native (same-screen) rectangle on exit
        // made those windows cross the selected row and flash over it.
        return m_stacking ? mix(w.from,w.to,ease(std::chrono::duration<double>(Clock::now()-w.start).count()/m_duration)) : project(worldFrame(w), fixed);
    }
    static float closedAlpha(const ClosedWindow& w) {
        const double t = std::clamp(std::chrono::duration<double>(Clock::now()-w.start).count()/.2,0.0,1.0);
        return 1-t*t*(3-2*t);
    }
    CBox closedFrame(const ClosedWindow& w, const Camera& cam) const {
        if (m_stacking) return w.frame;
        const double scale = cam.zoom / w.camera.zoom;
        return {w.frame.pos()*scale + Vector2D{cam.x-w.camera.x*scale,cam.y-w.camera.y*scale},w.frame.size()*scale};
    }
    void closedPass(Render::IHyprRenderer* r, const ClosedWindow& w, const Camera& cam, PHLMONITOR monitor) const {
        CTexPassElement::SRenderData data;
        data.tex = w.snapshot->getTexture(); data.a = closedAlpha(w);
        const double scale = m_stacking ? 1 : cam.zoom / w.camera.zoom;
        data.box = CBox{{},monitor->m_transformedSize}.scale(scale);
        if (!m_stacking) data.box.translate(Vector2D{cam.x-w.camera.x*scale,cam.y-w.camera.y*scale}*monitor->m_scale);
        r->addPassElement(g_pHyprRenderer->context(), makeUnique<CTexPassElement>(data));
    }
    void captureClosingWindow(PHLWINDOW window) {
        const auto monitor = m_monitor.lock();
        if (!m_running || m_closing || !monitor || g_pSessionLockManager->isSessionLocked()) return;
        const auto state = std::ranges::find_if(m_windows, [&](const auto& w) { return w.window == window && valid(w); });
        if (state == m_windows.end() || !window->wlSurface() || !window->wlSurface()->resource()) return;
        const auto cam = currentCamera();
        const auto source = nativeBox(window, false), destination = frame(*state, &cam);
        if (destination.intersection(CBox{{},monitor->m_size}).empty()) return;
        auto* r = g_pHyprRenderer.get();
        auto snapshot = r->createFB("Overview closing window");
        if (!snapshot || !snapshot->alloc(monitor->m_pixelSize.x,monitor->m_pixelSize.y,DRM_FORMAT_ABGR16161616F)) return;
        snapshot->setImageDescription(monitor->workBufferImageDescription());
        snapshot->getTexture()->m_transform = Math::wlTransformToHyprutils(Math::invertTransform(monitor->m_transform));
        CRegion damage{CBox{{},monitor->m_transformedSize}};
        if (!r->beginFullFakeRender(monitor,damage,snapshot)) return;
        const bool oldSnapshot = r->context().m_renderingSnapshot;
        r->context().m_renderingSnapshot = true;
        r->draw(g_pHyprRenderer->context(), CClearPassElement::SClearData{CHyprColor(0,0,0,0)});
        r->startRenderPass(r->context());
        const auto wsOffset = window->m_workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED) ? window->m_workspace->m_renderOffset->value() : Vector2D{};
        const double scale = destination.w / std::max(1.0,source.w);
        hints(r,scale,destination.pos()-(source.pos()+wsOffset)*scale,monitor);
        windowPass(r,window,monitor,Time::steadyNow(),1);
        hints(r,1,{},monitor);
        r->endRender(); r->context().m_renderingSnapshot = oldSnapshot;
        const auto& windows = Desktop::windowState()->windows();
        const auto position = std::ranges::find(windows,window);
        m_closed.push_back({state->address,snapshot,destination,cam,Clock::now(),static_cast<size_t>(std::distance(windows.begin(),position))});
        std::ranges::stable_sort(m_closed,{},&ClosedWindow::zIndex);
        g_pHyprRenderer->damageMonitor(monitor);
    }
    CBox visualFrame(const Window& state, const Camera* fixed = nullptr) const {
        auto result = frame(state, fixed);
        const auto window = state.window.lock();
        const auto source = nativeBox(window, false);
        const double scale = result.w / std::max(1.0, source.w);
        const auto extents = window->getWindowExtentsUnified(Desktop::View::INPUT_EXTENTS | Desktop::View::RESERVED_EXTENTS);
        result.addExtents({extents.topLeft * scale, extents.bottomRight * scale});
        return result;
    }
    CBox nativeBox(PHLWINDOW w, bool goal) const {
        const auto monitor=m_monitor.lock();
        return { (goal ? w->positionAnimation()->goal() : w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT)) + w->presentation().floatingOffset() - monitor->m_position,
            goal ? w->sizeAnimation()->goal() : w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) };
    }
    static void hints(Render::IHyprRenderer* r, double scale, Vector2D translation, PHLMONITOR monitor) {
        Render::SRenderModifData transform;
        if (std::abs(scale-1) > .00001) transform.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, static_cast<float>(scale));
        if (translation != Vector2D{}) transform.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, translation*monitor->m_scale);
        r->addPassElement(g_pHyprRenderer->context(), makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{transform}));
    }
    void watchBackground(PHLMONITOR monitor) {
        std::vector<SP<CWLSurfaceResource>> sources;
        for (const auto& weak : monitor->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND]) {
            const auto layer = weak.lock();
            if (!layer || !layer->mapped() || !layer->wlSurface()) continue;
            const auto surface = layer->wlSurface()->resource();
            if (surface) sources.push_back(surface);
        }
        if (sources.size() == m_backgroundSources.size() && std::equal(sources.begin(), sources.end(), m_backgroundSources.begin(),
            [](const auto& a, const auto& b) { return a == b.lock(); })) return;
        m_backgroundCommits.clear(); m_backgroundSources.clear();
        m_backgroundDirty = true;
        for (const auto& surface : sources) {
            m_backgroundSources.push_back(surface);
            m_backgroundCommits.push_back(surface->m_events.commit.listen([this] {
                m_backgroundDirty = true;
                if (const auto monitor = m_monitor.lock()) g_pHyprRenderer->damageMonitor(monitor);
            }));
        }
    }
    std::vector<UP<IPassElement>> backgroundPass() {
        std::vector<UP<IPassElement>> elements;
        const auto monitor = m_monitor.lock();
        if (!m_running || !monitor) return elements;
        auto* r = g_pHyprRenderer.get();
        const auto target = r->context().m_data.currentFB;
        if (!target) return elements;
        const CBox canvas{{}, monitor->m_transformedSize};
        if (!m_background || m_background->m_size != target->m_size || m_background->imageDescription() != target->imageDescription()) m_backgroundDirty = true;
        if (m_backgroundDirty) {
            m_background = m_blur.render(target, 48.0 * monitor->m_scale);
            if (!m_background) return elements;
            m_backgroundDirty = false;
        }
        CTexPassElement::SRenderData texture;
        texture.tex = m_background->getTexture(); texture.box = canvas;
        // The Gaussian preserves raw framebuffer coordinates. Undo the output
        // rotation when sampling it back through the compositor's projection.
        texture.tex->m_transform = Math::wlTransformToHyprutils(Math::invertTransform(monitor->m_transform));
        texture.a = m_closing ? 1-phase() : phase();
        elements.push_back(makeUnique<CTexPassElement>(texture));
        return elements;
    }
    void outline(Render::IHyprRenderer* r, const Window& state, const Camera& cam, PHLMONITOR monitor) const {
        const auto window = state.window.lock();
        const auto b = visualFrame(state, &cam);
        const double scale = frame(state, &cam).w / std::max(1.0, nativeBox(window, false).w);
        const double p = m_stacking ? phase() : std::clamp((1-currentCamera().zoom)/.6,0.0,1.0);
        auto colour=m_colour; colour.a=static_cast<float>(p*.8);
        CBorderPassElement::SBorderData border;
        border.box = b.copy().scale(monitor->m_scale);
        border.grad1 = Config::CGradientValueData(colour);
        border.borderSize = 2;
        border.round = std::round(std::max(12.0, static_cast<double>(window->presentation().rounding())) * scale * monitor->m_scale);
        border.roundingPower = window->presentation().roundingPower();
        r->addPassElement(g_pHyprRenderer->context(), makeUnique<CBorderPassElement>(border));
    }
    static void windowPass(Render::IHyprRenderer* r, PHLWINDOW window, PHLMONITOR monitor, const Time::steady_tp& now, float opacity) {
        const auto surface=window->wlSurface(); if (!surface || !surface->resource()) return;
        const auto offset=window->m_workspace && !(window->m_state & Desktop::View::WINDOW_STATE_PINNED) ? window->m_workspace->m_renderOffset->value() : Vector2D{};
        CSurfacePassElement::SRenderData data{monitor,now};
        data.pos=window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT)+window->presentation().floatingOffset()+offset;
        const auto size=window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
        data.w=std::max(1.0,size.x); data.h=std::max(1.0,size.y); data.pWindow=window;
        data.alpha=window->presentation().alphaValue(Desktop::View::WINDOW_ALPHA_ACTIVE); data.fadeAlpha=opacity;
        data.workspacePresentation=window->presentation().renderPresentation();
        data.workspacePresentation.workspaceAlpha=1; data.workspacePresentation.fadeAlpha=opacity; data.workspacePresentation.alphaVisible=true;
        data.dontRound=false; data.rounding=std::round(window->presentation().rounding()*monitor->m_scale); data.roundingPower=window->presentation().roundingPower();
        // Overview opacity is independent of hidden-workspace/fullscreen alpha.
        // Keep actual subsurfaces, native CSD geometry and compositor decorations.
        r->context().m_data.currentWindow=window;
        // Decorations read native animated geometry during this stage too.
        Event::bus()->m_events.render.stage.emit({RENDER_PRE_WINDOW, monitor, r->context()});
        g_pDecorationPositioner->onWindowUpdate(window);
        const bool decorate=!window->backend().traits().suggestsNoBorder;
        if (decorate) for (const auto& deco:window->presentation().decorations())
            if (deco->getDecorationLayer()==DECORATION_LAYER_BOTTOM || deco->getDecorationLayer()==DECORATION_LAYER_UNDER) deco->draw(r->context(),monitor,opacity,data.workspacePresentation);
        surface->resource()->breadthfirst([&](SP<CWLSurfaceResource> child,const Vector2D& local,void*) {
            if (!child->m_current.texture || child->m_current.size.x<1 || child->m_current.size.y<1) return;
            data.surface=child; data.texture=child->m_current.texture; data.localPos=local; data.mainSurface=child==surface->resource();
            r->addPassElement(g_pHyprRenderer->context(), makeUnique<CSurfacePassElement>(data));
            child->frame(now);
        },nullptr);
        if (decorate) for (const auto& deco:window->presentation().decorations())
            if (deco->getDecorationLayer()==DECORATION_LAYER_OVER) deco->draw(r->context(),monitor,opacity,data.workspacePresentation);
        Event::bus()->m_events.render.stage.emit({RENDER_POST_WINDOW, monitor, r->context()});
        r->context().m_data.currentWindow.reset();
    }

    PHLMONITORREF m_monitor;
    bool m_running=false,m_closing=false,m_stacking=false;
    int64_t m_workspace=1,m_originalWorkspace=1;
    std::string m_selected;
    std::vector<Window> m_windows;
    std::vector<ClosedWindow> m_closed;
    std::vector<Row> m_rows;
    Camera m_home,m_cameraFrom,m_cameraTo;
    CHyprColor m_colour;
    std::string m_wallpaper;
    SP<Render::IFramebuffer> m_background;
    WallpaperBlur m_blur;
    bool m_backgroundDirty = true;
    std::vector<WP<CWLSurfaceResource>> m_backgroundSources;
    std::vector<CHyprSignalListener> m_backgroundCommits;
    Clock::time_point m_started,m_cameraStarted,m_heartbeat;
    double m_duration=.28;
    Json m_input=Json::object();
    std::set<uint32_t> m_keys,m_buttons;
    SP<CEventLoopTimer> m_timer;
    CHyprSignalListener m_key,m_move,m_button,m_axis,m_render,m_unmap,m_swipeBegin,m_swipeUpdate,m_swipeEnd;
    bool m_swipeOwned = false;
    Vector2D m_swipeDelta;
};
static UP<Scene> scene;
using RectDraw = void (*)(Render::GL::CHyprOpenGLImpl*, Render::CRenderContext&, const CBox&, const CHyprColor&, Render::GL::CHyprOpenGLImpl::SRectRenderData);
static void drawSceneRect(Render::GL::CHyprOpenGLImpl* renderer, Render::CRenderContext& ctx, const CBox& source, const CHyprColor& colour,
    Render::GL::CHyprOpenGLImpl::SRectRenderData data) {
    auto& render = g_pHyprRenderer->context().m_data;
    const auto original = reinterpret_cast<RectDraw>(rectHook->m_original);
    if (!scene || !scene->runningFor(render.pMonitor.lock()) || render.renderModif.modifs.empty()) {
        original(renderer, ctx, source, colour, data); return;
    }
    // The pinned GL rectangle path transforms its geometry but leaves rounded
    // corner/stencil uniforms in source coordinates. A scaled titlebar then
    // disappears partly or entirely. Bake both into the same output space.
    auto transform = render.renderModif;
    const auto clip = render.clipBox;
    Hyprutils::Utils::CScopeGuard restore([&] { render.renderModif = transform; render.clipBox = clip; });
    auto destination = source;
    transform.applyToBox(destination);
    if (!render.clipBox.empty()) transform.applyToBox(render.clipBox);
    data.round = std::round(data.round * transform.combinedScale());
    data.damage = &render.damage;
    render.renderModif = {};
    original(renderer, ctx, destination, colour, data);
}
using TextureDraw = void (*)(Render::IElementRenderer*, Render::CRenderContext&, WP<CTexPassElement>, const CRegion&);
static void drawSceneTexture(Render::IElementRenderer* renderer, Render::CRenderContext& ctx, WP<CTexPassElement> element, const CRegion& damage) {
    auto& render = g_pHyprRenderer->context().m_data;
    const auto original = reinterpret_cast<TextureDraw>(textureHook->m_original);
    if (!element || !scene || !scene->runningFor(render.pMonitor.lock()) || render.renderModif.modifs.empty()) {
        original(renderer, ctx, element, damage); return;
    }
    // drawSurface intersects damage with its *source* box before drawTex.
    // Offscreen scrolling columns consequently get clipped even though their
    // transformed box is visible. Bake the same camera into texture geometry
    // and clips, then draw against the real output damage. No client is resized.
    const auto saved = element->m_data;
    const auto transform = render.renderModif;
    const auto clip = render.clipBox;
    Hyprutils::Utils::CScopeGuard restore([&] {
        render.renderModif = transform;
        render.clipBox = clip;
        element->m_data = saved;
    });
    render.renderModif.applyToBox(element->m_data.box);
    render.renderModif.applyToRegion(element->m_data.clipRegion);
    element->m_data.round = std::round(element->m_data.round * render.renderModif.combinedScale());
    element->m_data.damage = render.damage;
    if (!render.clipBox.empty()) render.renderModif.applyToBox(render.clipBox);
    render.renderModif = {};
    original(renderer, ctx, element, render.damage);
}
static void renderScene(Render::IHyprRenderer* renderer, Render::CRenderContext& ctx, PHLMONITOR monitor, PHLWORKSPACE workspace,
    const Time::steady_tp& now, Render::eSceneMode mode, const Vector2D& translate, const float& scale) {
    if (mode == Render::eSceneMode::MONITOR && scene && scene->runningFor(monitor)) scene->render(renderer,monitor,now);
    else reinterpret_cast<WorkspaceRender>(renderHook->m_original)(renderer,ctx,monitor,workspace,now,mode,translate,scale);
}
static void renderSceneFadeouts(Render::IHyprRenderer* renderer, Render::CRenderContext& ctx, PHLMONITOR monitor, Desktop::eFadeoutPlane plane, PHLWORKSPACE workspace) {
    // Closing previews already own their last transformed frame. Rendering the
    // ordinary desktop fade too would flash a second image at native size.
    if (scene && scene->runningFor(monitor) && (plane == Desktop::FADEOUT_PLANE_WINDOW_TILED ||
        plane == Desktop::FADEOUT_PLANE_WINDOW_FLOATING || plane == Desktop::FADEOUT_PLANE_WINDOW_OVER_FULLSCREEN)) return;
    reinterpret_cast<FadeoutRender>(fadeoutHook->m_original)(renderer,ctx,monitor,plane,workspace);
}
using CanScanout = bool (*)(const Monitor::CMonitor*);
static bool canScanout(const Monitor::CMonitor* monitor) {
    if (scene && monitor && scene->runningFor(monitor->m_self.lock())) return false;
    return reinterpret_cast<CanScanout>(scanoutHook->m_original)(monitor);
}
static int luaScene(lua_State* L) {
    const std::string action=luaL_checkstring(L,1);
    try {
        if (action=="show") scene->update(Json::parse(luaL_checkstring(L,2)));
        else if (action=="close") scene->close(lua_toboolean(L,2));
        else if (action=="reset") scene->reset();
        else if (action=="heartbeat") scene->heartbeat();
        else if (action=="status" || action=="input" || action=="geometry") {
            const auto value=(action=="status" ? scene->status() : action=="geometry" ? Scene::geometry() : scene->takeInput()).dump();
            lua_pushlstring(L,value.data(),value.size()); return 1;
        }
        lua_pushboolean(L,true); return 1;
    } catch (const std::exception& e) { return luaL_error(L,"Hyprstack overview: %s",e.what()); }
}
static void remove(HANDLE handle) {
    HyprstackTileFrame::remove(handle);
    g_pHyprRenderer->context().m_pass.removeAllOfType("HyprstackOverviewBackground");
    scene.reset();
    if (scanoutHook) HyprlandAPI::removeFunctionHook(handle,scanoutHook);
    scanoutHook=nullptr;
    HyprstackCamera::remove();
    if (fadeoutHook) HyprlandAPI::removeFunctionHook(handle,fadeoutHook);
    fadeoutHook=nullptr;
    if (rectHook) HyprlandAPI::removeFunctionHook(handle,rectHook);
    rectHook=nullptr;
    if (textureHook) HyprlandAPI::removeFunctionHook(handle,textureHook);
    textureHook=nullptr;
    if (renderHook) HyprlandAPI::removeFunctionHook(handle,renderHook);
    renderHook=nullptr;
}
static void install(HANDLE handle) {
    const auto function=[&](const char* name,const char* prefix) -> void* {
        const auto matches=HyprlandAPI::findFunctionsByName(handle,name);
        const auto found=std::ranges::find_if(matches,[&](const auto& f){return f.demangled.starts_with(prefix) && (std::string(name) != "renderAllClientsForWorkspace" || f.demangled.contains("eSceneMode"));});
        if (found==matches.end()) throw std::runtime_error(std::string("[hyprstack] Missing pinned overview function ")+name);
        return found->address;
    };
    try {
        renderLayer=reinterpret_cast<LayerRender>(function("renderLayer","Render::IHyprRenderer::renderLayer("));
        renderBackground=reinterpret_cast<BackgroundRender>(function("renderBackground","Render::IHyprRenderer::renderBackground("));
        renderHook=HyprlandAPI::createFunctionHook(handle,function("renderAllClientsForWorkspace","Render::IHyprRenderer::renderAllClientsForWorkspace("),reinterpret_cast<void*>(&renderScene));
        if (!renderHook || !renderHook->hook()) throw std::runtime_error("[hyprstack] Cannot hook the pinned overview renderer");
        textureHook=HyprlandAPI::createFunctionHook(handle,function("drawTex","Render::IElementRenderer::drawTex("),reinterpret_cast<void*>(&drawSceneTexture));
        if (!textureHook || !textureHook->hook()) throw std::runtime_error("[hyprstack] Cannot hook overview texture clipping");
        rectHook=HyprlandAPI::createFunctionHook(handle,function("renderRect","Render::GL::CHyprOpenGLImpl::renderRect("),reinterpret_cast<void*>(&drawSceneRect));
        if (!rectHook || !rectHook->hook()) throw std::runtime_error("[hyprstack] Cannot hook overview decoration rounding");
        fadeoutHook=HyprlandAPI::createFunctionHook(handle,function("renderFadeouts","Render::IHyprRenderer::renderFadeouts("),reinterpret_cast<void*>(&renderSceneFadeouts));
        if (!fadeoutHook || !fadeoutHook->hook()) throw std::runtime_error("[hyprstack] Cannot hook overview window fadeouts");
        scanoutHook=HyprlandAPI::createFunctionHook(handle,function("canAttemptDirectScanoutFast","Monitor::CMonitor::canAttemptDirectScanoutFast("),reinterpret_cast<void*>(&canScanout));
        if (!scanoutHook || !scanoutHook->hook()) throw std::runtime_error("[hyprstack] Cannot block overview direct scanout");
        scene=makeUnique<Scene>();
        HyprstackCamera::install(handle);
        HyprstackTileFrame::install(handle);
        HyprlandAPI::addLuaFunction(handle,"hyprbars","overview_scene",luaScene);
    } catch (...) { remove(handle); throw; }
}
} // namespace HyprstackOverview

// The native titlebar's explicit scissor must use the same camera transform as
// its drawing primitives. This is evaluated when the render pass is executed.
bool hyprstackOverviewRendering() {
    return HyprstackOverview::scene && HyprstackOverview::scene->runningFor(g_pHyprRenderer->context().m_data.pMonitor.lock());
}
