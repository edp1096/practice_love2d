-- game/data/loot_tables.lua
-- Loot tables for enemy drops (pure data - no logic)

local loot_tables = {}

-- Slime drop table
loot_tables.slime = {
    drop_chance = 0.8,                                     -- 80% chance to drop something
    items = {
        { item = "apple",      weight = 33, quantity = 1 }, -- 33% of drops (20 HP)
        { item = "orange",     weight = 33, quantity = 1 }, -- 33% of drops (20 HP)
        { item = "strawberry", weight = 34, quantity = 1 } -- 34% of drops (20 HP)
    }
}

-- Humanoid enemy drop table
loot_tables.humanoid = {
    drop_chance = 0.7,                                        -- 70% chance
    items = {
        { item = "apple",        weight = 10, quantity = 1 }, -- 10% of drops (20 HP)
        { item = "orange",       weight = 10, quantity = 1 }, -- 10% of drops (20 HP)
        { item = "strawberry",   weight = 10, quantity = 1 }, -- 10% of drops (20 HP)
        { item = "small_potion", weight = 50, quantity = 1 }, -- 50% of drops (30 HP)
        { item = "large_potion", weight = 20, quantity = 1 }  -- 20% of drops (60 HP)
    }
}

loot_tables.deceiver = {
    drop_chance = 1.0,   -- 100% 확률
    items = {
        { item = "iron_axe", weight = 100, quantity = 1 }
    }
}

return loot_tables
