local vars = require("variables")
local fn   = require("utils.functions")


local descriptions = {
    kbLauncher = "Shell: Open launcher",
    kbSession = "Session: Open session menu",
    kbShowSidebar = "Shell: Open notification centre",
    kbClearNotifs = "Shell: Clear notifications",
    kbShowPanels = "Shell: Show or hide panels",
    kbLock = "Session: Lock screen",
    kbRestoreLock = "Session: Restore lock screen",
    kbPrevWs = "Workspaces: Previous workspace",
    kbNextWs = "Workspaces: Next workspace",
    kbPrevWsGroup = "Workspaces: Previous workspace group",
    kbNextWsGroup = "Workspaces: Next workspace group",
    kbMoveWinToWsNext = "Workspaces: Move window to next workspace",
    kbMoveWinToWsPrev = "Workspaces: Move window to previous workspace",
    kbMoveWinToWsSpecial = "Workspaces: Move window to special workspace",
    kbMoveWinFromWsSpecial = "Workspaces: Return window from special workspace",
    kbWindowCycleNext = "Windows: Next window",
    kbWindowCyclePrev = "Windows: Previous window",
    kbWindowGroupCycleNext = "Windows: Next window in group",
    kbWindowGroupCyclePrev = "Windows: Previous window in group",
    kbToggleGroup = "Windows: Toggle window group",
    kbUngroup = "Windows: Remove window from group",
    kbGroupLockActive = "Windows: Lock window group",
    kbWindowDecreaseWidth = "Windows: Decrease window width",
    kbWindowIncreaseWidth = "Windows: Increase window width",
    kbWindowDecreaseHeight = "Windows: Decrease window height",
    kbWindowIncreaseHeight = "Windows: Increase window height",
    kbMoveWindow = "Windows: Drag window",
    kbResizeWindow = "Windows: Resize window",
    kbCenterWindow = "Windows: Centre window",
    kbNormalizeWindow = "Windows: Restore window size",
    kbWindowPip = "Windows: Picture in picture",
    kbPinWindow = "Windows: Pin window",
    kbWindowFullscreen = "Windows: Toggle fullscreen",
    kbWindowBorderedFullscreen = "Windows: Toggle maximized",
    kbToggleWindowFloating = "Windows: Toggle floating",
    kbCloseWindow = "Windows: Close window",
    kbSpecialWs = "Workspaces: Toggle special workspace",
    kbSystemMonitorWs = "Workspaces: Toggle system monitor workspace",
    kbMusicWs = "Workspaces: Toggle music workspace",
    kbTodoWs = "Workspaces: Toggle todo workspace",
    kbTerminal = "Applications: Open terminal",
    kbBrowser = "Applications: Open browser",
    kbEditor = "Applications: Open editor",
    kbFileExplorer = "Applications: Open file manager",
    kbAudioSettings = "Applications: Open audio settings",
    kbScreenshot = "Capture: Screenshot current monitor",
    kbScreenshotFreeze = "Capture: Screenshot frozen region",
    kbScreenshotRegion = "Capture: Screenshot region",
    kbRecord = "Capture: Start or stop recording",
    kbRecordSound = "Capture: Record with audio",
    kbRecordRegion = "Capture: Record region",
    kbColorPicker = "Capture: Pick colour",
    kbSleep = "Session: Suspend",
    kbClipboard = "Clipboard: Open clipboard history",
    kbClipboardDel = "Clipboard: Delete clipboard entry",
    kbClipboardPasteLatest = "Clipboard: Paste latest entry",
    kbEmoji = "Clipboard: Open emoji picker",
}

-- Flags
local locked           = { locked = true }
local mouse            = { mouse = true }
local release          = { release = true }
local repeating        = { repeating = true }
local locked_repeating = { locked = true, repeating = true }

local function normalise_keybind(key)
    return key:gsub("%s+", ""):lower()
end

local function valid_keybind(key)
    return type(key) == "string" and key:match("%S") ~= nil
end

local function repeating_unless_mouse(key)
    return not normalise_keybind(key):find("mouse", 1, true) and repeating or nil
end

local function flatten_keybinds(keybinds, keys)
    keys = keys or {}

    if type(keybinds) == "table" then
        for _, keybind in pairs(keybinds) do
            flatten_keybinds(keybind, keys)
        end
    elseif valid_keybind(keybinds) then
        keys[#keys + 1] = keybinds
    end

    return keys
end

local function create_bind(keybinds, action, flags, description)
    local get_flags = type(flags) == "function" and flags or function()
        return flags
    end

    for _, key in ipairs(flatten_keybinds(keybinds)) do
        local options = {}
        for name, value in pairs(get_flags(key) or {}) do options[name] = value end
        options.description = description
        hl.bind(key, action, options)
    end
end

local function bind_variable(name, action, flags)
    create_bind(vars[name], action, flags, descriptions[name])
end

local function extend_keybind(base, suffix)
    return valid_keybind(base) and base .. " + " .. suffix or nil
end

-- Launcher
local launcher_default = normalise_keybind("SUPER + SUPER_L")
bind_variable("kbLauncher",
    hl.dsp.global("hyprstack:launcher"),
    function(key)
        return normalise_keybind(key) == launcher_default and release or nil
    end
)

-- Misc
bind_variable("kbSession", hl.dsp.global("hyprstack:session"))
bind_variable("kbShowSidebar", hl.dsp.global("hyprstack:sidebar"))
bind_variable("kbClearNotifs", hl.dsp.global("hyprstack:clearNotifs"), locked)
bind_variable("kbShowPanels", hl.dsp.global("hyprstack:showall"))
bind_variable("kbLock", hl.dsp.global("hyprstack:lock"))

-- Restore lock
bind_variable("kbRestoreLock", function()
    hl.dispatch(hl.dsp.exec_cmd("hyprstack shell -d"))
    hl.dispatch(hl.dsp.global("hyprstack:lock"))
end)

-- Kill/restart
create_bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("hyprstack-session stop"), release, "Session: Stop shell")
create_bind(
    "CTRL + SUPER + ALT + R",
    hl.dsp.exec_cmd("hyprstack-session restart"),
    release, "Session: Restart shell"
)

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    create_bind(extend_keybind(vars.kbGoToWs, key), fn.wsaction("focus", "", i), nil, "Workspaces: Go to workspace " .. i)
    create_bind(extend_keybind(vars.kbMoveWinToWs, key), fn.wsaction("move", "", i), nil, "Workspaces: Move window to workspace " .. i)
    create_bind(extend_keybind(vars.kbGoToWsGroup, key), fn.wsaction("focus", "group", i), nil, "Workspaces: Go to workspace group " .. i)
    create_bind(extend_keybind(vars.kbMoveWinToWsGroup, key), fn.wsaction("move", "group", i), nil, "Workspaces: Move window to workspace group " .. i)
end

-- Go to workspace -1/+1
bind_variable("kbPrevWs", hl.dsp.focus({ workspace = "-1" }), repeating_unless_mouse)
bind_variable("kbNextWs", hl.dsp.focus({ workspace = "+1" }), repeating_unless_mouse)

-- Go to workspace group -1/+1
bind_variable("kbPrevWsGroup", hl.dsp.focus({ workspace = "-10" }), repeating_unless_mouse)
bind_variable("kbNextWsGroup", hl.dsp.focus({ workspace = "+10" }), repeating_unless_mouse)

-- Move window to workspace -1/+1
bind_variable("kbMoveWinToWsNext", hl.dsp.window.move({ workspace = "+1" }), repeating_unless_mouse)
bind_variable("kbMoveWinToWsPrev", hl.dsp.window.move({ workspace = "-1" }), repeating_unless_mouse)

-- Move window to/from special workspace
bind_variable("kbMoveWinToWsSpecial", hl.dsp.window.move({ workspace = "special:special" }))
bind_variable("kbMoveWinFromWsSpecial", hl.dsp.window.move({ workspace = "e+0" }))

-- Window groups
bind_variable("kbWindowCycleNext", hl.dsp.window.cycle_next(), repeating)
bind_variable("kbWindowCyclePrev", hl.dsp.window.cycle_next({ next = false }), repeating)
bind_variable("kbWindowGroupCycleNext", hl.dsp.group.next(), repeating)
bind_variable("kbWindowGroupCyclePrev", hl.dsp.group.prev(), repeating)
bind_variable("kbToggleGroup", hl.dsp.group.toggle())
bind_variable("kbUngroup", hl.dsp.window.move({ out_of_group = true }))
bind_variable("kbGroupLockActive", hl.dsp.group.lock_active())

-- Window actions
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    create_bind("SUPER + " .. dir, hl.dsp.focus({ direction = dir }), nil, "Windows: Focus " .. dir)
    create_bind("SUPER + SHIFT + " .. dir, hl.dsp.window.move({ direction = dir }), nil, "Windows: Move window " .. dir)
end

bind_variable("kbWindowDecreaseWidth", fn.resize_active_window(-10, 0), repeating)
bind_variable("kbWindowIncreaseWidth", fn.resize_active_window(10, 0), repeating)
bind_variable("kbWindowDecreaseHeight", fn.resize_active_window(0, -10), repeating)
bind_variable("kbWindowIncreaseHeight", fn.resize_active_window(0, 10), repeating)

create_bind({ vars.kbMoveWindow, "SUPER + mouse:272" }, hl.dsp.window.drag(), mouse, "Windows: Drag window")
create_bind({ vars.kbResizeWindow, "SUPER + mouse:273" }, hl.dsp.window.resize(), mouse, "Windows: Resize window")
bind_variable("kbCenterWindow", hl.dsp.window.center())
bind_variable("kbNormalizeWindow", function()
    hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
    hl.dispatch(hl.dsp.window.center())
end)
bind_variable("kbWindowPip", function()
    local a = hl.get_active_window()
    if a then
        local pip = fn.move_actions(a) or {}
        if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
        table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))

        for _, x in ipairs(pip) do
            hl.dispatch(x)
        end
    end
end)
bind_variable("kbPinWindow", hl.dsp.window.pin())
bind_variable("kbWindowFullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind_variable("kbWindowBorderedFullscreen", hl.dsp.window.fullscreen({ mode = "maximized" }))
bind_variable("kbToggleWindowFloating", hl.dsp.window.float())
bind_variable("kbCloseWindow", hl.dsp.window.close())

-- Special workspace toggles
bind_variable("kbSpecialWs", fn.toggle("specialws"))
bind_variable("kbSystemMonitorWs", fn.toggle("sysmon"))
bind_variable("kbMusicWs", fn.toggle("music"))
bind_variable("kbTodoWs", fn.toggle("todo"))

-- Apps
bind_variable("kbTerminal", hl.dsp.exec_cmd(vars.terminal))
bind_variable("kbBrowser", hl.dsp.exec_cmd(vars.browser))
bind_variable("kbEditor", hl.dsp.exec_cmd(vars.editor))
bind_variable("kbFileExplorer", hl.dsp.exec_cmd(vars.fileExplorer))
bind_variable("kbAudioSettings", hl.dsp.exec_cmd(vars.audioSettings))

-- Utilities
bind_variable("kbScreenshot", hl.dsp.exec_cmd("hyprstack screenshot"), locked)
bind_variable("kbScreenshotFreeze", hl.dsp.global("hyprstack:screenshotFreeze"))
bind_variable("kbScreenshotRegion", hl.dsp.global("hyprstack:screenshot"))
bind_variable("kbRecord", hl.dsp.exec_cmd("hyprstack record"))
bind_variable("kbRecordSound", hl.dsp.exec_cmd("hyprstack record -s"))
bind_variable("kbRecordRegion", hl.dsp.exec_cmd("hyprstack record -r"))
bind_variable("kbColorPicker", hl.dsp.exec_cmd("hyprpicker -a"))

-- Brightness
create_bind("XF86MonBrightnessUp", hl.dsp.global("hyprstack:brightnessUp"), locked, "Media: Increase brightness")
create_bind("XF86MonBrightnessDown", hl.dsp.global("hyprstack:brightnessDown"), locked, "Media: Decrease brightness")

-- Media
create_bind({ vars.kbMediaToggle, "XF86AudioPlay", "XF86AudioPause" }, hl.dsp.global("hyprstack:mediaToggle"), locked, "Media: Play or pause media")
create_bind({ vars.kbMediaNext, "XF86AudioNext" }, hl.dsp.global("hyprstack:mediaNext"), locked, "Media: Next media track")
create_bind({ vars.kbMediaPrev, "XF86AudioPrev" }, hl.dsp.global("hyprstack:mediaPrev"), locked, "Media: Previous media track")
create_bind({ vars.kbMediaStop, "XF86AudioStop" }, hl.dsp.global("hyprstack:mediaStop"), locked, "Media: Stop media")

-- Volume
create_bind({ vars.kbVolumeMute, "XF86AudioMute" }, hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked, "Media: Mute audio")
create_bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked, "Media: Mute microphone")
create_bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l " ..
        (vars.volumeMax / 100) .. " @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%+"
    ),
    locked_repeating, "Media: Increase volume"
)
create_bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%-"
    ),
    locked_repeating, "Media: Decrease volume"
)

-- Sleep
bind_variable("kbSleep", hl.dsp.exec_cmd(vars.sleepGestureCmd), locked)

-- Clipboard and emoji picker
bind_variable("kbClipboard", hl.dsp.exec_cmd("hyprstack clipboard"))
bind_variable("kbEmoji", hl.dsp.exec_cmd("hyprstack emoji"))
bind_variable("kbClipboardPasteLatest",
    hl.dsp.exec_cmd('sleep 0.5s && ydotool type -d 1 "$(cliphist list | head -1 | cliphist decode)"'),
    locked
)
