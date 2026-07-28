-- engine/core/debug/hotreload.lua
-- Hot reload functionality for debug mode
-- Uses dependency injection - config paths set via hotreload.config_paths

local hotreload = {}

-- Config paths (set via dependency injection from game/setup.lua)
hotreload.config_paths = {
    player = nil,         -- e.g., "game.data.player"
    entity_types = nil    -- e.g., "game.data.entities.types"
}

-- Reload player configuration at runtime
function hotreload.reloadPlayerConfig(player)
    if not player then
        dprint("[F7] No player!")
        return
    end

    if not hotreload.config_paths.player then
        dprint("[F7] Player config path not set!")
        return
    end

    dprint("[F7] Reloading player config...")

    -- Clear require cache
    package.loaded[hotreload.config_paths.player] = nil

    -- Reload config
    local player_config = require(hotreload.config_paths.player)

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
function hotreload.reloadWeaponConfig(player, inventory)
    if not player or not player.weapon then
        dprint("[F7] No weapon equipped!")
        return
    end

    if not hotreload.config_paths.entity_types then
        dprint("[F7] Entity types config path not set!")
        return
    end

    local weapon_type = player.weapon.type
    dprint("[F7] Reloading weapon config for: " .. weapon_type)

    -- Clear require cache for entity types
    package.loaded[hotreload.config_paths.entity_types] = nil

    -- Reload types
    local entity_types = require(hotreload.config_paths.entity_types)

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

    -- Update base_stats with new weapon base values
    if player.base_stats then
        player.base_stats.damage = new_config.damage or 0
        player.base_stats.range = new_config.range or 0
        player.base_stats.swing_radius = new_config.swing_radius or 0
    end

    -- Re-apply equipment stats from inventory instance
    if inventory and inventory.equipment_slots then
        local combat = require "engine.entities.player.combat"
        local equipped_weapon = inventory:getEquippedItem("weapon")
        if equipped_weapon and equipped_weapon.stats then
            combat.applyEquipmentStats(player, equipped_weapon.stats)
            dprint(string.format("[F7] ✓ Reloaded! Base dmg: %d + Item bonus: %d = %d",
                new_config.damage or 0,
                equipped_weapon.stats.damage or 0,
                player.weapon.config.damage))
            return
        end
    end

    dprint(string.format("[F7] ✓ Reloaded! Damage: %d, Range: %s",
        player.weapon.config.damage, player.weapon.config.range))
end

return hotreload
