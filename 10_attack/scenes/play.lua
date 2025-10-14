-- scenes/play.lua
-- Main gameplay scene: manages world, player, and camera with PARRY system

local play = {}

local player = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local debug = require "systems.debug"
local screen = require "lib.screen"

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

    -- Camera shake
    self.camera_shake_x = 0
    self.camera_shake_y = 0
    self.camera_shake_timer = 0
    self.camera_shake_intensity = 0

    -- Slow motion system (for parry effects)
    self.slow_motion_active = false
    self.slow_motion_timer = 0
    self.slow_motion_duration = 0.5
    self.time_scale = 1.0
    self.target_time_scale = 1.0
end

function play:exit()
    if self.world then
        self.world:destroy()
    end
end

function play:pause() end

function play:resume() end

function play:shakeCamera(intensity, duration)
    self.camera_shake_intensity = intensity or 10
    self.camera_shake_timer = duration or 0.3
end

function play:activateSlowMotion(duration, time_scale)
    self.slow_motion_active = true
    self.slow_motion_timer = duration or 0.5
    self.target_time_scale = time_scale or 0.3
end

function play:update(dt)
    -- Handle slow motion
    if self.slow_motion_active then
        self.slow_motion_timer = self.slow_motion_timer - dt

        if self.slow_motion_timer <= 0 then
            self.slow_motion_active = false
            self.target_time_scale = 1.0
        end
    end

    -- Smoothly transition time scale
    local time_scale_speed = 8.0
    if self.time_scale < self.target_time_scale then
        self.time_scale = math.min(self.time_scale + time_scale_speed * dt, self.target_time_scale)
    elseif self.time_scale > self.target_time_scale then
        self.time_scale = math.max(self.time_scale - time_scale_speed * dt, self.target_time_scale)
    end

    -- Apply time scale to delta time
    local scaled_dt = dt * self.time_scale

    -- Fade in effect (always at normal speed)
    if self.is_fading and self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
        if self.fade_alpha == 0 then
            self.is_fading = false
        end
    end

    -- Update camera shake (always at normal speed)
    if self.camera_shake_timer > 0 then
        self.camera_shake_timer = math.max(0, self.camera_shake_timer - dt)

        if self.camera_shake_timer > 0 then
            self.camera_shake_x = (math.random() - 0.5) * 2 * self.camera_shake_intensity
            self.camera_shake_y = (math.random() - 0.5) * 2 * self.camera_shake_intensity
        else
            self.camera_shake_x = 0
            self.camera_shake_y = 0
        end
    end

    -- Update player with scaled time
    local vx, vy = self.player:update(scaled_dt, self.cam)

    self.world:moveEntity(self.player, vx, vy, scaled_dt)
    self.world:updateEnemies(scaled_dt, self.player.x, self.player.y)

    -- Check if enemies attack player
    local shake_callback = function(intensity, duration)
        self:shakeCamera(intensity, duration)
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
                    -- Successful parry!
                    print(is_perfect and "PERFECT PARRY!" or "PARRY!")

                    -- Stun the enemy
                    enemy:stun(nil, is_perfect)

                    -- Activate slow motion
                    if is_perfect then
                        self:activateSlowMotion(0.3, 0.2) -- Longer, slower for perfect parry
                    else
                        self:activateSlowMotion(0.2, 0.4) -- Shorter, faster for normal parry
                    end

                    -- Camera shake for feedback
                    self:shakeCamera(8, 0.2)
                end
            end
        end
    end

    self.world:update(scaled_dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    -- Check weapon collisions with enemies
    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
        end
    end

    -- Apply camera shake to lookAt
    self.cam:lookAt(
        self.player.x + self.camera_shake_x,
        self.player.y + self.camera_shake_y
    )

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    -- Update transition cooldown
    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - scaled_dt
    end

    -- Check for map transitions
    if self.transition_cooldown <= 0 then
        local player_w, player_h = 32, 32
        local transition = self.world:checkTransition(
            self.player.x - player_w / 2,
            self.player.y - player_h / 2,
            player_w,
            player_h
        )

        -- Check if player is dead
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

    self.cam:attach()

    self.world:drawLayer("Ground")
    self.world:drawEnemies()
    self.player:drawAll()

    if debug.debug_mode then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees")

    if debug.debug_mode then
        self.world:drawDebug()
    end

    self.cam:detach()

    -- Draw health bar UI
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 10, 10, 214, 44)

    love.graphics.setColor(0.3, 0, 0, 1)
    love.graphics.rectangle("fill", 12, 12, 210, 20)

    local health_ratio = self.player.health / self.player.max_health
    love.graphics.setColor(0, 1, 0, 1)
    if health_ratio < 0.3 then
        love.graphics.setColor(1, 0, 0, 1)
    elseif health_ratio < 0.6 then
        love.graphics.setColor(1, 1, 0, 1)
    end
    love.graphics.rectangle("fill", 12, 12, 210 * health_ratio, 20)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        string.format("HP: %d / %d", self.player.health, self.player.max_health),
        17, 15
    )

    -- Invincibility indicator
    if self.player:isInvincible() then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print("INVINCIBLE", 17, 35)
    end

    -- Dodge cooldown/invincibility indicator (bottom left)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 10, love.graphics.getHeight() - 54, 214, 44)

    -- Dodge status bar background
    love.graphics.setColor(0.2, 0.2, 0.3, 1)
    love.graphics.rectangle("fill", 12, love.graphics.getHeight() - 52, 210, 20)

    -- Dodge cooldown bar or ready indicator
    if self.player.dodge_cooldown > 0 then
        local cooldown_ratio = 1 - (self.player.dodge_cooldown / self.player.dodge_cooldown_duration)
        love.graphics.setColor(0.3, 0.5, 1, 1)
        love.graphics.rectangle("fill", 12, love.graphics.getHeight() - 52, 210 * cooldown_ratio, 20)

        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(
            string.format("Dodge CD: %.1f", self.player.dodge_cooldown),
            17, love.graphics.getHeight() - 49
        )
    elseif self.player.dodge_active then
        -- During dodge
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.rectangle("fill", 12, love.graphics.getHeight() - 52, 210, 20)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("DODGING!", 17, love.graphics.getHeight() - 49)
    else
        -- Ready to dodge
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(0.3, 1, 0.3, pulse)
        love.graphics.rectangle("fill", 12, love.graphics.getHeight() - 52, 210, 20)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("DODGE READY! (SPACE)", 17, love.graphics.getHeight() - 49)
    end

    -- Dodge i-frames indicator
    if self.player:isDodgeInvincible() then
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("I-FRAMES!", 17, love.graphics.getHeight() - 29)
    end

    -- Parry cooldown indicator
    if self.player.parry_cooldown > 0 then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        local cooldown_text = string.format("Parry CD: %.1f", self.player.parry_cooldown)
        love.graphics.print(cooldown_text, 17, 35)
    end

    -- Parry active indicator
    if self.player.parry_active then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 15)
        love.graphics.setColor(0.3, 0.6, 1, pulse)
        love.graphics.print("PARRY READY!", 17, 35)
    end

    love.graphics.setColor(1, 1, 1, 1)

    -- Parry success text (large, center screen)
    if self.player.parry_success_timer > 0 then
        local text = self.player.parry_perfect and "PERFECT PARRY!" or "PARRY!"
        local font_size = self.player.parry_perfect and 48 or 36
        local old_font = love.graphics.getFont()
        local font = love.graphics.newFont(font_size)
        love.graphics.setFont(font)

        local alpha = self.player.parry_success_timer / 0.5
        if self.player.parry_perfect then
            love.graphics.setColor(1, 1, 0, alpha)     -- Gold for perfect
        else
            love.graphics.setColor(0.5, 0.8, 1, alpha) -- Blue for normal
        end

        local text_width = font:getWidth(text)
        love.graphics.print(text, love.graphics.getWidth() / 2 - text_width / 2, 150)

        love.graphics.setFont(old_font)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Slow motion visual effect (vignette)
    if self.time_scale < 0.9 then
        local vignette_alpha = (1.0 - self.time_scale) * 0.3
        love.graphics.setColor(0.2, 0.4, 0.6, vignette_alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1, 1)
    end

    if debug.show_fps then
        local marking_info = self.player:getHandMarkingInfo()
        local panel_height = marking_info and 280 or 230

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 0, 0, 280, panel_height)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        love.graphics.print(string.format("Player: %.1f, %.1f", self.player.x, self.player.y), 10, 30)
        love.graphics.print("Press ESC to pause", 10, 50)
        love.graphics.print("Left Click to Attack", 10, 70)
        love.graphics.print("Right Click to Parry", 10, 90)
        love.graphics.print("Space to Dodge/Roll", 10, 110)
        love.graphics.print("H = Hand Marking Mode", 10, 130)
        love.graphics.print("P = Mark Position", 10, 150)

        local state_text = "State: " .. self.player.state
        if self.player.attack_cooldown > 0 then
            state_text = state_text .. string.format(" (CD: %.1f)", self.player.attack_cooldown)
        end
        if self.player.dodge_active then
            state_text = state_text .. " [DODGING]"
        end
        love.graphics.print(state_text, 10, 170)

        -- Show time scale
        if self.time_scale < 1.0 then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print(string.format("Time Scale: %.2fx", self.time_scale), 10, 190)
            love.graphics.setColor(1, 1, 1, 1)
        end

        if marking_info then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("--- HAND MARKING MODE ---", 10, 210)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("Animation: " .. marking_info.animation, 10, 230)
            love.graphics.print(string.format("Frame: %d / %d", marking_info.frame, marking_info.frame_count), 10, 250)
            love.graphics.print("PgUp/PgDown: Change frame", 10, 270)
        end
    end

    -- Draw fade overlay
    if self.fade_alpha > 0 then
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end
end

function play:resize(w, h)
    self.cam:zoomTo(w / 960)
end

function play:keypressed(key)
    if key == "escape" then
        local pause = require "scenes.pause"
        scene_control.push(pause)
    elseif key == "space" then
        -- Space bar: Dodge
        if self.player:startDodge() then
            print("Dodge!")
        end
    elseif key == "p" and debug.debug_mode then
        -- P key: Mark anchor positions (hand or weapon)
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = self.cam:worldCoords(mouse_x, mouse_y)

        if love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl') then
            -- Ctrl+P: Mark weapon anchor
            self.player:markWeaponAnchor(world_x, world_y)
        else
            -- P: Mark hand position
            self.player:markHandPosition(world_x, world_y)
        end
    elseif key == "h" and debug.debug_mode then
        self.player:toggleHandMarking()
    elseif key == "pageup" and debug.debug_mode then
        self.player:prevFrame()
    elseif key == "pagedown" and debug.debug_mode then
        self.player:nextFrame()
    end
end

function play:mousepressed(x, y, button)
    if button == 1 then
        -- Left click: Attack
        self.player:attack()
    elseif button == 2 then
        -- Right click: Parry (always, no debug exception)
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
