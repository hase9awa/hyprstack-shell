-- Hyprland 0.57 decoration preferences shared by startup and live shell edits.
local effects = {}

local function number(value, fallback, minimum, maximum, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback end
    value = math.max(minimum, math.min(maximum, value))
    return integer and math.floor(value + 0.5) or value
end

function effects.apply(options, game_mode, palette)
    options = type(options) == "table" and options or {}
    palette = palette or {}
    local accent = (palette.primary or "7e9cd8"):gsub("#", "")
    if not accent:match("^%x%x%x%x%x%x$") then accent = "7e9cd8" end
    local glow_opacity = number(options.glowOpacity, 0.35, 0, 1)
    local glow_color = string.format("rgba(%s%02x)", accent, math.floor(glow_opacity * 255 + 0.5))
    local config = { decoration = {
        blur = {
            enabled = options.blur ~= false and not game_mode,
            variant = number(options.blurVariant, 0, 0, 10, true),
            size = number(options.blurSize, 8, 0, 100, true),
            passes = number(options.blurPasses, 2, 1, 10, true),
            proportional = options.proportionalBlur == true,
        },
        wobble = {
            enabled = options.windowWobble == true and not game_mode,
            intensity = number(options.wobbleIntensity, 0.2, 0, 2),
            stiffness = number(options.wobbleStiffness, 200, 1, 1000),
            damping = number(options.wobbleDamping, 12, 0, 100),
        },
        glow = {
            enabled = options.windowGlow == true and glow_opacity > 0 and not game_mode,
            range = number(options.glowSize, 10, 0, 100, true),
            color = glow_color, color_inactive = glow_color,
        },
        motion_blur = {
            enabled = options.motionBlur == true and not game_mode,
            samples = number(options.motionBlurSamples, 7, 1, 64, true),
        },
    } }
    hl.config(config)
    return config
end

return effects
