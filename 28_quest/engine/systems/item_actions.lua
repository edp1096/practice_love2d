-- engine/systems/item_actions.lua
-- Item action system (handles item usage logic based on data)
-- Pure logic - receives item data via dependency injection

local item_actions = {}

-- Check if player can use an item
-- @param item_data: item configuration from game/data/items/
-- @param player: player entity
-- @return boolean: true if item can be used
function item_actions.canUse(item_data, player)
    if not item_data or not item_data.use_condition then
        return false
    end

    local condition = item_data.use_condition

    -- Explicit condition types
    if condition.type == "health_not_full" then
        return player.health < player.max_health
    elseif condition.type == "never" then
        -- Equipment items cannot be used directly
        return false
    elseif condition.type == "always" then
        return true
    end

    -- Unknown condition type - default to false
    return false
end

-- Use an item and apply its effects
-- @param item_data: item configuration from game/data/items/
-- @param player: player entity
-- @return boolean: true if item was successfully used
function item_actions.use(item_data, player)
    if not item_data or not item_data.effects then
        return false
    end

    local success = false
    local old_health = player.health

    -- Apply all effects
    for i, effect in ipairs(item_data.effects) do
        if effect.type == "heal" then
            -- Heal player
            player.health = math.min(player.max_health, player.health + effect.amount)
            if player.health > old_health then
                success = true
                print(string.format("✓ HP RESTORED: %d → %d (+%d)", old_health, player.health, player.health - old_health))
            end

        elseif effect.type == "play_sound" then
            -- Play sound effect
            local sound = require("engine.core.sound")
            if sound and sound.playSFX then
                pcall(function()
                    sound:playSFX(effect.category, effect.name)
                end)
            end

        -- Add more effect types here as needed:
        -- elseif effect.type == "restore_stamina" then
        --     player.stamina = math.min(player.max_stamina, player.stamina + effect.amount)
        -- elseif effect.type == "buff" then
        --     player.buffs[effect.stat] = (player.buffs[effect.stat] or 0) + effect.amount
        -- elseif effect.type == "cure_status" then
        --     player.status_effects[effect.status] = nil
        end
    end

    return success
end

return item_actions
