// Hyprland 0.57's Wayland backend deliberately leaves every client maximized.
// Stacking uses the client's real state, including its own titlebar controls.
#pragma once
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>

inline SP<CXDGToplevelResource> clientToplevel(PHLWINDOW window) {
    if (!window || window->backend().isX11()) return nullptr;
    const auto surface = window->resource();
    const auto role = surface ? dynamicPointerCast<CXDGSurfaceRole>(surface->m_role) : nullptr;
    const auto xdg = role ? role->m_xdgSurface.lock() : nullptr;
    return xdg ? xdg->m_toplevel.lock() : nullptr;
}

inline void setClientMaximized(PHLWINDOW window, bool maximized) {
    if (const auto toplevel = clientToplevel(window))
        toplevel->setMaximized(maximized);
    else if (window)
        window->backend().setMaximized(maximized);
}
