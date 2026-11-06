// Compositor-native drag targets: full, halves and quarters of the work area.
#pragma once
#include "globals.hpp"
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>
#include <hyprland/src/config/lua/ConfigManager.hpp>
#include <nlohmann/json.hpp>

namespace HyprstackSnap {
using Json = nlohmann::json;
struct Choice { std::string zone; CBox box; };
struct Drop { std::string zone, monitor; };
static Json encode(const CBox& b) { return {{"x",b.x},{"y",b.y},{"width",b.w},{"height",b.h}}; }
static CBox workArea(PHLMONITOR monitor) { return monitor->m_reservedArea.apply({monitor->m_position,monitor->m_size}); }
static CBox zoneBox(CBox area, const std::string& zone) {
    if (zone == "left" || zone == "top-left" || zone == "bottom-left") area.w /= 2;
    if (zone == "right" || zone == "top-right" || zone == "bottom-right") { area.x += area.w/2; area.w /= 2; }
    if (zone == "top" || zone == "top-left" || zone == "top-right") area.h /= 2;
    if (zone == "bottom" || zone == "bottom-left" || zone == "bottom-right") { area.y += area.h/2; area.h /= 2; }
    return area;
}
static CHyprColor parseColour(const std::string& text) {
    const auto hex = text.starts_with('#') ? text.substr(1) : text;
    if (hex.size() != 6) throw std::runtime_error("Expected an RGB colour");
    const unsigned rgb = std::stoul(hex,nullptr,16);
    return {((rgb>>16)&255)/255.0,((rgb>>8)&255)/255.0,(rgb&255)/255.0,1.0};
}

class Preview {
  public:
    Preview() {
        m_render = Event::bus()->m_events.render.stage.listen([this](Event::SRenderStageEvent event) {
            const auto stage = event.stage;
            if (stage == RENDER_POST_WINDOWS) render();
        });
    }
    ~Preview() { clear(); }
    void theme(CHyprColor accent, CHyprColor surface) { m_accent=accent; m_surface=surface; }
    void clear() {
        if (const auto monitor=m_monitor.lock()) g_pHyprRenderer->damageMonitor(monitor);
        m_window.reset(); m_monitor.reset(); m_selected.clear(); m_choices.clear();
    }
    void update(PHLWINDOW window, Vector2D pointer) {
        PHLMONITOR monitor;
        for (const auto& candidate : State::monitorState()->monitors())
            if (CBox{candidate->m_position,candidate->m_size}.containsPoint(pointer)) { monitor=candidate; break; }
        if (!monitor) { clear(); return; }
        if (m_monitor != monitor) clear();
        m_monitor=monitor; m_window=window;
        const auto area=workArea(monitor);
        const double card=std::min(84.0,(area.w-64)/4), gap=12;
        m_palette={area.x+(area.w-(4*card+5*gap))/2,area.y+12,4*card+5*gap,72};
        m_choices.clear();
        const auto add=[&](int column,const std::string& zone,double x,double y,double w,double h) {
            const CBox inner{m_palette.x+gap+column*(card+gap),m_palette.y+12,card,48};
            m_choices.push_back({zone,{inner.x+x*inner.w+2,inner.y+y*inner.h+2,w*inner.w-4,h*inner.h-4}});
        };
        add(0,"full",0,0,1,1);
        add(1,"left",0,0,.5,1); add(1,"right",.5,0,.5,1);
        add(2,"top",0,0,1,.5); add(2,"bottom",0,.5,1,.5);
        add(3,"top-left",0,0,.5,.5); add(3,"top-right",.5,0,.5,.5);
        add(3,"bottom-left",0,.5,.5,.5); add(3,"bottom-right",.5,.5,.5,.5);
        m_selected.clear();
        for (const auto& choice : m_choices) if (choice.box.containsPoint(pointer)) { m_selected=choice.zone; break; }
        if (m_selected.empty() && !m_palette.containsPoint(pointer)) {
            const auto local=pointer-monitor->m_position;
            const bool left=local.x<24, right=local.x>=monitor->m_size.x-24;
            const bool top=local.y<24, bottom=local.y>=monitor->m_size.y-24;
            if (left || right) {
                const auto side=left ? "left" : "right";
                m_selected=local.y<monitor->m_size.y*.22 ? std::string("top-")+side :
                    local.y>monitor->m_size.y*.78 ? std::string("bottom-")+side : side;
            } else if (top) m_selected="full";
            else if (bottom) m_selected="bottom";
        }
        m_dropBox=zoneBox(area,m_selected);
        g_pHyprRenderer->damageMonitor(monitor);
    }
    Drop drop() const { return {m_selected,m_monitor ? m_monitor->m_name : ""}; }
    Json status() const {
        Json result={{"active",bool(m_window)},{"zone",m_selected},{"monitor",m_monitor ? m_monitor->m_name : ""},
            {"preview",encode(m_dropBox)},{"palette",encode(m_palette)},{"choices",Json::array()}};
        for (const auto& choice:m_choices) { auto value=encode(choice.box); value["zone"]=choice.zone; result["choices"].push_back(value); }
        return result;
    }
  private:
    void rectangle(CBox box,CHyprColor colour,int radius,PHLMONITOR monitor) {
        CRectPassElement::SRectData data;
        data.box=box.translate(-monitor->m_position).scale(monitor->m_scale);
        data.color=colour; data.round=std::round(radius*monitor->m_scale);
        g_pHyprRenderer->addPassElement(g_pHyprRenderer->context(), makeUnique<CRectPassElement>(data));
    }
    void outline(CBox box,CHyprColor colour,int radius,PHLMONITOR monitor) {
        CBorderPassElement::SBorderData data;
        data.box=box.translate(-monitor->m_position).scale(monitor->m_scale);
        data.grad1=Config::CGradientValueData(colour); data.round=std::round(radius*monitor->m_scale); data.borderSize=2;
        g_pHyprRenderer->addPassElement(g_pHyprRenderer->context(), makeUnique<CBorderPassElement>(data));
    }
    void render() {
        const auto monitor=m_monitor.lock();
        const auto window=m_window.lock();
        if (!monitor || !window) return;
        const auto drag=g_layoutManager->dragController().get();
        if (!g_pGlobalState->config.enabled->value() || !window->mapped() || window->isHidden() ||
            !drag->target() || drag->target()->window()!=window || drag->mode()!=MBIND_MOVE) { clear(); return; }
        if (g_pHyprRenderer->context().m_data.pMonitor!=monitor) return;
        if (!m_selected.empty()) {
            auto fill=m_accent; fill.a=.18;
            auto edge=m_accent; edge.a=.9;
            const auto box=m_dropBox.copy().expand(-4);
            rectangle(box,fill,12,monitor); outline(box,edge,12,monitor);
        }
        auto backing=m_surface; backing.a=.97;
        rectangle(m_palette,backing,16,monitor);
        for (const auto& choice:m_choices) {
            auto colour=m_accent; colour.a=choice.zone==m_selected ? .9 : .23;
            rectangle(choice.box,colour,5,monitor);
            if (choice.zone==m_selected) outline(choice.box,m_accent,5,monitor);
        }
    }
    PHLWINDOWREF m_window;
    PHLMONITORREF m_monitor;
    CHyprSignalListener m_render;
    CHyprColor m_accent{.49,.61,.85,1}, m_surface{.12,.13,.18,1};
    CBox m_palette,m_dropBox;
    std::string m_selected;
    std::vector<Choice> m_choices;
};
static UP<Preview> preview;
static void clear() { if (preview) preview->clear(); }
static void update(PHLWINDOW window,Vector2D pointer) { if (preview) preview->update(window,pointer); }
static Drop drop() { return preview ? preview->drop() : Drop{}; }
static bool apply(PHLWINDOW window,const Drop& target) {
    const auto manager=dynamic_cast<Config::Lua::CConfigManager*>(Config::mgr().get());
    if (!manager || !window || !window->mapped() || target.zone.empty()) return false;
    const auto result=manager->eval(std::format("if not hyprstack_layouts then return false end; return hyprstack_layouts.snap('{}','{:x}',{},{})",
        std::format("0x{:x}",reinterpret_cast<uintptr_t>(window.get())),window->metadata().stableID(),
        Json(target.zone).dump(),Json(target.monitor).dump()),true);
    return result && *result=="true";
}
static int luaSnap(lua_State* L) {
    const std::string action=luaL_checkstring(L,1);
    if (action=="status") {
        const auto value=preview->status().dump(); lua_pushlstring(L,value.data(),value.size()); return 1;
    }
    if (action=="theme") {
        try { preview->theme(parseColour(luaL_checkstring(L,2)),parseColour(luaL_checkstring(L,3))); }
        catch (const std::exception& e) { return luaL_error(L,"Snap theme: %s",e.what()); }
    } else return luaL_error(L,"Unknown snap preview action");
    lua_pushboolean(L,true); return 1;
}
static void install(HANDLE handle) {
    preview=makeUnique<Preview>();
    HyprlandAPI::addLuaFunction(handle,"hyprbars","snap_zones",luaSnap);
}
static void remove() { preview.reset(); }
}
