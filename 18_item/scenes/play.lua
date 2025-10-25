-- scenes/play.lua
-- Main gameplay scene with save, gamepad, sound

local play = {}

local player = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local debug = require "systems.debug"
local screen = require "lib.screen"
local camera_sys = require "systems.camera"
local hud = require "systems.hud"
local effects = require "systems.effects"
local dialogue = require "systems.dialogue"
local save_sys = require "systems.save"
local input = require "systems.input"
local constants = require "systems.constants"
local sound = require "systems.sound"
local player_sound = require "entities.player.sound"
local util = require "utils.util"
local inventory_class = require "systems.inventory"

local pb = { x = 0, y = 0, w = 960, h = 540 }

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- function play:enter(previous, mapPath, spawn_x, spawn_y, save_slot)
function play:enter(_, mapPath, spawn_x, spawn_y, save_slot)
    mapPath = mapPath or "assets/maps/level1/area1.lua"
    spawn_x = spawn_x or 400
    spawn_y = spawn_y or 250
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
    self.player = player:new("assets/images/player-sheet.png", spawn_x, spawn_y)

    self.current_save_slot = save_slot

    local save_data = save_sys:loadGame(save_slot)
    if save_data and save_data.hp then
        self.player.health = save_data.hp
        self.player.max_health = save_data.max_hp
        print("Loaded from save slot " .. save_slot)
    else
        print("Starting new game in slot " .. save_slot)
    end

    self.world:addEntity(self.player)

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
    sound:playBGM(level)
end

function play:exit()
    if self.world then self.world:destroy() end
    sound:stopBGM()
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

function play:update(dt)
    camera_sys:update(dt)
    local scaled_dt = camera_sys:get_scaled_dt(dt)

    effects:update(dt)
    dialogue:update(dt)

    if self.save_notification.active then
        self.save_notification.timer = self.save_notification.timer - dt
        if self.save_notification.timer <= 0 then
            self.save_notification.active = false
        end
    end

    if self.is_fading and self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
        if self.fade_alpha == 0 then
            self.is_fading = false
        end
    end

    -- CRITICAL: Check player death at the start
    if self.player.health <= 0 then
        print("Player died! Switching to game over...")
        local gameover = require "scenes.gameover"
        scene_control.switch(gameover, self, false)
        return
    end

    local is_dialogue_open = dialogue:isOpen()

    local vx, vy = self.player:update(scaled_dt, self.cam, is_dialogue_open)

    -- Update healing points
    self.world:updateHealingPoints(scaled_dt, self.player)
    -- Update healing points
    self.world:updateHealingPoints(scaled_dt, self.player)
    -- Update healing points
    self.world:updateHealingPoints(scaled_dt, self.player)
    -- Update healing points
    self.world:updateHealingPoints(scaled_dt, self.player)

    for _, enemy in ipairs(self.world.enemies) do
        if enemy.anim then enemy.anim:update(scaled_dt) end
    end

    for _, npc in ipairs(self.world.npcs) do
        if npc.anim then npc.anim:update(scaled_dt) end
    end

    if is_dialogue_open then
        local shake_x, shake_y = camera_sys:get_shake_offset()
        self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

        local mapWidth = self.world.map.width * self.world.map.tilewidth
        local mapHeight = self.world.map.height * self.world.map.tileheight

        local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
        self.cam:lockBounds(mapWidth, mapHeight, w, h)

        return
    end

    self.world:moveEntity(self.player, vx, vy, scaled_dt)
    self.world:updateEnemies(scaled_dt, self.player.x, self.player.y)
    self.world:updateNPCs(scaled_dt, self.player.x, self.player.y)

    local shake_callback = function(intensity, duration)
        camera_sys:shake(intensity, duration)
    end

    for _, enemy in ipairs(self.world.enemies) do
        if enemy.state == "attack" and not enemy.stunned and not enemy.has_attacked then
            -- Calculate distance using collider centers
            local enemy_center_x = enemy.x + enemy.collider_offset_x
            local enemy_center_y = enemy.y + enemy.collider_offset_y
            local dx = enemy_center_x - self.player.x
            local dy = enemy_center_y - self.player.y
            local distance = math.sqrt(dx * dx + dy * dy)

            local in_attack_range = false

            if enemy.is_humanoid then
                -- Calculate edge-to-edge distance for humanoid
                local abs_dx = math.abs(dx)
                local abs_dy = math.abs(dy)

                local edge_distance = distance
                if abs_dy > abs_dx then
                    -- Vertical: subtract height radii (enemy: 40, player: 50)
                    edge_distance = distance - 90
                else
                    -- Horizontal: subtract width radii (enemy: 20, player: 25)
                    edge_distance = distance - 45
                end

                in_attack_range = (edge_distance < (enemy.attack_range or 60))
            else
                -- Slime uses simple center-to-center distance
                in_attack_range = (distance < (enemy.attack_range or 60))
            end

            if in_attack_range then
                local damaged, parried, is_perfect = self.player:takeDamage(enemy.damage or 10, shake_callback)

                enemy.has_attacked = true

                if parried then
                    print(is_perfect and "PERFECT PARRY!" or "PARRY!")
                    enemy:stun(nil, is_perfect)

                    if is_perfect then
                        camera_sys:activate_slow_motion(0.3, 0.2)
                    else
                        camera_sys:activate_slow_motion(0.2, 0.4)
                    end

                    camera_sys:shake(8, 0.2)
                end
            end
        end
    end

    -- CRITICAL: Check player death again after enemy attacks
    if self.player.health <= 0 then
        print("Player died after enemy attack! Switching to game over...")
        local gameover = require "scenes.gameover"
        -- scene_control.switch(gameover, self, false)
        scene_control.switch(gameover, false)
        return
    end

    self.world:update(scaled_dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
            local v = constants.VIBRATION.WEAPON_HIT; input:vibrate(v.duration, v.left, v.right)
            player_sound.playWeaponHit()
        end
    end

    local shake_x, shake_y = camera_sys:get_shake_offset()
    self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight

    local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
    self.cam:lockBounds(mapWidth, mapHeight, w, h)

    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - scaled_dt
    end

    -- Transition check
    if self.transition_cooldown <= 0 then
        local player_w, player_h = 32, 32
        local transition = self.world:checkTransition(
            self.player.x - player_w / 2,
            self.player.y - player_h / 2,
            player_w, player_h
        )

        if transition then
            if transition.transition_type == "gameclear" then
                local gameover = require "scenes.gameover"
                -- scene_control.switch(gameover, self, true)
                scene_control.switch(gameover, true)
                return
            else
                self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
            end
        end
    end
end

function play:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    self.world:drawLayer("Ground")
    self.world:drawEntitiesYSorted(self.player)
    self.world:drawSavePoints()
    if debug.enabled then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees")

    -- Draw healing points
    self.world:drawHealingPoints()
    if debug.enabled then
        self.world:drawHealingPointsDebug()
    end
    effects:draw()
    if debug.enabled then self.world:drawDebug() end

    self.cam:detach()

    screen:Attach()

    local vw, vh = screen:GetVirtualDimensions()
    pb = screen.physical_bounds

    hud:draw_health_bar(pb.x + 12, pb.y + 12, 210, 20, self.player.health, self.player.max_health)

    love.graphics.setFont(hud.small_font)
    if self.player:isInvincible() or self.player:isDodgeInvincible() then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print("INVINCIBLE", 17, 35)
    end

    if self.player.dodge_active then
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, 0, 1, "Dodge", input:getPrompt("dodge"))
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("DODGING", 17, vh - 29)
    else
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, self.player.dodge_cooldown, self.player.dodge_cooldown_duration, "Dodge", input:getPrompt("dodge"))
    end

    if self.player.parry_cooldown > 0 then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(string.format("Parry CD: %.1f", self.player.parry_cooldown), 17, 35)
    end

    if self.player.parry_active then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 15)
        love.graphics.setColor(0.3, 0.6, 1, pulse)
        love.graphics.print("PARRY READY!", 17, 35)
    end

    love.graphics.setColor(1, 1, 1, 1)

    if debug.show_fps then
        hud:draw_debug_panel(self.player, self.current_save_slot)
        if debug.enabled then
            love.graphics.setFont(hud.tiny_font)
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("Active Effects: " .. effects:getCount(), 8, 150)

            if input:hasGamepad() then
                love.graphics.print(input:getDebugInfo(), 8, 168)
            end

            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    hud:draw_parry_success(self.player, vw, vh)
    hud:draw_slow_motion_vignette(camera_sys.time_scale, vw, vh)

    if self.save_notification.active then
        local alpha = math.min(1, self.save_notification.timer / 0.5)
        local font = love.graphics.newFont(28)
        love.graphics.setFont(font)

        local text = self.save_notification.text
        local text_width = font:getWidth(text)

        love.graphics.setColor(0, 0, 0, 0.7 * alpha)
        love.graphics.rectangle("fill", vw / 2 - text_width / 2 - 20, 150, text_width + 40, 50)

        love.graphics.setColor(0, 1, 0.5, alpha)
        love.graphics.print(text, vw / 2 - text_width / 2, 160)

        love.graphics.setColor(1, 1, 1, 1)
    end

    dialogue:draw()

    if debug.enabled then debug:drawHelp(vw - 250, 10) end

    -- Draw inventory
    hud:draw_inventory(self.inventory, vw, vh)

    screen:Detach()

    if self.fade_alpha > 0 then
        local real_w, real_h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, real_w, real_h)
    end
end

function play:resize(w, h)
    -- Use screen module for proper scaling
    local vw, vh = screen:GetVirtualDimensions()
    local scale_x = w / vw
    local scale_y = h / vh
    local cam_scale = math.min(scale_x, scale_y)
    self.cam:zoomTo(cam_scale)
end

function play:keypressed(key)
    -- Toggle debug with F12

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
        if self.player:startDodge() then print("Dodge!") end
    elseif input:wasPressed("use_item", "keyboard", key) then
        -- Use selected item from inventory
        if self.inventory and self.inventory:useSelectedItem(self.player) then
            print("Used item!")
        end
    elseif input:wasPressed("next_item", "keyboard", key) then
        -- Select next item in inventory
        if self.inventory then
            self.inventory:selectNext()
            local item = self.inventory:getSelectedItem()
            if item then
                print("Selected: " .. item.name)
            end
        end
    elseif input:wasPressed("slot_1", "keyboard", key) then
        if self.inventory then
            self.inventory:selectSlot(1)
            local item = self.inventory:getSelectedItem()
            if item then print("Selected slot 1: " .. item.name) end
        end
    elseif input:wasPressed("slot_2", "keyboard", key) then
        if self.inventory then
            self.inventory:selectSlot(2)
            local item = self.inventory:getSelectedItem()
            if item then print("Selected slot 2: " .. item.name) end
        end
    elseif input:wasPressed("slot_3", "keyboard", key) then
        if self.inventory then
            self.inventory:selectSlot(3)
            local item = self.inventory:getSelectedItem()
            if item then print("Selected slot 3: " .. item.name) end
        end
    elseif input:wasPressed("slot_4", "keyboard", key) then
        if self.inventory then
            self.inventory:selectSlot(4)
            local item = self.inventory:getSelectedItem()
            if item then print("Selected slot 4: " .. item.name) end
        end
    elseif input:wasPressed("slot_5", "keyboard", key) then
        if self.inventory then
            self.inventory:selectSlot(5)
            local item = self.inventory:getSelectedItem()
            if item then print("Selected slot 5: " .. item.name) end
        end
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
                print("Game saved to slot " .. slot .. " at savepoint: " .. savepoint.id)
            end)
        end
    elseif input:wasPressed("manual_save", "keyboard", key) then
        self:saveGame()
        print("Manual save triggered (F9)")
    else
        debug:handleInput(key, {
            player = self.player,
            world = self.world,
            camera = self.cam
        })
    end
end

function play:mousepressed(x, y, button)
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
        if self.player:startParry() then print("Parry stance activated!") end
    end
end

function play:mousereleased(x, y, button)
    -- Ignore mouse events on mobile
    if is_mobile then
        return
    end
end

function play:gamepadpressed(joystick, button)
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
    elseif input:wasPressed("attack", "gamepad", button) then
        self.player:attack()
    elseif input:wasPressed("parry", "gamepad", button) then
        if self.player:startParry() then print("Parry activated!") end
    elseif input:wasPressed("dodge", "gamepad", button) then
        if self.player:startDodge() then print("Dodge!") end
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
                print("Game saved to slot " .. slot .. " at savepoint: " .. savepoint.id)
            end)
        end
    elseif input:wasPressed("use_item", "gamepad", button) then
        -- Use selected item from inventory
        if self.inventory and self.inventory:useSelectedItem(self.player) then
            print("Used item! [L1]")
        end
    elseif input:wasPressed("next_item", "gamepad", button) then
        -- Select next item in inventory
        if self.inventory then
            self.inventory:selectNext()
            local item = self.inventory:getSelectedItem()
            if item then
                print("Selected: " .. item.name .. " [R1]")
            end
        end
    end
end

function play:touchreleased(id, x, y, dx, dy, pressure)
    -- Handle debug button release
    if self:handleDebugButtonTouch(x, y, id, false) then
        return
    end
end

function play:switchMap(new_map_path, spawn_x, spawn_y)
    if self.world then self.world:destroy() end

    self.current_map_path = new_map_path
    self.world = world:new(new_map_path)

    self.player.x = spawn_x
    self.player.y = spawn_y

    self.player.collider = nil

    self.world:addEntity(self.player)

    self.transition_cooldown = 0.5

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight

    local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
    self.cam:lockBounds(mapWidth, mapHeight, w, h)

    self.fade_alpha = 1.0
    self.is_fading = true
end

return play
