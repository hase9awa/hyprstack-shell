// Hyprstack visual task animation for the pinned Hyprland 0.57 renderer.
// The client's layout and configured size stay intact throughout the animation.
#pragma once
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/view/window/WindowFullscreenPolicy.hpp>
#include <hyprland/src/desktop/view/window/WindowEffectsController.hpp>
#include <hyprland/src/render/transformer/TransformerList.hpp>

#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/ClearPassElement.hpp>
#include <hyprland/src/render/transformer/Transformer.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <algorithm>
#include <chrono>

class CTaskAnimation final : public Render::IWindowTransformer {
  public:
    CTaskAnimation(PHLWINDOW window, const CBox& from, const CBox& to, double panelTop) :
        m_window(window), m_from(from), m_to(to), m_panelTop(panelTop) {
        // The entire swept area is safe even when rendering is delayed. Leave
        // the rest of the output (and other outputs) outside the damage region.
        const double left = std::min(from.x, to.x), top = std::min(from.y, to.y);
        m_damage = CBox{left, top, std::max(from.x + from.w, to.x + to.w) - left,
            std::max(from.y + from.h, to.y + to.h) - top}.expand(2);
        m_timer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(1), [this](SP<CEventLoopTimer> timer, void*) {
            const auto window = m_window.lock();
            if (!window || !window->mapped()) return;
            if (const auto monitor = window->m_monitor.lock())
                monitor->addDamage(m_damage.copy().translate(-monitor->m_position).scale(monitor->m_scale).round());
            // Match the output's frame interval, including high-refresh displays.
            if (busy()) {
                const auto monitor = window->m_monitor.lock();
                timer->updateTimeout(std::chrono::milliseconds(monitor ?
                    std::max(1, static_cast<int>(std::floor(1000.0 / monitor->m_refreshRate))) : 8));
            }
        }, nullptr);
        g_pEventLoopManager->addTimer(m_timer);
    }

    ~CTaskAnimation() override {
        if (m_timer && g_pEventLoopManager) g_pEventLoopManager->removeTimer(m_timer);
    }

    bool busy() const { return elapsed() < 0.23; }

    CBox current() const {
        const double t = std::clamp(elapsed() / 0.22, 0.0, 1.0);
        const double p = t * t * (3.0 - 2.0 * t);
        return {m_from.pos() + (m_to.pos() - m_from.pos()) * p,
            m_from.size() + (m_to.size() - m_from.size()) * p};
    }

    // Lua completes the workspace hand-off after busy() becomes false. Keep
    // the final transformed image until that hand-off explicitly clears us;
    // expiring here would expose the full-size window for an intervening frame.
    bool active() const override { return !m_cancelled; }
    int priority() const override { return 100; }

    CBox transformedExtents(const CBox&) const override {
        const auto window = m_window.lock();
        const auto monitor = window ? window->m_monitor.lock() : nullptr;
        return monitor ? current().translate(-monitor->m_position) : CBox{};
    }

    Render::SWindowTransformBuffer transform(Render::CRenderContext& ctx,
        const Render::SWindowTransformBuffer& in, const Render::SWindowTransformContext& context) override {
        if (!context.monitor || context.standalone || context.renderingSnapshot || !in.framebuffer) return in;
        const auto monitor = context.monitor.lock();
        const auto destination = current().translate(-monitor->m_position);
        const auto canvas = Render::pixelBoxForLogical(context.outputBox, monitor->m_scale);
        if (canvas.empty() || context.currentBox.empty()) return in;
        const auto output = g_pHyprRenderer->getWorkBuffer(ctx, canvas.size());
        if (!output) return {in.framebuffer, in.box, false};
        auto state = ctx.saveDrawState();
        auto binding = g_pHyprRenderer->bindTempFB(ctx, output);
        auto& render = ctx.m_data;
        render.damage = CRegion{0, 0, static_cast<int>(canvas.w), static_cast<int>(canvas.h)};
        render.fbSize = canvas.size();
        render.renderModif = {};
        render.clipBox = {};
        render.transformDamage = false;
        g_pHyprRenderer->setProjectionType(ctx, Render::RPT_EXPORT);
        g_pHyprRenderer->draw(ctx, CClearPassElement::SClearData{CHyprColor(0, 0, 0, 0)});
        const Vector2D ratio = destination.size() / context.currentBox.size();
        CTexPassElement::SRenderData texture;
        texture.tex = in.framebuffer->getTexture();
        texture.box = {destination.pos() * monitor->m_scale +
            (in.box.pos() - context.currentBox.pos() * monitor->m_scale) * ratio - canvas.pos(), in.box.size() * ratio};
        const double panelTop = (m_panelTop - monitor->m_position.y) * monitor->m_scale - canvas.y;
        if (m_panelTop - monitor->m_position.y > monitor->m_size.y / 2)
            texture.clipBox = {0, 0, canvas.w, std::max(0.0, panelTop)};
        else {
            const auto task = m_from.h < m_to.h ? m_from : m_to;
            const double bottom = (task.y + task.h - monitor->m_position.y + 4) * monitor->m_scale - canvas.y;
            texture.clipBox = {0, std::max(0.0, bottom), canvas.w, std::max(0.0, canvas.h - bottom)};
        }
        g_pHyprRenderer->draw(ctx, texture, render.damage);
        return {output, canvas};
    }

    static CTaskAnimation* find(PHLWINDOW window) {
        const auto task = window->effects().transformers()->get<CTaskAnimation>();
        return task && task->active() ? task : nullptr;
    }

    static void clear(PHLWINDOW window) {
        if (!window) return;
        const auto task = window->effects().transformers()->get<CTaskAnimation>();
        if (!task) return;
        const auto damage = task->m_damage;
        task->m_cancelled = true;
        window->effects().transformers()->removeInactive();
        if (const auto monitor = window->m_monitor.lock())
            monitor->addDamage(damage.copy().translate(-monitor->m_position).scale(monitor->m_scale).round());
    }

  private:
    double elapsed() const { return std::chrono::duration<double>(Time::steadyNow() - m_start).count(); }
    PHLWINDOWREF m_window;
    CBox m_from, m_to, m_source, m_destination, m_damage;
    bool m_cancelled = false;
    double m_panelTop;
    Time::steady_tp m_start = Time::steadyNow();
    SP<CEventLoopTimer> m_timer;
};
