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

    -- Quickslot usage (1-5 number keys)
    if key >= "1" and key <= "5" then
        local slot_index = tonumber(key)
        local success, message = self.inventory:useQuickslot(slot_index, self.player)
        if not success and message then
            print("[Quickslot] " .. message)
        end
        return
    end

    if input:wasPressed("pause", "keyboard", key) then
        scene_control.push("pause")

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("open_inventory", "keyboard", key) then
        -- Open inventory UI (I key or R2 on gamepad)
        scene_control.push("inventory", self.inventory, self.player)
    elseif input:wasPressed("dodge", "keyboard", key) then
        -- Dodge (lshift key or R1 on gamepad) - works in both modes
        self.player:startDodge()
    elseif input:wasPressed("jump", "keyboard", key) then
        -- Jump works in both modes
        -- Platformer: physics-based jump
        -- Topdown: visual jump (no physics collision)
        self.player:jump()
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
        -- F key: Interact with NPC, Save Point, or Pick up Item (A button on gamepad uses context logic)
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)

            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            scene_control.push("saveslot", function(slot)
                self:saveGame(slot)
            end)
            return
        end

        -- Check for world items
        local world_item = self.world:getInteractableWorldItem(self.player.x, self.player.y, self.player.game_mode)
        if world_item then
            -- Try to add to inventory
            local success, item_id = self.inventory:addItem(world_item.item_type, world_item.quantity)
            if success then
                -- Auto-equip if equipment slot is empty
                local item_data = self.inventory.items[item_id]
                if item_data and item_data.item.equipment_slot then
                    local slot = item_data.item.equipment_slot
                    if not self.inventory.equipment_slots[slot] then
                        self.inventory:equipItem(item_id, slot, self.player)
                    end
                end

                -- Track non-respawning items (one-time pickup)
                if not world_item.respawn and world_item.map_id then
                    self.picked_items[world_item.map_id] = true
                end

                -- Remove from world
                self.world:removeWorldItem(world_item.id)
                sound:playSFX("item", "pickup")
            end
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
        if input:wasPressed("menu_select", "gamepad", button) or input:wasPressed("interact", "gamepad", button) then
            dialogue:onAction()
        end
        -- Start charging skip with menu_back button
        if input:wasPressed("menu_back", "gamepad", button) then
            self.skip_button_held = true
        end
        return
    end

    -- LB button: Cycle quickslot (1 -> 2 -> 3 -> 4 -> 5 -> 1)
    if button == "leftshoulder" then
        self.selected_quickslot = self.selected_quickslot % 5 + 1
        sound:playSFX("ui", "move")
        return
    end

    -- D-pad Up: Use selected quickslot
    if button == "dpup" then
        local success, message = self.inventory:useQuickslot(self.selected_quickslot, self.player)
        if not success and message then
            print("[Quickslot] " .. message)
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
        scene_control.push("saveslot", function(slot)
            self:saveGame(slot)
        end)

    elseif action == "attack" then
        self.player:attack()

    elseif action == "jump" then
        self.player:jump()

    elseif action == "parry" then
        self.player:startParry()

    elseif action == "interact" then
        -- Direct interact (Y button) - NPC, Save Point, or Pick up Item
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)
            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            scene_control.push("saveslot", function(slot)
                self:saveGame(slot)
            end)
            return
        end

        -- Check for world items
        local world_item = self.world:getInteractableWorldItem(self.player.x, self.player.y, self.player.game_mode)
        if world_item then
            -- Try to add to inventory
            local success, item_id = self.inventory:addItem(world_item.item_type, world_item.quantity)
            if success then
                -- Auto-equip if equipment slot is empty
                local item_data = self.inventory.items[item_id]
                if item_data and item_data.item.equipment_slot then
                    local slot = item_data.item.equipment_slot
                    if not self.inventory.equipment_slots[slot] then
                        self.inventory:equipItem(item_id, slot, self.player)
                    end
                end

                -- Track non-respawning items (one-time pickup)
                if not world_item.respawn and world_item.map_id then
                    self.picked_items[world_item.map_id] = true
                end

                -- Track non-respawning items (one-time pickup)
                if not world_item.respawn and world_item.map_id then
                    self.picked_items[world_item.map_id] = true
                end

                -- Remove from world
                self.world:removeWorldItem(world_item.id)
                sound:playSFX("item", "pickup")
            end
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
        scene_control.push("inventory", self.inventory, self.player)
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
        scene_control.push("inventory", self.inventory, self.player)
    end
end

-- Gamepad release handler
function input_handler.gamepadreleased(self, joystick, button)
    -- Handle skip button release (regardless of dialogue state)
    if input:wasPressed("menu_back", "gamepad", button) then
        self.skip_button_held = false
        if dialogue.skip_button then
            dialogue.skip_button.is_pressed = false
            -- Force charge decay when button is released
            if not dialogue.skip_button:isFullyCharged() then
                dialogue.skip_button.charge = 0
            end
        end
    end

    -- Early return if dialogue is open (handled above)
    if dialogue:isOpen() then
        return
    end
end

-- Touch input handler
function input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
    if dialogue:handleInput("touch", id, x, y) then
        return true
    end

    -- Check if touch is on HUD quickslot
    if self:checkQuickslotTouch(x, y) then
        return true
    end

    return false
end

-- Check if touch is on HUD quickslot and use it
function input_handler.checkQuickslotTouch(self, touch_x, touch_y)
    local coords = require "engine.core.coords"
    local display = require "engine.core.display"

    -- Convert physical touch to virtual coordinates
    local vx, vy = coords:physicalToVirtual(touch_x, touch_y, display)

    -- Calculate quickslot positions (same as quickslots.draw)
    local SLOT_SIZE = 50
    local SLOT_SPACING = 10
    local SLOT_COUNT = 5

    local vw, vh = display:GetVirtualDimensions()
    local total_width = SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_SPACING
    local start_x = (vw - total_width) / 2
    local y = vh - SLOT_SIZE - 20  -- 20px from bottom

    -- Check each slot
    for i = 1, SLOT_COUNT do
        local slot_x = start_x + (i - 1) * (SLOT_SIZE + SLOT_SPACING)

        if vx >= slot_x and vx <= slot_x + SLOT_SIZE and
           vy >= y and vy <= y + SLOT_SIZE then
            -- Touch is on this slot, use it
            local success, message = self.inventory:useQuickslot(i, self.player)
            if not success and message then
                print("[Quickslot] " .. message)
            end
            return true
        end
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
