-- scenes/play/input.lua
-- Input handling for play scene

local scene_control = require "engine.scene_control"
local dialogue = require "engine.dialogue"
local input = require "engine.input"
local sound = require "engine.sound"
local debug = require "engine.debug"

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
        local pause = require "game.scenes.pause"
        scene_control.push(pause)

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("open_inventory", "keyboard", key) then
        -- Open inventory UI (I key or R2 on gamepad)
        local inventory_ui = require "game.scenes.inventory"
        scene_control.push(inventory_ui, self.inventory, self.player)
    elseif input:wasPressed("dodge", "keyboard", key) then
        -- Dodge (lshift key or R1 on gamepad) - works in both modes
        self.player:startDodge()
    elseif input:wasPressed("jump", "keyboard", key) or input_handler.isJumpKey(self, key) then
        -- Mode-dependent behavior
        if self.player.game_mode == "platformer" then
            -- Platformer: space/w/up = jump (B button on gamepad)
            self.player:jump()
        else
            -- Topdown: space = dodge (W/Up is for movement)
            if key == "space" then
                self.player:startDodge()
            end
        end
    elseif input:wasPressed("use_item", "keyboard", key) then
        -- Use selected item from inventory (Q key or L1 on gamepad)
        self.inventory:useSelectedItem(self.player)
    elseif input:wasPressed("next_item", "keyboard", key) then
        -- Select next item in inventory (Tab key or L2 on gamepad)
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
        -- F key: Interact with NPC or Save Point (A button on gamepad uses context logic)
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)

            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            local saveslot = require "game.scenes.saveslot"
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
    -- Dialogue takes priority
    if dialogue:isOpen() then
        if button == "a" or button == "y" then
            dialogue:onAction()
        end
        return
    end

    -- Let input coordinator handle button mapping and context
    local action, ctx = input:handleGamepadPressed(joystick, button)

    if not action then
        return
    end

    -- Handle high-level actions
    if action == "pause" then
        local pause = require "game.scenes.pause"
        scene_control.push(pause)
        sound:playSFX("ui", "pause")
        sound:pauseBGM()

    elseif action == "interact_npc" then
        -- ctx is the NPC
        if ctx then
            local messages = ctx:interact()
            dialogue:showMultiple(ctx.name, messages)
        end

    elseif action == "interact_savepoint" then
        -- ctx is the savepoint
        local saveslot = require "game.scenes.saveslot"
        scene_control.push(saveslot, function(slot)
            self:saveGame(slot)
        end)

    elseif action == "attack" then
        self.player:attack()

    elseif action == "jump" then
        if self.player.game_mode == "platformer" then
            self.player:jump()
        end

    elseif action == "parry" then
        self.player:startParry()

    elseif action == "interact" then
        -- Direct interact (Y button)
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)
            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            local saveslot = require "game.scenes.saveslot"
            scene_control.push(saveslot, function(slot)
                self:saveGame(slot)
            end)
        end

    elseif action == "use_item" then
        self.inventory:useSelectedItem(self.player)

    elseif action == "next_item" then
        if self.inventory then
            self.inventory:selectNext()
        end

    elseif action == "dodge" then
        self.player:startDodge()

    elseif action == "open_inventory" then
        local inventory_ui = require "game.scenes.inventory"
        scene_control.push(inventory_ui, self.inventory, self.player)
    end
end

-- Gamepad axis handler (for triggers on Xbox controllers)
function input_handler.gamepadaxis(self, joystick, axis, value)
    -- Dialogue takes priority
    if dialogue:isOpen() then
        return
    end

    -- Let input coordinator handle trigger axis to button conversion
    local action = input:handleGamepadAxis(joystick, axis, value)

    if not action then
        return
    end

    -- Handle the action (same as gamepadpressed)
    if action == "use_item" then
        self.inventory:useSelectedItem(self.player)

    elseif action == "next_item" then
        if self.inventory then
            self.inventory:selectNext()
        end

    elseif action == "open_inventory" then
        local inventory_ui = require "game.scenes.inventory"
        scene_control.push(inventory_ui, self.inventory, self.player)
    end
end

-- Touch input handler
function input_handler.touchpressed(id, x, y, dx, dy, pressure)
    -- Dialogue takes priority for touch input
    if dialogue:isOpen() then
        dialogue:onAction()
        return true -- Block virtual gamepad
    end

    return false -- Let virtual gamepad handle it
end

function input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
    -- Handle debug button release
    if self:handleDebugButtonTouch(x, y, id, false) then
        return
    end
end

return input_handler
