-- systems/debug.lua
local debug = {}

debug.debug_mode = false
debug.show_fps = false
debug.show_colliders = false

function debug:toggle_debug()
    self.debug_mode = not self.debug_mode
    self.show_fps = self.debug_mode
    self.show_colliders = self.debug_mode
end

return debug
