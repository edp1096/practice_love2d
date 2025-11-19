-- engine/utils/helpers.lua
-- Common helper functions for persistence and cleanup

local helpers = {}

-- Sync persistence data from world to scene
-- Used before saving or switching maps to ensure scene has latest state
function helpers.syncPersistenceData(scene)
    if not scene.world then
        return
    end

    scene.picked_items = scene.world.picked_items or scene.picked_items
    scene.killed_enemies = scene.world.killed_enemies or scene.killed_enemies
    scene.transformed_npcs = scene.world.transformed_npcs or scene.transformed_npcs
end

-- Destroy entity colliders and clear references
-- Prevents memory leaks and dangling references
function helpers.destroyColliders(entity)
    if entity.collider then
        entity.collider:destroy()
        entity.collider = nil
    end

    if entity.foot_collider then
        entity.foot_collider:destroy()
        entity.foot_collider = nil
    end
end

-- Count non-nil entries in a table
-- Generic helper for debugging persistence tables
function helpers.countTable(tbl)
    if not tbl then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

return helpers
