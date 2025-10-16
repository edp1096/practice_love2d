-- scenes/play.lua
-- Main gameplay scene with save functionality

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

local pb = { x = 0, y = 0, w = 960, h = 540 }

function play:enter(previous, mapPath, spawn_x, spawn_y, save_slot)
    mapPath = mapPath or "assets/maps/level1/area1.lua"
    spawn_x = spawn_x or 400
    spawn_y = spawn_y or 250
    save_slot = save_slot or 1

    self.current_map_path = mapPath
    self.cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)
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
end

function play:exit()
    if self.world then
        self.world:destroy()
    end
end

function play:saveGame(slot)
    slot = slot or self.current_save_slot or 1

    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y
    }

    local success = save_sys:saveGame(slot, save_data)
    if success then
        self.current_save_slot = slot
        self:showSaveNotification()
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

    if dialogue:isOpen() then return end

    if self.is_fading and self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
        if self.fade_alpha == 0 then
            self.is_fading = false
        end
    end

    local vx, vy = self.player:update(scaled_dt, self.cam)

    self.world:moveEntity(self.player, vx, vy, scaled_dt)
    self.world:updateEnemies(scaled_dt, self.player.x, self.player.y)
    self.world:updateNPCs(scaled_dt, self.player.x, self.player.y)

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

    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
        end
    end

    local shake_x, shake_y = camera_sys:get_shake_offset()
    self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - scaled_dt
    end

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
    self.world:drawEnemies()
    self.world:drawNPCs()
    self.world:drawSavePoints()
    self.player:drawAll()
    if debug.enabled then
        self.player:drawDebug()
    end
    self.world:drawLayer("Trees")
    effects:draw()
    if debug.enabled then
        self.world:drawDebug()
    end
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
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, 0, 1, "Dodge", "")
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("DODGING", 17, vh - 29)
    else
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, self.player.dodge_cooldown, self.player.dodge_cooldown_duration, "Dodge", "SPACE")
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
            love.graphics.print("Active Effects: " .. effects:getCount(), 8, 140)
            love.graphics.print("F5: Test Effects at Mouse", 8, 154)
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

    if debug.enabled then
        debug:drawHelp(vw - 250, 10)
    end

    screen:Detach()

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
    elseif key == "f9" then
        self:saveGame()
        print("Manual save triggered (F9)")
    elseif key == "f1" then
        self:saveGame(1)
        print("Quick saved to slot 1 (F1)")
    elseif key == "f2" then
        self:saveGame(2)
        print("Quick saved to slot 2 (F2)")
    elseif key == "f3" then
        self:saveGame(3)
        print("Quick saved to slot 3 (F3)")
    else
        debug:handleInput(key, {
            player = self.player,
            world = self.world,
            camera = self.cam
        })
    end
end

function play:mousepressed(x, y, button)
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

function play:mousereleased(x, y, button) end

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
    self.cam:lockBounds(mapWidth, mapHeight)

    self.fade_alpha = 1.0
    self.is_fading = true
end

return play
