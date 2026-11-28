#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <format>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include <cairo.h>
#include <glib.h>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/gl/GLFramebuffer.hpp>
#include <hyprland/src/state/MonitorState.hpp>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

namespace {

// Hyprland's toplevel export skips windows that do not intersect their output.
// Render those windows into a private framebuffer, using its standalone pass.
class WindowRenderer : public Render::IHyprRenderer {
public:
    using Render::IHyprRenderer::renderWindow;
};

SP<Render::IFramebuffer> renderThumbnail(PHLWINDOW window, PHLMONITOR monitor, Vector2D size) {
    auto& renderer = *g_pHyprRenderer;
    auto framebuffer = renderer.createFB("HyprStack workspace preview");
    if (!framebuffer || !framebuffer->alloc(size.x, size.y))
        return nullptr;
    framebuffer->setImageDescription(NColorManagement::DEFAULT_SRGB_IMAGE_DESCRIPTION);

    CRegion damage(0, 0, size.x, size.y);
    if (!renderer.beginFullFakeRender(monitor, damage, framebuffer))
        return nullptr;
    bool finishing = false;
    const Render::CScopeGuard abort([&] {
        if (!finishing)
            renderer.abortRender();
    });

    auto& context = renderer.context();
    context.m_data.fbSize = size;
    context.m_data.transformDamage = false;
    context.m_data.blockScreenShader = true;
    context.m_renderingCapture = true;
    context.m_blockSurfaceFeedback = true;
    renderer.setProjectionType(context, Render::RPT_EXPORT);
    renderer.setViewport(0, 0, size.x, size.y);
    renderer.draw(context, CClearPassElement::SClearData{{0, 0, 0, 0}}, damage);
    renderer.startRenderPass(context);
    const auto renderWindow = &WindowRenderer::renderWindow;
    (renderer.*renderWindow)(context, window, monitor, window->presentation().renderPresentation(nullptr),
                             Time::steadyNow(), false, Render::RENDER_PASS_ALL, true, true);
    finishing = true;
    renderer.endRender();
    return framebuffer;
}

std::string encodeThumbnail(const SP<Render::IFramebuffer>& source) {
    const auto size = source->m_size;
    const double scale = std::min(1., 400. / std::max(size.x, size.y));
    const int width = std::max(1, int(std::round(size.x * scale)));
    const int height = std::max(1, int(std::round(size.y * scale)));
    std::vector<uint8_t> rgba(size_t(width) * height * 4);

    {
        auto backend = g_pHyprRenderer->glBackend();
        if (!backend)
            return {};
        backend->makeEGLCurrent();
        const Render::GL::CFramebufferBindingGuard bindings{backend};
        auto thumbnail = g_pHyprRenderer->createFB("HyprStack thumbnail readback");
        if (!thumbnail || !thumbnail->alloc(width, height))
            return {};

        const bool scissor = glIsEnabled(GL_SCISSOR_TEST);
        backend->setCapStatus(GL_SCISSOR_TEST, false);
        const Render::CScopeGuard restoreScissor([&] { backend->setCapStatus(GL_SCISSOR_TEST, scissor); });
        backend->bindFramebuffer(GL_READ_FRAMEBUFFER, static_cast<Render::GL::CGLFramebuffer*>(source.get())->getFBID());
        thumbnail->bind();
        glBlitFramebuffer(0, 0, size.x, size.y, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        backend->bindFramebuffer(GL_READ_FRAMEBUFFER, static_cast<Render::GL::CGLFramebuffer*>(thumbnail.get())->getFBID());

        constexpr std::array packParameters{GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_PIXELS, GL_PACK_SKIP_ROWS};
        std::array<GLint, packParameters.size()> packValues;
        for (size_t index = 0; index < packParameters.size(); ++index) {
            glGetIntegerv(packParameters[index], &packValues[index]);
            glPixelStorei(packParameters[index], index == 0 ? 4 : 0);
        }
        GLint packBuffer = 0;
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &packBuffer);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
        glBindBuffer(GL_PIXEL_PACK_BUFFER, packBuffer);
        for (size_t index = 0; index < packParameters.size(); ++index)
            glPixelStorei(packParameters[index], packValues[index]);
    }

    std::vector<uint32_t> pixels(size_t(width) * height);
    // RPT_EXPORT already writes rows in the order used by the capture protocol.
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const auto* pixel = rgba.data() + (size_t(y) * width + x) * 4;
            pixels[size_t(y) * width + x] = (uint32_t(pixel[3]) << 24) | (uint32_t(pixel[0]) << 16)
                | (uint32_t(pixel[1]) << 8) | pixel[2];
        }
    }

    const std::unique_ptr<cairo_surface_t, decltype(&cairo_surface_destroy)> surface(
        cairo_image_surface_create_for_data(reinterpret_cast<unsigned char*>(pixels.data()),
                                            CAIRO_FORMAT_ARGB32, width, height, width * 4), cairo_surface_destroy);
    std::string png;
    const auto status = cairo_surface_write_to_png_stream(surface.get(), [](void* target, const unsigned char* data, unsigned length) {
        try {
            static_cast<std::string*>(target)->append(reinterpret_cast<const char*>(data), length);
            return CAIRO_STATUS_SUCCESS;
        } catch (...) {
            return CAIRO_STATUS_WRITE_ERROR;
        }
    }, &png);
    if (status != CAIRO_STATUS_SUCCESS)
        return {};

    const std::unique_ptr<gchar, decltype(&g_free)> base64(
        g_base64_encode(reinterpret_cast<const guchar*>(png.data()), png.size()), g_free);
    return std::string("data:image/png;base64,") + base64.get();
}

int capture(lua_State* state) {
    const std::string_view address = luaL_checkstring(state, 1);
    const std::string_view stableId = luaL_checkstring(state, 2);
    static const CConfigValue<Config::BOOL> enforcePermissions("ecosystem:enforce_permissions");
    if (*enforcePermissions || !g_pSessionLockManager || g_pSessionLockManager->isSessionLocked()
        || !g_pHyprRenderer || g_pHyprRenderer->type() != Render::IHyprRenderer::RT_GL || g_pHyprRenderer->context().active())
        return 0;

    for (const auto& window : Desktop::windowState()->windows()) {
        if (!window->mapped() || address != std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get()))
            || stableId != std::format("{:x}", window->metadata().stableID()))
            continue;

        const auto monitor = window->m_monitor.lock();
        if (!monitor || !window->m_workspace || (window->m_ruleApplicator && window->m_ruleApplicator->noScreenShare().valueOrDefault()))
            return 0;
        const auto workspace = monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace;
        if (window->m_workspace != workspace)
            return 0;

        const auto size = (window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) * monitor->m_scale).round();
        if (size.x < 1 || size.y < 1 || size.x > 8192 || size.y > 8192)
            return 0;

        const auto framebuffer = renderThumbnail(window, monitor, size);
        if (!framebuffer)
            return 0;
        const auto image = encodeThumbnail(framebuffer);
        lua_pushlstring(state, image.data(), image.size());
        return 1;
    }
    return 0;
}

int workspaceMoving(lua_State* state) {
    const auto monitor = State::monitorState()->query().name(luaL_checkstring(state, 1)).run();
    const auto workspace = monitor ? (monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace)
                                   : nullptr;
    const bool moving = workspace && std::ranges::any_of(Desktop::windowState()->windows(), [&](const auto& window) {
        return window->mapped() && !window->isHidden() && window->m_workspace == workspace
            && (window->positionAnimation()->isBeingAnimated() || window->sizeAnimation()->isBeingAnimated()
                || window->presentation().alpha(Desktop::View::WINDOW_ALPHA_ACTIVE)->isBeingAnimated());
    });
    lua_pushboolean(state, moving);
    return 1;
}

}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string_view(__hyprland_api_get_hash()) != HYPRSTACK_BUILD_ABI_HASH)
        throw std::runtime_error("HyprStack workspace previews require matching Hyprland headers");

    HyprlandAPI::addLuaFunction(handle, "hyprstack_previews", "capture", capture);
    HyprlandAPI::addLuaFunction(handle, "hyprstack_previews", "workspace_moving", workspaceMoving);
    return {"hyprstack-workspace-previews", "Undecorated previews of workspace windows", "HyprStack", HYPRSTACK_VERSION};
}

APICALL EXPORT void PLUGIN_EXIT() {}
