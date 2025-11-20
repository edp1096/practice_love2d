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
local weather = require "engine.systems.weather"

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

-- Calculate attack distance based on enemy type and game mode
local function calculateAttackDistance(enemy, dx, dy, is_platformer)
    local distance
    if is_platformer then
        distance = math.abs(dx)
        -- CRITICAL: Check Y distance in platformer to prevent air attacks
        local vertical_distance = math.abs(dy)
        if vertical_distance > constants.COMBAT.VERTICAL_ATTACK_LIMIT then
            return nil  -- Too far vertically, skip this enemy
        end
    else
        distance = math.sqrt(dx * dx + dy * dy)
    end

    local attack_distance = distance
    if enemy.is_humanoid then
        -- Calculate edge-to-edge distance for humanoid
        local abs_dx = math.abs(dx)
        local abs_dy = math.abs(dy)

        if is_platformer then
            attack_distance = distance - constants.COMBAT.HUMANOID_WIDTH_RADIUS
        elseif abs_dy > abs_dx then
            attack_distance = distance - constants.COMBAT.HUMANOID_HEIGHT_RADIUS
        else
            attack_distance = distance - constants.COMBAT.HUMANOID_WIDTH_RADIUS
        end
    else
        -- Slime uses simple distance check
        if is_platformer then
            attack_distance = distance - constants.COMBAT.SLIME_COLLIDER_WIDTH
        end
    end

    return attack_distance
end

-- Handle parry effects (slow-motion and camera shake)
local function handleParryEffects(is_perfect)
    if is_perfect then
        camera_sys:activate_slow_motion(
            constants.COMBAT.PERFECT_PARRY_SLOW_MO,
            constants.COMBAT.PERFECT_PARRY_SLOW_DURATION
        )
    else
        camera_sys:activate_slow_motion(
            constants.COMBAT.NORMAL_PARRY_SLOW_MO,
            constants.COMBAT.NORMAL_PARRY_SLOW_DURATION
        )
    end
    camera_sys:shake(constants.COMBAT.PARRY_SHAKE_INTENSITY, constants.COMBAT.PARRY_SHAKE_DURATION)
end

-- Handle enemy attack detection and damage
function update.handleEnemyAttacks(self, scaled_dt, shake_callback)
    local is_platformer = self.world.game_mode == "platformer"

    for _, enemy in ipairs(self.world.enemies) do
        -- Early skip: only process attacking enemies that haven't attacked yet
        if enemy.state == constants.ENEMY_STATES.ATTACK and not enemy.is_stunned and not enemy.has_attacked then
            -- Calculate distance
            local enemy_center_x = enemy.x + enemy.collider_offset_x
            local enemy_center_y = enemy.y + enemy.collider_offset_y
            local dx = enemy_center_x - self.player.x
            local dy = enemy_center_y - self.player.y

            local attack_distance = calculateAttackDistance(enemy, dx, dy, is_platformer)
            if attack_distance then
                -- Check if in attack range
                local in_attack_range = (attack_distance < (enemy.attack_range or constants.COMBAT.DEFAULT_ATTACK_RANGE))
                if in_attack_range then
                    -- Process attack
                    local damaged, parried, is_perfect = self.player:takeDamage(enemy.damage or 10, shake_callback)
                    enemy.has_attacked = true

                    if parried then
                        enemy:stun(nil, is_perfect)
                        handleParryEffects(is_perfect)
                    end
                end
            end
        end
    end
end

-- Handle ground detection for platformer mode
function update.updateGroundDetection(self)
    if self.player.game_mode ~= "platformer" then return end

    local px, py = self.player.x, self.player.y
    local half_height = self.player.collider_height / 2

    -- If player is grounded (from PreSolve), use contact surface for shadow
    if self.player.is_grounded and self.player.contact_surface_y then
        self.player.ground_y = self.player.contact_surface_y
    else
        -- Player is in air - use raycast to find ground below for shadow
        local half_width = self.player.collider_width / 2
        local ray_length = constants.PLAYER.RAYCAST_LENGTH
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
    if self.player.weapon and self.player.weapon.is_attacking then
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

-- Get player foot position for zone checking
local function getPlayerFootPosition(player)
    local px, py = player.collider:getPosition()

    -- In topdown mode, check foot position (center Y + half height)
    -- This represents where the shadow/feet are touching the ground
    if player.game_mode == "topdown" then
        py = py + player.collider_height / 2
    end

    return px, py
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
            scene_control.switch("ending")
        elseif transition.transition_type == "intro" then
            local intro_id = transition.intro_id or constants.GAME_START.DEFAULT_INTRO_ID
            local save = require "engine.core.save"

            -- Check if this intro has already been viewed
            if save:hasViewedIntro(intro_id) then
                -- Skip intro, treat as normal portal
                self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
            else
                -- Show intro for the first time
                local cutscene = require "engine.scenes.cutscene"
                scene_control.switch(cutscene, intro_id, transition.target_map, transition.spawn_x, transition.spawn_y)
            end
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

    local px, py = getPlayerFootPosition(self.player)

    -- Check each death zone (Box2D testPoint for accurate polygon collision)
    for _, zone in ipairs(self.world.death_zones) do
        -- Use Box2D's testPoint to check if player foot is inside the zone
        -- This works accurately for any polygon shape
        if zone.fixture:testPoint(px, py) then
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
        local px, py = getPlayerFootPosition(self.player)

        -- Use Box2D's testPoint to check if player foot is inside the zone
        local is_in_zone = zone_data.collider.fixture:testPoint(px, py)
        if is_in_zone then
            -- Check cooldown
            local zone_id = "zone_" .. i
            local cooldown = self.player.damage_zone_cooldowns[zone_id] or 0
            if cooldown <= 0 then
                -- Apply damage
                local damaged = self.player:takeDamage(zone_data.damage, shake_callback)
                if damaged then
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
    weather:update(dt)

    -- Sync gamepad skip button state to dialogue (same as cutscene)
    if dialogue.skip_button and self.skip_button_held then
        dialogue.skip_button.is_pressed = true
    end

    dialogue:update(dt)

    -- Reset skip button state when dialogue is closed
    if not dialogue:isOpen() and self.skip_button_held then
        self.skip_button_held = false
        if dialogue.skip_button then
            dialogue.skip_button.is_pressed = false
            dialogue.skip_button.charge = 0
        end
    end

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

    -- Sync player position from foot_collider in topdown mode
    if self.player.game_mode == "topdown" and self.player.foot_collider then
        self.player.x = self.player.foot_collider:getX()
        self.player.y = self.player.foot_collider:getY() - self.player.collider_height * 0.40625

        -- Sync main collider to foot_collider
        self.player.collider:setPosition(self.player.x, self.player.y)
    else
        -- Platformer mode or no foot_collider: use main collider
        self.player.x = self.player.collider:getX()
        self.player.y = self.player.collider:getY()

        -- Sync foot_collider if exists (when switching modes)
        if self.player.foot_collider then
            local bottom_y_offset = self.player.collider_height * 0.375
            self.player.foot_collider:setPosition(
                self.player.x,
                self.player.y + bottom_y_offset
            )
        end
    end

    update.updateGroundDetection(self)
    update.handleWeaponCollisions(self)
    update.updateCamera(self)

    -- Check hazard zones
    local death_zone_hit = update.checkDeathZones(self)
    if death_zone_hit then
        -- Player died from death zone - use existing helper
        checkPlayerDeath(self)
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
