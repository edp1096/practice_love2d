-- entities/item/types/apple.lua
-- Apple (small healing fruit)

local apple = {
    name = "Apple",
    description = "Restores 20 HP",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 99,
    heal_amount = 20,

    -- Sprite information for world item (animation)
    sprite = {
        file = "assets/images/apple.png",
        width = 32,
        height = 32,
        frames = 17,  -- Total animation frames
        duration = 0.1,  -- Animation speed (per frame)

        -- Inventory display (first frame only)
        x = 0,  -- First frame column
        y = 0,  -- First row
        w = 32, -- Frame width
        h = 32, -- Frame height
        scale = 1  -- 1:1 scale
    }
}

function apple.use(player)
    if player.health >= player.max_health then
        return false
    end

    player.health = math.min(player.max_health, player.health + apple.heal_amount)

    -- Play heal sound effect if available
    local sound = require("engine.core.sound")
    if sound.playSFX then
        sound:playSFX("item", "eat")
    end

    return true
end

function apple.canUse(player)
    return player.health < player.max_health
end

return apple
