-- entities/item/types/large_potion.lua
-- Large health potion configuration

local large_potion = {
    name = "Large Health Potion",
    description = "Restores 60 HP",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 10,
    heal_amount = 60,

    -- Sprite information (single image, not sprite sheet)
    sprite = {
        file = "assets/images/drink1.png",
        x = 0,
        y = 0,
        w = 32,
        h = 32,
        scale = 1
    }
}

function large_potion.use(player)
    if player.health >= player.max_health then
        return false
    end

    player.health = math.min(player.max_health, player.health + large_potion.heal_amount)

    -- Play heal sound effect if available
    local sound = require("engine.core.sound")
    if sound.playEffect then
        sound:playEffect("heal")
    end

    return true
end

function large_potion.canUse(player)
    return player.health < player.max_health
end

return large_potion
