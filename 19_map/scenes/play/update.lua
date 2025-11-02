-- scenes/play/update.lua
-- Update logic for play scene

local camera_sys = require "systems.camera"
local effects = require "systems.effects"
local dialogue = require "systems.dialogue"
local scene_control = require "systems.scene_control"
local util = require "utils.util"
local constants = require "systems.constants"
local input = require "systems.input"
local player_sound = require "entities.player.sound"

local update = {}

-- Handle enemy attack detection and damage
function update.handleEnemyAttacks(self, scaled_dt, shake_callback)
    for _, enemy in ipairs(self.world.enemies) do
        if enemy.state == "attack" and not enemy.stunned and not enemy.has_attacked then
            -- Calculate distance using collider centers
            local enemy_center_x = enemy.x + enemy.collider_offset_x
            local enemy_center_y = enemy.y + enemy.collider_offset_y
            local dx = enemy_center_x - self.player.x
            local dy = enemy_center_y - self.player.y

            -- Check if platformer mode
            local is_platformer = self.world.game_mode == "platformer"

            -- In platformer mode, only use horizontal distance
            local distance
            if is_platformer then
                distance = math.abs(dx)
            else
                distance = math.sqrt(dx * dx + dy * dy)
            end

            local in_attack_range = false

            if enemy.is_humanoid then
                -- Calculate edge-to-edge distance for humanoid
                local abs_dx = math.abs(dx)
                local abs_dy = math.abs(dy)

                local edge_distance = distance
                if is_platformer then
                    -- Platformer: horizontal only, subtract width radii
                    edge_distance = distance - 45
                elseif abs_dy > abs_dx then
                    -- Topdown vertical: subtract height radii (enemy: 40, player: 50)
                    edge_distance = distance - 90
                else
                    -- Topdown horizontal: subtract width radii (enemy: 20, player: 25)
                    edge_distance = distance - 45
                end

                in_attack_range = (edge_distance < (enemy.attack_range or 60))
            else
                -- Slime uses simple distance check
                local attack_distance = distance
                if is_platformer then
                    -- Platformer: subtract collider widths (slime 16 + player 25 = ~40)
                    attack_distance = distance - 40
                end

                in_attack_range = (attack_distance < (enemy.attack_range or 60))
            end

            if in_attack_range then
                local damaged, parried, is_perfect = self.player:takeDamage(enemy.damage or 10, shake_callback)

                enemy.has_attacked = true

                if parried then
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
end

-- Handle ground detection for platformer mode
function update.updateGroundDetection(self)
    if self.player.game_mode ~= "platformer" then return end

    local px, py = self.player.x, self.player.y
    local half_height = self.player.height / 2

    -- If player is grounded (from PreSolve), use contact surface for shadow
    if self.player.is_grounded and self.player.contact_surface_y then
        self.player.ground_y = self.player.contact_surface_y
    else
        -- Player is in air - use raycast to find ground below for shadow
        local half_width = self.player.width / 2
        local ray_length = 1000
        local closest_ground_y = nil

        -- Cast 3 rays: left edge, center, right edge
        local ray_points = {
            { x = px - half_width + 5, y = py + half_height },
            { x = px, y = py + half_height },
            { x = px + half_width - 5, y = py + half_height }
        }

        for _, point in ipairs(ray_points) do
            self.world.physicsWorld.box2d_world:rayCast(
                point.x, point.y,
                point.x, point.y + ray_length,
                function(fixture, x, y, xn, yn, fraction)
                    local collider = fixture:getUserData()
                    if collider and (collider.collision_class == "Wall" or
                                     collider.collision_class == "Enemy" or
                                     collider.collision_class == "NPC") then
                        if not closest_ground_y or y < closest_ground_y then
                            closest_ground_y = y
                        end
                        return 0
                    end
                    return 1
                end
            )
        end

        if closest_ground_y then
            self.player.ground_y = closest_ground_y
        else
            -- No ground detected, default to player's feet
            if not self.player.ground_y then
                self.player.ground_y = py + half_height
            end
        end
    end
end

-- Handle weapon collision detection
function update.handleWeaponCollisions(self)
    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
            local v = constants.VIBRATION.WEAPON_HIT
            input:vibrate(v.duration, v.left, v.right)
            player_sound.playWeaponHit()
        end
    end
end

-- Update camera position and bounds
function update.updateCamera(self)
    local shake_x, shake_y = camera_sys:get_shake_offset()
    self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight

    local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
    self.cam:lockBounds(mapWidth, mapHeight, w, h)
end

-- Check for map transitions
function update.checkTransitions(self, scaled_dt)
    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - scaled_dt
        return
    end

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
        else
            self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
        end
    end
end

-- Main update function
function update.update(self, dt)
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
        local gameover = require "scenes.gameover"
        scene_control.switch(gameover, self, false)
        return
    end

    local is_dialogue_open = dialogue:isOpen()

    local vx, vy = self.player:update(scaled_dt, self.cam, is_dialogue_open)

    -- Update healing points
    self.world:updateHealingPoints(scaled_dt, self.player)

    for _, enemy in ipairs(self.world.enemies) do
        if enemy.anim then enemy.anim:update(scaled_dt) end
    end

    for _, npc in ipairs(self.world.npcs) do
        if npc.anim then npc.anim:update(scaled_dt) end
    end

    if is_dialogue_open then
        update.updateCamera(self)
        return
    end

    self.world:moveEntity(self.player, vx, vy, scaled_dt)
    self.world:updateEnemies(scaled_dt, self.player.x, self.player.y)
    self.world:updateNPCs(scaled_dt, self.player.x, self.player.y)

    local shake_callback = function(intensity, duration)
        camera_sys:shake(intensity, duration)
    end

    update.handleEnemyAttacks(self, scaled_dt, shake_callback)

    -- CRITICAL: Check player death again after enemy attacks
    if self.player.health <= 0 then
        local gameover = require "scenes.gameover"
        scene_control.switch(gameover, false)
        return
    end

    -- Reset grounded status BEFORE physics update
    -- PreSolve callback will set it to true if player is on ground
    if self.player.game_mode == "platformer" then
        self.player.is_grounded = false
    end

    self.world:update(scaled_dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    update.updateGroundDetection(self)
    update.handleWeaponCollisions(self)
    update.updateCamera(self)
    update.checkTransitions(self, scaled_dt)
end

return update
