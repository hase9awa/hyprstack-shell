local vars = require("variables")

-- Themes
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("XCURSOR_THEME", vars.cursorTheme)
hl.env("XCURSOR_SIZE", vars.cursorSize)

-- Toolkit backends
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- XDG specifications
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Others
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")

-- ssh falls back to this only without a terminal to ask on, and sudo only
-- when it is called with -A, so neither takes over a terminal prompt.
local data_dir = os.getenv("HYPRSTACK_DATA_DIR")
    or ((os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/hyprstack")
local askpass = data_dir .. "/shell/assets/askpass.py"
hl.env("SSH_ASKPASS", askpass)
hl.env("SUDO_ASKPASS", askpass)

-- Application theme inheritance is generated from the shell's theme settings.
local theme_env = (os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config")
    .. "/hyprstack/theme/environment.lua"
local theme_file = io.open(theme_env, "r")
if theme_file then
    theme_file:close()
    local ok, environment = pcall(dofile, theme_env)
    if ok and type(environment) == "table" then
        for _, key in ipairs({ "GTK_THEME", "QT_QPA_PLATFORMTHEME", "QT_QUICK_CONTROLS_STYLE", "QT_PLUGIN_PATH", "JAVA_TOOL_OPTIONS" }) do
            if type(environment[key]) == "string" then hl.env(key, environment[key]) end
        end
    end
end
