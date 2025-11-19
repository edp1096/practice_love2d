-- systems/world/entities.lua
-- Contains entity management functions

local effects = require "engine.systems.effects"
local constants = require "engine.core.constants"
local collision = require "engine.systems.collision"
local loot_system = require "engine.systems.loot"
local helpers = require "engine.utils.helpers"

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

    local item_type, quantity = loot_system.getLoot(enemy.type, self.loot_tables)
    if item_type then
        self:addWorldItem(item_type, drop_x, drop_y, quantity)
    end
end

-- Calculate Y offset based on enemy type
local function getYOffset(enemy)
    if enemy.is_humanoid then
        return enemy.collider_height * 0.4375  -- Same as player
    else
        return enemy.collider_height * 0.2  -- Slime offset
    end
end

-- Update enemy position in topdown mode
local function updateTopdownEnemyPosition(enemy, vx, vy)
    if not enemy.foot_collider then
        -- Fallback: use main collider
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

    -- Sync main collider position
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
    -- Store player reference in world (needed for NPC→Enemy transformation)
    self.player = entity

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

                local drop_x, drop_y = getEnemyDropPosition(enemy, self.game_mode)
                stopEnemyMovement(enemy)
                tryDropLoot(self, enemy, drop_x, drop_y)
            end

            enemy.death_timer = (enemy.death_timer or 0) + dt
            if enemy.death_timer > 2 then
                -- Track killed enemies (for persistence)
                -- Only enemies with respawn=true will respawn on map reload
                -- All others (respawn=false or nil) stay dead permanently
                if enemy.map_id and not enemy.respawn then
                    self.killed_enemies[enemy.map_id] = true
                end

                -- Note: Do NOT remove from transformed_npcs!
                -- We keep the transformation record so loadNPCs can skip the original NPC
                -- The killed_enemies entry prevents loading in both loadEnemies and loadNPCs

                helpers.destroyColliders(enemy)
                table.remove(self.enemies, i)
            end
        else
            -- Check if enemy should transform to NPC (surrender)
            if enemy.should_transform_to_npc and enemy.surrender_npc then
                self:transformEnemyToNPC(enemy, enemy.surrender_npc)
                table.remove(self.enemies, i)
            else
                -- Update enemy movement
                local vx, vy = enemy:update(dt, player_x, player_y)

                -- Update position based on game mode
                if self.game_mode == "topdown" then
                    updateTopdownEnemyPosition(enemy, vx, vy)
                else
                    updatePlatformerEnemyPosition(enemy, vx)
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
-- @param npc_or_id: NPC object or NPC ID (string)
-- @param enemy_type: Enemy type to create
function entities.transformNPCToEnemy(self, npc_or_id, enemy_type)
    if not npc_or_id or not enemy_type then
        return nil
    end

    -- Find NPC object if ID was provided
    local npc = npc_or_id
    if type(npc_or_id) == "string" then
        -- Search for NPC by ID
        npc = nil
        for _, n in ipairs(self.npcs) do
            if n.id == npc_or_id then
                npc = n
                break
            end
        end
        if not npc then
            return nil
        end
    end

    -- Save NPC position and state
    local x, y = npc.x, npc.y
    local facing = npc.facing or "down"
    local map_id = npc.map_id  -- Use map_id (e.g., "level1_area3_obj_46") for persistence
    local original_npc_type = npc.type  -- Save original NPC type for restoration

    -- Save transformation info (for persistence and restoration)
    -- NOTE: Do NOT mark in killed_enemies - that's for actually dead enemies only
    if map_id then
        if not self.transformed_npcs then
            self.transformed_npcs = {}
        end
        self.transformed_npcs[map_id] = {
            enemy_type = enemy_type,  -- Current form (enemy)
            original_npc_type = original_npc_type,  -- Original NPC type
            x = x,
            y = y,
            facing = facing,
            map_name = self.map.properties.name or "unknown"
        }
    end

    -- Remove NPC (cleanup collider)
    helpers.destroyColliders(npc)
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
        enemy.map_id = map_id  -- Use same map_id for tracking (e.g., "level1_area3_obj_46")
        enemy.was_npc = true  -- Flag to indicate this was transformed from NPC
        enemy.respawn = false  -- Transformed enemies don't respawn when killed
        enemy.world = self  -- CRITICAL: Set world reference for AI

        -- Make enemy immediately aggressive
        enemy.state = "chase"
        enemy.target = self.player
        -- Set target position to player (so AI starts moving immediately)
        if self.player then
            enemy.target_x = self.player.x
            enemy.target_y = self.player.y
        end
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
    helpers.destroyColliders(enemy)

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
