-- engine/scenes/gameplay/input.lua
-- Input handling for play scene

local scene_control = require "engine.core.scene_control"
local dialogue = require "engine.ui.dialogue"
local input = require "engine.core.input"
local sound = require "engine.core.sound"
local debug = require "engine.core.debug"
local quest_system = require "engine.core.quest"
local coords = require "engine.core.coords"
local display = require "engine.core.display"
local shop_ui = require "engine.ui.screens.shop"
local entity_registry = require "engine.core.entity_registry"

local input_handler = {}

-- Helper: Update vehicle registry when player disembarks
local function updateVehicleRegistryOnDisembark(scene, vehicle)
    if not vehicle or not vehicle.map_id then return end

    local map_name = scene.world and scene.world.map and scene.world.map.properties
                     and scene.world.map.properties.name or "unknown"

    entity_registry:updateVehiclePosition(
        vehicle.map_id,
        map_name,
        vehicle.x,
        vehicle.y,
        vehicle.direction
    )
end

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- Keyboard input handler
function input_handler.keypressed(self, key)
    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:keypressed(key)
        return
    end

    -- Dialogue takes priority (pass key for choice navigation)
    if input:wasPressed("interact", "keyboard", key) or
        input:wasPressed("menu_select", "keyboard", key) then
        if dialogue:handleInput("keyboard", key) then
            return
        end
    end

    -- Also check for up/down keys when dialogue is open (for choice navigation)
    if dialogue:isOpen() and (key == "up" or key == "down" or key == "w" or key == "s") then
        if dialogue:handleInput("keyboard", key) then
            return
        end
    end

    -- Quickslot usage (1-5 number keys)
    if key >= "1" and key <= "5" then
        local slot_index = tonumber(key)
        self.inventory:useQuickslot(slot_index, self.player)
        return
    end

    if input:wasPressed("pause", "keyboard", key) then
        scene_control.push("pause")

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("toggle_inventory", "keyboard", key) then
        -- Toggle container UI with inventory tab (I key or Back button on gamepad)
        scene_control.push("container", self.inventory, self.player, quest_system, "inventory")
    elseif input:wasPressed("toggle_questlog", "keyboard", key) then
        -- Toggle container UI with questlog tab (J key)
        scene_control.push("container", self.inventory, self.player, quest_system, "questlog")
    elseif input:wasPressed("dodge", "keyboard", key) then
        -- Dodge (lshift key or R1 on gamepad) - works in both modes
        self.player:startDodge()
    elseif input:wasPressed("evade", "keyboard", key) then
        -- Evade (Alt or / key, or R2 on gamepad) - stationary invincibility
        self.player:startEvade()
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
        -- F key: Interact with NPC, Save Point, Pick up Item, or Vehicle (A button on gamepad uses context logic)
        -- Priority: NPC/SavePoint/Item > Disembark > Board vehicle

        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            self:processDeliveryQuests(npc.id)

            -- Check for completable quests
            local completable_quest = self:getCompletableQuest(npc.id)
            if completable_quest then
                self:showQuestTurnInDialogue(completable_quest, npc.name)
                quest_system:onNPCTalked(npc.id)
                return
            end

            -- Check for delivery quests
            local delivery_quest_id, item_type = quest_system:getActiveDeliveryQuest(npc.id)
            if delivery_quest_id and item_type and self.inventory:hasItem(item_type) then
                self.inventory:removeItemByType(item_type, 1)
                quest_system:onItemDelivered(item_type, npc.id)
                local item_name = item_type:gsub("_", " ")
                dialogue:showSimple(npc.name, "Thank you for bringing me the " .. item_name .. "!")
                quest_system:onNPCTalked(npc.id)
                return
            end

            -- Regular NPC dialogue (pickup is handled via quest accept dialogue)
            local interaction_data = npc:interact()
            if interaction_data.type == "tree" then
                -- New: dialogue tree system (pass NPC object for transformations)
                dialogue:showTreeById(interaction_data.dialogue_id, npc.id, npc)
            else
                -- Simple dialogue: message array (non-interactive)
                dialogue:showMultiple(npc.name, interaction_data.messages)
            end

            -- Track quest progress (talk quests)
            quest_system:onNPCTalked(npc.id)

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

                -- Track non-respawning items (one-time pickup, permanent)
                if not world_item.respawn and world_item.map_id then
                    self.picked_items[world_item.map_id] = true
                end

                -- Session tracking: ALL picked items (preserved by persist_state=true maps)
                if world_item.map_id then
                    self.world.session_picked_items[world_item.map_id] = true
                end

                -- Remove from world
                self.world:removeWorldItem(world_item.id)
                sound:playSFX("item", "pickup")
            end
            return
        end

        -- Board/Disembark vehicle (lowest priority - only if no other interaction available)
        if self.player.is_boarded then
            local vehicle = self.player.boarded_vehicle
            self.player:disembark()
            updateVehicleRegistryOnDisembark(self, vehicle)
            sound:playSFX("ui", "select")
            return
        end

        local vehicle = self.world:getInteractableVehicle(self.player.x, self.player.y)
        if vehicle then
            self.player:boardVehicle(vehicle)
            sound:playSFX("ui", "select")
            return
        end
    else
        debug:handleInput(key, {
            player = self.player,
            world = self.world,
            camera = self.cam,
            inventory = self.inventory
        })
    end
end

-- Mouse input handler
function input_handler.mousepressed(self, x, y, button)
    if is_mobile then return end

    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:mousepressed(x, y, button)
        return
    end

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

-- Mouse move handler
function input_handler.mousemoved(self, x, y, dx, dy)
    if is_mobile then return end

    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:mousemoved(x, y)
        return
    end

    -- Pass to dialogue for choice hover
    dialogue:handleInput("touch_move", 0, x, y)
end

-- Mouse wheel handler
function input_handler.wheelmoved(self, x, y)
    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:wheelmoved(x, y)
        return
    end
end

-- Mouse release handler
function input_handler.mousereleased(self, x, y, button)
    if is_mobile then return end

    -- Always pass release event to dialogue (no wasPressed check on release!)
    -- Released events don't trigger wasPressed (that's for press events)
    if button == 1 then  -- Left mouse button
        dialogue:handleInput("mouse_release", x, y)
    end
end

-- Gamepad input handler
function input_handler.gamepadpressed(self, joystick, button)
    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:gamepadpressed(joystick, button)
        return
    end

    -- Dialogue takes priority
    if dialogue:isOpen() then
        -- Start charging skip with menu_back button (B/Circle)
        if input:wasPressed("menu_back", "gamepad", button) then
            self.skip_button_held = true
            return
        end
        -- Pass button to dialogue for choice navigation and selection
        dialogue:handleInput("gamepad", button)
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
            
            -- Process delivery quests first (might complete objectives)
            self:processDeliveryQuests(ctx.id)

            -- Check for completable quests
            local completable_quest = self:getCompletableQuest(ctx.id)
            if completable_quest then
                -- Show quest completion dialogue
                self:showQuestTurnInDialogue(completable_quest, ctx.name)
                quest_system:onNPCTalked(ctx.id)
                return
            end

            -- Regular NPC dialogue
            local interaction_data = ctx:interact()
            if interaction_data.type == "tree" then
                -- New: dialogue tree system (pass NPC object for transformations)
                dialogue:showTreeById(interaction_data.dialogue_id, ctx.id, ctx)
            else
                -- Simple dialogue: message array (non-interactive)
                dialogue:showMultiple(ctx.name, interaction_data.messages)
            end

            -- Track quest progress (talk quests)
            quest_system:onNPCTalked(ctx.id)
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
        -- Y button logic:
        -- Priority: NPC/SavePoint/Item > Disembark > Board vehicle > Quickslot
        -- Quickslot selection/use
        --   - First press on slot: Select
        --   - Second press on same slot: Use

        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)

        -- NPC interaction
        if npc then

            self:processDeliveryQuests(npc.id)

            -- Check for completable quests
            local completable_quest = self:getCompletableQuest(npc.id)
            if completable_quest then
                self:showQuestTurnInDialogue(completable_quest, npc.name)
                quest_system:onNPCTalked(npc.id)
                return
            end

            -- Check for delivery quests
            local delivery_quest_id, item_type = quest_system:getActiveDeliveryQuest(npc.id)
            if delivery_quest_id and item_type and self.inventory:hasItem(item_type) then
                self.inventory:removeItemByType(item_type, 1)
                quest_system:onItemDelivered(item_type, npc.id)
                local item_name = item_type:gsub("_", " ")
                dialogue:showSimple(npc.name, "Thank you for bringing me the " .. item_name .. "!")
                quest_system:onNPCTalked(npc.id)
                return
            end

            -- Regular NPC dialogue (pickup is handled via quest accept dialogue)
            local interaction_data = npc:interact()
            if interaction_data.type == "tree" then
                -- New: dialogue tree system (pass NPC object for transformations)
                dialogue:showTreeById(interaction_data.dialogue_id, npc.id, npc)
            else
                -- Simple dialogue: message array (non-interactive)
                dialogue:showMultiple(npc.name, interaction_data.messages)
            end

            -- Track quest progress (talk quests)
            quest_system:onNPCTalked(npc.id)

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

                -- Track non-respawning items (one-time pickup, permanent)
                if not world_item.respawn and world_item.map_id then
                    self.picked_items[world_item.map_id] = true
                end

                -- Session tracking: ALL picked items (preserved by persist_state=true maps)
                if world_item.map_id then
                    self.world.session_picked_items[world_item.map_id] = true
                end

                -- Remove from world
                self.world:removeWorldItem(world_item.id)
                sound:playSFX("item", "pickup")
            end
            return
        end

        -- Board/Disembark vehicle (lower priority than NPC/SavePoint/Item)
        if self.player.is_boarded then
            local vehicle = self.player.boarded_vehicle
            self.player:disembark()
            updateVehicleRegistryOnDisembark(self, vehicle)
            sound:playSFX("ui", "select")
            return
        end

        local vehicle = self.world:getInteractableVehicle(self.player.x, self.player.y)
        if vehicle then
            self.player:boardVehicle(vehicle)
            sound:playSFX("ui", "select")
            return
        end

        -- Quickslot selection/use (no NPC/SavePoint/Item/Vehicle nearby)
        -- First press: Select quickslot
        -- Second press on same slot: Use quickslot
        if not self.last_selected_quickslot or self.last_selected_quickslot ~= self.selected_quickslot then
            -- First press or different slot - just select
            self.last_selected_quickslot = self.selected_quickslot
            sound:playSFX("ui", "select")
        else
            -- Second press on same slot - use it
            self.inventory:useQuickslot(self.selected_quickslot, self.player)
            self.last_selected_quickslot = nil  -- Reset after use
        end

    elseif action == "use_item" then
        self.inventory:useSelectedItem(self.player)

    elseif action == "next_item" then
        if self.inventory then
            self.inventory:selectNext()
        end

    elseif action == "dodge" then
        self.player:startDodge()

    elseif action == "evade" then
        self.player:startEvade()

    elseif action == "use_quickslot_potion" then
        -- L1: Use quickslot 1 (potion slot)
        self.inventory:useQuickslot(1, self.player)

    elseif action == "use_selected_quickslot" then
        -- D-pad Up or R key: Use currently selected quickslot
        self.inventory:useQuickslot(self.selected_quickslot, self.player)

    elseif action == "next_quickslot" then
        -- L2 or D-pad Right: Cycle quickslot right (1->2->3->4->5->1)
        self.selected_quickslot = self.selected_quickslot % 5 + 1
        sound:playSFX("ui", "move")

    elseif action == "prev_quickslot" then
        -- D-pad Left: Cycle quickslot left (5<-4<-3<-2<-1<-5)
        self.selected_quickslot = self.selected_quickslot - 1
        if self.selected_quickslot < 1 then
            self.selected_quickslot = 5
        end
        sound:playSFX("ui", "move")

    elseif action == "toggle_inventory" then
                scene_control.push("container", self.inventory, self.player, quest_system, "inventory")

    elseif action == "toggle_questlog" then
                scene_control.push("container", self.inventory, self.player, quest_system, "questlog")
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

    elseif action == "next_quickslot" then
        -- L2: Cycle quickslot right - 1 -> 2 -> 3 -> 4 -> 5 -> 1
        self.selected_quickslot = self.selected_quickslot % 5 + 1
        sound:playSFX("ui", "move")

    elseif action == "evade" then
        self.player:startEvade()

    elseif action == "toggle_inventory" then
                scene_control.push("container", self.inventory, self.player, quest_system, "inventory")

    elseif action == "toggle_questlog" then
                scene_control.push("container", self.inventory, self.player, quest_system, "questlog")
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
    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:touchpressed(id, x, y, dx, dy, pressure)
        return true
    end

    if dialogue:handleInput("touch", id, x, y) then
        return true
    end

    -- Check if touch is on HUD quickslot
    if input_handler.checkQuickslotTouch(self, x, y) then
        return true
    end

    return false
end

-- Check if touch is on HUD quickslot and use it
function input_handler.checkQuickslotTouch(self, touch_x, touch_y)
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
            self.inventory:useQuickslot(i, self.player)
            return true
        end
    end

    return false
end

function input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:touchreleased(id, x, y, dx, dy, pressure)
        return true
    end

    if dialogue:handleInput("touch_release", id, x, y) then
        return true
    end

    if self.handleDebugButtonTouch and self:handleDebugButtonTouch(x, y, id, false) then
        return
    end
end

function input_handler.touchmoved(self, id, x, y, dx, dy, pressure)
    -- Shop takes priority when open
    if shop_ui:isOpen() then
        shop_ui:touchmoved(id, x, y, dx, dy, pressure)
        return
    end

    dialogue:handleInput("touch_move", id, x, y)
end

return input_handler
