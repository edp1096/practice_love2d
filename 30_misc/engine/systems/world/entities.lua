-- systems/world/entities.lua
-- Contains entity management functions (update, collision, movement)

local effects = require "engine.systems.effects"
local constants = require "engine.core.constants"
local collision = require "engine.systems.collision"
local loot_system = require "engine.systems.loot"
local helpers = require "engine.utils.helpers"

-- Import sub-modules
local transform = require "engine.systems.world.transform"
local stairs = require "engine.systems.world.stairs"

local entities = {}

-- Helper functions for enemy update logic

-- Get accurate drop position from enemy colliders
local function getEnemyDropPosition(enemy, game_mode)
    local drop_x, drop_y = enemy.x, enemy.y

    if game_mode == "topdown" and enemy.foot_collider then
        drop_x = enemy.foot_collider:getX()
        drop_y = enemy.foot_collider:getY()
    elseif enemy.collider then
        drop_x = enemy.collider:getX()
        drop_y = enemy.collider:getY()
    end

    return drop_x, drop_y
end

-- Stop all enemy movement
local function stopEnemyMovement(enemy)
    if enemy.collider then
        enemy.collider:setLinearVelocity(0, 0)
    end
    if enemy.foot_collider then
        enemy.foot_collider:setLinearVelocity(0, 0)
    end
end

-- Try to drop loot from dead enemy
local function tryDropLoot(self, enemy, drop_x, drop_y)
    if not (self.loot_tables and self.world_item_class) then
        return
    end

    local enemy_config = self.enemy_class and self.enemy_class.type_registry and self.enemy_class.type_registry[enemy.type]
    local item_type, quantity = loot_system.getLoot(enemy.type, enemy_config, self.loot_tables)
    if item_type then
        self:addWorldItem(item_type, drop_x, drop_y, quantity)
    end
end

-- Calculate Y offset based on enemy type
local function getYOffset(enemy)
    local offsets = constants.COLLIDER_OFFSETS
    if enemy.is_humanoid then
        return enemy.collider_height * offsets.HUMANOID_FOOT_POSITION
    else
        return enemy.collider_height * offsets.SLIME_FOOT_POSITION
    end
end

-- Update enemy position in topdown mode
local function updateTopdownEnemyPosition(enemy, vx, vy)
    if not enemy.foot_collider then
        if enemy.collider then
            enemy.collider:setLinearVelocity(vx, vy)
            enemy.x = enemy.collider:getX() - enemy.collider_offset_x
            enemy.y = enemy.collider:getY() - enemy.collider_offset_y
        end
        return
    end

    enemy.foot_collider:setLinearVelocity(vx, vy)

    local y_offset = getYOffset(enemy)
    enemy.x = enemy.foot_collider:getX() - enemy.collider_offset_x
    enemy.y = enemy.foot_collider:getY() - enemy.collider_offset_y - y_offset

    if enemy.collider then
        enemy.collider:setPosition(
            enemy.x + enemy.collider_offset_x,
            enemy.y + enemy.collider_offset_y
        )
        enemy.collider:setLinearVelocity(0, 0)
    end
end

-- Update enemy position in platformer mode
local function updatePlatformerEnemyPosition(enemy, vx)
    if not enemy.collider then return end

    local _, vy = enemy.collider:getLinearVelocity()
    enemy.collider:setLinearVelocity(vx, vy)
    enemy.x = enemy.collider:getX() - enemy.collider_offset_x
    enemy.y = enemy.collider:getY() - enemy.collider_offset_y
end

-- Helper: Count transformed NPCs
function entities.countTransformedNPCs(self)
    return helpers.countTable(self.transformed_npcs)
end

function entities.addEntity(self, entity)
    self.player = entity
    collision.createPlayerColliders(entity, self.physicsWorld)
end

function entities.addEnemy(self, enemy)
    collision.createEnemyCollider(enemy, self.physicsWorld, self.game_mode)
    table.insert(self.enemies, enemy)
end

function entities.moveEntity(self, entity, vx, vy, dt)
    if not entity.collider then return end

    if entity.game_mode == "platformer" then
        local physics_collider = entity.collider
        if entity.is_boarded and entity.boarded_vehicle and entity.boarded_vehicle.ground_collider then
            physics_collider = entity.boarded_vehicle.ground_collider
        end

        local current_vx, current_vy = physics_collider:getLinearVelocity()

        if entity.dodge_active then
            physics_collider:setLinearVelocity(vx, current_vy)
        elseif not entity.is_grounded then
            local target_vx = vx
            local force_x = (target_vx - current_vx) * physics_collider:getMass() * 15
            physics_collider:applyLinearImpulse(force_x * dt, 0)

            local new_vx, new_vy = physics_collider:getLinearVelocity()
            local max_air_speed = entity.speed * 1.2
            if math.abs(new_vx) > max_air_speed then
                local sign = new_vx >= 0 and 1 or -1
                physics_collider:setLinearVelocity(sign * max_air_speed, new_vy)
            end
        else
            physics_collider:setLinearVelocity(vx, current_vy)
        end
    else
        -- Topdown mode: use foot_collider for wall collision
        local final_vx, final_vy = vx, vy

        if entity.foot_collider then
            local foot_x = entity.foot_collider:getX()
            local foot_y = entity.foot_collider:getY()
            local adjusted_vx, adjusted_vy, stair = self:adjustVelocityForStairs(vx, vy, foot_x, foot_y)
            final_vx, final_vy = adjusted_vx, adjusted_vy
            entity.on_stair = stair
        end

        if entity.foot_collider then
            entity.foot_collider:setLinearVelocity(final_vx, final_vy)
        else
            entity.collider:setLinearVelocity(final_vx, final_vy)
        end
    end
end

function entities.updateEnemies(self, dt, player_x, player_y)
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]

        if enemy.state == "dead" then
            if not enemy.loot_dropped then
                enemy.loot_dropped = true

                if enemy.map_id and not enemy.respawn then
                    self.killed_enemies[enemy.map_id] = true
                end

                if enemy.map_id then
                    self.session_killed_enemies[enemy.map_id] = true
                end

                local drop_x, drop_y = getEnemyDropPosition(enemy, self.game_mode)
                tryDropLoot(self, enemy, drop_x, drop_y)
            end

            enemy.death_timer = (enemy.death_timer or 0) + dt

            if not enemy.colliders_destroyed then
                if self.game_mode == "topdown" and enemy.foot_collider then
                    local y_offset = getYOffset(enemy)
                    enemy.x = enemy.foot_collider:getX() - enemy.collider_offset_x
                    enemy.y = enemy.foot_collider:getY() - enemy.collider_offset_y - y_offset
                elseif enemy.collider then
                    enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                    enemy.y = enemy.collider:getY() - enemy.collider_offset_y
                end
            end

            if enemy.is_humanoid and enemy.weapon then
                local weapon_x = enemy.x + enemy.collider_offset_x
                local weapon_y = enemy.y + enemy.collider_offset_y
                enemy.weapon:update(dt, weapon_x, weapon_y, 0, enemy.direction, "idle_" .. enemy.direction, 1, false)
            end

            if not enemy.colliders_destroyed and enemy.death_timer > 0.3 then
                enemy.colliders_destroyed = true
                stopEnemyMovement(enemy)
                helpers.destroyColliders(enemy)
            end

            if enemy.death_timer > 2 then
                table.remove(self.enemies, i)
            end
        else
            if enemy.should_transform_to_npc and enemy.surrender_npc then
                self:transformEnemyToNPC(enemy, enemy.surrender_npc)
                table.remove(self.enemies, i)
            else
                local is_knockback_state = enemy.state == constants.ENEMY_STATES.HIT or enemy.is_stunned
                if is_knockback_state then
                    if self.game_mode == "topdown" and enemy.foot_collider then
                        local y_offset = getYOffset(enemy)
                        enemy.x = enemy.foot_collider:getX() - enemy.collider_offset_x
                        enemy.y = enemy.foot_collider:getY() - enemy.collider_offset_y - y_offset
                        if enemy.collider then
                            enemy.collider:setPosition(
                                enemy.x + enemy.collider_offset_x,
                                enemy.y + enemy.collider_offset_y
                            )
                        end
                    elseif enemy.collider then
                        enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                        enemy.y = enemy.collider:getY() - enemy.collider_offset_y
                    end
                end

                local vx, vy = enemy:update(dt, player_x, player_y)

                if not is_knockback_state then
                    if self.game_mode == "topdown" then
                        updateTopdownEnemyPosition(enemy, vx, vy)
                    else
                        updatePlatformerEnemyPosition(enemy, vx)
                    end
                end
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
                type = "enemy",
                enemy = enemy,
                damage = weapon:getDamage(),
                knockback = weapon:getKnockback()
            })
        end
    end

    for _, prop in ipairs(self.props) do
        if prop.breakable and not prop.dead and weapon:checkHitProp(prop) then
            table.insert(hit_results, {
                type = "prop",
                prop = prop,
                damage = weapon:getDamage()
            })
        end
    end

    return hit_results
end

function entities.applyWeaponHit(self, hit_result)
    if hit_result.type == "prop" then
        local prop = hit_result.prop
        local damage = hit_result.damage
        local knockback = hit_result.knockback or 40

        local destroyed = prop:takeDamage(damage)

        local weapon_angle = nil
        if self.player and self.player.weapon then
            weapon_angle = self.player.weapon.angle
        end
        effects:spawnHitEffect(prop.x, prop.y, "prop", weapon_angle)

        if prop.movable and prop.collider and not destroyed then
            local player_x, player_y = self.player.x, self.player.y
            local dir_x = prop.x - player_x
            local dir_y = prop.y - player_y
            local dist = math.sqrt(dir_x * dir_x + dir_y * dir_y)

            if dist > 0 then
                dir_x = dir_x / dist
                dir_y = dir_y / dist
            else
                dir_x, dir_y = 0, -1
            end

            prop.collider:setLinearVelocity(dir_x * knockback, dir_y * knockback)
        end

        prop.hit_flash = 0.05

        return
    end

    local enemy = hit_result.enemy
    local damage = hit_result.damage
    local knockback = hit_result.knockback

    local player_x, player_y = self.player.x, self.player.y
    local enemy_x, enemy_y = enemy.x + enemy.collider_offset_x, enemy.y + enemy.collider_offset_y

    local dir_x = enemy_x - player_x
    local dir_y = enemy_y - player_y
    local dist = math.sqrt(dir_x * dir_x + dir_y * dir_y)

    if dist > 0 then
        dir_x = dir_x / dist
        dir_y = dir_y / dist
    else
        dir_x, dir_y = 0, -1
    end

    local was_alive = enemy.health > 0
    enemy:takeDamage(damage)
    local is_dead = enemy.health <= 0

    local knockback_multiplier = is_dead and 1.0 or 0.5
    local final_knockback = knockback * knockback_multiplier

    if final_knockback > 0 then
        local velocity_x = dir_x * final_knockback * 16
        local velocity_y = dir_y * final_knockback * 16

        if self.game_mode == "topdown" then
            if enemy.foot_collider then
                enemy.foot_collider:setLinearVelocity(velocity_x, velocity_y)
                enemy.foot_collider:setLinearDamping(45)
                local y_offset = getYOffset(enemy)
                enemy.x = enemy.foot_collider:getX() - enemy.collider_offset_x
                enemy.y = enemy.foot_collider:getY() - enemy.collider_offset_y - y_offset
            elseif enemy.collider then
                enemy.collider:setLinearVelocity(velocity_x, velocity_y)
                enemy.collider:setLinearDamping(45)
                enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                enemy.y = enemy.collider:getY() - enemy.collider_offset_y
            end
        else
            if enemy.collider then
                local _, vy = enemy.collider:getLinearVelocity()
                enemy.collider:setLinearVelocity(velocity_x, vy)
                enemy.collider:setLinearDamping(45)
                enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                enemy.y = enemy.collider:getY() - enemy.collider_offset_y
            end
        end
    end

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

-- World Item Management
function entities.addWorldItem(self, item_type, x, y, quantity)
    if not self.world_item_class then
        error("world_item_class not injected into world system")
    end

    local world_item = self.world_item_class:new(x, y, item_type, quantity)
    table.insert(self.world_items, world_item)
    return world_item
end

function entities.updateWorldItems(self, dt)
    for i = #self.world_items, 1, -1 do
        local item = self.world_items[i]
        item:update(dt)
    end
end

function entities.getInteractableWorldItem(self, player_x, player_y, game_mode)
    for _, item in ipairs(self.world_items) do
        if item:canPickup(player_x, player_y, game_mode) then
            return item
        end
    end

    return nil
end

function entities.removeWorldItem(self, item_id)
    for i = #self.world_items, 1, -1 do
        if self.world_items[i].id == item_id then
            table.remove(self.world_items, i)
            return true
        end
    end

    return false
end

-- Delegate stair functions to stairs module
entities.getStairInfo = stairs.getStairInfo
entities.adjustVelocityForStairs = stairs.adjustVelocityForStairs
entities.getStairOffset = stairs.getStairOffset

-- Delegate transform functions to transform module
entities.transformNPCToEnemy = transform.transformNPCToEnemy
entities.transformEnemyToNPC = transform.transformEnemyToNPC

-- Update all props
function entities.updateProps(self, dt)
    for i = #self.props, 1, -1 do
        local prop = self.props[i]
        prop:update(dt)

        if prop.dead and prop.map_id then
            if not prop.respawn then
                self.destroyed_props[prop.map_id] = true
            end
            self.session_destroyed_props[prop.map_id] = true
        end

        if prop.dead and prop.death_timer > 1 then
            table.remove(self.props, i)
        end
    end
end

-- Update all vehicles
function entities.updateVehicles(self, dt, player_x, player_y)
    for _, vehicle in ipairs(self.vehicles) do
        vehicle:update(dt, player_x, player_y)
    end
end

-- Get interactable vehicle near player
function entities.getInteractableVehicle(self, player_x, player_y)
    for _, vehicle in ipairs(self.vehicles) do
        if vehicle.can_interact and not vehicle.is_boarded then
            return vehicle
        end
    end
    return nil
end

-- Add a vehicle to the world (for map transition persistence)
function entities.addVehicle(self, vehicle)
    vehicle.world = self
    collision.createVehicleCollider(vehicle, self.physicsWorld, self.game_mode)
    table.insert(self.vehicles, vehicle)
end

return entities
