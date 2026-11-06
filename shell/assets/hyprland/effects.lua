-- Hyprland 0.57 decoration preferences shared by startup and live shell edits.
local effects = {}

local function number(value, fallback, minimum, maximum, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback end
    value = math.max(minimum, math.min(maximum, value))
    return integer and math.floor(value + 0.5) or value
end

function effects.apply(options, game_mode)
    options = type(options) == "table" and options or {}
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
        -- Ignore legacy saved preferences for the removed inner-glow effect.
        glow = { enabled = false },
        motion_blur = {
            enabled = options.motionBlur == true and not game_mode,
            samples = number(options.motionBlurSamples, 7, 1, 64, true),
        },
    } }
    hl.config(config)
    return config
end

return effects
