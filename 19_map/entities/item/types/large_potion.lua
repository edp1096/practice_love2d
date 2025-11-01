-- entities/item/types/large_potion.lua
-- Large health potion configuration

local large_potion = {
    name = "Large Health Potion",
    description = "Restores 60 HP",
    max_stack = 10,
    heal_amount = 60
}

function large_potion.use(player)
    if player.health >= player.max_health then
        return false
    end

    local old_health = player.health
    player.health = math.min(player.max_health, player.health + large_potion.heal_amount)

    local healed = player.health - old_health
    print(string.format("Used Large Potion! Healed %d HP", healed))

    -- Play heal sound effect if available
    local sound = require("systems.sound")
    if sound.playEffect then
        sound:playEffect("heal")
    end

    return true
end

function large_potion.canUse(player)
    return player.health < player.max_health
end

return large_potion
