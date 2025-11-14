-- game/data/loot_tables.lua
-- Loot tables for enemy drops

local loot_tables = {}

-- Helper: Roll random loot from weighted table
local function rollLoot(loot_table)
    local total_weight = 0
    for _, entry in ipairs(loot_table) do
        total_weight = total_weight + entry.weight
    end

    local roll = math.random() * total_weight
    local cumulative = 0

    for _, entry in ipairs(loot_table) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.item, entry.quantity or 1
        end
    end

    return nil, 0
end

-- Slime drop table
loot_tables.slime = {
    drop_chance = 0.8,  -- 80% chance to drop something
    items = {
        { item = "apple", weight = 33, quantity = 1 },      -- 33% of drops (20 HP)
        { item = "orange", weight = 33, quantity = 1 },     -- 33% of drops (20 HP)
        { item = "strawberry", weight = 34, quantity = 1 }  -- 34% of drops (20 HP)
    }
}

-- Humanoid enemy drop table
loot_tables.humanoid = {
    drop_chance = 0.7,  -- 70% chance
    items = {
        { item = "apple", weight = 10, quantity = 1 },         -- 10% of drops (20 HP)
        { item = "orange", weight = 10, quantity = 1 },        -- 10% of drops (20 HP)
        { item = "strawberry", weight = 10, quantity = 1 },    -- 10% of drops (20 HP)
        { item = "small_potion", weight = 50, quantity = 1 },  -- 50% of drops (30 HP)
        { item = "large_potion", weight = 20, quantity = 1 }   -- 20% of drops (60 HP)
    }
}

-- Get loot for an enemy type
function loot_tables.getLoot(enemy_type)
    -- Determine loot table based on enemy type
    local loot_table
    if enemy_type:find("slime") then
        loot_table = loot_tables.slime
    else
        -- Default to humanoid table
        loot_table = loot_tables.humanoid
    end

    -- Check drop chance
    if math.random() > loot_table.drop_chance then
        return nil, 0  -- No drop
    end

    -- Roll for item
    return rollLoot(loot_table.items)
end

return loot_tables
