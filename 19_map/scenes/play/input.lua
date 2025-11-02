-- scenes/play/input.lua
-- Input handling for play scene

local scene_control = require "systems.scene_control"
local dialogue = require "systems.dialogue"
local input = require "systems.input"
local sound = require "systems.sound"
local debug = require "systems.debug"

local input_handler = {}

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- Check if a key is a jump key in current game mode
function input_handler.isJumpKey(self, key)
    if self.player.game_mode == "platformer" then
        -- In platformer mode, W, Up arrow, and Space are jump keys
        return key == "w" or key == "up" or key == "space"
    else
        -- In topdown mode, only Space is used (for dodge)
        return false
    end
end

-- Keyboard input handler
function input_handler.keypressed(self, key)
    if dialogue:isOpen() then
        if input:wasPressed("interact", "keyboard", key) or
            input:wasPressed("menu_select", "keyboard", key) then
            dialogue:onAction()
        end

        return
    end

    if input:wasPressed("pause", "keyboard", key) then
        local pause = require "scenes.pause"
        scene_control.push(pause)

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("open_inventory", "keyboard", key) then
        -- Open inventory UI
        local inventory_ui = require "scenes.inventory_ui"
        scene_control.push(inventory_ui, self.inventory, self.player)
    elseif input:wasPressed("dodge", "keyboard", key) then
        -- Dodge (lshift) - works in both modes
        self.player:startDodge()
    elseif input:wasPressed("jump", "keyboard", key) or input_handler.isJumpKey(self, key) then
        -- Mode-dependent behavior
        if self.player.game_mode == "platformer" then
            -- Platformer: space/w/up = jump
            self.player:jump()
        else
            -- Topdown: space = dodge (W/Up is for movement)
            if key == "space" then
                self.player:startDodge()
            end
        end
    elseif input:wasPressed("use_item", "keyboard", key) then
        -- Use selected item from inventory
        self.inventory:useSelectedItem(self.player)
    elseif input:wasPressed("next_item", "keyboard", key) then
        -- Select next item in inventory
        if self.inventory then
            self.inventory:selectNext()
        end
    elseif input:wasPressed("slot_1", "keyboard", key) then
        if self.inventory then self.inventory:selectSlot(1) end
    elseif input:wasPressed("slot_2", "keyboard", key) then
        if self.inventory then self.inventory:selectSlot(2) end
    elseif input:wasPressed("slot_3", "keyboard", key) then
        if self.inventory then self.inventory:selectSlot(3) end
    elseif input:wasPressed("slot_4", "keyboard", key) then
        if self.inventory then self.inventory:selectSlot(4) end
    elseif input:wasPressed("slot_5", "keyboard", key) then
        if self.inventory then self.inventory:selectSlot(5) end
    elseif input:wasPressed("interact", "keyboard", key) then
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)

            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            local saveslot = require "scenes.saveslot"
            scene_control.push(saveslot, function(slot)
                self:saveGame(slot)
            end)
        end
    elseif input:wasPressed("manual_save", "keyboard", key) then
        self:saveGame()
    else
        debug:handleInput(key, {
            player = self.player,
            world = self.world,
            camera = self.cam
        })
    end
end

-- Mouse input handler
function input_handler.mousepressed(self, x, y, button)
    -- Ignore mouse events on mobile (virtual gamepad handles all input)
    if is_mobile then
        return
    end

    if dialogue:isOpen() then
        if input:wasPressed("menu_select", "mouse", button) then
            dialogue:onAction()
        end
        return
    end

    if input:wasPressed("attack", "mouse", button) then
        self.player:attack()
    elseif input:wasPressed("parry", "mouse", button) then
        self.player:startParry()
    end
end

-- Mouse release handler
function input_handler.mousereleased(self, x, y, button)
    -- Ignore mouse events on mobile
    if is_mobile then
        return
    end
end

-- Gamepad input handler
function input_handler.gamepadpressed(self, joystick, button)
    if dialogue:isOpen() then
        if input:wasPressed("interact", "gamepad", button) or
            input:wasPressed("menu_select", "gamepad", button) then
            dialogue:onAction()
        end

        return
    end

    if input:wasPressed("pause", "gamepad", button) then
        local pause = require "scenes.pause"
        scene_control.push(pause)

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("attack", "gamepad", button) or input:wasPressed("jump", "gamepad", button) then
        -- A button: attack in topdown, jump in platformer
        if self.player.game_mode == "platformer" then
            self.player:jump()
        else
            self.player:attack()
        end
    elseif input:wasPressed("parry", "gamepad", button) then
        self.player:startParry()
    elseif input:wasPressed("dodge", "gamepad", button) then
        self.player:startDodge()
    elseif input:wasPressed("interact", "gamepad", button) then
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)

            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            local saveslot = require "scenes.saveslot"
            scene_control.push(saveslot, function(slot)
                self:saveGame(slot)
            end)
        end
    elseif input:wasPressed("use_item", "gamepad", button) then
        -- Use selected item from inventory
        self.inventory:useSelectedItem(self.player)
    elseif input:wasPressed("next_item", "gamepad", button) then
        -- Select next item in inventory
        if self.inventory then
            self.inventory:selectNext()
        end
    end
end

-- Touch input handler
function input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
    -- Handle debug button release
    if self:handleDebugButtonTouch(x, y, id, false) then
        return
    end
end

return input_handler
