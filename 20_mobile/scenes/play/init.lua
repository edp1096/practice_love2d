-- scenes/play/init.lua
-- Main gameplay scene coordinator

local play = {}

local player_module = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local save_sys = require "systems.save"
local inventory_class = require "systems.inventory"
local dialogue = require "systems.dialogue"
local sound = require "systems.sound"
local parallax_sys = require "systems.parallax"
local util = require "utils.util"
local constants = require "systems.constants"
local minimap_class = require "systems.minimap"

-- Import sub-modules
local update_module = require "scenes.play.update"
local input_module = require "scenes.play.input"
local render_module = require "scenes.play.render"

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

function play:enter(_, mapPath, spawn_x, spawn_y, save_slot)
    mapPath = mapPath or constants.GAME_START.DEFAULT_MAP
    spawn_x = spawn_x or constants.GAME_START.DEFAULT_SPAWN_X
    spawn_y = spawn_y or constants.GAME_START.DEFAULT_SPAWN_Y
    save_slot = save_slot or 1

    self.current_map_path = mapPath

    -- Use screen module for proper scaling
    local vw, vh = screen:GetVirtualDimensions()
    local sw, sh = screen:GetScreenDimensions()
    local scale_x = sw / vw
    local scale_y = sh / vh
    local cam_scale = math.min(scale_x, scale_y)

    self.cam = camera(0, 0, cam_scale, 0, 0)
    self.world = world:new(mapPath)
    self.player = player_module:new("assets/images/player-sheet.png", spawn_x, spawn_y)

    -- Set player game mode based on world
    self.player.game_mode = self.world.game_mode

    -- Initialize parallax backgrounds
    self.parallax = parallax_sys:new()
    self.parallax:loadFromMap(self.world.map)

    self.current_save_slot = save_slot

    local save_data = save_sys:loadGame(save_slot)
    if save_data and save_data.hp then
        self.player.health = save_data.hp
        self.player.max_health = save_data.max_hp
    end

    self.world:addEntity(self.player)

    -- Initialize minimap
    self.minimap = minimap_class:new()
    self.minimap:setMap(self.world)

    -- Initialize inventory
    self.inventory = inventory_class:new()

    -- Load inventory from save data
    if save_data and save_data.inventory then
        self.inventory:load(save_data.inventory)
    else
        -- Give starting items for testing
        self.inventory:addItem("small_potion", 3)
        self.inventory:addItem("large_potion", 1)
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

    dialogue:initialize()

    local level = mapPath:match("level(%d+)")
    if not level then level = "1" end
    level = "level" .. level
    -- Always rewind BGM on enter (restart/new game)
    sound:playBGM(level, 1.0, true)

    -- Show virtual gamepad for mobile gameplay
    if is_mobile then
        local virtual_gamepad = require "systems.input.virtual_gamepad"
        -- Force init if not initialized
        if not virtual_gamepad.enabled then
            virtual_gamepad:init()
        end
        virtual_gamepad:show()
        print("Virtual gamepad status - enabled:", virtual_gamepad.enabled, "visible:", virtual_gamepad.visible)
    end
end

function play:exit()
    if self.world then self.world:destroy() end
    sound:stopBGM()

    -- Hide virtual gamepad when leaving gameplay
    if is_mobile then
        local virtual_gamepad = require "systems.input.virtual_gamepad"
        virtual_gamepad:hide()
    end
end

function play:saveGame(slot)
    slot = slot or self.current_save_slot or 1

    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y,
        inventory = self.inventory and self.inventory:save() or nil,
    }

    local success = save_sys:saveGame(slot, save_data)
    if success then
        self.current_save_slot = slot
        self:showSaveNotification()

        sound:playSFX("ui", "save")
    end
end

function play:showSaveNotification()
    self.save_notification.active = true
    self.save_notification.timer = self.save_notification.duration
end

function play:switchMap(new_map_path, spawn_x, spawn_y)
    if self.world then self.world:destroy() end

    self.current_map_path = new_map_path
    self.world = world:new(new_map_path)

    self.player.x = spawn_x
    self.player.y = spawn_y

    self.player.collider = nil

    self.world:addEntity(self.player)

    -- CRITICAL: Update player game mode when switching maps
    self.player.game_mode = self.world.game_mode

    -- Reload parallax backgrounds for new map
    if self.parallax then
        self.parallax:clear()
        self.parallax:loadFromMap(self.world.map)
    end

    -- Update minimap for new map
    if self.minimap then
        self.minimap:setMap(self.world)
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
function play:handleDebugButtonTouch(x, y, id, is_press)
    local debug = require "systems.debug"
    local constants = require "systems.constants"

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

function play:touchpressed(id, x, y, dx, dy, pressure)
    -- Handle debug button first
    if self:handleDebugButtonTouch(x, y, id, true) then
        return
    end

    -- Delegate to input module for dialogue and other touch handling
    return input_module.touchpressed(id, x, y, dx, dy, pressure)
end

-- Delegate to sub-modules
function play:update(dt)
    return update_module.update(self, dt)
end

function play:draw()
    return render_module.draw(self)
end

function play:resize(w, h)
    -- Use screen module for proper scaling
    local vw, vh = screen:GetVirtualDimensions()
    local sw, sh = screen:GetScreenDimensions()
    local scale_x = sw / vw
    local scale_y = sh / vh
    local cam_scale = math.min(scale_x, scale_y)

    self.cam:zoomTo(cam_scale)

    -- Recreate minimap canvas after resize
    if self.minimap then
        self.minimap:setMap(self.world)
    end
end

-- Input handlers delegate to input module
function play:keypressed(key)
    return input_module.keypressed(self, key)
end

function play:mousepressed(x, y, button)
    return input_module.mousepressed(self, x, y, button)
end

function play:mousereleased(x, y, button)
    return input_module.mousereleased(self, x, y, button)
end

function play:gamepadpressed(joystick, button)
    return input_module.gamepadpressed(self, joystick, button)
end

function play:touchreleased(id, x, y, dx, dy, pressure)
    return input_module.touchreleased(self, id, x, y, dx, dy, pressure)
end

return play
