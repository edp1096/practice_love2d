-- entities/item/types/small_potion.lua
-- Small health potion configuration

local small_potion = {
    name = "Small Health Potion",
    description = "Restores 30 HP",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 20,
    heal_amount = 30,

    -- UI color (for inventory/HUD display)
    color = {0.5, 1, 0.5, 1},  -- Light green

    -- Sprite information (single image, not sprite sheet)
    sprite = {
        file = "assets/images/energy-red.png",
        x = 0,
        y = 0,
        w = 32,
        h = 32,
        scale = 1
    }
}

function small_potion.use(player)
    if player.health >= player.max_health then
        return false
    end

    player.health = math.min(player.max_health, player.health + small_potion.heal_amount)

    -- Play heal sound effect if available
    local sound = require("engine.core.sound")
    if sound.playEffect then
        sound:playEffect("heal")
    end

    return true
end

function small_potion.canUse(player)
    return player.health < player.max_health
end

return small_potion
