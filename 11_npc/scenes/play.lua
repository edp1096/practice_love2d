-- scenes/play.lua
-- Main gameplay scene with refactored modules and effects

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

function play:enter(previous, mapPath, spawn_x, spawn_y)
    mapPath = mapPath or "assets/maps/level1/area1.lua"
    spawn_x = spawn_x or 400
    spawn_y = spawn_y or 250

    self.cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)
    self.world = world:new(mapPath)
    self.player = player:new("assets/images/player-sheet.png", spawn_x, spawn_y)

    self.world:addEntity(self.player)

    self.transition_cooldown = 0

    -- Fade effect
    self.fade_alpha = 1.0
    self.fade_speed = 2.0
    self.is_fading = true

    -- Initialize dialogue system
    dialogue:initialize()
end

function play:exit()
    if self.world then
        self.world:destroy()
    end
end

function play:update(dt)
    -- Camera system update
    camera_sys:update(dt)
    local scaled_dt = camera_sys:get_scaled_dt(dt)

    -- Effects update
    effects:update(dt)

    -- Dialogue update
    dialogue:update(dt)

    -- If dialogue is open, skip game updates
    if dialogue:isOpen() then
        return
    end

    -- Fade in
    if self.is_fading and self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
        if self.fade_alpha == 0 then
            self.is_fading = false
        end
    end

    -- Update player
    local vx, vy = self.player:update(scaled_dt, self.cam)

    self.world:moveEntity(self.player, vx, vy, scaled_dt)
    self.world:updateEnemies(scaled_dt, self.player.x, self.player.y)
    self.world:updateNPCs(scaled_dt, self.player.x, self.player.y)

    -- Check enemy attacks
    local shake_callback = function(intensity, duration)
        camera_sys:shake(intensity, duration)
    end

    for _, enemy in ipairs(self.world.enemies) do
        if enemy.state == "attack" and not enemy.stunned then
            local dx = enemy.x - self.player.x
            local dy = enemy.y - self.player.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance < (enemy.attack_range or 60) then
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

    self.world:update(scaled_dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    -- Weapon collisions
    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
        end
    end

    -- Camera follow with shake
    local shake_x, shake_y = camera_sys:get_shake_offset()
    self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    -- Transition cooldown
    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - scaled_dt
    end

    -- Check transitions and death
    if self.transition_cooldown <= 0 then
        local player_w, player_h = 32, 32
        local transition = self.world:checkTransition(
            self.player.x - player_w / 2,
            self.player.y - player_h / 2,
            player_w, player_h
        )

        if not self.player:isAlive() then
            local gameover = require "scenes.gameover"
            scene_control.switch(gameover)
            return
        end

        if transition then
            self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
        end
    end
end

function play:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    -- World rendering
    self.cam:attach()
    self.world:drawLayer("Ground")
    self.world:drawEnemies()
    self.world:drawNPCs()
    self.player:drawAll()
    if debug.debug_mode then
        self.player:drawDebug()
    end
    self.world:drawLayer("Trees")
    effects:draw()
    if debug.debug_mode then
        self.world:drawDebug()
    end
    self.cam:detach()

    -- UI rendering (virtual resolution)
    screen:Attach()

    local vw, vh = screen:GetVirtualDimensions()

    -- HUD elements in virtual resolution
    hud:draw_health_bar(12, 12, 210, 20, self.player.health, self.player.max_health)

    love.graphics.setFont(hud.small_font)
    if self.player:isInvincible() then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print("INVINCIBLE", 17, 35)
    end

    if self.player.dodge_active then
        hud:draw_cooldown(12, vh - 52, 210, 0, 1, "Dodge", "")
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("DODGING !", 17, vh - 29)
    else
        hud:draw_cooldown(12, vh - 52, 210, self.player.dodge_cooldown, self.player.dodge_cooldown_duration, "Dodge", "SPACE")
    end

    if self.player:isDodgeInvincible() then
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("I-FRAMES!", 17, vh - 29)
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
        hud:draw_debug_panel(self.player, debug.debug_mode)
        if debug.debug_mode then
            love.graphics.setFont(hud.tiny_font)
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("Active Effects: " .. effects:getCount(), 8, 140)
            love.graphics.print("F1: Test Effects at Mouse", 8, 154)
            love.graphics.print("F2: Toggle Effects Debug", 8, 168)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    hud:draw_parry_success(self.player, vw, vh)
    hud:draw_slow_motion_vignette(camera_sys.time_scale, vw, vh)

    dialogue:draw()

    screen:Detach()

    -- Fade overlay (REAL screen coordinates)
    if self.fade_alpha > 0 then
        local real_w, real_h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, real_w, real_h)
    end
end

function play:resize(w, h)
    self.cam:zoomTo(w / 960)
end

function play:keypressed(key)
    -- Dialogue controls (priority when dialogue is open)
    if dialogue:isOpen() then
        if key == "space" or key == "return" or key == "f" then
            dialogue:onAction()
        end
        return
    end

    if key == "escape" then
        local pause = require "scenes.pause"
        scene_control.push(pause)
    elseif key == "space" then
        if self.player:startDodge() then
            print("Dodge!")
        end
    elseif key == "f" then
        -- NPC interaction
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)
        end
    elseif key == "f1" and debug.debug_mode then
        -- Test effects at mouse position
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = self.cam:worldCoords(mouse_x, mouse_y)
        effects:test(world_x, world_y)
    elseif key == "f2" and debug.debug_mode then
        -- Toggle effects debug
        effects:toggleDebug()
    elseif key == "p" and debug.debug_mode then
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = self.cam:worldCoords(mouse_x, mouse_y)

        if love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl') then
            -- Ctrl+P: Mark weapon anchor (stub for future)
            print("Weapon anchor marking not implemented in refactored version")
        else
            debug:mark_hand_position(self.player, world_x, world_y)
        end
    elseif key == "h" and debug.debug_mode then
        debug:toggle_hand_marking(self.player)
    elseif key == "pageup" and debug.debug_mode then
        debug:prev_frame(self.player)
    elseif key == "pagedown" and debug.debug_mode then
        debug:next_frame(self.player)
    end
end

function play:mousepressed(x, y, button)
    -- Dialogue controls (priority when dialogue is open)
    if dialogue:isOpen() then
        if button == 1 then
            dialogue:onAction()
        end
        return
    end

    if button == 1 then
        self.player:attack()
    elseif button == 2 then
        if self.player:startParry() then
            print("Parry stance activated!")
        end
    end
end

function play:mousereleased(x, y, button)
end

function play:switchMap(new_map_path, spawn_x, spawn_y)
    if self.world then self.world:destroy() end

    self.world = world:new(new_map_path)

    self.player.x = spawn_x
    self.player.y = spawn_y

    self.player.collider = nil

    self.world:addEntity(self.player)

    self.transition_cooldown = 0.5

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    self.fade_alpha = 1.0
    self.is_fading = true
end

return play
