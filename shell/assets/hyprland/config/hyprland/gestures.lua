local vars = require("variables")

hl.config({
    gestures = {
        workspace_swipe_distance                 = 700,
        workspace_swipe_cancel_ratio             = 0.15,
        workspace_swipe_min_speed_to_force       = 5,
        workspace_swipe_direction_lock           = false,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new               = false,
        workspace_swipe_invert                   = true,
        scrolling = {
            move_snap_to_grid = true,
            move_snap_cursor  = false,
        },
    },
})

-- The scrolling layout owns these two bindings; layouts.lua removes them in
-- stacking mode and restores them when returning to scrolling. The enabled
-- flags let the shell disable a gesture without leaving a registration that
-- layouts.lua would later unset by mistake.
if vars.gestureScrollEnabled then
    hl.gesture({ fingers = vars.gestureFingers, direction = "horizontal", action = "scroll_move" })
end
if vars.gestureWorkspaceEnabled then
    hl.gesture({ fingers = vars.workspaceSwipeFingers, direction = "vertical", action = "workspace" })
end

local function overview(open)
    -- Function actions work with the pinned Hyprland package on both Arch and
    -- NixOS, including builds without lifecycle callback table support.
    return function()
        hl.dispatch(hl.dsp.global("hyprstack:" .. (open and "overviewOpen" or "overviewAccept")))
    end
end

hl.gesture({
    fingers   = vars.gestureFingersMore,
    direction = "up",
    action    = overview(true),
})
hl.gesture({
    fingers   = vars.gestureFingersMore,
    direction = "down",
    action    = overview(false),
})
