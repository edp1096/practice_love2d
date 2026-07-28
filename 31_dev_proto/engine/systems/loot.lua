-- engine/systems/loot.lua
-- Loot drop system (handles random item generation from loot tables)
-- Pure logic - receives loot table data via dependency injection

local probability = require "engine.utils.probability"

local loot = {}

-- Get loot drop for an enemy
-- @param enemy_type: string (e.g., "red_slime", "bandit")
-- @param enemy_config: enemy configuration table (contains loot_category)
-- @param loot_tables_data: table from game/data/loot_tables.lua
-- @return item_type, quantity (or nil, 0 if no drop)
function loot.getLoot(enemy_type, enemy_config, loot_tables_data)
    if not loot_tables_data then
        return nil, 0
    end

    -- Determine loot category from config
    local loot_category = "humanoid"  -- Default
    if enemy_config and enemy_config.loot_category then
        loot_category = enemy_config.loot_category
    end

    -- Get loot table for this category
    local loot_table = loot_tables_data[loot_category]
    if not loot_table then
        return nil, 0
    end

    -- Check drop chance
    if math.random() > loot_table.drop_chance then
        return nil, 0  -- No drop
    end

    -- Roll for item (uses probability utility)
    return probability.weightedRandomEntry(loot_table.items)
end

return loot
