-- engine/scenes/gameplay/init.lua
-- Main gameplay scene coordinator

local gameplay = {}
local helpers = require "engine.utils.helpers"

-- Game config (injected from game)
gameplay.player_config = {}
gameplay.loot_tables = {}
gameplay.starting_items = {}

-- Import scene lifecycle modules
local scene_setup = require "engine.scenes.gameplay.scene_setup"
local save_manager = require "engine.scenes.gameplay.save_manager"
local quest_interactions = require "engine.scenes.gameplay.quest_interactions"

-- Import scene behavior modules
local update_module = require "engine.scenes.gameplay.update"
local input_module = require "engine.scenes.gameplay.input"
local render_module = require "engine.scenes.gameplay.render"

-- Import core systems (for coordinator functions)
local display = require "engine.core.display"
local lighting = require "engine.systems.lighting"
local constants = require "engine.core.constants"

-- Delegate to scene_setup module
function gameplay:enter(_, mapPath, spawn_x, spawn_y, save_slot, is_new_game)
    scene_setup.enter(self, _, mapPath, spawn_x, spawn_y, save_slot, is_new_game)
end

function gameplay:exit()
    scene_setup.exit(self)
end

function gameplay:resume()
    scene_setup.resume(self)
end

-- Delegate to save_manager module
function gameplay:saveGame(slot)
    save_manager.saveGame(self, slot)
end

function gameplay:showSaveNotification()
    save_manager.showSaveNotification(self)
end

-- Delegate to scene_setup for map switching
function gameplay:switchMap(new_map_path, spawn_x, spawn_y)
    scene_setup.switchMap(self, new_map_path, spawn_x, spawn_y)
end

-- Mobile debug button handling (kept in main file for simplicity)
function gameplay:handleDebugButtonTouch(x, y, id, is_press)
    local debug = require "engine.core.debug"

    local real_w, real_h = love.graphics.getDimensions()
    local button_size = constants.DEBUG.BUTTON_SIZE
    local button_x = real_w - button_size - 10
    local button_y = 10

    local dx = x - (button_x + button_size / 2)
    local dy = y - (button_y + button_size / 2)
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance < button_size / 2 then
        if is_press then
            debug:toggle()
        end
        return true
    end

    return false
end

function gameplay:touchpressed(id, x, y, dx, dy, pressure)
    -- Handle debug button first
    if self:handleDebugButtonTouch(x, y, id, true) then
        return
    end

    -- Delegate to input module for dialogue and other touch handling
    return input_module.touchpressed(self, id, x, y, dx, dy, pressure)
end

-- Delegate to sub-modules
function gameplay:update(dt)
    return update_module.update(self, dt)
end

function gameplay:draw()
    return render_module.draw(self)
end

function gameplay:resize(w, h)
    -- Use screen module for proper scaling
    local vw, vh = display:GetVirtualDimensions()
    local sw, sh = display:GetScreenDimensions()
    local scale_x = sw / vw
    local scale_y = sh / vh
    local cam_scale = math.min(scale_x, scale_y) * constants.CAMERA.ZOOM_FACTOR

    self.cam:zoomTo(cam_scale)

    -- Recreate minimap canvas after resize
    if self.minimap then
        self.minimap:setMap(self.world)
    end

    -- Recreate lighting canvas after resize (use actual screen dimensions)
    local real_w, real_h = love.graphics.getDimensions()
    lighting:resize(real_w, real_h)
end

-- Input handlers delegate to input module
function gameplay:keypressed(key)
    return input_module.keypressed(self, key)
end

function gameplay:mousepressed(x, y, button)
    return input_module.mousepressed(self, x, y, button)
end

function gameplay:mousereleased(x, y, button)
    return input_module.mousereleased(self, x, y, button)
end

function gameplay:mousemoved(x, y, dx, dy)
    -- Pass mouse move to dialogue for choice hover
    local dialogue = require "engine.ui.dialogue"
    dialogue:handleInput("touch_move", 0, x, y)
end

function gameplay:gamepadpressed(joystick, button)
    return input_module.gamepadpressed(self, joystick, button)
end

function gameplay:gamepadreleased(joystick, button)
    return input_module.gamepadreleased(self, joystick, button)
end

function gameplay:gamepadaxis(joystick, axis, value)
    return input_module.gamepadaxis(self, joystick, axis, value)
end

function gameplay:touchreleased(id, x, y, dx, dy, pressure)
    return input_module.touchreleased(self, id, x, y, dx, dy, pressure)
end

function gameplay:touchmoved(id, x, y, dx, dy, pressure)
    return input_module.touchmoved(self, id, x, y, dx, dy, pressure)
end

-- Check if minimap should be shown (game config + map override)
function gameplay:shouldShowMinimap()
    -- 1. Check game default setting
    if not APP_CONFIG.hud or not APP_CONFIG.hud.minimap_enabled then
        return false
    end

    -- 2. Check map property override (if explicitly set to false, hide minimap)
    if self.world and self.world.map and self.world.map.properties then
        if self.world.map.properties.minimap == false then
            return false
        end
    end

    -- 3. Default: show minimap
    return true
end

-- Helper: Count transformed NPCs
function gameplay:countTransformedNPCs()
    return helpers.countTable(self.transformed_npcs)
end

-- Helper: Count killed enemies
function gameplay:countKilledEnemies()
    return helpers.countTable(self.killed_enemies)
end

-- Helper: Count picked items
function gameplay:countPickedItems()
    return helpers.countTable(self.picked_items)
end

-- Delegate quest interaction helpers to quest_interactions module
function gameplay:getCompletableQuest(npc_id)
    return quest_interactions.getCompletableQuest(self, npc_id)
end

function gameplay:getAvailableQuest(npc_id)
    return quest_interactions.getAvailableQuest(self, npc_id)
end

function gameplay:showQuestOfferDialogue(quest_info, npc_name)
    quest_interactions.showQuestOfferDialogue(self, quest_info, npc_name)
end

function gameplay:processDeliveryQuests(npc_id)
    quest_interactions.processDeliveryQuests(self, npc_id)
end

function gameplay:showQuestTurnInDialogue(quest_info, npc_name)
    quest_interactions.showQuestTurnInDialogue(self, quest_info, npc_name)
end

return gameplay
