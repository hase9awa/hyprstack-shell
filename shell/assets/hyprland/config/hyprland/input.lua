local vars = require("variables")

hl.config({
    input = {
        follow_mouse       = 2,
        float_switch_override_focus = 0,
        kb_layout          = "us",
        numlock_by_default = false,
        repeat_delay       = 250,
        repeat_rate        = 35,
        focus_on_close     = 1,

        touchpad           = {
            natural_scroll       = true,
            disable_while_typing = vars.touchpadDisableTyping,
            scroll_factor        = vars.touchpadScrollFactor,
        },
    },

    binds = {
        scroll_event_delay = 0,
        -- Keep the grabbed point under the cursor when a tile becomes floating.
        drag_center_window = false,
    },

    cursor = {
        hotspot_padding = 1,
    },
})
