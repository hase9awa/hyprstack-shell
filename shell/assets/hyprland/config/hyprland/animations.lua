-- Independently selectable shell/layer and application-window motion.
-- Loaded at compositor startup and called live by qs.services.Animations.
local M = {}

-- Animation curves
hl.curve("specialWorkSwitch", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("emphasizedAccel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("emphasizedDecel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.curve("windowGeometry", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1 } } })

hl.curve("hs_spring", { type = "bezier", points = { { 0.22, 1.25 }, { 0.32, 1 } } })
hl.curve("hs_glide", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("hs_snap", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("hs_cinema", { type = "bezier", points = { { 0.76, 0 }, { 0.24, 1 } } })
hl.curve("hs_exit", { type = "bezier", points = { { 0.4, 0 }, { 1, 1 } } })

local window_profiles = {
    spring = { enter = 4.8, exit = 2.8, move = 4.6, workspace = 4.8,
        curve = "hs_spring", out = "hs_exit", style = "popin 88%", workspace_style = "slidefade 12%" },
    glide = { enter = 3.8, exit = 2.6, move = 3.8, workspace = 4.2,
        curve = "hs_glide", out = "hs_exit", style = "slide", workspace_style = "slidefade 18%" },
    snappy = { enter = 2, exit = 1.5, move = 2.2, workspace = 2.5,
        curve = "hs_snap", out = "hs_exit", style = "popin 97%", workspace_style = "slidefade 8%" },
    cinematic = { enter = 6, exit = 4, move = 5.6, workspace = 6.5,
        curve = "hs_cinema", out = "hs_exit", style = "popin 82%", workspace_style = "slidefadevert 22%" },
}
local layer_profiles = {
    goop = { enter = 4.6, exit = 2.8, curve = "hs_spring", style = "slide" },
    fluent = { enter = 3, exit = 2, curve = "hs_glide", style = "slide" },
    snappy = { enter = 2.1, exit = 1.4, curve = "hs_snap", style = "slide" },
    cinematic = { enter = 5.2, exit = 3.6, curve = "hs_cinema", style = "fade" },
}

local function animation(leaf, speed, curve, style, enabled)
    hl.animation({ leaf = leaf, enabled = enabled ~= false, speed = speed, bezier = curve, style = style })
end

function M.apply(window_preset, shell_preset, game_mode)
    M.window_preset = window_profiles[window_preset] and window_preset or window_preset == "reduced" and "reduced" or "default"
    M.shell_preset = shell_preset
    M.game_mode = game_mode == true
    local plugin = hl.plugin and hl.plugin.hyprbars
    M.native()
    -- Reset the leaves we own before applying the next preset. Inherited
    -- children remain inherited, including the scrolling camera workspace branch.
    hl.config({ animations = { enabled = game_mode ~= true } })
    animation("fadeOut", 6, "standard")
    -- Animation configs
    hl.animation({ leaf = "layersIn", enabled = true, speed = 5, bezier = "emphasizedDecel", style = "slide" })
    hl.animation({ leaf = "layersOut", enabled = true, speed = 4, bezier = "emphasizedAccel", style = "slide" })
    hl.animation({ leaf = "fadeLayers", enabled = true, speed = 5, bezier = "standard" })

    -- Grow from a nearby size instead of Hyprland's default five-pixel pop-in.
    -- New columns and the existing columns' camera movement share one curve.
    hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "windowGeometry", style = "popin 94%" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "emphasizedAccel" })
    hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "windowGeometry" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "standard" })

    hl.animation({
        leaf    = "specialWorkspace",
        enabled = true,
        speed   = 4,
        bezier  = "specialWorkSwitch",
        style   = "slidefadevert 15%"
    })
    hl.animation({ leaf = "fade", enabled = true, speed = 6, bezier = "standard" })
    -- Application opening and focus changes keep a constant opacity. Layer-shell
    -- popouts and geometric window animations retain their own transitions.
    hl.animation({ leaf = "fadeIn", enabled = false })
    hl.animation({ leaf = "fadeSwitch", enabled = false })
    hl.animation({ leaf = "fadeDim", enabled = false })
    -- Native application context menus appear at full opacity immediately.
    hl.animation({ leaf = "fadePopups", enabled = false })
    hl.animation({ leaf = "fadePopupsIn", enabled = false })
    hl.animation({ leaf = "fadePopupsOut", enabled = false })
    hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "standard" })

    local profile = window_profiles[window_preset]
    if profile then
        animation("windowsIn", profile.enter, profile.curve, profile.style)
        animation("windowsOut", profile.exit, profile.out, "popin 94%")
        animation("windowsMove", profile.move, profile.curve)
        animation("workspaces", profile.workspace, profile.curve, profile.workspace_style)
        animation("specialWorkspace", profile.workspace, profile.curve, "slidefadevert 15%")
        animation("fadeOut", profile.exit, "standard")
    elseif window_preset == "reduced" then
        for _, leaf in ipairs({ "windowsIn", "windowsOut", "windowsMove", "workspaces",
            "specialWorkspace", "fadeOut", "border" }) do
            animation(leaf, 1, "standard", nil, false)
        end
    end

    local layer = layer_profiles[shell_preset]
    if layer then
        animation("layersIn", layer.enter, layer.curve, layer.style)
        animation("layersOut", layer.exit, "hs_exit", layer.style)
        animation("fadeLayers", layer.enter, "standard")
    elseif shell_preset == "reduced" then
        for _, leaf in ipairs({ "layersIn", "layersOut", "fadeLayers" }) do
            animation(leaf, 1, "standard", nil, false)
        end
    end
    if hyprstack_layouts then
        M.workspaces(hyprstack_layouts.mode() == "scrolling", plugin and plugin.workspace_camera ~= nil)
    end
end

-- The scrolling camera owns the scene; native workspace animation would apply
-- the same movement twice. Stacking's default keeps its original instant switch.
function M.native()
    local plugin = hl.plugin and hl.plugin.hyprbars
    if plugin and plugin.motion_preset then plugin.motion_preset(M.window_preset, M.game_mode) end
end

function M.task_delay()
    if M.game_mode or M.window_preset == "reduced" then return 1 end
    return ({ spring = 360, glide = 280, snappy = 160, cinematic = 420 })[M.window_preset] or 240
end

function M.workspaces(scrolling, camera)
    M.native()
    local profile = window_profiles[M.window_preset]
    animation("workspaces", profile and profile.workspace or 5, profile and profile.curve or "standard",
        profile and profile.workspace_style or "slidevert",
        not (scrolling and camera) and M.window_preset ~= "reduced" and (scrolling or profile ~= nil))
end

local config = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hyprstack/shell.json"
local file = io.open(config, "r")
local preferences = {}
if file then
    local ok, data = pcall(require("utils.json").decode, file:read("*a"))
    file:close()
    if ok and type(data) == "table" and type(data.appearance) == "table"
        and type(data.appearance.anim) == "table" then
        preferences = data.appearance.anim
    end
end
M.apply(preferences.windowPreset, preferences.shellPreset, false)
return M
