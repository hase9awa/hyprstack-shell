local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"
local data = os.getenv("XDG_DATA_HOME") or home .. "/.local/share"
local installed = os.getenv("HYPRSTACK_DATA_DIR") or data .. "/hyprstack"
if not os.getenv("HYPRSTACK_SESSION_COMMAND") then
    local user_bin = home .. "/.local/bin"
    local path_env = os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"
    if not (":" .. path_env .. ":"):find(":" .. user_bin .. ":", 1, true) then
        hl.env("PATH", user_bin .. ":" .. path_env)
    end
end
dofile(installed .. "/shell/assets/hyprland/layouts.lua")
for _, name in ipairs({ "monitors.lua", "local.lua" }) do
    local path = config .. "/hyprstack/" .. name
    local file = io.open(path)
    if file then file:close(); dofile(path) end
end
