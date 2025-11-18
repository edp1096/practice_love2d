-- systems/world/entities.lua
-- Contains entity management functions

local effects = require "engine.systems.effects"
local constants = require "engine.core.constants"
local collision = require "engine.systems.collision"
local loot_system = require "engine.systems.loot"

local entities = {}

function entities.addEntity(self, entity)
    -- Create player colliders using collision module
    collision.createPlayerColliders(entity, self.physicsWorld)
end

function entities.addEnemy(self, enemy)
    -- Create enemy collider using collision module
    collision.createEnemyCollider(enemy, self.physicsWorld, self.game_mode)
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
        -- Topdown mode: use foot_collider for wall collision
        if entity.foot_collider then
            entity.foot_collider:setLinearVelocity(vx, vy)
        else
            -- Fallback: use main collider
            entity.collider:setLinearVelocity(vx, vy)
        end
    end
end

function entities.updateEnemies(self, dt, player_x, player_y)
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]

        if enemy.state == "dead" then
            -- Drop loot once when first entering dead state
            if not enemy.loot_dropped then
                enemy.loot_dropped = true

                -- Get accurate drop position from collider BEFORE stopping movement
                local drop_x, drop_y = enemy.x, enemy.y
                if self.game_mode == "topdown" and enemy.foot_collider then
                    -- Topdown: use foot_collider position (center of entity)
                    drop_x = enemy.foot_collider:getX()
                    drop_y = enemy.foot_collider:getY()
                elseif enemy.collider then
                    -- Platformer: use main collider position
                    drop_x = enemy.collider:getX()
                    drop_y = enemy.collider:getY()
                end

                -- Stop all movement
                if enemy.collider then
                    enemy.collider:setLinearVelocity(0, 0)
                end
                if enemy.foot_collider then
                    enemy.foot_collider:setLinearVelocity(0, 0)
                end

                -- Try to drop item (requires loot_tables and world_item_class)
                if self.loot_tables and self.world_item_class then
                    local item_type, quantity = loot_system.getLoot(enemy.type, self.loot_tables)
                    if item_type then
                        -- Drop at accurate enemy collider position
                        self:addWorldItem(item_type, drop_x, drop_y, quantity)
                    end
                end
            end

            enemy.death_timer = (enemy.death_timer or 0) + dt
            if enemy.death_timer > 2 then
                -- Track non-respawning enemies (one-time kill)
                if not enemy.respawn and enemy.map_id then
                    self.killed_enemies[enemy.map_id] = true
                end

                if enemy.collider then
                    enemy.collider:destroy()
                    enemy.collider = nil
                end
                if enemy.foot_collider then
                    enemy.foot_collider:destroy()
                    enemy.foot_collider = nil
                end
                table.remove(self.enemies, i)
            end
        else
            -- Check if enemy should transform to NPC (surrender)
            if enemy.should_transform_to_npc and enemy.surrender_npc then
                self:transformEnemyToNPC(enemy, enemy.surrender_npc)
                table.remove(self.enemies, i)
                goto continue
            end

            local vx, vy = enemy:update(dt, player_x, player_y)

            if self.game_mode == "topdown" then
                -- Topdown mode: use foot_collider for wall collision
                if enemy.foot_collider then
                    enemy.foot_collider:setLinearVelocity(vx, vy)

                    -- Sync enemy position from foot_collider
                    -- Calculate offset based on enemy type
                    local y_offset
                    if enemy.is_humanoid then
                        y_offset = enemy.collider_height * 0.4375  -- Same as player
                    else
                        y_offset = enemy.collider_height * 0.2  -- Slime offset
                    end

                    enemy.x = enemy.foot_collider:getX() - enemy.collider_offset_x
                    enemy.y = enemy.foot_collider:getY() - enemy.collider_offset_y - y_offset

                    -- Sync main collider position with foot_collider
                    if enemy.collider then
                        enemy.collider:setPosition(
                            enemy.x + enemy.collider_offset_x,
                            enemy.y + enemy.collider_offset_y
                        )
                        -- Set velocity to 0 so main collider doesn't drift
                        enemy.collider:setLinearVelocity(0, 0)
                    end
                else
                    -- Fallback: use main collider
                    enemy.collider:setLinearVelocity(vx, vy)
                    enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                    enemy.y = enemy.collider:getY() - enemy.collider_offset_y
                end
            else
                -- Platformer mode: preserve vertical velocity (gravity)
                -- Only set horizontal velocity from AI
                if enemy.collider then
                    _, vy = enemy.collider:getLinearVelocity()
                    enemy.collider:setLinearVelocity(vx, vy)

                    enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                    enemy.y = enemy.collider:getY() - enemy.collider_offset_y
                end
            end
        end

        ::continue::
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

-- Transform NPC to Enemy (for hostile NPCs)
function entities.transformNPCToEnemy(self, npc, enemy_type)
    if not npc or not enemy_type then return nil end

    -- Save NPC position and state
    local x, y = npc.x, npc.y
    local facing = npc.facing or "down"

    -- Remove NPC (cleanup collider)
    if npc.collider then
        npc.collider:destroy()
        npc.collider = nil
    end
    for i = #self.npcs, 1, -1 do
        if self.npcs[i] == npc then
            table.remove(self.npcs, i)
            break
        end
    end

    -- Create enemy at same position
    local enemy = self.enemy_class:new(x, y, enemy_type)
    if enemy then
        enemy.facing = facing
        -- Make enemy immediately aggressive
        enemy.state = "chase"
        enemy.target = self.player
        -- Add to world
        self:addEnemy(enemy)
    end

    return enemy
end

-- Transform Enemy to NPC (for surrendering enemies)
function entities.transformEnemyToNPC(self, enemy, npc_type)
    if not enemy or not npc_type then return nil end

    -- Get accurate position from collider (before it's destroyed)
    local x, y = enemy.x, enemy.y
    if self.game_mode == "topdown" and enemy.foot_collider then
        x = enemy.foot_collider:getX()
        y = enemy.foot_collider:getY()
    elseif enemy.collider then
        x = enemy.collider:getX()
        y = enemy.collider:getY()
    end

    local facing = enemy.facing or "down"

    -- Remove enemy light (if exists)
    if enemy.light and self.lighting_sys then
        self.lighting_sys:removeLight(enemy.light)
        enemy.light = nil
    end

    -- Mark enemy as "killed" for persistence (prevent respawn)
    if enemy.map_id then
        self.killed_enemies[enemy.map_id] = true

        -- Save transformed NPC info for persistence
        if not self.transformed_npcs then
            self.transformed_npcs = {}
        end
        self.transformed_npcs[enemy.map_id] = {
            npc_type = npc_type,
            x = x,
            y = y,
            facing = facing,
            map_name = self.map.properties.name or "unknown"  -- Explicit map tracking
        }
    end

    -- Destroy enemy colliders
    if enemy.collider then
        enemy.collider:destroy()
        enemy.collider = nil
    end
    if enemy.foot_collider then
        enemy.foot_collider:destroy()
        enemy.foot_collider = nil
    end

    -- Create NPC at same position
    local npc = self.npc_class:new(x, y, npc_type)
    if npc then
        npc.facing = facing
        npc.map_id = enemy.map_id  -- Store map_id for future reference

        -- Add to world
        table.insert(self.npcs, npc)
        collision.createNPCCollider(npc, self.physicsWorld)

        -- Add NPC light (cyan/blue-white color, matching other NPCs)
        if self.lighting_sys then
            npc.light = self.lighting_sys:addLight({
                type = "point",
                x = x,
                y = y,
                radius = 120,
                color = {0.8, 0.9, 1.0},  -- Cyan/blue-white (same as other NPCs)
                intensity = 0.7,
                entity = npc
            })
        end
    end

    return npc
end

return entities
