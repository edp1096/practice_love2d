-- engine/scenes/gameplay/update.lua
-- Update logic for play scene

local camera_sys = require "engine.core.camera"
local effects = require "engine.systems.effects"
local dialogue = require "engine.ui.dialogue"
local scene_control = require "engine.core.scene_control"
local util = require "engine.utils.util"
local constants = require "engine.core.constants"
local input = require "engine.core.input"
local player_sound = require "engine.entities.player.sound"
local lighting = require "engine.systems.lighting"

local update = {}

-- Check if player is dead and switch to gameover scene
-- Returns true if player died (scene switched)
local function checkPlayerDeath(self)
    if self.player.health <= 0 then
        scene_control.switch("gameover", false)
        return true
    end
    return false
end

-- Handle enemy attack detection and damage
function update.handleEnemyAttacks(self, scaled_dt, shake_callback)
    for _, enemy in ipairs(self.world.enemies) do
        if enemy.state == constants.ENEMY_STATES.ATTACK and not enemy.stunned and not enemy.has_attacked then
            -- Calculate distance using collider centers
            local enemy_center_x = enemy.x + enemy.collider_offset_x
            local enemy_center_y = enemy.y + enemy.collider_offset_y
            local dx = enemy_center_x - self.player.x
            local dy = enemy_center_y - self.player.y

            -- Check if platformer mode
            local is_platformer = self.world.game_mode == "platformer"

            -- In platformer mode, check both horizontal AND vertical distance
            local distance
            if is_platformer then
                distance = math.abs(dx)
                -- CRITICAL: Also check Y distance in platformer to prevent air attacks
                local vertical_distance = math.abs(dy)
                -- If Y distance is too large (player jumping/falling), skip attack
                if vertical_distance > 50 then
                    goto continue_enemy_loop
                end
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

        ::continue_enemy_loop::
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
                    if collider and (collider.collision_class == constants.COLLISION_CLASSES.WALL or
                                     collider.collision_class == constants.COLLISION_CLASSES.ENEMY or
                                     collider.collision_class == constants.COLLISION_CLASSES.NPC) then
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
            scene_control.switch("gameover", true)
        elseif transition.transition_type == "intro" then
            local cutscene = require "engine.scenes.cutscene"
            local intro_id = transition.intro_id or "level1"
            scene_control.switch(cutscene, intro_id, transition.target_map, transition.spawn_x, transition.spawn_y)
        elseif transition.transition_type == "ending" then
            local cutscene = require "engine.scenes.cutscene"
            local intro_id = transition.intro_id or "ending"
            scene_control.switch(cutscene, intro_id, nil, nil, nil)
        else
            self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
        end
    end
end

-- Check for death zones (instant death)
function update.checkDeathZones(self)
    if not self.player.collider then return false end

    -- Check each death zone (Box2D testPoint for accurate polygon collision)
    for _, zone in ipairs(self.world.death_zones) do
        -- Get player foot position (shadow position for topdown)
        local px, py = self.player.collider:getPosition()

        -- In topdown mode, check foot position (center Y + half height)
        -- This represents where the shadow/feet are touching the ground
        if self.player.game_mode == "topdown" then
            py = py + self.player.height / 2
        end

        -- Use Box2D's testPoint to check if player foot is inside the zone
        -- This works accurately for any polygon shape
        local is_in_zone = zone.fixture:testPoint(px, py)

        if is_in_zone then
            -- Player is in death zone - instant death
            self.player.health = 0
            return true
        end
    end

    return false
end

-- Check for damage zones (continuous damage)
function update.checkDamageZones(self, scaled_dt, shake_callback)
    if not self.player.collider then return end

    -- Initialize damage zone cooldowns if not exists
    if not self.player.damage_zone_cooldowns then
        self.player.damage_zone_cooldowns = {}
    end

    -- Update all cooldowns
    for zone_id, cooldown in pairs(self.player.damage_zone_cooldowns) do
        if cooldown > 0 then
            self.player.damage_zone_cooldowns[zone_id] = cooldown - scaled_dt
        end
    end

    -- Check each damage zone (Box2D testPoint for accurate polygon collision)
    for i, zone_data in ipairs(self.world.damage_zones) do
        local zone = zone_data.collider

        -- Get player foot position (shadow position for topdown)
        local px, py = self.player.collider:getPosition()

        -- In topdown mode, check foot position (center Y + half height)
        -- This represents where the shadow/feet are touching the ground
        if self.player.game_mode == "topdown" then
            py = py + self.player.height / 2
        end

        -- Use Box2D's testPoint to check if player foot is inside the zone
        -- This works accurately for any polygon shape
        local is_in_zone = zone.fixture:testPoint(px, py)

        if is_in_zone then
            -- Player is in damage zone - check cooldown
            local zone_id = "zone_" .. i
            local cooldown = self.player.damage_zone_cooldowns[zone_id] or 0

            if cooldown <= 0 then
                -- Apply damage
                local damaged = self.player:takeDamage(zone_data.damage, shake_callback)

                if damaged then
                    -- Reset cooldown
                    self.player.damage_zone_cooldowns[zone_id] = zone_data.damage_cooldown
                end
            end
        end
    end
end

-- Main update function
function update.update(self, dt)
    camera_sys:update(dt)
    local scaled_dt = camera_sys:get_scaled_dt(dt)

    effects:update(dt)
    effects.screen:update(dt)
    lighting:update(dt)
    dialogue:update(dt)

    -- Update player light position
    if self.player.light then
        self.player.light:setPosition(self.player.x, self.player.y)
    end

    -- Update enemy lights
    for _, enemy in ipairs(self.world.enemies) do
        if enemy.light and enemy.state ~= constants.ENEMY_STATES.DEAD then
            local enemy_center_x = enemy.x + enemy.collider_offset_x
            local enemy_center_y = enemy.y + enemy.collider_offset_y
            enemy.light:setPosition(enemy_center_x, enemy_center_y)
            enemy.light:setEnabled(true)
        elseif enemy.light and enemy.state == constants.ENEMY_STATES.DEAD then
            enemy.light:setEnabled(false)
        end
    end

    -- Update NPC lights
    for _, npc in ipairs(self.world.npcs) do
        if npc.light then
            local npc_center_x = npc.x + npc.collider_offset_x
            local npc_center_y = npc.y + npc.collider_offset_y
            npc.light:setPosition(npc_center_x, npc_center_y)
        end
    end

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
    if checkPlayerDeath(self) then
        return
    end

    local is_dialogue_open = dialogue:isOpen()

    -- Hide/show virtual gamepad based on dialogue state
    if input.virtual_gamepad then
        if is_dialogue_open then
            input.virtual_gamepad:hide()
        else
            input.virtual_gamepad:show()
        end
    end

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
    if checkPlayerDeath(self) then
        return
    end

    -- Reset grounded status BEFORE physics update
    -- PreSolve callback will set it to true if player is on ground
    -- Store previous grounded state for input handling between frames
    if self.player.game_mode == "platformer" then
        self.player.was_grounded = self.player.is_grounded
        self.player.is_grounded = false
    end

    self.world:update(scaled_dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    update.updateGroundDetection(self)
    update.handleWeaponCollisions(self)
    update.updateCamera(self)

    -- Check hazard zones
    local death_zone_hit = update.checkDeathZones(self)
    if death_zone_hit then
        -- Player died from death zone
        scene_control.switch("gameover", false)
        return
    end

    update.checkDamageZones(self, scaled_dt, shake_callback)

    -- CRITICAL: Check player death again after damage zones
    if checkPlayerDeath(self) then
        return
    end

    update.checkTransitions(self, scaled_dt)
end

return update
