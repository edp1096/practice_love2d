-- engine/scenes/gameplay/init.lua
-- Main gameplay scene coordinator

local gameplay = {}

-- Game config (injected from game)
gameplay.player_config = {}
gameplay.loot_tables = {}
gameplay.starting_items = {}

local player_module = require "engine.entities.player"
local world = require "engine.systems.world"
local camera = require "vendor.hump.camera"
local camera_sys = require "engine.core.camera"
local scene_control = require "engine.core.scene_control"
local display = require "engine.core.display"
local save_sys = require "engine.core.save"
local inventory_class = require "engine.systems.inventory"
local item_class = require "engine.entities.item"
local enemy_class = require "engine.entities.enemy"
local npc_class = require "engine.entities.npc"
local healing_point_class = require "engine.entities.healing_point"
local world_item_class = require "engine.entities.world_item"
local dialogue = require "engine.ui.dialogue"
local sound = require "engine.core.sound"
local util = require "engine.utils.util"
local constants = require "engine.core.constants"
local minimap_class = require "engine.systems.hud.minimap"
local lighting = require "engine.systems.lighting"
local effects = require "engine.systems.effects"
local weather = require "engine.systems.weather"

-- Import sub-modules
local update_module = require "engine.scenes.gameplay.update"
local input_module = require "engine.scenes.gameplay.input"
local render_module = require "engine.scenes.gameplay.render"

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

function gameplay:enter(_, mapPath, spawn_x, spawn_y, save_slot, is_new_game)
    -- Initialize lighting system if not already initialized
    if not lighting.canvas then lighting:init() end

    -- Reset camera effects (shake, slow-motion)
    camera_sys:reset()

    mapPath = mapPath or constants.GAME_START.DEFAULT_MAP
    spawn_x = spawn_x or constants.GAME_START.DEFAULT_SPAWN_X
    spawn_y = spawn_y or constants.GAME_START.DEFAULT_SPAWN_Y
    save_slot = save_slot or 1
    -- Explicit nil check: nil defaults to false, but explicit false/true values are preserved
    if is_new_game == nil then
        is_new_game = false
    end

    self.current_map_path = mapPath

    -- Use screen module for proper scaling
    local vw, vh = display:GetVirtualDimensions()
    local sw, sh = display:GetScreenDimensions()
    local scale_x = sw / vw
    local scale_y = sh / vh
    local cam_scale = math.min(scale_x, scale_y) * 1.4  -- 1.4x zoom for closer view

    self.cam = camera(0, 0, cam_scale, 0, 0)

    -- Load save data first (before creating world)
    local save_data = nil
    if not is_new_game then
        save_data = save_sys:loadGame(save_slot)
    end

    -- Initialize persistence lists (for non-respawning items/enemies)
    self.picked_items = {}
    if save_data and save_data.picked_items then
        self.picked_items = save_data.picked_items
    end

    self.killed_enemies = {}
    if save_data and save_data.killed_enemies then
        self.killed_enemies = save_data.killed_enemies
    end

    -- Create world with injected entity classes and persistence data
    self.world = world:new(mapPath, {
        enemy = enemy_class,
        npc = npc_class,
        healing_point = healing_point_class,
        world_item = world_item_class,
        loot_tables = gameplay.loot_tables
    }, self.picked_items, self.killed_enemies)

    self.player = player_module:new(spawn_x, spawn_y, gameplay.player_config)

    -- Set player game mode based on world
    self.player.game_mode = self.world.game_mode

    self.current_save_slot = save_slot

    -- Apply loaded save data
    if save_data and save_data.hp then
        self.player.health = save_data.hp
        self.player.max_health = save_data.max_hp
    end

    self.world:addEntity(self.player)

    -- Initialize minimap
    self.minimap = minimap_class:new()
    self.minimap:setMap(self.world)

    -- Initialize weather system
    weather:initialize(self.world.map)

    -- Initialize inventory with item_class injection
    self.inventory = inventory_class:new(item_class)

    -- Load inventory from save data (reuse already loaded save_data)
    if save_data and save_data.inventory then
        self.inventory:load(save_data.inventory)

        -- Apply equipped weapon to player
        local weapon_item_id = self.inventory.equipment_slots["weapon"]
        if weapon_item_id then
            local weapon_data = self.inventory.items[weapon_item_id]
            if weapon_data and weapon_data.item.weapon_type then
                self.player:equipWeapon(weapon_data.item.weapon_type)
            end
        end

        -- Apply equipped items' stats to player
        for slot_name, item_id in pairs(self.inventory.equipment_slots) do
            local item_data = self.inventory.items[item_id]
            if item_data and item_data.item.stats then
                self.player:applyEquipmentStats(item_data.item.stats)
            end
        end
    else
        -- Give starting items (for both new game and no save data)
        for _, item_config in ipairs(gameplay.starting_items) do
            self.inventory:addItem(item_config.type, item_config.quantity)
        end
    end


    self.transition_cooldown = 0

    self.fade_alpha = 1.0
    self.fade_speed = 2.0
    self.is_fading = true

    self.save_notification = {
        active = false,
        timer = 0,
        duration = 2.0,
        text = "Game Saved!"
    }

    -- Track gamepad skip button state
    self.skip_button_held = false

    -- Track selected quickslot for gamepad (1-5)
    self.selected_quickslot = 1

    dialogue:initialize(display)

    -- Initialize lighting
    self:setupLighting()

    local level = mapPath:match("level(%d+)")
    if not level then level = "1" end
    level = "level" .. level
    -- Always rewind BGM on enter (restart/new game)
    sound:playBGM(level, 1.0, true)

    -- Show virtual gamepad for mobile gameplay
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        -- Force init if not initialized
        if not virtual_gamepad.enabled then
            virtual_gamepad:init()
        end
        virtual_gamepad:show()
    end

    -- Set game context for input coordinator (for context-based actions)
    local input = require "engine.core.input"
    input:setGameContext({
        player = self.player,
        world = self.world
    })
end

function gameplay:exit()
    if self.world then self.world:destroy() end
    weather:cleanup()
    sound:stopBGM()

    -- Hide virtual gamepad when leaving gameplay
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        virtual_gamepad:hide()
    end
end

function gameplay:saveGame(slot)
    slot = slot or self.current_save_slot or 1

    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y,
        inventory = self.inventory and self.inventory:save() or nil,
        picked_items = self.picked_items or {},
        killed_enemies = self.killed_enemies or {},
    }

    local success = save_sys:saveGame(slot, save_data)
    if success then
        self.current_save_slot = slot
        self:showSaveNotification()

        sound:playSFX("ui", "save")
    end
end

function gameplay:showSaveNotification()
    self.save_notification.active = true
    self.save_notification.timer = self.save_notification.duration
end

function gameplay:setupLighting()
    lighting:clearLights()
    local ambient = self.world.map.properties.ambient or "day"
    lighting:setAmbient(ambient)

    -- Add lights only for dark environments (not day mode)
    if ambient ~= "day" then
        -- Add player light
        self.player.light = lighting:addLight({
            type = "point",
            x = self.player.x,
            y = self.player.y,
            radius = 250,
            color = {1, 0.9, 0.7},
            intensity = 1.0
        })

        -- Add lights to enemies
        for _, enemy in ipairs(self.world.enemies) do
            local enemy_center_x = enemy.x + enemy.collider_offset_x
            local enemy_center_y = enemy.y + enemy.collider_offset_y
            enemy.light = lighting:addLight({
                type = "point",
                x = enemy_center_x,
                y = enemy_center_y,
                radius = 100,
                color = {1, 0.4, 0.4},
                intensity = 0.6
            })
        end

        -- Add lights to NPCs
        for _, npc in ipairs(self.world.npcs) do
            local npc_center_x = npc.x + npc.collider_offset_x
            local npc_center_y = npc.y + npc.collider_offset_y
            npc.light = lighting:addLight({
                type = "point",
                x = npc_center_x,
                y = npc_center_y,
                radius = 120,
                color = {0.8, 0.9, 1.0},
                intensity = 0.7
            })
        end

        -- Add lights to save points
        for _, savepoint in ipairs(self.world.savepoints) do
            savepoint.light = lighting:addLight({
                type = "point",
                x = savepoint.center_x,
                y = savepoint.center_y,
                radius = 150,
                color = {0.3, 1.0, 0.5},
                intensity = 0.8,
                flicker = true,
                flicker_speed = 3.0,
                flicker_amount = 0.2
            })
        end
    else
        -- Day mode: no lights needed
        self.player.light = nil
    end
end

function gameplay:switchMap(new_map_path, spawn_x, spawn_y)
    -- Clean up old colliders BEFORE destroying world
    if self.player.collider then
        self.player.collider:destroy()
        self.player.collider = nil
    end
    if self.player.foot_collider then
        self.player.foot_collider:destroy()
        self.player.foot_collider = nil
    end

    -- Now destroy world
    if self.world then self.world:destroy() end
    weather:cleanup()

    self.current_map_path = new_map_path
    -- Create world with injected entity classes and persistence data
    self.world = world:new(new_map_path, {
        enemy = enemy_class,
        npc = npc_class,
        healing_point = healing_point_class,
        world_item = world_item_class,
        loot_tables = gameplay.loot_tables
    }, self.picked_items, self.killed_enemies)

    -- Reinitialize weather for new map
    weather:initialize(self.world.map)

    self.player.x = spawn_x
    self.player.y = spawn_y

    -- CRITICAL: Update player game mode BEFORE adding to world
    -- (createPlayerColliders needs correct game_mode to create foot_collider in topdown)
    self.player.game_mode = self.world.game_mode

    self.world:addEntity(self.player)

    -- Update minimap for new map
    if self.minimap then
        self.minimap:setMap(self.world)
    end

    -- Update lighting for new map
    self:setupLighting()

    -- Handle BGM based on map properties
    local map_bgm = self.world.map.properties and self.world.map.properties.bgm

    if map_bgm then
        -- Map has custom BGM property, use it
        sound:playBGM(map_bgm, 1.0, false)  -- rewind=false for smooth transition
    else
        -- No custom BGM, use level-based BGM (default behavior)
        local level = new_map_path:match("level(%d+)")
        if not level then level = "1" end
        level = "level" .. level
        sound:playBGM(level, 1.0, false)  -- rewind=false to continue if same BGM
    end

    self.transition_cooldown = 0.5

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight

    local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
    self.cam:lockBounds(mapWidth, mapHeight, w, h)

    self.fade_alpha = 1.0
    self.is_fading = true
end

-- Mobile debug button handling (kept in main file for simplicity)
function gameplay:handleDebugButtonTouch(x, y, id, is_press)
    local debug = require "engine.core.debug"
    local constants = require "engine.core.constants"

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
    local cam_scale = math.min(scale_x, scale_y) * 1.4  -- 1.4x zoom for closer view

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

return gameplay
