-- utils/restart.lua
-- Centralized restart logic for pause and gameover scenes

local restart = {}

local save_sys = require "engine.core.save"
local sound = require "engine.core.sound"
local constants = require "engine.core.constants"

-- Restart from current map using saved position if available
-- @param play_scene: The play scene table from previous scene
-- @return map_path, spawn_x, spawn_y, save_slot
function restart:fromCurrentMap(play_scene)
    local current_slot = play_scene.current_save_slot or 1
    local current_map = play_scene.current_map_path or constants.GAME_START.DEFAULT_MAP

    -- Get player's starting position for this map
    local save_data = save_sys:loadGame(current_slot)

    local spawn_x, spawn_y
    if save_data and save_data.map == current_map then
        -- Use saved position if it's the same map
        spawn_x = save_data.x
        spawn_y = save_data.y
    else
        -- Use default spawn position for this map
        spawn_x = constants.GAME_START.DEFAULT_SPAWN_X
        spawn_y = constants.GAME_START.DEFAULT_SPAWN_Y
    end

    sound:playSFX("menu", "select")
    return current_map, spawn_x, spawn_y, current_slot
end

-- Load from last save point
-- @param play_scene: The play scene table from previous scene
-- @return map_path, spawn_x, spawn_y, save_slot (or nil if no save data)
function restart:fromLastSave(play_scene)
    local current_slot = play_scene.current_save_slot or 1
    local save_data = save_sys:loadGame(current_slot)

    if save_data then
        sound:playSFX("menu", "select")
        return save_data.map, save_data.x, save_data.y, current_slot
    else
        -- No save data, fallback to starting position
        sound:playSFX("menu", "error")
        return constants.GAME_START.DEFAULT_MAP,
               constants.GAME_START.DEFAULT_SPAWN_X,
               constants.GAME_START.DEFAULT_SPAWN_Y,
               current_slot
    end
end

return restart
