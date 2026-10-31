local json = require("utils.json")
local config_dir = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hyprstack"
local runtime_path = os.getenv("XDG_RUNTIME_DIR") .. "/hyprstack-layouts-" .. os.getenv("HYPRLAND_INSTANCE_SIGNATURE") .. ".json"

local function read(path)
    local file = io.open(path, "r")
    if not file then return {} end
    local ok, value = pcall(json.decode, file:read("*a"))
    file:close()
    return ok and type(value) == "table" and value or {}
end

local function write(path, value)
    local file = assert(io.open(path .. ".tmp", "w"))
    file:write(json.encode(value), "\n")
    file:close()
    assert(os.rename(path .. ".tmp", path))
end

local preferences = read(config_dir .. "/layouts.json")
preferences = { mode = (preferences.mode or preferences.default_mode) == "stacking" and "stacking" or "scrolling" }
local workspace_config = read(config_dir .. "/workspaces.json")
local per_monitor = workspace_config.per_monitor == true
local workspace_count = math.max(1, math.floor(tonumber(workspace_config.count) or 10))
workspace_config.monitor_bases = workspace_config.monitor_bases or {}

local runtime = read(runtime_path)
local workspace_bank_views = runtime.workspace_bank_views or {}
local secondary_overlay = runtime.secondary_overlay
local secondary_overlay_timer
local secondary_overlay_name = "hyprstack-secondary"
local records = runtime.windows or runtime
local tiled_views = runtime.tiled_views or {}
local changing = false
local navigation_since_reload = false
local animation_timer
local overview_active = false
local overview_watchdog
local tiling_preferences = read(config_dir .. "/tiling.json")
tiling_preferences.focusOnHover = tiling_preferences.focusOnHover ~= false
tiling_preferences.edgeScroll = tiling_preferences.edgeScroll ~= false
local theme_palette = {}
local window_effects = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "effects.lua")
local effects_game_mode = false
local border_color_roles = { primary = true, secondary = true, tertiary = true,
    error = true, success = true, onSurface = true, outline = true }
for index = 0, 15 do border_color_roles["term" .. index] = true end
local function valid_border_role(role)
    return type(role) == "string" and (border_color_roles[role]
        or (#role <= 104 and role:match("^palette_%a[%w_]*$")))
end
local function active_border(palette)
    local role = valid_border_role(tiling_preferences.focusBorderColor) and tiling_preferences.focusBorderColor or "primary"
    return "rgba(" .. (palette[role] or palette.primary or "7e9cd8"):gsub("#", "") .. "e6)"
end
local tiled_gaps_in = hl.get_config("general.gaps_in")
local tiled_gaps_out = hl.get_config("general.gaps_out")
local tiled_rounding = math.max(0, math.min(60, math.floor(tonumber(tiling_preferences.windowRounding) or hl.get_config("decoration.rounding"))))
local tiled_border = math.max(0, math.min(10, math.floor(tonumber(tiling_preferences.focusBorderWidth) or hl.get_config("general.border_size"))))
local tiled_no_warps = runtime.tiled_no_warps
local tiled_focus = runtime.tiled_focus
local tiled_resize_on_border = runtime.tiled_resize_on_border
local tiled_border_grab = runtime.tiled_border_grab
if tiled_resize_on_border == nil or preferences.mode == "scrolling" then
    tiled_resize_on_border = hl.get_config("general.resize_on_border")
    tiled_border_grab = hl.get_config("general.extend_border_grab_area")
end
if tiled_no_warps == nil or preferences.mode == "scrolling" then
    tiled_no_warps = hl.get_config("cursor.no_warps")
end
if tiled_focus == nil or preferences.mode == "scrolling" then
    tiled_focus = { follow_mouse = hl.get_config("input.follow_mouse"),
        float_switch_override_focus = hl.get_config("input.float_switch_override_focus"),
        mouse_move_focuses_monitor = hl.get_config("misc.mouse_move_focuses_monitor"),
        focus_on_activate = hl.get_config("misc.focus_on_activate") }
end
if tiled_focus.focus_on_activate == nil then tiled_focus.focus_on_activate = hl.get_config("misc.focus_on_activate") end
if tiled_focus.follow_min_visible == nil then tiled_focus.follow_min_visible = hl.get_config("scrolling.follow_min_visible") end
local last_rounding, last_border, last_tiling_gaps
local last_gaps_in, last_gaps_out
local touching_tiles_rule
local titlebar_height = 32
local swipe_enabled = true
local pending_pins = {}
local task_targets, minimize_timers = {}, {}
local layouts = {}
hyprstack_layouts = layouts

local telegram_classes = "(?i)^(com\\.ayugram\\.desktop|AyugramDesktop|ayugram|org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop)$"
local telegram_class_names = { ["com.ayugram.desktop"] = true, ayugramdesktop = true, ayugram = true,
    ["org.telegram.desktop"] = true, telegramdesktop = true, ["telegram-desktop"] = true }
-- Telegram's viewer has its own toplevel, not a transient parent on Linux.
-- Match the official localized viewer titles, without floating the chat window.
local telegram_media_titles = { "Media viewer", "Просмотр медиа", "Просмотрщик медиа", "Окно просмотра медиа",
    "Медіапереглядач", "Medienbetrachter", "Visor multimedia", "Lecteur multimédia",
    "Visualizzatore multimediale", "Visualizador de Mídia", "Przeglądarka multimediów",
    "Medya görüntüleyici", "媒体查看器", "媒體瀏覽器", "メディアビューア", "미디어 뷰어" }
local telegram_media_names = {}
for _, title in ipairs(telegram_media_titles) do telegram_media_names[title] = true end
-- The default application title is also used by WebApps and other Qt windows.
-- Only explicit video titles can safely request PiP pinning and aspect ratio.
local telegram_auxiliary_titles = { "AyugramDesktop", "AyuGramDesktop", "TelegramDesktop" }
local telegram_auxiliary_names = {}
for _, title in ipairs(telegram_auxiliary_titles) do telegram_auxiliary_names[title] = true end
local telegram_pip_titles = { "Picture-in-Picture", "Picture in picture", "Картинка в картинке" }
local telegram_pip_names = {}
for _, title in ipairs(telegram_pip_titles) do telegram_pip_names[title] = true end

local function telegram_pip(window)
    return telegram_class_names[window.class:lower()]
        and (telegram_pip_names[window.initial_title] or telegram_pip_names[window.title])
end

local function telegram_media(window)
    return telegram_class_names[window.class:lower()]
        and (telegram_media_names[window.initial_title] or telegram_media_names[window.title] or telegram_pip(window))
end

local function telegram_auxiliary(window)
    return telegram_class_names[window.class:lower()]
        and (telegram_auxiliary_names[window.initial_title] or telegram_auxiliary_names[window.title])
end

-- Share the shell's opacity preference instead of leaving a hard-coded window
-- opacity behind. Reloads also apply these preferences before the shell starts.
function layouts.effects(options)
    if not options then
        local appearance = read(config_dir .. "/shell.json").appearance or {}
        local transparency = appearance.transparency or {}
        options = { enabled = transparency.enabled == true, opacity = transparency.base or 0.85,
            blur = read(config_dir .. "/effects.json").blur ~= false }
    end
    local enabled = options.enabled == true
    local opacity = enabled and math.max(0, math.min(1, tonumber(options.opacity) or 0.85)) or 1
    local browsers_and_telegram = "(?i)^(thorium.*|chromium.*|google-chrome.*|firefox|librewolf|zen(-browser)?|com\\.ayugram\\.desktop|AyugramDesktop|org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop)$"
    hl.config({ decoration = { blur = { enabled = options.blur ~= false } } })
    hl.window_rule({ name = "hyprstack-window-opacity", match = { class = "negative:" .. browsers_and_telegram },
        opacity = string.format("%g override %g override 1.0 override", opacity, opacity), opaque = not enabled })
    hl.window_rule({ name = "hyprstack-opaque-apps", match = { class = browsers_and_telegram },
        opacity = "1.0 override 1.0 override 1.0 override", opaque = true, no_blur = true })
end

local function key(workspace)
    return workspace.addressable_name
end

local function monitor_for(monitor)
    if type(monitor) == "string" then return hl.get_monitor(monitor) end
    return monitor or hl.get_active_monitor()
end

function layouts.workspace_base(monitor)
    monitor = monitor_for(monitor)
    if not per_monitor or not monitor then return 0 end
    local base = workspace_config.monitor_bases[monitor.name]
    if base == nil then
        local used = {}
        for _, value in pairs(workspace_config.monitor_bases) do used[value] = true end
        base = 0
        while used[base] do base = base + workspace_count end
        workspace_config.monitor_bases[monitor.name] = base
        write(config_dir .. "/workspaces.json", workspace_config)
    end
    return base
end

function layouts.focus(number, monitor)
    monitor = monitor_for(monitor)
    if not monitor then return end
    if per_monitor and (number < 1 or number > workspace_count) then return end
    if secondary_overlay and secondary_overlay.monitor == monitor.name then
        layouts.show_secondary_workspace(number)
        return
    end
    if layouts.mode() ~= "scrolling" then return end
    navigation_since_reload = true
    hl.dispatch(hl.dsp.focus({ monitor = monitor }))
    hl.dispatch(hl.dsp.focus({ workspace = tostring(layouts.workspace_base(monitor) + number) }))
end

function layouts.step(direction, monitor)
    monitor = monitor_for(monitor)
    if not monitor or not monitor.active_workspace then return end
    if secondary_overlay and secondary_overlay.monitor == monitor.name then
        layouts.show_secondary_workspace(secondary_overlay.workspace - secondary_overlay.base + direction)
        return
    end
    if layouts.mode() ~= "scrolling" then return end
    if not per_monitor then
        if direction > 0 or monitor.active_workspace.id > 1 then
            hl.dispatch(hl.dsp.focus({ monitor = monitor }))
            hl.dispatch(hl.dsp.focus({ workspace = direction > 0 and "r+1" or "r-1" }))
        end
        return
    end
    local number = monitor.active_workspace.id - layouts.workspace_base(monitor)
    layouts.focus(number + direction, monitor)
end

function layouts.mode()
    return preferences.mode
end

function layouts.focus_column(direction)
    if layouts.mode() ~= "scrolling" then return end
    local active = hl.get_active_window()
    local column = active and active.layout and active.layout.column
    if not active or not column then
        if not active then
            layouts.focus_other_monitor(direction)
        else
            -- Floating windows have no column index. Restrict geometric
            -- navigation to this workspace, then use the same monitor edge
            -- handling; Hyprland's generic fallback can cycle the focus.
            local x, y = active.at.x + active.size.x / 2, active.at.y + active.size.y / 2
            local target, distance
            for _, window in ipairs(active.workspace:get_windows()) do
                if window ~= active and window.mapped and not window.hidden then
                    local dx = (window.at.x + window.size.x / 2 - x) * direction
                    local score = dx + math.abs(window.at.y + window.size.y / 2 - y) * 2
                    if dx > 0 and (not distance or score < distance) then target, distance = window, score end
                end
            end
            if target then
                navigation_since_reload = true
                hl.dispatch(hl.dsp.focus({ window = target }))
            else
                layouts.focus_other_monitor(direction)
            end
        end
        return
    end
    -- Geometric focus ignores off-screen columns and can be blocked by a
    -- maximized column. The scrolling layout's indices describe the real order.
    local target, distance
    for _, window in ipairs(active.workspace:get_windows()) do
        local other = window.layout and window.layout.column
        if window.mapped and not window.floating and other then
            local delta = (other.index - column.index) * direction
            if delta > 0 and (not distance or delta < distance) then
                target, distance = window, delta
            end
        end
    end
    navigation_since_reload = true
    if target then
        hl.dispatch(hl.dsp.focus({ window = target }))
    else
        layouts.focus_other_monitor(direction)
    end
end

local function save()
    -- Config verification has no live desktop and must not replace session
    -- records or preferences with the verifier's empty workspace state.
    if not hl.get_active_monitor() then return end
    write(config_dir .. "/layouts.json", preferences)
    write(runtime_path, { windows = records, tiled_views = tiled_views, tiled_no_warps = tiled_no_warps,
        tiled_resize_on_border = tiled_resize_on_border, tiled_border_grab = tiled_border_grab, tiled_focus = tiled_focus,
        secondary_overlay = secondary_overlay, workspace_bank_views = workspace_bank_views })
end

local function eligible(window)
    return window and window.mapped and not window.pinned and window.workspace and not window.workspace.special
end

local function record_for(window)
    local record = records[window.address]
    if record and record.id ~= window.stable_id then
        records[window.address] = nil
        record = nil
    end
    return record
end

local function geometry(window)
    return { x = window.at.x, y = window.at.y, width = window.size.x, height = window.size.y }
end

local function monitor_size(monitor)
    local width, height = monitor.width, monitor.height
    if monitor.transform % 2 == 1 then width, height = height, width end
    return width / monitor.scale, height / monitor.scale
end

function layouts.focus_other_monitor(direction)
    if layouts.mode() ~= "scrolling" then return end
    local source = hl.get_active_monitor()
    if not source then return end
    local sw, sh = monitor_size(source)
    local sx, sy = source.x + sw / 2, source.y + sh / 2
    local target, distance
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor ~= source and monitor.active_workspace then
            local edge, edge_index
            for _, window in ipairs(monitor.active_workspace:get_windows()) do
                if window.mapped and not window.hidden then
                    local column = window.layout and window.layout.column
                    local index = column and column.index or 0
                    if not edge or index * direction < edge_index * direction then
                        edge, edge_index = window, index
                    end
                end
            end
            if edge then
                local width, height = monitor_size(monitor)
                local x, y = monitor.x + width / 2, monitor.y + height / 2
                local dx = (x - sx) * direction
                local score = math.abs(x - sx) + math.abs(y - sy) * 2
                if dx > 0 and (not distance or score < distance) then target, distance = edge, score end
            end
        end
    end
    -- Only occupied outputs in the requested physical direction are eligible.
    -- At the outer edge the focus stays put, without wrapping around.
    if target then
        navigation_since_reload = true
        hl.dispatch(hl.dsp.focus({ window = target }))
    end
end

local function browser(window)
    local class = window.class:lower()
    return class:find("thorium", 1, true) or class:find("chromium", 1, true)
        or class:find("google-chrome", 1, true) or class == "firefox" or class == "librewolf"
        or class == "zen" or class == "zen-browser"
end

local function default_column_width(window)
    if window.monitor then
        local width, height = monitor_size(window.monitor)
        if height > width then return 0.5 end
    end
    return browser(window) and 1.0 or 0.5
end

local monitor_directions = {}
local browser_classes = "(?i)^(thorium.*|chromium.*|google-chrome.*|firefox|librewolf|zen(-browser)?)$"
function layouts.monitor_directions()
    for _, monitor in ipairs(hl.get_monitors()) do
        local width, height = monitor_size(monitor)
        local direction = height > width and "down" or "right"
        if monitor_directions[monitor.name] ~= direction then
            monitor_directions[monitor.name] = direction
            local selector = "m[" .. monitor.name .. "]s[false]"
            hl.workspace_rule({ workspace = selector, layout_opts = { direction = direction } })
            -- The browser default follows the output, while colresize retains
            -- manually selected fractions and monitor transfers retain size.
            hl.window_rule({ name = "hyprstack-browser-column-" .. monitor.name,
                match = { class = browser_classes, workspace = selector },
                scrolling_width = direction == "down" and 0.5 or 1.0 })
        end
    end
end

local function client_decorated(window)
    local class = window.class:lower()
    return browser(window) or class:find("ayugram", 1, true) or class:find("telegram", 1, true)
        or class == "discord" or class:match("^org%.gnome%.")
end

local function scroll_position(window)
    local layout = window.layout
    if not layout or not layout.column then return {} end
    return { column = layout.column.index, width = layout.column.width, row = layout.index_in_column }
end

local function float(window, enabled)
    hl.dispatch(hl.dsp.window.float({ window = window, action = enabled and "enable" or "disable" }))
end

local function move_to_workspace(window, workspace)
    if window.pinned then
        -- Hyprland can leave a pinned window without a monitor after hot unplug.
        -- Moving it first gives the pin dispatcher a valid monitor again.
        if not window.monitor then
            hl.dispatch(hl.dsp.window.move({ window = window, workspace = workspace, follow = false }))
        end
        hl.dispatch(hl.dsp.window.pin({ window = window, action = "disable" }))
        pending_pins[#pending_pins + 1] = window
    end
    hl.dispatch(hl.dsp.window.move({ window = window, workspace = workspace, follow = false }))
end

local function set_geometry(window, value)
    assert(value.width > 0 and value.height > 0, "Invalid floating geometry for " .. window.title .. ": " .. json.encode(value))
    local plugin = hl.plugin.hyprbars
    if plugin and plugin.animate_window and plugin.animate_window(window.address,
        window.stable_id, "geometry", value.x, value.y, value.width, value.height) then return end
    hl.dispatch(hl.dsp.window.resize({ window = window, x = value.width, y = value.height, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = window, x = value.x, y = value.y, relative = false }))
end

local function raise(window)
    -- bring_to_top() accepts no window selector in Hyprland 0.56. Passing
    -- {window=...} silently raises the previous focus instead of this window.
    hl.dispatch(hl.dsp.window.alter_zorder({ window = window, mode = "top" }))
end

function layouts.clear_focus()
    local plugin = hl.plugin.hyprbars
    if layouts.mode() == "stacking" and plugin and plugin.clear_focus then plugin.clear_focus() end
end

function layouts.toggle_width()
    if layouts.mode() ~= "scrolling" then return end
    local window = hl.get_active_window()
    local column = window and not window.floating and window.layout and window.layout.column
    if not column or window.fullscreen == 2 then return end
    if window.fullscreen ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
    end
    hl.dispatch(hl.dsp.layout("colresize " .. (column.width >= 0.99 and "0.5" or "1.0")))
    local record = record_for(window)
    if record then record.scroll = scroll_position(window); save() end
end

local function fit_geometry(window, value, index)
    local monitor = window.monitor
    local width, height = monitor_size(monitor)
    local reserved = monitor.reserved
    local top, bottom = reserved.top, reserved.bottom
    -- The shell receives the new edge after this dispatch finishes. Anticipate
    -- its reservation so restored floating windows do not overlap the bar.
    if (layouts.mode() == "stacking" and top > bottom) or (layouts.mode() == "scrolling" and bottom > top) then
        top, bottom = bottom, top
    end
    width = width - reserved.left - reserved.right
    height = height - top - bottom
    local x, y = monitor.x + reserved.left, monitor.y + top
    if layouts.mode() == "stacking" and not client_decorated(window) then
        y, height = y + titlebar_height, height - titlebar_height
    end
    -- Hidden scrolling windows can briefly report an uninitialised size after
    -- output or workspace changes; never replay that as floating geometry.
    if value and (not value.width or not value.height or value.width <= 0 or value.height <= 0) then
        value = nil
    end
    if not value then
        local offset = (index % 6) * 28
        value = { x = x + width * 0.225 + offset, y = y + height * 0.15 + offset,
            width = width * 0.55, height = height * 0.7 }
    end
    return {
        x = math.floor(math.max(x, math.min(value.x, x + width - math.min(value.width, width)))),
        y = math.floor(math.max(y, math.min(value.y, y + height - math.min(value.height, height)))),
        width = math.floor(math.min(value.width, width)),
        height = math.floor(math.min(value.height, height)),
    }
end

local function capture_views()
    local views = {}
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor.active_workspace then
            views[#views + 1] = { monitor = monitor.name, workspace = key(monitor.active_workspace) }
        end
    end
    return views
end

local function without_cursor_warps(action)
    local no_warps = hl.get_config("cursor.no_warps")
    if no_warps then return action() end
    hl.config({ cursor = { no_warps = true } })
    local ok, err = pcall(action)
    hl.config({ cursor = { no_warps = no_warps } })
    if not ok then error(err) end
end

local function restore_focus(active, focused, visible)
    without_cursor_warps(function()
        for _, entry in ipairs(visible) do
            local monitor = hl.get_monitor(entry.monitor)
            if monitor and (not monitor.active_workspace or key(monitor.active_workspace) ~= entry.workspace) then
                local workspace = hl.get_workspace(entry.workspace)
                if workspace then
                    monitor:set_workspace(workspace)
                else
                    hl.dispatch(hl.dsp.focus({ monitor = monitor }))
                    hl.dispatch(hl.dsp.focus({ workspace = entry.workspace }))
                end
            end
        end
        if focused and focused.name and hl.get_active_monitor() ~= focused then
            hl.dispatch(hl.dsp.focus({ monitor = focused }))
        end
        if active and active.mapped and hl.get_active_window() ~= active then
            hl.dispatch(hl.dsp.focus({ window = active }))
        elseif not active then
            layouts.clear_focus()
        end
    end)
end

local function preserve_focus(action, views)
    local active, focused = hl.get_active_window(), hl.get_active_monitor()
    local visible = views or capture_views()
    -- Config reloads and layout bookkeeping restore focus internally. Only
    -- explicit navigation should apply the user's usual pointer warp policy.
    without_cursor_warps(function()
        local ok, err = pcall(action)
        restore_focus(active, focused, visible)
        if not ok then error(err) end
    end)
end

local function visual_animation(window, operation, box)
    local plugin = hl.plugin.hyprbars
    if not plugin or not plugin.animate_window then return false end
    return plugin.animate_window(window.address, window.stable_id, operation,
        box and box.x, box and box.y, box and (box.width or box.w), box and (box.height or box.h),
        box and box.bar_top)
end

local function maximized_geometry(window)
    local monitor = window.monitor
    local width, height = monitor_size(monitor)
    local reserved = monitor.reserved
    local top = changing and 0 or reserved.top
    local bottom = changing and 40 or reserved.bottom
    local bar = client_decorated(window) and 0 or titlebar_height
    return { x = monitor.x + reserved.left, y = monitor.y + top + bar,
        width = width - reserved.left - reserved.right,
        height = height - top - bottom - bar }
end

local function set_maximized(window, enabled)
    local record = record_for(window) or { id = window.stable_id, workspace = key(window.workspace) }
    records[window.address] = record
    if enabled then
        -- Client-side maximize state is independent of the compositor's exclusive
        -- fullscreen layer. All stacking windows share one visual/input Z order.
        record.maximized = record.maximized or { geometry = geometry(window) }
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 1, action = "set" }))
        set_geometry(window, maximized_geometry(window))
    else
        local normal = record.maximized and record.maximized.geometry
        record.maximized = nil
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
        if normal then set_geometry(window, fit_geometry(window, normal, 0)) end
    end
    -- fullscreen_state intentionally separates maximize from the compositor's
    -- exclusive layer. Re-enable synchronization for subsequent native video
    -- fullscreen requests; setting this property does not change today's state.
    hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "sync_fullscreen", value = "1" }))
    hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "rounding", value = enabled and "0" or "unset" }))
    visual_animation(window, "client-state")
end

function layouts.set_task_targets(monitor, targets)
    task_targets[monitor] = targets
end

local function task_target(window)
    for _, target in ipairs(task_targets[window.monitor.name] or {}) do
        if target.address == window.address and target.id == window.stable_id then
            return { x = target.x, y = target.y, w = target.w, h = target.h, bar_top = target.barTop }
        end
    end
    local monitor = window.monitor
    local width, height = monitor_size(monitor)
    return { x = monitor.x + width / 2 - 90,
        y = monitor.y + height - 36, w = 180, h = 32,
        bar_top = monitor.y + height - 40 }
end

local function cancel_minimize(window)
    local timer = minimize_timers[window.address]
    if timer then timer:set_enabled(false); minimize_timers[window.address] = nil end
end

local function finish_minimize(window, hidden)
    cancel_minimize(window)
    local record = record_for(window)
    if not window.mapped or not record or record.minimized ~= hidden then return end
    local active = hl.get_active_window()
    move_to_workspace(window, "special:hyprstack-minimized-" .. hidden.monitor)
    visual_animation(window, "workspace-opacity")
    visual_animation(window, "reset", hidden.geometry)
    hidden.animating = nil
    -- Moving a window to its hidden workspace triggers Hyprland's fallback
    -- focus. Keep the user's subsequent click, or leave the desktop unfocused.
    if active and active ~= window and active.mapped then
        hl.dispatch(hl.dsp.focus({ window = active }))
    else
        layouts.clear_focus()
    end
    save()
end

local function stack(workspace, prepared)
    local windows = {}
    -- Capture every column before floating the first window changes its indices.
    for _, window in ipairs(workspace:get_windows()) do
        local monitor = window.monitor
        if eligible(window) and (not window.floating or prepared) and monitor and monitor.width > 0 and monitor.height > 0 then
            local record = record_for(window) or { id = window.stable_id }
            if not prepared and not window.floating then record.scroll = scroll_position(window) end
            record.workspace = key(workspace)
            record.stacked = record.stacked or not window.floating
            records[window.address] = record
            windows[#windows + 1] = window
        end
    end
    for index, window in ipairs(windows) do
        local record = records[window.address]
        local internal, client = window.fullscreen, window.fullscreen_client
        local cached = record.stacking_state
        local normal = cached and cached.geometry or (not record.stacked and geometry(window)) or record.geometry
        if cached and cached.monitor == window.monitor.name and cached.monitor_x then
            normal = { x = normal.x + window.monitor.x - cached.monitor_x,
                y = normal.y + window.monitor.y - cached.monitor_y, width = normal.width, height = normal.height }
        end
        local maximize = cached and cached.maximized or (not cached and (internal == 1 or record.maximized ~= nil))
        record.maximized = nil
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
        float(window, true)
        -- A tiled fullscreen exit can leave a pending synthetic maximize echo.
        -- The stacking controller owns maximize requests after this migration.
        visual_animation(window, "clear-maximize-echo")
        set_geometry(window, fit_geometry(window, normal, index - 1))
        if maximize then
            set_maximized(window, true)
        end
        if internal == 2 then
            record.video_fullscreen = true
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 2, client = 2, action = "set" }))
        elseif not record.maximized then
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
        end
    end
end

local function tile(workspace, prepared)
    local entries = {}
    for _, window in ipairs(workspace:get_windows()) do
        local record = record_for(window)
        if eligible(window) and ((record and record.stacked) or not window.floating) then
            record = record or { id = window.stable_id, scroll = scroll_position(window) }
            if not record.stacked and not prepared then record.scroll = scroll_position(window) end
            records[window.address] = record
            entries[#entries + 1] = { window = window, record = record,
                internal = record.tiled_fullscreen and record.tiled_fullscreen.internal or (window.fullscreen == 2 and 2 or 0),
                client = record.tiled_fullscreen and record.tiled_fullscreen.client or (window.fullscreen == 2 and 2 or 0) }
        end
    end
    table.sort(entries, function(a, b)
        local sa, sb = a.record.scroll or {}, b.record.scroll or {}
        if (sa.column or 100000) ~= (sb.column or 100000) then return (sa.column or 100000) < (sb.column or 100000) end
        if (sa.row or 0) ~= (sb.row or 0) then return (sa.row or 0) < (sb.row or 0) end
        return a.window.stable_id < b.window.stable_id
    end)
    for _, entry in ipairs(entries) do
        cancel_minimize(entry.window)
        visual_animation(entry.window, "clear")
        if entry.window.floating then
            entry.record.geometry = entry.record.stacking_state and entry.record.stacking_state.geometry
                or (entry.record.maximized and entry.record.maximized.geometry) or geometry(entry.window)
        end
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = entry.window, internal = 0, client = 0, action = "set" }))
        entry.record.maximized, entry.record.tiled_fullscreen = nil, nil
        hl.dispatch(hl.dsp.window.set_prop({ window = entry.window, prop = "rounding", value = "unset" }))
        float(entry.window, true)
    end
    local previous
    for _, entry in ipairs(entries) do
        local window, scroll = entry.window, entry.record.scroll or {}
        if previous then hl.dispatch(hl.dsp.focus({ window = previous })) end
        float(window, false)
        -- A scrolling column always has exactly one full-height window, even
        -- for windows created in stacking mode or previously consumed rows.
        hl.dispatch(hl.dsp.focus({ window = window }))
        hl.dispatch(hl.dsp.layout("colresize " .. tostring(scroll.width or default_column_width(window))))
        entry.record.stacked = false
        previous = window
    end
    for _, entry in ipairs(entries) do
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = entry.window,
            internal = entry.internal, client = entry.client, action = "set" }))
        -- The first decoration refresh runs while these windows are floating.
        -- Reapply tiled CSD state and its final configure after the column has
        -- reclaimed the complete height, keeping stacking geometry independent.
        visual_animation(entry.window, "client-state")
    end
end

local function workspace_animation()
    local scrolling = layouts.mode() == "scrolling"
    local camera = hl.plugin.hyprbars and hl.plugin.hyprbars.workspace_camera
    if camera then
        local vars = require("variables")
        camera("gestures", vars.gestureFingers, vars.workspaceSwipeFingers)
        camera("enable", scrolling)
    end
    hl.animation({ leaf = "workspaces", enabled = scrolling and not camera, speed = 5,
        bezier = "standard", style = "slidevert" })
end

local function settle_animation()
    if animation_timer then animation_timer:set_enabled(false) end
    local camera = hl.plugin.hyprbars and hl.plugin.hyprbars.workspace_camera
    if camera then camera("enable", false) end
    -- Workspace moves are bookkeeping during a mode change. Keep native window
    -- animations enabled, without sliding the temporary workspaces into view.
    hl.animation({ leaf = "workspaces", enabled = false, speed = 5, bezier = "standard", style = "slidevert" })
    animation_timer = hl.timer(function()
        animation_timer = nil
        workspace_animation()
    end, { timeout = 420, type = "oneshot" })
end

local function appearance()
    local rounding = tiled_rounding
    local border = layouts.mode() == "stacking" and 0 or tiled_border
    if rounding ~= last_rounding or border ~= last_border then
        hl.config({ decoration = { rounding = rounding }, general = { border_size = border } })
        last_rounding, last_border = rounding, border
    end
end

local function pointer_focus()
    local scrolling = layouts.mode() == "scrolling"
    local hover = scrolling and tiling_preferences.focusOnHover == true
    -- Scrolling follows the pointer by default; stacking and the optional
    -- click-focus mode keep keyboard focus until a click.
    hl.config({ input = { follow_mouse = hover and 1 or 2,
        float_switch_override_focus = hover and tiled_focus.float_switch_override_focus or 0 },
        misc = { mouse_move_focuses_monitor = hover and tiled_focus.mouse_move_focuses_monitor or false,
            focus_on_activate = scrolling and tiled_focus.focus_on_activate or false },
        -- Soft pointer focus may select an exposed tile without moving the
        -- tape. Native click and keyboard focus still bring it fully into view.
        scrolling = { follow_min_visible = tiling_preferences.edgeScroll == false and 1
            or tiled_focus.follow_min_visible } })
    if hl.plugin.hyprbars and hl.plugin.hyprbars.tiling_hover then
        hl.plugin.hyprbars.tiling_hover("focus_on_hover", tiling_preferences.focusOnHover == true)
    end
end

function layouts.tiling(options)
    options = options or tiling_preferences
    local appearance_changed = false
    if options.focusBorderColor ~= nil then
        tiling_preferences.focusBorderColor = valid_border_role(options.focusBorderColor) and options.focusBorderColor or "primary"
        hl.config({ general = { col = { active_border = active_border(theme_palette) } } })
    end
    if options.focusBorderWidth ~= nil then
        tiled_border = math.max(0, math.min(10, math.floor(tonumber(options.focusBorderWidth) or 1)))
        tiling_preferences.focusBorderWidth = tiled_border
        appearance_changed = true
    end
    if options.windowRounding ~= nil then
        tiled_rounding = math.max(0, math.min(60, math.floor(tonumber(options.windowRounding) or 15)))
        tiling_preferences.windowRounding = tiled_rounding
        appearance_changed = true
    end
    if appearance_changed then appearance() end
    if options.focusOnHover ~= nil then tiling_preferences.focusOnHover = options.focusOnHover == true end
    if options.edgeScroll ~= nil then tiling_preferences.edgeScroll = options.edgeScroll ~= false end
    pointer_focus()
    if options.gaps ~= nil then tiling_preferences.gaps = options.gaps ~= false end
    if options.gapsIn ~= nil then
        tiled_gaps_in = math.max(0, math.min(100, math.floor(tonumber(options.gapsIn) or 5)))
        tiling_preferences.gapsIn = tiled_gaps_in
    end
    if options.gapsOut ~= nil then
        tiled_gaps_out = math.max(0, math.min(100, math.floor(tonumber(options.gapsOut) or 10)))
        tiling_preferences.gapsOut = tiled_gaps_out
    end
    if options.autoscroll ~= nil then tiling_preferences.autoscroll = options.autoscroll ~= false end
    if hl.plugin.hyprbars and hl.plugin.hyprbars.autoscroll then
        hl.plugin.hyprbars.autoscroll("enable", tiling_preferences.autoscroll ~= false)
    end
    local enabled = tiling_preferences.gaps ~= false
    local changed = last_tiling_gaps ~= nil and (last_tiling_gaps ~= enabled
        or last_gaps_in ~= tiled_gaps_in or last_gaps_out ~= tiled_gaps_out)
    last_tiling_gaps = enabled
    last_gaps_in, last_gaps_out = tiled_gaps_in, tiled_gaps_out
    -- Lua css_gap accepts a number or a table, unlike legacy config strings.
    hl.config({ general = { gaps_in = enabled and tiled_gaps_in or 0,
        gaps_out = enabled and tiled_gaps_out or 0 } })
    -- The same outer gap applies to every window count and column width.
    local outer = enabled and tiled_gaps_out or 0
    hl.workspace_rule({ workspace = "w[tv1]s[false]", gaps_out = outer })
    hl.workspace_rule({ workspace = "f[1]s[false]", gaps_out = outer })
    -- Separated windows use the global radius. Touching tiles use square
    -- shared edges without shadows; their outer frame clips the outer corners.
    -- Reuse a fixed rule rather than accumulating effects on each setting edit.
    if not touching_tiles_rule then
        touching_tiles_rule = hl.window_rule({ name = "hyprstack-touching-tiles", enabled = not enabled,
            match = { float = false }, rounding = 0, no_shadow = true })
    elseif touching_tiles_rule:is_enabled() == enabled then
        touching_tiles_rule:set_enabled(not enabled)
    end
    if changed and hl.plugin.hyprbars and hl.plugin.hyprbars.tile_frame then
        if hl.plugin.hyprbars.workspace_camera then hl.plugin.hyprbars.workspace_camera("settle") end
        hl.plugin.hyprbars.tile_frame("settle")
    end
end

function layouts.shadows(options)
    options = options or read(config_dir .. "/effects.json")
    local size = math.max(0, math.min(60, math.floor(tonumber(options.shadowSize) or 18)))
    local opacity = math.max(0, math.min(1, tonumber(options.shadowOpacity) or 0.35))
    local color = string.format("rgba(000000%02x)", math.floor(opacity * 255 + 0.5))
    hl.config({ decoration = { shadow = {
        enabled = options.windowShadows ~= false and size > 0 and opacity > 0,
        range = size, render_power = 3,
        color = color, color_inactive = color,
    } } })
end

function layouts.window_effects(options, game_mode)
    if type(options) == "string" then options = json.decode(options) end
    if game_mode ~= nil then effects_game_mode = game_mode == true end
    return window_effects.apply(options or read(config_dir .. "/effects.json"), effects_game_mode, theme_palette)
end

function layouts.toggle_gaps()
    if layouts.mode() ~= "scrolling" then return end
    tiling_preferences = read(config_dir .. "/tiling.json")
    tiling_preferences.gaps = tiling_preferences.gaps == false
    layouts.tiling(tiling_preferences)
    write(config_dir .. "/tiling.json", tiling_preferences)
end

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local native_dir = (os.getenv("HYPRSTACK_DATA_DIR") or
    (os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/hyprstack") .. "/native/"
local plugin_override = os.getenv("HYPRSTACK_TITLEBAR_PLUGIN")
local plugin_path = plugin_override or read(config_dir .. "/titlebars.json").path or native_dir .. "hyprstack-bars.so"
-- Older local installations pinned a versioned snapshot inside this directory.
-- Updates rebuild the canonical module, so loading that snapshot after a
-- Hyprland upgrade leaves all native navigation and decoration policies absent.
-- Keep explicit external builds, including the environment override, intact.
if not plugin_override and plugin_path:sub(1, #native_dir) == native_dir
    and plugin_path:sub(#native_dir + 1):match("^hyprstack%-bars%-[^/]+%.so$") then
    plugin_path = native_dir .. "hyprstack-bars.so"
end
local plugin_file = io.open(plugin_path, "r")
if plugin_file then plugin_file:close(); hl.plugin.load(plugin_path) end
-- Loading is deferred until the config has been parsed. The plugin requests a
-- reload after registering its effects; the first pass must use core rules only.
local no_titlebar = hl.plugin.hyprbars and hl.plugin.hyprbars.clear_buttons and true or nil

function layouts.theme(palette)
    palette = palette or theme_palette
    theme_palette = palette
    layouts.window_effects()
    local hex = (palette.outline or "808080"):gsub("#", "")
    local grey = math.floor((tonumber(hex:sub(1,2),16) or 128)*0.2126
        + (tonumber(hex:sub(3,4),16) or 128)*0.7152
        + (tonumber(hex:sub(5,6),16) or 128)*0.0722 + 0.5)
    hl.config({ general = { col = {
        active_border = active_border(palette),
        inactive_border = string.format("rgba(%02x%02x%02xff)", grey, grey, grey),
    } } })
    if not hl.plugin.hyprbars or not hl.plugin.hyprbars.clear_buttons then return end
    if hl.plugin.hyprbars.snap_zones then
        hl.plugin.hyprbars.snap_zones("theme", palette.primary or "#7e9cd8", palette.surfaceContainerLow or "#1f2335")
    end
    if hl.plugin.hyprbars.tiling_hover then
        hl.plugin.hyprbars.tiling_hover("theme", palette.primary or "#7e9cd8", palette.surfaceContainerLow or "#1f2335")
    end
    local function color(name, fallback) return "rgb(" .. (palette[name] or fallback):gsub("#", "") .. ")" end
    local function luminance(value)
        local hex = value:gsub("#", "")
        local function linear(start)
            local channel = (tonumber(hex:sub(start, start + 1), 16) or 0) / 255
            return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055)^2.4
        end
        return linear(1)*0.2126 + linear(3)*0.7152 + linear(5)*0.0722
    end
    -- Lowest containers are dark in dark schemes; surfaceDim is darker in
    -- light schemes. Select a scheme colour below the application's surface.
    local header = palette.surface or "#24242c"
    for _, role in ipairs({ "surfaceContainerLowest", "surfaceDim", "background" }) do
        if palette[role] and luminance(palette[role]) < luminance(header) then header = palette[role] end
    end
    if luminance(header) >= luminance(palette.surface or "#24242c") then
        header = header:gsub("#", ""):gsub("%x%x", function(channel)
            return string.format("%02x", math.floor(tonumber(channel, 16) * 0.85))
        end)
    end
    local header_color = "rgb(" .. header:gsub("#", "") .. ")"
    -- Address and stable ID come from the decoration's owning window, so a
    -- button always acts on that window even when another one has the focus.
    local command = "python3 " .. string.format("%q", script_dir .. "window-action.py") .. " "
    hl.config({ plugin = { hyprbars = {
        enabled = layouts.mode() == "stacking", bar_height = titlebar_height,
        bar_color = header_color, col = { text = color("onSurface", "dcd7ba") },
        inactive_button_color = header_color,
        bar_text_font = "Noto Sans", bar_text_size = 12, bar_text_weight = 400, bar_text_align = "center",
        bar_padding = 8, bar_button_padding = 4, bar_part_of_window = true,
        bar_precedence_over_border = true, bar_blur = false, icon_on_hover = false,
        on_double_click = command .. "maximize",
        on_minimize = command .. "minimize",
        on_maximize = command,
    } } })
    hl.window_rule({ name = "hyprstack-active-title", match = { focus = true },
        ["hyprbars:bar_color"] = header_color,
        ["hyprbars:title_color"] = color("primary", "7e9cd8") })
    hl.window_rule({ name = "hyprstack-client-decorations", match = {
        class = "(?i)^(thorium(-browser)?|chromium(-browser)?|google-chrome.*|firefox|librewolf|zen(-browser)?|com\\.ayugram\\.desktop|AyugramDesktop|org\\.telegram\\.desktop|TelegramDesktop|discord|org\\.gnome\\..*)$"
    }, ["hyprbars:no_bar"] = true })
    hl.plugin.hyprbars.clear_buttons()
    local controls = { close = "e46876", maximize = "98bb6c", minimize = "e6c384" }
    for _, operation in ipairs({ "close", "maximize", "minimize" }) do
        hl.plugin.hyprbars.add_button({ bg_color = "rgb(" .. controls[operation] .. ")",
            fg_color = "rgb(1f1f28)", size = 26, icon = "hyprstack:" .. operation, action = command .. operation })
    end
    for _, window in ipairs(hl.get_windows()) do
        if window.mapped then visual_animation(window, "decorations") end
    end
end

local function refresh_decorations(animate, keep_appearance)
    local state_home = os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state"
    layouts.theme(read(state_home .. "/hyprstack/scheme.json").colours)
    local scrolling = layouts.mode() == "scrolling"
    hl.config({ cursor = { no_warps = not scrolling or tiled_no_warps } })
    pointer_focus()
    hl.config({ general = { resize_on_border = not scrolling or tiled_resize_on_border,
        extend_border_grab_area = scrolling and tiled_border_grab or 8 } })
    if scrolling ~= swipe_enabled then
        local vars = require("variables")
        hl.gesture({ fingers = vars.gestureFingers, direction = "horizontal", action = scrolling and "scroll_move" or "unset" })
        hl.gesture({ fingers = vars.workspaceSwipeFingers, direction = "vertical", action = scrolling and "workspace" or "unset" })
        swipe_enabled = scrolling
    end
    -- Border width changes atomically with the layout. There is no interpolated
    -- appearance value, so a per-frame timer only repeats the same settings.
    if not keep_appearance then appearance() end
end

local function change(action, views, transition)
    if changing then return end
    changing = true
    pending_pins = {}
    if transition then settle_animation() end
    local ok, err = pcall(function() preserve_focus(action, views) end)
    -- Pinning assigns the window to its monitor's active workspace. Wait until
    -- all temporary focus changes and monitor views have been restored.
    for _, window in ipairs(pending_pins) do
        if window.mapped then hl.dispatch(hl.dsp.window.pin({ window = window, action = "enable" })) end
    end
    pending_pins = {}
    changing = false
    if not animation_timer then workspace_animation() end
    if transition then refresh_decorations(true) end
    save()
    if not ok then error(err) end
end

function layouts.toggle_floating(window)
    window = window or hl.get_active_window()
    if layouts.mode() ~= "scrolling" or not window or not eligible(window) then return end
    change(function()
        local record = record_for(window) or { id = window.stable_id }
        records[window.address] = record
        record.stacked = false
        if window.floating then
            record.floating_geometry = geometry(window)
            float(window, false)
            hl.dispatch(hl.dsp.focus({ window = window }))
            hl.dispatch(hl.dsp.layout("colresize " .. tostring((record.scroll or {}).width or default_column_width(window))))
        else
            record.scroll = scroll_position(window)
            float(window, true)
            set_geometry(window, fit_geometry(window, record.floating_geometry, 0))
            raise(window)
        end
        visual_animation(window, "clear-maximize-echo")
        visual_animation(window, "client-state")
    end)
end

local switcher_active = false
function layouts.end_switcher(action)
    if not switcher_active then return end
    switcher_active = false
    hl.dispatch(hl.dsp.submap("reset"))
    if action then hl.dispatch(hl.dsp.global("hyprstack:switcher" .. action)) end
end

function layouts.window_cycle(direction)
    if layouts.mode() ~= "stacking" then
        hl.dispatch(hl.dsp.window.cycle_next({ next = direction > 0 }))
        return
    end
    switcher_active = true
    hl.dispatch(hl.dsp.submap("hyprstack-switcher"))
    hl.dispatch(hl.dsp.global("hyprstack:switcher" .. (direction > 0 and "Next" or "Prev")))
end

local function gather(target)
    local targets = {}
    if per_monitor then
        for _, monitor in ipairs(hl.get_monitors()) do
            if monitor.active_workspace then targets[monitor.name] = monitor.active_workspace end
        end
    end
    local workspaces = {}
    for _, workspace in ipairs(hl.get_workspaces()) do
        if not workspace.special then workspaces[#workspaces + 1] = workspace end
    end
    table.sort(workspaces, function(a, b)
        if a == target then return b ~= target end
        if b == target then return false end
        return a.id < b.id
    end)
    tiled_views = capture_views()
    local windows = {}
    for _, workspace in ipairs(workspaces) do
        for _, window in ipairs(workspace:get_windows()) do
            if window.mapped then
                local record = record_for(window) or { id = window.stable_id }
                local monitor = window.monitor or workspace.monitor or hl.get_active_monitor()
                local destination = targets[monitor and monitor.name] or target
                windows[#windows + 1] = { window = window, workspace = key(destination) }
                local origin = per_monitor and window.pinned and monitor and monitor.active_workspace or workspace
                record.origin = { workspace = key(origin), monitor = monitor and monitor.name }
                if not window.floating then
                    record.scroll = scroll_position(window)
                end
                record.tiled_fullscreen = { internal = window.fullscreen, client = window.fullscreen_client }
                record.workspace = key(destination)
                records[window.address] = record
            end
        end
    end
    -- Snapshot every source before moves change scrolling column indices.
    for _, entry in ipairs(windows) do
        move_to_workspace(entry.window, entry.workspace)
    end
    if not per_monitor then return { target } end
    local result = {}
    for _, workspace in pairs(targets) do result[#result + 1] = workspace end
    return result
end

local function restore()
    local windows = hl.get_windows()
    -- A mode switch is also a recovery point: no window remains in the hidden
    -- minimized workspace after returning to the scrolling layout.
    for _, window in ipairs(windows) do
        local record = record_for(window)
        if record and record.minimized then layouts.restore_window(window, false) end
    end
    for _, window in ipairs(windows) do
        local record = record_for(window)
        if window.mapped and window.workspace and not window.workspace.special and record and record.origin then
            local origin = record.origin
            local monitor, workspace = hl.get_monitor(origin.monitor), hl.get_workspace(origin.workspace)
            if not workspace then
                if monitor then hl.dispatch(hl.dsp.focus({ monitor = monitor })) end
                hl.dispatch(hl.dsp.focus({ workspace = origin.workspace }))
                workspace = hl.get_workspace(origin.workspace)
            end
            if monitor and workspace.monitor ~= monitor then
                hl.dispatch(hl.dsp.workspace.move({ workspace = origin.workspace, monitor = monitor }))
            end
            move_to_workspace(window, origin.workspace)
            record.workspace = origin.workspace
            record.origin = nil
        end
    end
    for _, workspace in ipairs(hl.get_workspaces()) do
        if not workspace.special then tile(workspace, true) end
    end
    tiled_views = {}
end

local function remember_window(window)
    local record = record_for(window)
    if not eligible(window) and not (record and record.minimized) then return end
    record = record or { id = window.stable_id }
    records[window.address] = record
    local hidden = record.minimized
    local monitor = hidden and hl.get_monitor(hidden.monitor) or window.monitor
    local normal = record.maximized and record.maximized.geometry or (hidden and hidden.geometry) or geometry(window)
    record.stacking_state = { geometry = normal, maximized = record.maximized ~= nil,
        monitor = monitor and monitor.name, monitor_x = monitor and monitor.x, monitor_y = monitor and monitor.y }
end

local function remember_stacking()
    -- Capture floating positions before workspace moves or fullscreen resets
    -- can change them. Tiling has its own independent geometry and fullscreen.
    for _, window in ipairs(hl.get_windows()) do
        remember_window(window)
    end
end

function layouts.move_monitor(direction)
    local window = hl.get_active_window()
    local source = window and window.monitor
    if not source or not eligible(window) then return end
    local horizontal = direction == "left" or direction == "right"
    local sign = (direction == "left" or direction == "up") and -1 or 1
    local target, score
    local source_width, source_height = monitor_size(source)
    local center_x = source.x + source_width / 2
    local center_y = source.y + source_height / 2
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor ~= source then
            local width, height = monitor_size(monitor)
            local dx = monitor.x + width / 2 - center_x
            local dy = monitor.y + height / 2 - center_y
            local axis, cross = horizontal and dx or dy, horizontal and dy or dx
            -- A taller display alongside this one is still a side neighbour,
            -- even when its centre is above/below this display's centre.
            local on_side = direction == "right" and monitor.x >= source.x + source_width - 1
                or direction == "left" and monitor.x + width <= source.x + 1
                or direction == "down" and monitor.y >= source.y + source_height - 1
                or direction == "up" and monitor.y + height <= source.y + 1
            if axis * sign > 0 and (layouts.mode() ~= "stacking" or on_side) then
                local distance = math.abs(axis) + math.abs(cross) * 2
                if not score or distance < score then target, score = monitor, distance end
            end
        end
    end
    -- Keep the existing horizontal wrap only for scrolling navigation.
    if not target and horizontal and layouts.mode() ~= "stacking" then
        local extreme
        for _, monitor in ipairs(hl.get_monitors()) do
            if monitor ~= source and (not extreme or monitor.x * sign < extreme) then
                target, extreme = monitor, monitor.x * sign
            end
        end
    end
    if not target or not target.active_workspace then
        if layouts.mode() == "stacking" then
            local record = record_for(window)
            if record and record.maximized then return end
            local bounds, box = maximized_geometry(window), geometry(window)
            if direction == "left" then box.x = bounds.x
            elseif direction == "right" then box.x = bounds.x + bounds.width - box.width
            elseif direction == "up" then box.y = bounds.y
            elseif direction == "down" then box.y = bounds.y + bounds.height - box.height end
            set_geometry(window, fit_geometry(window, box, 0))
            remember_window(window)
            save()
        end
        return
    end
    local record = record_for(window)
    local column_width = window.layout and window.layout.column and window.layout.column.width
    local normal = record and record.maximized and record.maximized.geometry or geometry(window)
    local translated = { x = normal.x + target.x - source.x, y = normal.y + target.y - source.y,
        width = normal.width, height = normal.height }
    local warp = hl.get_config("cursor.no_warps")
    hl.config({ cursor = { no_warps = true } })
    local ok, err = pcall(function()
        hl.dispatch(hl.dsp.window.move({ window = window, monitor = target, follow = true }))
        if layouts.mode() == "stacking" then
            record = record or { id = window.stable_id }
            records[window.address] = record
            local destination = key(target.active_workspace)
            record.workspace = destination
            record.origin = { workspace = destination, monitor = target.name }
            record.scroll = {}
            if record.maximized then
                record.maximized.geometry = fit_geometry(window, translated, 0)
                set_maximized(window, true)
            else
                set_geometry(window, fit_geometry(window, translated, 0))
            end
            remember_window(window)
            raise(window)
        elseif record then
            record.workspace, record.scroll = key(window.workspace), scroll_position(window)
        end
        hl.dispatch(hl.dsp.focus({ window = window }))
        if layouts.mode() == "scrolling" and column_width then
            hl.dispatch(hl.dsp.layout("colresize " .. tostring(column_width)))
            if record then record.scroll = scroll_position(window) end
        end
        save()
    end)
    hl.config({ cursor = { no_warps = warp } })
    if not ok then error(err) end
end

function layouts.snap(address, stable_id, zone, monitor_name)
    if layouts.mode() ~= "stacking" then return false end
    local window = hl.get_window("address:" .. address)
    if not window or window.stable_id ~= stable_id or not eligible(window) or window.fullscreen == 2 then return false end
    local zones = {
        full={0,0,1,1}, left={0,0,0.5,1}, right={0.5,0,1,1}, top={0,0,1,0.5}, bottom={0,0.5,1,1},
        ["top-left"]={0,0,0.5,0.5}, ["top-right"]={0.5,0,1,0.5},
        ["bottom-left"]={0,0.5,0.5,1}, ["bottom-right"]={0.5,0.5,1,1},
    }
    local fraction, monitor = zones[zone], hl.get_monitor(monitor_name)
    if not fraction or not monitor or not monitor.active_workspace then return false end
    local record = record_for(window) or { id=window.stable_id, workspace=key(window.workspace) }
    records[window.address] = record
    local normal = (record.snapped and record.snapped.geometry) or record.drag_origin
        or (record.maximized and record.maximized.geometry) or geometry(window)
    local source = window.monitor
    if source ~= monitor then
        normal={x=normal.x+monitor.x-source.x,y=normal.y+monitor.y-source.y,width=normal.width,height=normal.height}
        hl.dispatch(hl.dsp.window.move({window=window,monitor=monitor,follow=true}))
        record.workspace=key(monitor.active_workspace)
        record.origin={workspace=record.workspace,monitor=monitor.name}
    end
    if record.maximized then set_maximized(window,false) end
    record.drag_origin=nil
    if zone == "full" then
        record.snapped=nil
        record.maximized={geometry=fit_geometry(window,normal,0)}
        set_maximized(window,true)
    else
        record.snapped={geometry=fit_geometry(window,normal,0),zone=zone}
        local bounds = maximized_geometry(window)
        local bar = client_decorated(window) and 0 or titlebar_height
        local height = bounds.height + bar
        local x1,x2=math.floor(bounds.width*fraction[1]+0.5),math.floor(bounds.width*fraction[3]+0.5)
        local y1,y2=math.floor(height*fraction[2]+0.5),math.floor(height*fraction[4]+0.5)
        hl.dispatch(hl.dsp.window.fullscreen_state({window=window,internal=0,client=0,action="set"}))
        hl.dispatch(hl.dsp.window.set_prop({window=window,prop="rounding",value="0"}))
        set_geometry(window,{x=bounds.x+x1,y=bounds.y+y1,width=x2-x1,height=math.max(1,y2-y1-bar)})
    end
    remember_window(window)
    raise(window)
    hl.dispatch(hl.dsp.focus({window=window}))
    save()
    return true
end

function layouts.set_overview(active)
    local camera = hl.plugin.hyprbars and hl.plugin.hyprbars.workspace_camera
    if overview_active ~= (active == true) and camera then camera("pause", active == true) end
    overview_active = active == true
    if overview_watchdog then overview_watchdog:set_enabled(false) end
    if overview_active then
        -- Recover normal navigation if the shell exits while showing overview.
        overview_watchdog = hl.timer(function()
            layouts.set_overview(false)
            layouts.overview_scene("reset")
        end,
            { timeout = 1500, type = "oneshot" })
    end
end

local native_module_error = "Hyprstack overview requires the native module built for the running Hyprland. Rebuild Hyprstack and log in again; run hyprstack-doctor for details."

function layouts.overview_scene(action, value)
    local renderer = hl.plugin.hyprbars and hl.plugin.hyprbars.overview_scene
    if not renderer then
        if action == "status" then return json.encode({ active = false, available = false, error = native_module_error }) end
        if action == "input" or action == "geometry" then return json.encode({}) end
        return false
    end
    return renderer(action, value)
end

function layouts.overview_snapshot(name)
    if not (hl.plugin.hyprbars and hl.plugin.hyprbars.overview_scene) then
        return json.encode({ error = native_module_error, renderer = { active = false, available = false } })
    end
    local monitor = hl.get_monitor(name)
    if not monitor or not monitor.active_workspace then return json.encode({}) end
    local width, height = monitor_size(monitor)
    local result = { mode = layouts.mode(), monitor = name, x = monitor.x, y = monitor.y,
        width = width, height = height, workspace = monitor.active_workspace.id,
        workspaces = {}, windows = {},
        renderer = json.decode(layouts.overview_scene("status")),
        input = json.decode(layouts.overview_scene("input")) }
    layouts.overview_scene("heartbeat")
    local visible_geometry = json.decode(layouts.overview_scene("geometry"))
    local active = hl.get_active_window()
    result.active = active and active.address or ""
    if layouts.mode() == "scrolling" then
        local base = layouts.workspace_base(monitor)
        for index = 1, workspace_count do result.workspaces[#result.workspaces + 1] = base + index end
    else
        result.workspaces = { monitor.active_workspace.id }
    end
    for _, window in ipairs(hl.get_windows()) do
        local record = record_for(window)
        local hidden = record and record.minimized
        if window.mapped and window.workspace and not window.pinned
            and ((not window.workspace.special and window.monitor == monitor)
                or (layouts.mode() == "stacking" and hidden and hidden.monitor == name)) then
            local box = hidden and hidden.geometry or visible_geometry[window.address] or geometry(window)
            local scroll = not window.floating and scroll_position(window) or {}
            result.windows[#result.windows + 1] = { address = window.address,
                identity = window.stable_id, title = window.title,
                appId = window.class, workspace = hidden and (tonumber(hidden.workspace) or monitor.active_workspace.id) or window.workspace.id,
                minimized = hidden ~= nil, floating = window.floating,
                column = scroll.column, row = scroll.row, columnWidth = scroll.width,
                extents = visible_geometry[window.address] and visible_geometry[window.address].extents or nil,
                x = box.x - monitor.x, y = box.y - monitor.y,
                width = math.max(1, box.width), height = math.max(1, box.height) }
        end
    end
    table.sort(result.windows, function(a, b)
        if a.workspace ~= b.workspace then return a.workspace < b.workspace end
        if (a.column or 100000) ~= (b.column or 100000) then return (a.column or 100000) < (b.column or 100000) end
        if (a.row or 0) ~= (b.row or 0) then return (a.row or 0) < (b.row or 0) end
        return a.identity < b.identity
    end)
    if layouts.mode() == "scrolling" then
        local present = {}
        for _, id in ipairs(result.workspaces) do present[id] = true end
        for _, entry in ipairs(result.windows) do
            if not present[entry.workspace] then
                result.workspaces[#result.workspaces + 1] = entry.workspace
                present[entry.workspace] = true
            end
        end
        if not present[result.workspace] then result.workspaces[#result.workspaces + 1] = result.workspace end
        table.sort(result.workspaces)
    end
    return json.encode(result)
end

function layouts.overview_close(address, identity, name)
    if not overview_active then return end
    local window = address and hl.get_window("address:" .. address)
    local monitor = hl.get_monitor(name)
    if not window or not window.mapped or not monitor or identity ~= window.stable_id then return end
    local record = record_for(window)
    if window.monitor ~= monitor and not (record and record.minimized and record.minimized.monitor == name) then return end
    hl.dispatch(hl.dsp.window.close({ window = window }))
end

function layouts.overview_activate(address, identity, workspace, name)
    local window = address ~= "" and hl.get_window("address:" .. address) or nil
    if window and window.mapped and identity == window.stable_id then
        if layouts.mode() == "stacking" then
            layouts.action("activate", address, identity)
        else
            hl.dispatch(hl.dsp.focus({ window = window }))
        end
    else
        local monitor = hl.get_monitor(name)
        if monitor then hl.dispatch(hl.dsp.focus({ monitor = monitor })) end
        if layouts.mode() == "scrolling" and tonumber(workspace) then
            hl.dispatch(hl.dsp.focus({ workspace = tostring(workspace) }))
        end
    end
end

function layouts.toggle()
    layouts.close_secondary_overlay()
    layouts.end_switcher("Cancel")
    local monitor = hl.get_active_monitor()
    local workspace = monitor and monitor.active_workspace
    if not workspace then return end
    if layouts.mode() == "scrolling" then
        change(function()
            local targets = gather(workspace)
            preferences.mode = "stacking"
            refresh_decorations(false, true)
            for _, target in ipairs(targets) do stack(target, true) end
        end, nil, true)
    else
        change(function()
            remember_stacking()
            preferences.mode = "scrolling"
            refresh_decorations(false, true)
            restore()
        end, #tiled_views > 0 and tiled_views or nil, true)
    end
end

function layouts.move(number, follow)
    if layouts.mode() ~= "scrolling" then return end
    local window = hl.get_active_window()
    local monitor = window and window.monitor or hl.get_active_monitor()
    if not window or (per_monitor and (number < 1 or number > workspace_count)) then return end
    local target = tostring(layouts.workspace_base(monitor) + number)
    hl.dispatch(hl.dsp.window.move({ window = window, workspace = target, follow = follow == true }))
    local record = record_for(window)
    if record and layouts.mode() == "stacking" then
        record.origin = { workspace = target, monitor = monitor.name }
        record.scroll = {}
        save()
    end
end

function layouts.restore_window(window, focus)
    local record = record_for(window)
    if not record or not record.minimized then return end
    local hidden = record.minimized
    cancel_minimize(window)
    local monitor = hl.get_monitor(hidden.monitor) or hl.get_active_monitor()
    local destination = layouts.mode() == "stacking" and monitor and monitor.active_workspace
    local workspace = destination and key(destination) or hidden.workspace
    record.minimized = nil
    move_to_workspace(window, workspace)
    set_geometry(window, fit_geometry(window, hidden.geometry, 0))
    hl.dispatch(hl.dsp.window.fullscreen_state({ window = window,
        internal = hidden.internal, client = hidden.client, action = "set" }))
    visual_animation(window, "workspace-opacity")
    if layouts.mode() == "stacking" then
        if record.maximized then set_maximized(window, true) end
        visual_animation(window, "from", task_target(window))
        local function finish_restore()
            if not window.mapped or record_for(window) ~= record or record.minimized then return end
            if visual_animation(window, "busy") then
                minimize_timers[window.address] = hl.timer(finish_restore, { timeout = 16, type = "oneshot" })
            else
                visual_animation(window, "clear")
                minimize_timers[window.address] = nil
            end
        end
        minimize_timers[window.address] = hl.timer(finish_restore, { timeout = 240, type = "oneshot" })
    else
        visual_animation(window, "clear")
    end
    if hidden.pinned then hl.dispatch(hl.dsp.window.pin({ window = window, action = "enable" })) end
    if focus ~= false then
        raise(window)
        hl.dispatch(hl.dsp.focus({ window = window }))
    end
    save()
end

function layouts.action(operation, address, stable_id)
    local window = address and hl.get_window("address:" .. address) or hl.get_active_window()
    if not window or not window.mapped then return end
    if stable_id and stable_id ~= window.stable_id then return end
    if operation == "toggle-floating" then layouts.toggle_floating(window); return end
    if layouts.mode() ~= "stacking" then return end
    local record = record_for(window) or { id = window.stable_id, workspace = key(window.workspace) }
    records[window.address] = record
    -- CSD apps can echo a maximize/unmaximize state after fullscreen exit or
    -- minimize. That delayed state request must not undo a newer minimize.
    -- A hidden client cannot initiate a fresh click on its native titlebar.
    if record.minimized and (operation == "maximize-set" or operation == "maximize-unset") then return end
    if operation == "close" then
        hl.dispatch(hl.dsp.window.close({ window = window }))
    elseif operation == "restore" or operation == "activate" then
        if record.minimized then
            layouts.restore_window(window)
        else
            local monitor = window.monitor
            if monitor and monitor.active_workspace and window.workspace ~= monitor.active_workspace then
                move_to_workspace(window, key(monitor.active_workspace))
            end
            raise(window)
            hl.dispatch(hl.dsp.focus({ window = window }))
        end
    elseif operation == "task-click" or operation == "task-minimize" then
        local plugin = hl.plugin.hyprbars
        local was_focused = plugin and plugin.task_focused and plugin.task_focused(address, stable_id)
        if was_focused == nil then was_focused = hl.get_active_window() == window end
        if not record.minimized and was_focused then
            layouts.action("minimize", address, stable_id)
        else
            layouts.action("activate", address, stable_id)
        end
    elseif operation == "minimize" and not record.minimized and not window.workspace.special then
        local monitor = window.monitor
        record.minimized = { workspace = key(window.workspace), monitor = monitor.name,
            internal = window.fullscreen, client = window.fullscreen_client,
            pinned = window.pinned, geometry = geometry(window), animating = true }
        if window.pinned then hl.dispatch(hl.dsp.window.pin({ window = window, action = "disable" })) end
        -- An ordinary maximized client stays maximized while its image moves.
        -- Clearing client state here can make CSD apps restore their normal size.
        if window.fullscreen ~= 0 then
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
        end
        local hidden = record.minimized
        if hl.get_active_window() == window then layouts.clear_focus() end
        visual_animation(window, "to", task_target(window))
        local function await_animation()
            if not window.mapped or record_for(window) ~= record or record.minimized ~= hidden then return end
            if visual_animation(window, "busy") then
                minimize_timers[window.address] = hl.timer(await_animation, { timeout = 16, type = "oneshot" })
            else
                finish_minimize(window, hidden)
            end
        end
        minimize_timers[window.address] = hl.timer(await_animation, { timeout = 240, type = "oneshot" })
        save()
    elseif operation == "maximize" or operation == "maximize-set" or operation == "maximize-unset" or operation == "maximize-snap" then
        if record.minimized then layouts.restore_window(window) end
        if operation == "maximize-snap" and record.drag_origin then
            record.maximized = { geometry = record.drag_origin }
        end
        record.drag_origin = nil
        set_maximized(window, operation == "maximize-set" or operation == "maximize-snap" or (operation == "maximize" and not record.maximized))
        -- Background clients may send delayed state requests. Geometry/state
        -- updates must not activate them as if a taskbar button was clicked.
        if operation == "maximize" or operation == "maximize-snap" or hl.get_active_window() == window then
            hl.dispatch(hl.dsp.focus({ window = window }))
            raise(window)
        end
        remember_window(window)
        save()
    elseif operation == "resize-start" then
        -- A native border/CSD resize is now a normal window, without first
        -- restoring an old box underneath the compositor's active drag.
        record.maximized, record.video_fullscreen, record.drag_origin, record.snapped = nil, nil, nil, nil
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
        hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "rounding", value = "unset" }))
        visual_animation(window, "clear")
        remember_window(window)
        save()
    elseif operation == "drag-restore" then
        if record.snapped then
            local normal = record.snapped.geometry
            record.snapped = nil
            hl.dispatch(hl.dsp.window.set_prop({window=window,prop="rounding",value="unset"}))
            set_geometry(window,fit_geometry(window,normal,0))
        end
    elseif operation == "drag-start" then
        record.drag_origin = geometry(window)
    elseif operation == "remember-stacking" then
        record.drag_origin = nil
        remember_window(window)
        save()
    end
end

-- Numeric workspace IDs are global in Hyprland. Give each output a stable,
-- disjoint range; the shell and shortcuts present these as local numbers.
local function apply_workspace_bank_rules()
    for name, base in pairs(workspace_config.monitor_bases) do
        for number = 1, workspace_count do
            hl.workspace_rule({ workspace = tostring(base + number), monitor = name,
                persistent = true, default = number == 1 })
        end
    end
end

local function prepare_workspace_banks()
    local views = capture_views()
    if not per_monitor then return views, function() end end
    local remap = {}
    local connected = hl.get_monitors()
    for _, monitor in ipairs(connected) do layouts.workspace_base(monitor) end
    table.sort(connected, function(a, b) return layouts.workspace_base(a) < layouts.workspace_base(b) end)
    -- Remember the current pair even while the shortcut option is off. Old
    -- connector names must not replace this output after it is disconnected.
    if #connected >= 2 then workspace_config.secondary_monitor = connected[2].name end
    for _, workspace in ipairs(hl.get_workspaces()) do
        local monitor = workspace.monitor
        if workspace.id and workspace.id > 0 and monitor then
            local base = layouts.workspace_base(monitor)
            if workspace.id <= base or workspace.id > base + workspace_count then
                local owner
                for name, start in pairs(workspace_config.monitor_bases) do
                    if workspace.id > start and workspace.id <= start + workspace_count then owner = name; break end
                end
                -- Keep a disconnected output's bank intact until it returns.
                if not owner or (not workspace_config.initialized and hl.get_monitor(owner)) then
                    remap[key(workspace)] = tostring(base + (workspace.id - 1) % workspace_count + 1)
                end
            end
        end
    end
    for _, view in ipairs(views) do
        local id = tonumber(view.workspace)
        local base = layouts.workspace_base(view.monitor)
        view.workspace = remap[view.workspace] or view.workspace
        if id and (id <= base or id > base + workspace_count) then
            view.workspace = tostring(base + (id - 1) % workspace_count + 1)
        end
    end
    for _, view in ipairs(tiled_views) do view.workspace = remap[view.workspace] or view.workspace end
    local moves = {}
    for _, window in ipairs(hl.get_windows()) do
        if window.mapped and window.workspace and remap[key(window.workspace)] then
            moves[#moves + 1] = { window = window, target = remap[key(window.workspace)] }
        end
    end
    for _, record in pairs(records) do
        record.workspace = remap[record.workspace] or record.workspace
        if record.origin and remap[record.origin.workspace] then
            record.origin.workspace = remap[record.origin.workspace]
        end
    end
    return views, function()
        apply_workspace_bank_rules()
        for _, entry in ipairs(moves) do move_to_workspace(entry.window, entry.target) end
        -- Existing empty workspaces also need their configured output.
        local ids = {}
        for _, workspace in ipairs(hl.get_workspaces()) do
            if workspace.id and workspace.id > 0 then ids[#ids + 1] = workspace.id end
        end
        for _, id in ipairs(ids) do
            local workspace = hl.get_workspace(tostring(id))
            if workspace and workspace.id then
                for name, base in pairs(workspace_config.monitor_bases) do
                    local monitor = hl.get_monitor(name)
                    if monitor and id > base and id <= base + workspace_count
                        and workspace.monitor ~= monitor then
                        hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = monitor }))
                    end
                end
            end
        end
        workspace_config.initialized = true
        write(config_dir .. "/workspaces.json", workspace_config)
    end
end

function layouts.enforce_workspace_banks()
    local views, prepare = prepare_workspace_banks()
    change(prepare, views)
end

function layouts.configure_workspaces(options)
    workspace_config.secondary_on_special = options.secondary_on_special == true
    write(config_dir .. "/workspaces.json", workspace_config)
    if not workspace_config.secondary_on_special then
        layouts.close_secondary_overlay()
        layouts.enforce_workspace_banks()
    end
    save()
end

local function remember_workspace_views()
    if changing then return end
    for _, monitor in ipairs(hl.get_monitors()) do
        local base = layouts.workspace_base(monitor)
        local workspace = monitor.active_workspace
        if workspace and workspace.id and workspace.id > base and workspace.id <= base + workspace_count
            and (workspace.windows > 0 or workspace_bank_views[tostring(base)] == nil) then
            workspace_bank_views[tostring(base)] = workspace.id
        end
    end
end

local function secondary_window_state(window, workspace)
    local monitor = window.monitor
    local record = record_for(window)
    return { id = window.stable_id, workspace = tostring(workspace), floating = window.floating,
        pinned = window.pinned, geometry = geometry(window), scroll = scroll_position(window),
        monitor_x = monitor and monitor.x or 0, monitor_y = monitor and monitor.y or 0,
        fullscreen = window.fullscreen, fullscreen_client = window.fullscreen_client,
        controller_state = record and json.decode(json.encode(record)) or false }
end

-- Only the temporary special workspace changes. Keep all regular monitor views
-- and the window controller's original workspace/stacking records intact.
local function secondary_transition(action)
    local views = capture_views()
    local camera = hl.plugin.hyprbars and hl.plugin.hyprbars.workspace_camera
    if camera then camera("pause", true) end
    changing = true
    local ok, err = pcall(function()
        without_cursor_warps(function()
            action()
            for _, view in ipairs(views) do
                local monitor = hl.get_monitor(view.monitor)
                if monitor then monitor:set_workspace(view.workspace) end
            end
        end)
    end)
    changing = false
    if camera then camera("pause", overview_active) end
    save()
    if not ok then error(err) end
end

local function restore_secondary_windows(overlay)
    local windows = {}
    for _, window in ipairs(hl.get_windows()) do
        if window.mapped and window.workspace and window.workspace.name == "special:" .. secondary_overlay_name then
            local state = overlay.windows[window.address]
            if not state or state.id ~= window.stable_id then
                state = secondary_window_state(window, overlay.workspace)
            end
            windows[#windows + 1] = { window = window, state = state }
        end
    end
    table.sort(windows, function(a, b)
        return (a.state.scroll.column or 100000) < (b.state.scroll.column or 100000)
    end)
    for _, entry in ipairs(windows) do
        local window, state = entry.window, entry.state
        local returning = hl.plugin.hyprbars and hl.plugin.hyprbars.secondary_return
        if returning then returning(window.address, window.stable_id) end
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
        hl.dispatch(hl.dsp.window.move({ window = window, workspace = state.workspace, follow = false }))
        if window.floating ~= state.floating then float(window, state.floating) end
        if state.floating and window.monitor then
            local box = state.geometry
            set_geometry(window, fit_geometry(window, { x = box.x + window.monitor.x - state.monitor_x,
                y = box.y + window.monitor.y - state.monitor_y, width = box.width, height = box.height }, 0))
        elseif state.scroll.width and window.layout and window.layout.column then
            hl.dispatch(hl.dsp.focus({ window = window }))
            hl.dispatch(hl.dsp.layout("colresize " .. tostring(state.scroll.width)))
        end
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = state.fullscreen,
            client = state.fullscreen_client, action = "set" }))
        if state.pinned then hl.dispatch(hl.dsp.window.pin({ window = window, action = "enable" })) end
        records[window.address] = state.controller_state or nil
    end
    overlay.windows = {}
end

function layouts.close_secondary_overlay(refocus)
    if not secondary_overlay then return end
    local overlay = secondary_overlay
    local active = hl.get_active_window()
    local keep_focus = refocus == false and active and active.workspace
        and active.workspace.name ~= "special:" .. secondary_overlay_name
        and { address = active.address, id = active.stable_id } or overlay.focus
    if secondary_overlay_timer then secondary_overlay_timer:set_enabled(false) end
    secondary_transition(function()
        local monitor = hl.get_monitor(overlay.monitor)
        -- Keep the source workspace visible while moving its windows. Hyprland
        -- records that monitor for the native cross-output flight only then.
        restore_secondary_windows(overlay)
        if monitor and monitor.active_special_workspace
            and monitor.active_special_workspace.name == "special:" .. secondary_overlay_name then
            monitor:set_special_workspace(nil)
        end
        secondary_overlay = nil
    end)
    local monitor = hl.get_monitor(overlay.monitor)
    if monitor then
        hl.dispatch(hl.dsp.focus({ monitor = monitor }))
        local window = keep_focus and hl.get_window("address:" .. keep_focus.address)
        if window and window.mapped and window.stable_id == keep_focus.id then
            hl.dispatch(hl.dsp.focus({ window = window }))
        end
    end
end

function layouts.show_secondary_workspace(number)
    local overlay = secondary_overlay
    if not overlay or number < 1 or number > workspace_count then return end
    local monitor = hl.get_monitor(overlay.monitor)
    if not monitor then layouts.close_secondary_overlay(false); return end
    secondary_transition(function()
        restore_secondary_windows(overlay)
        overlay.workspace = overlay.base + number
        workspace_bank_views[tostring(overlay.base)] = overlay.workspace
        -- Capture every column before the first move changes its neighbours.
        local windows = {}
        for _, window in ipairs(hl.get_windows()) do
            if window.mapped and window.workspace and window.workspace.id == overlay.workspace then
                overlay.windows[window.address] = secondary_window_state(window, overlay.workspace)
                windows[#windows + 1] = window
            end
        end
        save()
        hl.workspace_rule({ workspace = "special:" .. secondary_overlay_name, monitor = overlay.monitor,
            gaps_out = 40, layout = "scrolling" })
        for _, window in ipairs(windows) do
            local state = overlay.windows[window.address]
            if window.pinned then hl.dispatch(hl.dsp.window.pin({ window = window, action = "disable" })) end
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
            hl.dispatch(hl.dsp.window.move({ window = window, workspace = "special:" .. secondary_overlay_name, follow = false }))
            if window.floating then
                local box = state.geometry
                set_geometry(window, fit_geometry(window, { x = box.x + monitor.x - state.monitor_x,
                    y = box.y + monitor.y - state.monitor_y, width = box.width, height = box.height }, 0))
            elseif state.scroll.width then
                hl.dispatch(hl.dsp.focus({ window = window }))
                hl.dispatch(hl.dsp.layout("colresize " .. tostring(state.scroll.width)))
            end
        end
    end)
    hl.dispatch(hl.dsp.focus({ monitor = monitor }))
    local special = monitor.active_special_workspace
    if not special or special.name ~= "special:" .. secondary_overlay_name then
        hl.dispatch(hl.dsp.workspace.toggle_special(secondary_overlay_name))
    end
end

function layouts.toggle_special()
    if secondary_overlay then layouts.close_secondary_overlay(); return end
    if not per_monitor or not workspace_config.secondary_on_special then
        return require("utils.functions").toggle("specialws")()
    end
    local source = hl.get_active_monitor()
    if not source or not source.active_workspace then return end
    local special = source.active_special_workspace
    if special then return require("utils.functions").toggle("specialws")() end
    remember_workspace_views()
    local home, candidates = layouts.workspace_base(source), {}
    for name, base in pairs(workspace_config.monitor_bases) do
        if base ~= home then candidates[#candidates + 1] = { name = name, base = base } end
    end
    table.sort(candidates, function(a, b)
        local a_preferred, b_preferred = a.name == workspace_config.secondary_monitor, b.name == workspace_config.secondary_monitor
        if a_preferred ~= b_preferred then return a_preferred end
        local a_connected, b_connected = hl.get_monitor(a.name) ~= nil, hl.get_monitor(b.name) ~= nil
        if a_connected ~= b_connected then return a_connected end
        return a.base < b.base
    end)
    local target = candidates[1]
    if not target then return end
    local active = hl.get_active_window()
    secondary_overlay = { monitor = source.name, owner = target.name, base = target.base, windows = {},
        workspace = workspace_bank_views[tostring(target.base)] or target.base + 1,
        focus = active and { address = active.address, id = active.stable_id } or nil }
    navigation_since_reload = true
    layouts.show_secondary_workspace(secondary_overlay.workspace - target.base)
    secondary_overlay_timer = hl.timer(function()
        if changing or not secondary_overlay then return end
        local monitor = hl.get_monitor(secondary_overlay.monitor)
        local special = monitor and monitor.active_special_workspace
        if not special or special.name ~= "special:" .. secondary_overlay_name then layouts.close_secondary_overlay(false) end
    end, { timeout = 120, type = "repeat" })
    save()
end

local function sync_window(window)
    if changing or not window or not window.mapped or not window.workspace or window.workspace.special then return end
    local record = record_for(window)
    if layouts.mode() == "stacking" and (not record or not record.origin) then
        record = record or { id = window.stable_id }
        local monitor = window.monitor or window.workspace.monitor or hl.get_active_monitor()
        record.origin = { workspace = key(window.workspace), monitor = monitor and monitor.name }
        records[window.address] = record
    end
    if not eligible(window) then return end
    if layouts.mode() == "scrolling" and not window.floating then
        local scroll = scroll_position(window)
        record = record or { id = window.stable_id }
        records[window.address] = record
        -- The native target is between spaces during move_to_workspace. Its
        -- plugin retains the width; keep the last valid scrolling record here.
        if scroll.width then record.scroll = scroll end
    end
    if record and record.workspace ~= key(window.workspace) then
        record.workspace = key(window.workspace)
    end
    if layouts.mode() == "stacking" and not window.floating then
        change(function() stack(window.workspace) end)
    elseif layouts.mode() == "scrolling" and record and record.stacked then
        change(function() tile(window.workspace) end)
    end
end

local function place_telegram_webview(window)
    if not window or not window.mapped or not telegram_class_names[window.class:lower()] then return end
    local record = record_for(window)
    if record and record.webview then return end
    local plugin = hl.plugin.hyprbars
    if not plugin or not plugin.animate_window then return end
    local parent_address = plugin.animate_window(window.address, window.stable_id, "telegram-webview-parent")
    if not parent_address then return end
    local parent
    for _, candidate in ipairs(hl.get_windows()) do
        if candidate.address == parent_address and telegram_class_names[candidate.class:lower()] then
            parent = candidate
            break
        end
    end
    if not parent or not parent.monitor then return end
    -- The helper has a different app ID and an initially empty title. It is
    -- still an auxiliary window, even before its bot supplies a title.
    record = record or { id = window.stable_id }
    record.webview, record.stacked, record.maximized = true, false, nil
    records[window.address] = record
    if not window.floating then float(window, true) end
    if window.workspace ~= parent.workspace then move_to_workspace(window, key(parent.workspace)) end
    local box = geometry(window)
    local width, height = monitor_size(parent.monitor)
    box.width = math.min(box.width, math.floor(width * 0.82))
    box.height = math.min(box.height, math.floor(height * 0.82))
    set_geometry(window, box)
    plugin.animate_window(window.address, window.stable_id, "center", true)
    if record.origin then record.origin = { workspace = key(window.workspace), monitor = window.monitor.name } end
    save()
end

local media_placing = {}
local function place_telegram_media(window)
    if not window or not window.mapped or not telegram_media(window) then return end
    if media_placing[window.address] then return end
    media_placing[window.address] = true
    local parent, priority
    for _, candidate in ipairs(hl.get_windows()) do
        if candidate ~= window and candidate.mapped and not candidate.hidden and candidate.workspace
            and not candidate.workspace.special and candidate.class:lower() == window.class:lower()
            and not telegram_media(candidate) then
            local history = candidate.focus_history_id
            local score = (candidate.pid == window.pid and 0 or 1000000)
                + (candidate.visible and 0 or 100000)
                + (history >= 0 and history or 10000)
            if not priority or score < priority then parent, priority = candidate, score end
        end
    end
    -- Telegram opens its ordinary viewer with showMaximized(), which would
    -- otherwise hide the chat under Hyprland's exclusive maximize state.
    -- Actual video fullscreen is independent and remains available.
    if window.fullscreen == 1 or window.fullscreen_client == 1 then
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = window, internal = 0, client = 0, action = "set" }))
    end
    if not window.floating then float(window, true) end
    local record = record_for(window)
    if record then record.stacked, record.maximized = false, nil end
    if parent then
        if window.workspace ~= parent.workspace then move_to_workspace(window, key(parent.workspace)) end
        -- Fullscreen/maximized playback keeps the client's requested mode.
        -- Windowed media stays on the originating chat's output, centered in
        -- its work area even when the chat's scrolling column is offscreen.
        if window.fullscreen == 0 and window.fullscreen_client == 0 and not telegram_pip(window) then
            local box = geometry(window)
            local width, height = monitor_size(parent.monitor)
            -- A maximized first map or a recreated Qt handle can carry the
            -- output-sized geometry. Leave some chat visible around it.
            box.width = math.min(box.width, math.floor(width * 0.82))
            box.height = math.min(box.height, math.floor(height * 0.82))
            box.x = parent.monitor.x + (width - box.width) / 2
            box.y = parent.monitor.y + (height - box.height) / 2
            set_geometry(window, fit_geometry(window, box, 0))
            local plugin = hl.plugin.hyprbars
            if plugin and plugin.animate_window then
                plugin.animate_window(window.address, window.stable_id, "center", true)
            end
        end
    end
    visual_animation(window, "client-state")
    raise(window)
    media_placing[window.address] = nil
end

local function schedule_telegram_media(window)
    if not window or not telegram_media(window) then return end
    hl.timer(function()
        if window.mapped then place_telegram_media(window) end
    end, { timeout = 1, type = "oneshot" })
end

local function schedule_float_center(window)
    -- Capture floating state before stacking converts an ordinary new tile.
    -- Placement runs once after mapping; later drags and resizes stay intact.
    if not window.floating or telegram_media(window) or window.pinned then return end
    hl.timer(function()
        local plugin = hl.plugin.hyprbars
        if window.mapped and window.floating and plugin and plugin.animate_window then
            local record = record_for(window)
            local placed = plugin.animate_window(window.address, window.stable_id, "center",
                telegram_auxiliary(window) or (record and record.webview) or false)
            -- A parentless Qt window can first map on the focused output.
            -- Stacking must remember its originating application's workspace
            -- after placement, so switching back to tiles keeps them together.
            local record = placed and record_for(window)
            if record and record.origin and window.workspace and window.monitor then
                record.origin = { workspace = key(window.workspace), monitor = window.monitor.name }
                save()
            end
        end
    end, { timeout = 1, type = "oneshot" })
end

hl.config({ general = { layout = "scrolling" }, scrolling = { fullscreen_on_one_column = false, column_width = 0.5 } })
hl.window_rule({ name = "hyprstack-default-column", match = {
    class = "negative:(?i)^(thorium.*|chromium.*|google-chrome.*|firefox|librewolf|zen(-browser)?)$"
}, scrolling_width = 0.5 })
-- Apply width before mapping: resizing an already opened browser would start
-- a second camera/size animation. Manually selected column widths are retained.
hl.window_rule({ name = "hyprstack-browser-column", match = {
    class = "(?i)^(thorium.*|chromium.*|google-chrome.*|firefox|librewolf|zen(-browser)?)$"
}, scrolling_width = 1.0 })
layouts.monitor_directions()
hl.on("monitor.added", layouts.monitor_directions)

hl.window_rule({ name = "hyprstack-no-telegram-activation", match = {
    class = telegram_classes
}, suppress_event = "activate activatefocus", focus_on_activate = false })
hl.window_rule({ name = "hyprstack-telegram-media", match = {
    class = telegram_classes, initial_title = "(?i)^(" .. table.concat(telegram_media_titles, "|") .. ")$"
}, float = true, center = true, suppress_event = "maximize", ["hyprbars:no_bar"] = no_titlebar })
hl.window_rule({ name = "hyprstack-telegram-media-state", match = {
    class = telegram_classes, title = "(?i)^(" .. table.concat(telegram_media_titles, "|") .. ")$"
}, suppress_event = "maximize", ["hyprbars:no_bar"] = no_titlebar })
hl.window_rule({ name = "hyprstack-telegram-pip", match = {
    class = telegram_classes, initial_title = "(?i)^(" .. table.concat(telegram_pip_titles, "|") .. ")$"
}, float = true, keep_aspect_ratio = true, pin = true, no_initial_focus = true,
    suppress_event = "maximize", ["hyprbars:no_bar"] = no_titlebar })
hl.window_rule({ name = "hyprstack-telegram-auxiliary", match = {
    class = telegram_classes, initial_title = "(?i)^(" .. table.concat(telegram_auxiliary_titles, "|") .. ")$"
}, float = true, center = true, suppress_event = "maximize", ["hyprbars:no_bar"] = no_titlebar })

local function replace_binds(keys, action, description, options)
    if type(keys) == "table" then
        for _, value in pairs(keys) do replace_binds(value, action, description, options) end
    elseif type(keys) == "string" and keys:match("%S") then
        hl.unbind(keys)
        hl.bind(keys, action, { description = description, repeating = options == "repeat" })
    end
end
local shortcut_vars = require("variables")
replace_binds(shortcut_vars.kbSpecialWs, layouts.toggle_special, "Workspaces: Toggle special workspace")
replace_binds(shortcut_vars.kbToggleWindowFloating, layouts.toggle_floating, "Windows: Toggle floating")
replace_binds(shortcut_vars.kbWindowCycleNext, function() layouts.window_cycle(1) end, "Windows: Next window", "repeat")
replace_binds(shortcut_vars.kbWindowCyclePrev, function() layouts.window_cycle(-1) end, "Windows: Previous window", "repeat")
hl.define_submap("hyprstack-switcher", function()
    hl.bind("ALT + Tab", function() layouts.window_cycle(1) end,
        { repeating = true, description = "Windows: Next window" })
    hl.bind("ALT + SHIFT + Tab", function() layouts.window_cycle(-1) end,
        { repeating = true, description = "Windows: Previous window" })
    hl.bind("Right", function() layouts.window_cycle(1) end,
        { repeating = true, ignore_mods = true, description = "Windows: Next window" })
    hl.bind("Left", function() layouts.window_cycle(-1) end,
        { repeating = true, ignore_mods = true, description = "Windows: Previous window" })
    hl.bind("Return", function() layouts.end_switcher("Accept") end,
        { ignore_mods = true, description = "Windows: Activate selected window" })
    hl.bind("Escape", function() layouts.end_switcher("Cancel") end,
        { ignore_mods = true, description = "Windows: Cancel window switching" })
    for _, key in ipairs({ "Alt_L", "Alt_R" }) do
        hl.bind("ALT + " .. key, function() layouts.end_switcher("Accept") end,
            -- Alt was pressed before entering this submap. Hyprland matches
            -- releases against the submap at press time; later Tab presses
            -- must not shadow the held modifier either.
            { release = true, ignore_mods = true, non_consuming = true,
                submap_universal = true, transparent = true, description = "Windows: Activate selected window" })
    end
end)
hl.unbind("SUPER + CTRL + F")
hl.bind("SUPER + CTRL + F", layouts.toggle_width, { description = "Windows: Toggle column width" })
for _, direction in ipairs({ "Left", "Right", "Up", "Down" }) do
    local shortcut = "SUPER + SHIFT + " .. direction
    hl.unbind(shortcut)
    hl.bind(shortcut, function() layouts.move_monitor(direction:lower()) end,
        { description = "Windows: Move window to monitor " .. direction:lower() })
end
hl.bind("SUPER + CTRL + SHIFT + M", layouts.toggle, { description = "Windows: Toggle scrolling or stacking" })
for workspace = 1, 10 do
    local shortcut = "SUPER + SHIFT + " .. tostring(workspace % 10)
    hl.unbind(shortcut)
    hl.bind(shortcut, function() layouts.move(workspace, false) end,
        { description = "Workspaces: Move window to workspace " .. workspace })
    if per_monitor then
        for _, modifiers in ipairs({ "SUPER", "SUPER + CTRL" }) do
            local focus_shortcut = modifiers .. " + " .. tostring(workspace % 10)
            hl.unbind(focus_shortcut)
            hl.bind(focus_shortcut, function() layouts.focus(workspace) end,
                { description = "Workspaces: Go to workspace " .. workspace })
            local move_shortcut = modifiers .. " + ALT + " .. tostring(workspace % 10)
            hl.unbind(move_shortcut)
            hl.bind(move_shortcut, function() layouts.move(workspace, true) end,
                { description = "Workspaces: Move and follow window to workspace " .. workspace })
        end
    end
end
for _, direction in ipairs({ { "J", "r+1" }, { "K", "r-1" }, { "H", "left" }, { "L", "right" } }) do
    local shortcut, target = "SUPER + " .. direction[1], direction[2]
    hl.unbind(shortcut)
    hl.bind(shortcut, function()
        if overview_active then
            hl.dispatch(hl.dsp.global("hyprstack:overview" .. direction[1]))
            return
        end
        if layouts.mode() ~= "scrolling" then return end
        if target == "left" or target == "right" then
            layouts.focus_column(target == "left" and -1 or 1)
        else
            layouts.step(target == "r+1" and 1 or -1)
        end
    end, { repeating = true, description = "Workspaces: " .. ({ J = "Next workspace", K = "Previous workspace",
        H = "Previous column", L = "Next column" })[direction[1]] })
end
for _, direction in ipairs({ { "H", "l" }, { "L", "r" } }) do
    local shortcut = "SUPER + SHIFT + " .. direction[1]
    hl.unbind(shortcut)
    hl.bind(shortcut, function()
        if layouts.mode() == "scrolling" then hl.dispatch(hl.dsp.layout("swapcol " .. direction[2])) end
    end, { repeating = true, description = "Windows: Swap column " .. direction[2] })
end
for _, direction in ipairs({ { "J", 1 }, { "K", -1 } }) do
    local shortcut = "SUPER + SHIFT + " .. direction[1]
    hl.unbind(shortcut)
    hl.bind(shortcut, function()
        local monitor = hl.get_active_monitor()
        if monitor and monitor.active_workspace then
            layouts.move(monitor.active_workspace.id - layouts.workspace_base(monitor) + direction[2], true)
        end
    end, { description = "Workspaces: Move window to " .. (direction[2] == 1 and "next" or "previous") .. " workspace" })
end
hl.unbind("SUPER + O")
hl.bind("SUPER + O", hl.dsp.global("hyprstack:overview"), { description = "Shell: Open overview" })
hl.unbind("SUPER + G")
hl.bind("SUPER + G", layouts.toggle_gaps, { description = "Windows: Toggle window gaps" })
hl.unbind("SUPER + SUPER_L")
hl.unbind("SUPER + D")
-- Wrap the global action so Hyprland can shadow the modifier-only shortcut
-- when another key in a Super chord has already been used.
hl.bind("SUPER + SUPER_L", function()
    if hl.plugin.hyprbars and hl.plugin.hyprbars.solo_super and not hl.plugin.hyprbars.solo_super() then return end
    hl.dispatch(hl.dsp.global("hyprstack:dashboard"))
end, { release = true, ignore_mods = true, transparent = hl.plugin.hyprbars and hl.plugin.hyprbars.solo_super ~= nil,
    description = "Shell: Open dashboard" })
hl.bind("SUPER + D", hl.dsp.global("hyprstack:launcher"), { description = "Shell: Open launcher" })
if per_monitor then
    for _, direction in ipairs({
        { 1, { "SUPER + mouse_down", "CTRL + SUPER + Right", "SUPER + Page_Down", "CTRL + SUPER + mouse_down" },
            { "SUPER + ALT + mouse_down", "SUPER + ALT + Page_Down", "CTRL + SUPER + SHIFT + Right" } },
        { -1, { "SUPER + mouse_up", "CTRL + SUPER + Left", "SUPER + Page_Up", "CTRL + SUPER + mouse_up" },
            { "SUPER + ALT + mouse_up", "SUPER + ALT + Page_Up", "CTRL + SUPER + SHIFT + Left" } },
    }) do
        for _, shortcut in ipairs(direction[2]) do
            hl.unbind(shortcut)
            hl.bind(shortcut, function() layouts.step(direction[1]) end, { repeating = not shortcut:find("mouse_"),
                description = "Workspaces: " .. (direction[1] == 1 and "Next workspace" or "Previous workspace") })
        end
        for _, shortcut in ipairs(direction[3]) do
            hl.unbind(shortcut)
            hl.bind(shortcut, function()
                local monitor = hl.get_active_monitor()
                if monitor and monitor.active_workspace then
                    layouts.move(monitor.active_workspace.id - layouts.workspace_base(monitor) + direction[1], true)
                end
            end, { repeating = not shortcut:find("mouse_"), description = "Workspaces: Move window to "
                .. (direction[1] == 1 and "next" or "previous") .. " workspace" })
        end
    end
    hl.on("monitor.added", function()
        hl.timer(function()
            layouts.close_secondary_overlay(false)
            layouts.enforce_workspace_banks()
        end, { timeout = 100, type = "oneshot" })
    end)
    hl.on("workspace.active", remember_workspace_views)
    hl.on("window.active", remember_workspace_views)
end
hl.on("window.open", function(window)
    place_telegram_webview(window)
    schedule_float_center(window)
    place_telegram_media(window)
    sync_window(window)
    schedule_telegram_media(window)
end)
hl.on("window.title", schedule_telegram_media)
hl.on("window.move_to_workspace", sync_window)
hl.on("window.fullscreen", function(window)
    if telegram_media(window) then
        schedule_telegram_media(window)
        return
    end
    if changing or layouts.mode() ~= "stacking" or not eligible(window) then return end
    local internal, client = window.fullscreen, window.fullscreen_client
    local record = record_for(window)
    if internal == 2 and record then
        if not record.minimized then
            cancel_minimize(window)
            visual_animation(window, "clear")
        end
        record.video_fullscreen = true
        return
    end
    if internal == 0 and client == 0 and record and record.video_fullscreen then
        record.video_fullscreen = nil
        if record.maximized then
            local maximized = record.maximized
            hl.timer(function()
                if layouts.mode() == "stacking" and eligible(window) and record_for(window) == record
                    and record.maximized == maximized and not record.minimized and window.fullscreen == 0
                    and window.fullscreen_client == 0 then
                    set_maximized(window, true)
                    save()
                end
            end, { timeout = 1, type = "oneshot" })
            return
        end
    end
    if internal == 1 or (internal == 0 and client == 0 and record and record.maximized) then
        local maximized = record and record.maximized
        hl.timer(function()
            if layouts.mode() ~= "stacking" or not eligible(window) or record_for(window) ~= record
                or (record and (record.minimized or record.maximized ~= maximized))
                or window.fullscreen ~= internal or window.fullscreen_client ~= client then return end
            set_maximized(window, internal == 1)
            save()
        end, { timeout = 1, type = "oneshot" })
    end
end)
hl.on("monitor.layout_changed", function()
    layouts.monitor_directions()
    if changing then return end
    for _, window in ipairs(hl.get_windows()) do
        local record = record_for(window)
        if layouts.mode() == "stacking" and record and record.maximized and not record.minimized and window.fullscreen == 0 then
            set_geometry(window, maximized_geometry(window))
        end
        sync_window(window)
    end
end)
hl.on("window.close", function(window)
    cancel_minimize(window)
    records[window.address] = nil
    save()
end)
hl.on("config.reloaded", function()
    refresh_decorations(false)
    layouts.effects()
    layouts.tiling()
    for _, window in ipairs(hl.get_windows()) do schedule_telegram_media(window) end
end)

-- Runtime records survive config reloads, but never another compositor session.
local live = {}
for _, window in ipairs(hl.get_windows()) do live[window.address] = window.stable_id end
for address, record in pairs(records) do
    if live[address] ~= record.id then records[address] = nil end
end
-- Reloading during an animation completes the bookkeeping without losing an
-- application in a tiny rectangle on the visible desktop.
for _, window in ipairs(hl.get_windows()) do
    local record = record_for(window)
    if record and record.minimized and record.minimized.animating then
        finish_minimize(window, record.minimized)
    end
end
-- A configuration reload is a recovery point for temporary borrowed windows.
layouts.close_secondary_overlay(false)
local initial_views, prepare_banks = prepare_workspace_banks()
local initial_active, initial_focused = hl.get_active_window(), hl.get_active_monitor()
if per_monitor then
    -- Monitor managers can append conflicting workspace rules after this file.
    -- Reapply the banks after all configuration sources and their persistent
    -- workspaces have loaded, then restore the views captured before parsing.
    local reload_focus_pending = false
    local function remember_navigation()
        -- A click or an external dispatcher can change focus before the delayed
        -- bank repair. Preserve it just like navigation through our bindings.
        if reload_focus_pending and not changing then navigation_since_reload = true end
    end
    hl.on("window.active", remember_navigation)
    hl.on("workspace.active", remember_navigation)
    hl.on("monitor.focused", remember_navigation)
    hl.on("config.reloaded", function()
        apply_workspace_bank_rules()
        -- Verification has no outputs or event loop. Hyprland 0.57 cannot
        -- destroy Lua timers created in that mode, and there is no bank to fix.
        if not hl.get_active_monitor() then return end
        reload_focus_pending = true
        hl.timer(function()
            reload_focus_pending = false
            layouts.enforce_workspace_banks()
            if not navigation_since_reload then restore_focus(initial_active, initial_focused, initial_views) end
        end, { timeout = 100, type = "oneshot" })
    end)
end
change(function()
    prepare_banks()
    for _, workspace in ipairs(hl.get_workspaces()) do
        if not workspace.special and layouts.mode() == "stacking" then
            stack(workspace)
        else
            for _, window in ipairs(workspace:get_windows()) do
                local record = record_for(window)
                if record and record.stacked then tile(workspace); break end
            end
        end
    end
end, initial_views)
refresh_decorations(false)
local normalized_columns = false
-- Existing maximized floats may still carry the old unsynchronized property
-- after a reload. Repair it without changing their size, focus or workspace.
for _, window in ipairs(hl.get_windows()) do
    place_telegram_webview(window)
    -- A config reload also destroys Lua timers. A restored window has no
    -- minimized record, so its native transformer must be cleared explicitly.
    visual_animation(window, "clear")
    if eligible(window) then
        if layouts.mode() == "scrolling" and visual_animation(window, "normalize-tiled-maximize") then
            local record = record_for(window)
            if record then record.scroll = scroll_position(window) end
            normalized_columns = true
        end
        hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "sync_fullscreen", value = "1" }))
        local record = record_for(window)
        hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = "rounding",
            value = layouts.mode() == "stacking" and record and record.maximized and "0" or "unset" }))
    end
end
if normalized_columns then save() end
layouts.effects()
layouts.tiling()
layouts.shadows()
layouts.window_effects()

return layouts
