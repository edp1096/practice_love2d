-- utils/restart.lua
-- Centralized restart logic for pause and gameover scenes

local restart = {}

local save_sys = require "engine.core.save"
local sound = require "engine.core.sound"
local constants = require "engine.core.constants"

-- Restart from current map at the entry spawn point (portal spawn or map default)
-- Does NOT load save data - starts fresh at current map's entry point
-- @param play_scene: The play scene table from previous scene
-- @return map_path, spawn_x, spawn_y, save_slot
function restart:fromCurrentMap(play_scene)
    local current_slot = play_scene.current_save_slot or 1
    local current_map = play_scene.current_map_path or constants.GAME_START.DEFAULT_MAP

    -- Use the spawn position from when player entered this map
    -- This is stored in play_scene when entering through portal or starting new game
    local spawn_x = play_scene.map_entry_x or constants.GAME_START.DEFAULT_SPAWN_X
    local spawn_y = play_scene.map_entry_y or constants.GAME_START.DEFAULT_SPAWN_Y

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
