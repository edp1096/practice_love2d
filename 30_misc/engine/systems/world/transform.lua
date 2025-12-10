-- systems/world/transform.lua
-- NPC <-> Enemy transformation functions

local helpers = require "engine.utils.helpers"
local collision = require "engine.systems.collision"

local transform = {}

-- Transform NPC to Enemy (for hostile NPCs)
-- @param npc_or_id: NPC object or NPC ID (string)
-- @param enemy_type: Enemy type to create
function transform.transformNPCToEnemy(self, npc_or_id, enemy_type)
    if not npc_or_id or not enemy_type then
        return nil
    end

    -- Find NPC object if ID was provided
    local npc = npc_or_id
    if type(npc_or_id) == "string" then
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
    local direction = npc.direction or "down"
    local map_id = npc.map_id
    local original_npc_type = npc.type

    -- Save transformation info (for persistence and restoration)
    if map_id then
        if not self.transformed_npcs then
            self.transformed_npcs = {}
        end
        self.transformed_npcs[map_id] = {
            enemy_type = enemy_type,
            original_npc_type = original_npc_type,
            x = x,
            y = y,
            direction = direction,
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
        enemy.direction = direction
        enemy.map_id = map_id
        enemy.was_npc = true
        enemy.respawn = false
        enemy.world = self

        -- Make enemy immediately aggressive
        enemy.state = "chase"
        enemy.target = self.player
        if self.player then
            enemy.target_x = self.player.x
            enemy.target_y = self.player.y
        end

        -- Add to world
        collision.createEnemyCollider(enemy, self.physicsWorld, self.game_mode)
        table.insert(self.enemies, enemy)
    end

    return enemy
end

-- Transform Enemy to NPC (for surrendering enemies)
function transform.transformEnemyToNPC(self, enemy, npc_type)
    if not enemy or not npc_type then return nil end

    local x, y = enemy.x, enemy.y
    local direction = enemy.direction or "down"

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
            direction = direction,
            map_name = self.map.properties.name or "unknown"
        }
    end

    -- Destroy enemy colliders
    helpers.destroyColliders(enemy)

    -- Create NPC at same position
    local npc = self.npc_class:new(x, y, npc_type)
    if npc then
        npc.direction = direction
        npc.anim = npc.animations["idle_" .. direction]
        npc.map_id = enemy.map_id

        -- Add to world
        table.insert(self.npcs, npc)
        collision.createNPCCollider(npc, self.physicsWorld, self.game_mode)

        -- Add NPC light (cyan/blue-white color)
        if self.lighting_sys then
            npc.light = self.lighting_sys:addLight({
                type = "point",
                x = x,
                y = y,
                radius = 120,
                color = {0.8, 0.9, 1.0},
                intensity = 0.7,
                entity = npc
            })
        end
    end

    return npc
end

return transform
