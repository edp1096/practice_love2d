-- systems/world/entities.lua
-- Contains entity management functions

local effects = require "engine.systems.effects"
local constants = require "engine.core.constants"

local entities = {}

function entities.addEntity(self, entity)
    if not entity.collider then
        entity.collider = self.physicsWorld:newBSGRectangleCollider(
            entity.x, entity.y,
            entity.width, entity.height,
            10
        )
        entity.collider:setFixedRotation(true)
        entity.collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER)

        -- Reduce friction for better platformer feel
        entity.collider:setFriction(0.0)  -- No friction to prevent wall sliding issues

        -- Platformer grounded detection using PreSolve (called every frame during contact)
        entity.collider:setPreSolve(function(collider_1, collider_2, contact)
            if entity.game_mode == "platformer" then
                local nx, ny = contact:getNormal()

                -- Check both normal directions (collision order is not guaranteed)
                -- If normal is mostly vertical (player on top or bottom of object)
                if math.abs(ny) > 0.7 then
                    local _, vy = entity.collider:getLinearVelocity()

                    -- Player is on ground if:
                    -- 1. Normal points up (ny < 0) OR
                    -- 2. Normal points down (ny > 0) AND player is falling (vy > 0)
                    if ny < 0 or (ny > 0 and vy >= 0) then
                        entity.is_grounded = true
                        entity.can_jump = true
                        entity.is_jumping = false

                        -- Store contact surface Y position for shadow rendering
                        -- Get contact point world coordinates
                        local points = {contact:getPositions()}
                        if #points >= 2 then
                            -- Use first contact point's Y coordinate
                            entity.contact_surface_y = points[2]
                        end
                    end
                end
            end
        end)
    end
end

function entities.addEnemy(self, enemy)
    local bounds = enemy:getColliderBounds()
    enemy.collider = self.physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    enemy.collider:setFixedRotation(true)
    enemy.collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY)
    enemy.collider:setObject(enemy)

    -- Platformer mode: remove air resistance for faster falling
    if self.game_mode == "platformer" then
        enemy.collider:setLinearDamping(0)
        enemy.collider:setGravityScale(1)
        local body = enemy.collider.body
        if body then
            body:setLinearDamping(0)
        end
    end

    table.insert(self.enemies, enemy)
end

function entities.moveEntity(self, entity, vx, vy, dt)
    if not entity.collider then return end

    -- In platformer mode, only set horizontal velocity (gravity handles vertical)
    if entity.game_mode == "platformer" then
        local current_vx, current_vy = entity.collider:getLinearVelocity()

        -- Dodge: direct velocity setting for responsive dodge movement (ignores gravity temporarily)
        if entity.dodge_active then
            entity.collider:setLinearVelocity(vx, current_vy)
        -- Air control: use smoother velocity change when in air
        elseif not entity.is_grounded then
            -- Apply horizontal force instead of directly setting velocity for better air control
            local target_vx = vx
            local force_x = (target_vx - current_vx) * entity.collider:getMass() * 15 -- Air control multiplier
            entity.collider:applyLinearImpulse(force_x * dt, 0)

            -- Clamp horizontal velocity to prevent excessive speed
            local new_vx, new_vy = entity.collider:getLinearVelocity()
            local max_air_speed = entity.speed * 1.2  -- Allow slightly faster air movement
            if math.abs(new_vx) > max_air_speed then
                local sign = new_vx >= 0 and 1 or -1
                entity.collider:setLinearVelocity(sign * max_air_speed, new_vy)
            end
        else
            -- Ground control: direct velocity setting for responsive ground movement
            entity.collider:setLinearVelocity(vx, current_vy)
        end
    else
        -- Topdown mode: set both velocities
        entity.collider:setLinearVelocity(vx, vy)
    end
end

function entities.updateEnemies(self, dt, player_x, player_y)
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]

        if enemy.state == "dead" then
            enemy.death_timer = (enemy.death_timer or 0) + dt
            if enemy.death_timer > 2 then
                if enemy.collider then enemy.collider:destroy() end
                table.remove(self.enemies, i)
            end
        else
            local vx, vy = enemy:update(dt, player_x, player_y)

            if enemy.collider then
                -- In platformer mode, preserve vertical velocity (gravity)
                -- Only set horizontal velocity from AI
                if self.game_mode == "platformer" then
                    _, vy = enemy.collider:getLinearVelocity()
                end
                enemy.collider:setLinearVelocity(vx, vy)

                enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                enemy.y = enemy.collider:getY() - enemy.collider_offset_y
            end
        end
    end
end

function entities.updateNPCs(self, dt, player_x, player_y)
    for _, npc in ipairs(self.npcs) do
        npc:update(dt, player_x, player_y)
    end

    self:updateSavePoints(player_x, player_y)
end

function entities.updateHealingPoints(self, dt, player)
    for _, hp in ipairs(self.healing_points) do
        hp:update(dt, player)
    end
end

function entities.updateSavePoints(self, player_x, player_y)
    for _, savepoint in ipairs(self.savepoints) do
        local dx = player_x - savepoint.center_x
        local dy = player_y - savepoint.center_y
        local distance = math.sqrt(dx * dx + dy * dy)

        savepoint.can_interact = (distance < savepoint.interaction_range)
    end
end

function entities.checkLineOfSight(self, x1, y1, x2, y2)
    local items = self.physicsWorld:queryLine(x1, y1, x2, y2)

    for _, item in ipairs(items) do
        if item.collision_class == constants.COLLISION_CLASSES.WALL then return false end
    end

    return true
end

function entities.checkWeaponCollisions(self, weapon)
    local hit_results = {}

    if not weapon:canDealDamage() then return hit_results end

    for _, enemy in ipairs(self.enemies) do
        if enemy.state ~= "dead" and weapon:checkHit(enemy) then
            table.insert(hit_results, {
                enemy = enemy,
                damage = weapon:getDamage(),
                knockback = weapon:getKnockback()
            })
        end
    end

    return hit_results
end

function entities.applyWeaponHit(self, hit_result)
    local enemy = hit_result.enemy
    local damage = hit_result.damage
    local knockback = hit_result.knockback

    enemy:takeDamage(damage)

    local hit_x = enemy.x + enemy.collider_offset_x
    local hit_y = enemy.y + enemy.collider_offset_y

    local weapon_angle = nil
    if self.player and self.player.weapon then
        weapon_angle = self.player.weapon.angle
    end

    effects:spawnHitEffect(hit_x, hit_y, "enemy", weapon_angle)
end

function entities.getInteractableNPC(self, player_x, player_y)
    for _, npc in ipairs(self.npcs) do
        if npc.can_interact then return npc end
    end

    return nil
end

function entities.getInteractableSavePoint(self)
    for _, savepoint in ipairs(self.savepoints) do
        if savepoint.can_interact then return savepoint end
    end

    return nil
end

return entities
