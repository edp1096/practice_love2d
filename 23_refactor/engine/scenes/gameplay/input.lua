-- engine/scenes/gameplay/input.lua
-- Input handling for play scene

local scene_control = require "engine.core.scene_control"
local dialogue = require "engine.ui.dialogue"
local input = require "engine.core.input"
local sound = require "engine.core.sound"
local debug = require "engine.core.debug"

local input_handler = {}

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- Keyboard input handler
function input_handler.keypressed(self, key)
    -- Dialogue takes priority
    if input:wasPressed("interact", "keyboard", key) or
        input:wasPressed("menu_select", "keyboard", key) then
        if dialogue:handleInput("keyboard") then
            return
        end
    end

    if input:wasPressed("pause", "keyboard", key) then
        scene_control.push("pause")

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("open_inventory", "keyboard", key) then
        -- Open inventory UI (I key or R2 on gamepad)
        local inventory = require "engine.ui.screens.inventory"
        scene_control.push(inventory, self.inventory, self.player)
    elseif input:wasPressed("dodge", "keyboard", key) then
        -- Dodge (lshift key or R1 on gamepad) - works in both modes
        self.player:startDodge()
    elseif input:wasPressed("jump", "keyboard", key) then
        -- Mode-dependent behavior
        if self.player.game_mode == "platformer" then
            -- Platformer: space/w/up = jump (B button on gamepad)
            self.player:jump()
        elseif key == "space" then
            -- Topdown: only space = dodge (W/Up is for movement)
            self.player:startDodge()
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
            local saveslot = require "engine.ui.screens.saveslot"
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
    if is_mobile then return end

    if input:wasPressed("menu_select", "mouse", button) then
        if dialogue:handleInput("mouse", x, y) then
            return
        end
    end

    if input:wasPressed("attack", "mouse", button) then
        self.player:attack()
    elseif input:wasPressed("parry", "mouse", button) then
        self.player:startParry()
    end
end

-- Mouse release handler
function input_handler.mousereleased(self, x, y, button)
    if is_mobile then return end

    if input:wasPressed("menu_select", "mouse", button) then
        dialogue:handleInput("mouse_release", x, y)
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
        scene_control.push("pause")
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
        local saveslot = require "engine.ui.screens.saveslot"
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
            local saveslot = require "engine.ui.screens.saveslot"
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
        local inventory = require "engine.ui.screens.inventory"
        scene_control.push(inventory, self.inventory, self.player)
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
        local inventory = require "engine.ui.screens.inventory"
        scene_control.push(inventory, self.inventory, self.player)
    end
end

-- Touch input handler
function input_handler.touchpressed(id, x, y, dx, dy, pressure)
    if dialogue:handleInput("touch", id, x, y) then
        return true
    end
    return false
end

function input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
    if dialogue:handleInput("touch_release", id, x, y) then
        return true
    end

    if self:handleDebugButtonTouch(x, y, id, false) then
        return
    end
end

function input_handler.touchmoved(self, id, x, y, dx, dy, pressure)
    dialogue:handleInput("touch_move", id, x, y)
end

return input_handler
