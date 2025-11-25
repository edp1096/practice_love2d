-- engine/core/debug/hotreload.lua
-- Hot reload functionality for debug mode

local hotreload = {}

-- Reload player configuration at runtime
function hotreload.reloadPlayerConfig(player)
    if not player then
        dprint("[F7] No player!")
        return
    end

    dprint("[F7] Reloading player config...")

    -- Clear require cache
    package.loaded["game.data.player"] = nil

    -- Reload config
    local player_config = require "game.data.player"

    -- Update player's config reference
    player.config = player_config

    -- Update stats
    if player_config.stats then
        player.speed = player_config.stats.speed or player.speed
        player.jump_power = player_config.stats.jump_power or player.jump_power
    end

    -- Update animations config (will apply on next animation change)
    if player_config.animations then
        player.default_move = player_config.animations.default_move or "walk"
    end

    dprint(string.format("[F7] ✓ Player reloaded! Speed: %d, Move: %s",
        player.speed, player.default_move or "walk"))
end

-- Reload weapon configuration at runtime
function hotreload.reloadWeaponConfig(player)
    if not player or not player.weapon then
        dprint("[F7] No weapon equipped!")
        return
    end

    local weapon_type = player.weapon.type
    dprint("[F7] Reloading weapon config for: " .. weapon_type)

    -- Clear require cache for entity types
    package.loaded["game.data.entities.types"] = nil

    -- Reload types
    local entity_types = require "game.data.entities.types"

    -- Get weapon class
    local weapon_class = require "engine.entities.weapon"

    -- Update weapon type registry
    weapon_class.type_registry = entity_types.weapons

    -- Get new config
    local new_config = entity_types.weapons[weapon_type]
    if not new_config then
        dprint("[F7] ERROR: Weapon type not found in registry!")
        return
    end

    -- Update weapon's config (preserve scale override)
    local old_scale = player.weapon.config.scale
    player.weapon.config = {}
    for k, v in pairs(new_config) do
        player.weapon.config[k] = v
    end
    player.weapon.config.scale = old_scale

    dprint(string.format("[F7] ✓ Reloaded! New range: %s", player.weapon.config.range))
end

return hotreload
