// Hyprland 0.57 leaves xdg window-geometry cropping disabled. Respect a
// client's shadow margins and scale the complete image during geometry tweens.
#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/render/ElementRenderer.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/Popup.hpp>
#include <hyprland/src/desktop/view/Subsurface.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/core/Subcompositor.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include "globals.hpp"
#include "titlebar-actions.hpp"
#include <algorithm>
#include <optional>
#include <stdexcept>
#include <type_traits>

static CFunctionHook* clientSurfaceUVHook = nullptr;
static CFunctionHook* clientSurfacePassHook = nullptr;
static CFunctionHook* clientSurfaceInputHook = nullptr;
static CFunctionHook* clientPointerMotionHook = nullptr;
static CFunctionHook* clientStateHook = nullptr;
static CFunctionHook* clientTextureBoxHook = nullptr;
static CFunctionHook* clientMinSizeHook = nullptr;
static CFunctionHook* clientMaxSizeHook = nullptr;
static CFunctionHook* clientDamageHook = nullptr;
static CFunctionHook* clientSubsurfacePositionHook = nullptr;

// xdg_toplevel size limits already use window-geometry coordinates. Adding
// geometry.pos() (the client's shadow offset) makes fixed-size Qt windows
// grow on every configure/commit round trip in Hyprland 0.56.2.
static Vector2D clientMinSize(CXDGToplevelResource* toplevel) {
    return toplevel->m_current.minSize;
}

static Vector2D clientMaxSize(CXDGToplevelResource* toplevel) {
    return toplevel->m_current.maxSize;
}

static CBox clientGeometry(PHLWINDOW window, SP<CWLSurfaceResource> surface) {
    const auto geometry = window->backend().geometry().box;
    // xdg_surface.set_window_geometry is optional. Its default is the whole
    // surface; an unset rectangle must not disable fitting a delayed buffer.
    return geometry.w > 0 && geometry.h > 0 ? geometry : CBox{{}, surface->m_current.size};
}

// 0.57 passes the surface's current box to limit damage. Dropping this
// argument forwards an invalid optional to the compositor and leaves stale
// client pixels even while layer surfaces continue to update normally.
static_assert(std::is_same_v<decltype(&Desktop::View::CWLSurface::computeDamage),
    CRegion (Desktop::View::CWLSurface::*)(const std::optional<CBox>&) const>);
using ClientDamageFunction = CRegion (*)(const Desktop::View::CWLSurface*, const std::optional<CBox>&);
static CRegion clientSurfaceDamage(const Desktop::View::CWLSurface* wlSurface, const std::optional<CBox>& box) {
    const auto original = reinterpret_cast<ClientDamageFunction>(clientDamageHook->m_original);
    const auto window = Desktop::View::CWindow::fromView(wlSurface->view());
    const auto surface = wlSurface->resource();
    if (!window || !surface || window->backend().isX11() || !surface->m_current.texture)
        return original(wlSurface, box);
    auto& state = surface->m_current;
    const auto geometry = clientGeometry(window, surface);
    const auto target = window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    if (state.size.x <= 0 || state.size.y <= 0 || state.bufferSize.x <= 0 || state.bufferSize.y <= 0 ||
        geometry.w <= 0 || geometry.h <= 0 || geometry.x < 0 || geometry.y < 0 || target.x <= 0 || target.y <= 0)
        return original(wlSurface, box);
    const bool fitted = !window->isFloating() && !g_pGlobalState->config.enabled->value() && geometry.size() != target;
    if (geometry.pos() == Vector2D{} && geometry.size() == state.size && !fitted && !window->sizeAnimation()->isBeingAnimated())
        return original(wlSurface, box);

    // Invert the same UV crop used by clientSurfaceUV. Translating an already
    // clipped computeDamage() loses the right/bottom strips; leaving it alone
    // misses the left/top strips on every partial video frame with CSD margins.
    const auto crop = geometry.intersection(CBox{{}, state.size});
    const auto source = state.viewport.hasSource ? state.viewport.source : CBox{{}, state.bufferSize};
    if (crop.empty() || source.empty()) return original(wlSurface, box);
    auto damage = state.accumulateBufferDamage();
    damage.transform(Math::wlTransformToHyprutils(state.transform), state.bufferSize.x, state.bufferSize.y);
    damage.intersect(source).translate(-source.pos()).scale(state.size / source.size());
    damage.intersect(crop).translate(-crop.pos()).scale(target / crop.size());
    // Outward rounding covers bilinear samples at fractional output scales.
    return damage.expand(1).intersect(CBox{{}, target});
}

using SubsurfacePositionFunction = Vector2D (*)(const Desktop::View::CSubsurface*);
static Vector2D clientSubsurfacePosition(const Desktop::View::CSubsurface* subsurface) {
    const auto position = reinterpret_cast<SubsurfacePositionFunction>(clientSubsurfacePositionHook->m_original)(subsurface);
    const auto surface = subsurface->resource();
    const auto role = surface ? dynamicPointerCast<CSubsurfaceRole>(surface->m_role) : nullptr;
    const auto resource = role ? role->m_subsurface.lock() : nullptr;
    const auto parent = resource ? resource->t1Parent() : nullptr;
    const auto owner = Desktop::View::CWLSurface::fromResource(parent);
    const auto window = owner ? Desktop::View::CWindow::fromView(owner->view()) : nullptr;
    if (!window || window->backend().isX11()) return position;
    const auto geometry = clientGeometry(window, parent);
    if (geometry.w <= 0 || geometry.h <= 0 || geometry.x < 0 || geometry.y < 0) return position;
    // Video subsurfaces must publish damage and old/new bounds at the same
    // cropped origin used by clientSurfacePass, including nested subsurfaces.
    auto local = position - window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT) - geometry.pos();
    if (window->sizeAnimation()->isBeingAnimated()) {
        const auto reported = window->backend().reportedSize();
        if (reported.x > 0 && reported.y > 0)
            local = local * (window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) / reported);
    }
    return window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT) + local;
}

using PointerMotionFunction = void (*)(CSeatManager*, uint32_t, const Vector2D&);
static void clientPointerMotion(CSeatManager* seat, uint32_t time, const Vector2D& local) {
    const auto original = reinterpret_cast<PointerMotionFunction>(clientPointerMotionHook->m_original);
    const auto surface = seat->m_state.pointerFocus.lock();
    const auto wlSurface = Desktop::View::CWLSurface::fromResource(surface);
    const auto window = wlSurface ? Desktop::View::CWindow::fromView(wlSurface->view()) : nullptr;
    if (!window || !window->mapped() || window->backend().isX11() ||
        surface != window->resource() || !g_pGlobalState || g_pInputManager->isConstrained())
        return original(seat, time, local);
    const auto geometry = clientGeometry(window, surface);
    const auto target = window->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    const bool fitted = !window->isFloating() && !g_pGlobalState->config.enabled->value() &&
        target.x > 0 && target.y > 0 && geometry.size() != target;
    if (geometry.w <= 0 || geometry.h <= 0 || geometry.x < 0 || geometry.y < 0 ||
        (geometry.pos() == Vector2D{} && !fitted))
        return original(seat, time, local);
    // During a button grab Hyprland bypasses windowSurfaceAt() and subtracts
    // the cropped window box. Keep motion in the same surface coordinates as
    // pointer enter, so even a slight movement cannot cancel a GTK button.
    auto relative = g_pInputManager->getMouseCoordsInternal() - window->position(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    if (fitted) relative = relative * (geometry.size() / target);
    original(seat, time, relative + geometry.pos());
}

using TextureBoxFunction = CBox (*)(CSurfacePassElement*);
static CBox clientTextureBox(CSurfacePassElement* element) {
    const auto original = reinterpret_cast<TextureBoxFunction>(clientTextureBoxHook->m_original)(element);
    const auto& data = element->m_data;
    const auto window = data.pWindow;
    if (!data.mainSurface || !window || window->backend().isX11() ||
        window->isFloating() || g_pGlobalState->config.enabled->value() || data.w <= 0 || data.h <= 0)
        return original;
    // A client may still display its smaller stacking buffer after the final
    // tile configure. Hyprland otherwise shrinks its texture box independently
    // of the window border, leaving desktop gaps at the bottom and right.
    return {data.pos + data.localPos - data.pMonitor->m_position, {data.w, data.h}};
}

using ClientStateFunction = void (*)(Desktop::View::CWindow*, const Desktop::View::SBackendStateRequest&);
static void tiledClientState(Desktop::View::CWindow* window, const Desktop::View::SBackendStateRequest& request) {
    auto filtered = request;
    if (window && window->mapped() && g_pGlobalState) {
        const bool stacking = g_pGlobalState->config.enabled->value();
        if (stacking) {
            if (request.maximized && runDecorationAction(window->m_self.lock(), *request.maximized ? "maximize-set" : "maximize-unset"))
                filtered.maximized.reset();
            if (request.minimized.value_or(false)) runDecorationAction(window->m_self.lock(), "minimize");
        } else if (!window->isFloating()) {
            filtered.maximized.reset();
            filtered.minimized.reset();
            if (request.maximized || request.minimized) window->sendWindowSize(true);
        }
    }
    reinterpret_cast<ClientStateFunction>(clientStateHook->m_original)(window, filtered);
}

using SurfaceInputFunction = SP<CWLSurfaceResource> (*)(const Desktop::CViewHitTester*,
    const Vector2D&, PHLWINDOW, Vector2D&);
static SP<CWLSurfaceResource> clientSurfaceInput(const Desktop::CViewHitTester* tester,
    const Vector2D& point, PHLWINDOW window, Vector2D& local) {
    const auto original = reinterpret_cast<SurfaceInputFunction>(clientSurfaceInputHook->m_original);
    if (!window || !window->mapped() || window->backend().isX11() ||
        (window->hasPopupAt(point)))
        return original(tester, point, window, local);
    const auto surface = window->wlSurface()->resource();
    if (!surface) return original(tester, point, window, local);
    const auto geometry = clientGeometry(window, surface);
    const auto target = window->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    const bool fitted = !window->isFloating() && !g_pGlobalState->config.enabled->value() &&
        target.x > 0 && target.y > 0 && geometry.size() != target;
    if (geometry.w <= 0 || geometry.h <= 0 || geometry.x < 0 || geometry.y < 0 ||
        (geometry.pos() == Vector2D{} && !fitted))
        return original(tester, point, window, local);
    // Translate window coordinates back into the uncropped Wayland surface
    // tree before selecting the recipient and computing pointer coordinates.
    auto relative = point - window->position(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    if (fitted) relative = relative * (geometry.size() / target);
    const auto [recipient, coordinates] = surface->at(relative + geometry.pos(), true);
    if (recipient) local = coordinates;
    return recipient;
}

using SurfacePassFunction = void (*)(CSurfacePassElement*, const CSurfacePassElement::SRenderData&);
static void clientSurfacePass(CSurfacePassElement* element, const CSurfacePassElement::SRenderData& original) {
    auto data = original;
    const auto window = data.pWindow;
    if (window && !window->backend().isX11() &&
        !data.mainSurface && !data.popup && data.squishOversized) {
        // Subsurface positions include the parent's CSD shadow margins.
        // The main image's UVs already remove those margins; make the entire
        // render pass use the same window origin, including occlusion/clips.
        const auto geometry = window->backend().geometry().box;
        if (geometry.w > 0 && geometry.h > 0 && geometry.x >= 0 && geometry.y >= 0) {
            data.localPos -= geometry.pos();
            if (window->sizeAnimation()->isBeingAnimated()) {
                const auto reported = window->backend().reportedSize();
                if (reported.x > 0 && reported.y > 0)
                    data.localPos = data.localPos * (Vector2D{data.w, data.h} / reported);
            }
        }
    }
    reinterpret_cast<SurfacePassFunction>(clientSurfacePassHook->m_original)(element, data);
}
using SurfaceUVFunction = void (*)(Render::IElementRenderer*, Render::CRenderContext&, PHLWINDOW, SP<CWLSurfaceResource>,
    PHLMONITOR, bool, const Vector2D&, const Vector2D&, bool);

static void clientSurfaceUV(Render::IElementRenderer* renderer, Render::CRenderContext& ctx, PHLWINDOW window,
    SP<CWLSurfaceResource> surface, PHLMONITOR monitor, bool main,
    const Vector2D& projected, const Vector2D& logical, bool misaligned) {
    reinterpret_cast<SurfaceUVFunction>(clientSurfaceUVHook->m_original)(
        renderer, ctx, window, surface, monitor, main, projected, logical, misaligned);
    if (!main || !window || window->backend().isX11() ||
        !surface || surface != window->wlSurface()->resource()) return;

    const auto size = surface->m_current.size;
    const auto buffer = surface->m_current.bufferSize;
    const auto geometry = clientGeometry(window, surface);
    if (size.x <= 0 || size.y <= 0 || buffer.x <= 0 || buffer.y <= 0 ||
        geometry.w <= 0 || geometry.h <= 0 || geometry.x < 0 || geometry.y < 0) return;
    const bool margins = geometry.pos() != Vector2D{} || geometry.size() != size;
    const bool fitted = !window->isFloating() && !g_pGlobalState->config.enabled->value() && geometry.size() != logical;
    if (!margins && !fitted && !window->sizeAnimation()->isBeingAnimated()) return;

    // Geometry is in logical surface coordinates, after any viewporter crop
    // and destination scale. Compose it with the source viewport's buffer UVs.
    const auto cropped = geometry.intersection(CBox{{}, size});
    if (cropped.empty()) return;
    Vector2D sourceTL{}, sourceBR{1.0, 1.0};
    if (surface->m_current.viewport.hasSource) {
        const auto source = surface->m_current.viewport.source;
        sourceTL = source.pos() / buffer;
        sourceBR = (source.pos() + source.size()) / buffer;
    }
    const auto span = sourceBR - sourceTL;
    auto& data = ctx.m_data;
    data.primarySurfaceUVTopLeft = sourceTL + span * (cropped.pos() / size);
    data.primarySurfaceUVBottomRight = sourceTL + span * ((cropped.pos() + cropped.size()) / size);
}

static void removeClientSurfacePolicy(HANDLE handle) {
    if (clientSubsurfacePositionHook) HyprlandAPI::removeFunctionHook(handle, clientSubsurfacePositionHook);
    clientSubsurfacePositionHook = nullptr;
    if (clientDamageHook) HyprlandAPI::removeFunctionHook(handle, clientDamageHook);
    clientDamageHook = nullptr;
    if (clientPointerMotionHook) HyprlandAPI::removeFunctionHook(handle, clientPointerMotionHook);
    clientPointerMotionHook = nullptr;
    if (clientMaxSizeHook) HyprlandAPI::removeFunctionHook(handle, clientMaxSizeHook);
    clientMaxSizeHook = nullptr;
    if (clientMinSizeHook) HyprlandAPI::removeFunctionHook(handle, clientMinSizeHook);
    clientMinSizeHook = nullptr;
    if (clientTextureBoxHook) HyprlandAPI::removeFunctionHook(handle, clientTextureBoxHook);
    clientTextureBoxHook = nullptr;
    if (clientStateHook) HyprlandAPI::removeFunctionHook(handle, clientStateHook);
    clientStateHook = nullptr;
    if (clientSurfaceInputHook) HyprlandAPI::removeFunctionHook(handle, clientSurfaceInputHook);
    clientSurfaceInputHook = nullptr;
    if (clientSurfacePassHook) HyprlandAPI::removeFunctionHook(handle, clientSurfacePassHook);
    clientSurfacePassHook = nullptr;
    if (clientSurfaceUVHook) HyprlandAPI::removeFunctionHook(handle, clientSurfaceUVHook);
    clientSurfaceUVHook = nullptr;
}

static void installClientSurfacePolicy(HANDLE handle) {
    const auto install = [&](const char* name, const char* prefix, void* replacement) {
        const auto matches = HyprlandAPI::findFunctionsByName(handle, name);
        const auto found = std::ranges::find_if(matches, [&](const auto& match) {
            return match.demangled.starts_with(prefix);
        });
        if (found == matches.end()) throw std::runtime_error(std::string("[hyprstack] Missing pinned ") + name);
        auto hook = HyprlandAPI::createFunctionHook(handle, found->address, replacement);
        if (!hook || !hook->hook()) {
            if (hook) HyprlandAPI::removeFunctionHook(handle, hook);
            throw std::runtime_error(std::string("[hyprstack] Cannot hook ") + name);
        }
        return hook;
    };
    try {
        clientDamageHook = install("computeDamage", "Desktop::View::CWLSurface::computeDamage(", reinterpret_cast<void*>(&clientSurfaceDamage));
        clientSubsurfacePositionHook = install("coordsGlobal", "Desktop::View::CSubsurface::coordsGlobal(", reinterpret_cast<void*>(&clientSubsurfacePosition));
        clientMinSizeHook = install("layoutMinSize", "CXDGToplevelResource::layoutMinSize(", reinterpret_cast<void*>(&clientMinSize));
        clientMaxSizeHook = install("layoutMaxSize", "CXDGToplevelResource::layoutMaxSize(", reinterpret_cast<void*>(&clientMaxSize));
        clientTextureBoxHook = install("getTexBox", "CSurfacePassElement::getTexBox(", reinterpret_cast<void*>(&clientTextureBox));
        clientStateHook = install("onUpdateState", "Desktop::View::CWindow::onUpdateState(", reinterpret_cast<void*>(&tiledClientState));
        clientSurfaceUVHook = install("calculateUVForSurface", "Render::IElementRenderer::calculateUVForSurface(",
            reinterpret_cast<void*>(&clientSurfaceUV));
        clientSurfacePassHook = install("CSurfacePassElement", "CSurfacePassElement::CSurfacePassElement(CSurfacePassElement::SRenderData const&)",
            reinterpret_cast<void*>(&clientSurfacePass));
        clientSurfaceInputHook = install("windowSurfaceAt", "Desktop::CViewHitTester::windowSurfaceAt(",
            reinterpret_cast<void*>(&clientSurfaceInput));
        clientPointerMotionHook = install("sendPointerMotion", "CSeatManager::sendPointerMotion(",
            reinterpret_cast<void*>(&clientPointerMotion));
    } catch (...) {
        removeClientSurfacePolicy(handle);
        throw;
    }
}
