-- engine/utils/probability.lua
-- Probability and weighted random utilities

local probability = {}

-- Weighted random selection from a table pool
-- @param pool: table where keys are options and values are weights
--              e.g., { rain = 20, snow = 30, clear = 50 }
-- @param default: default value if pool is empty or nil
-- @return selected key
function probability.weightedRandomKey(pool, default)
    if not pool then return default end

    local total = 0
    for _, weight in pairs(pool) do
        total = total + weight
    end

    if total == 0 then return default end

    local roll = math.random() * total
    local cumulative = 0

    for key, weight in pairs(pool) do
        cumulative = cumulative + weight
        if roll <= cumulative then
            return key
        end
    end

    return default
end

-- Weighted random selection from an array of entries
-- @param entries: array of { item = "name", weight = N, ... }
-- @return item value, quantity (or 1), full entry
function probability.weightedRandomEntry(entries)
    if not entries or #entries == 0 then
        return nil, 0, nil
    end

    local total = 0
    for _, entry in ipairs(entries) do
        total = total + (entry.weight or 1)
    end

    if total == 0 then return nil, 0, nil end

    local roll = math.random() * total
    local cumulative = 0

    for _, entry in ipairs(entries) do
        cumulative = cumulative + (entry.weight or 1)
        if roll <= cumulative then
            return entry.item, entry.quantity or 1, entry
        end
    end

    return nil, 0, nil
end

-- Roll a percentage chance
-- @param percent: 0-100 chance
-- @return boolean
function probability.rollPercent(percent)
    return math.random() * 100 <= percent
end

-- Roll with a fractional chance
-- @param chance: 0.0-1.0 chance
-- @return boolean
function probability.rollChance(chance)
    return math.random() <= chance
end

return probability
