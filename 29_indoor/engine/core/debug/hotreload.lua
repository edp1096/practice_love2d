-- engine/core/debug/hotreload.lua
-- Hot reload functionality for debug mode

local hotreload = {}

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
