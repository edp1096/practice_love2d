-- game/data/entity_types.lua
-- Centralized entity type definitions for all game entities
-- Engine uses this data via dependency injection (no engine -> game imports)
--
-- ========================================
-- COORDINATE SYSTEM GUIDE
-- ========================================
--
-- Entity positioning uses three offset fields:
--
-- 1. collider_offset_x/y
--    Offset from Tiled object position (top-left) → Collider center
--    Usually (0, 0) to place collider at Tiled object position
--
-- 2. sprite_draw_offset_x/y
--    Offset from Collider center → Sprite draw position
--    Usually negative to center large sprite on small collider
--    Auto-calculated if omitted: -(sprite_size*scale - collider_size)/2
--
-- 3. sprite_origin_x/y
--    Pivot point within sprite image (for rotation)
--    (0, 0) = top-left corner
--    (sprite_width/2, sprite_height/2) = center
--
-- TIP: Use Hand Marking tool to find correct values:
--   F1 (debug) → H (hand marking) → PgUp/PgDn (navigate frames) → P (mark position)
--
-- For detailed explanation, see: docs/GUIDE.md "Entity Coordinate System"
-- ========================================

local humans = require "game.data.entities.humans"
local monsters = require "game.data.entities.monsters"

local entity_types = {}

-- Enemy type definitions (flatten nested structure for backward compatibility)
entity_types.enemies = {
    -- Monsters
    red_slime = monsters.slimes.red_slime,
    green_slime = monsters.slimes.green_slime,
    blue_slime = monsters.slimes.blue_slime,
    purple_slime = monsters.slimes.purple_slime,

    -- Hostile humans
    bandit = humans.bandits.bandit,
    rogue = humans.bandits.rogue,
    warrior = humans.bandits.warrior,
    guard = humans.bandits.guard,

    -- Erratic (unpredictable behavior: NPC → Enemy)
    deceiver = humans.erratic.enemies.deceiver,
}

-- NPC type definitions
entity_types.npcs = {
    -- Common NPCs
    merchant = humans.common.merchant,
    guard = humans.common.guard,
    villager = humans.common.villager,
    elder = humans.common.elder,

    -- Erratic (unpredictable behavior: Enemy → NPC or NPC → Enemy)
    surrendered_bandit = humans.erratic.npcs.surrendered_bandit,
    deceiver = humans.erratic.npcs.deceiver,
}

-- Weapon type definitions
entity_types.weapons = {
    sword = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 0,
        sprite_y = 0,
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.3,
        swing_radius = 35,

        damage = 25,
        range = 80,
        knockback = 100,

        hit_start = 0.3,
        hit_end = 0.7
    },

    axe = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 0,    -- 1x11: Row 1 (y coordinate)
        sprite_y = 160,  -- 1x11: Column 11 (x coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.4,
        swing_radius = 40,

        damage = 35,
        range = 85,
        knockback = 150,

        hit_start = 0.35,
        hit_end = 0.75
    },

    club = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 48,   -- 4x11: Row 4 (y coordinate)
        sprite_y = 160,  -- 4x11: Column 11 (x coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.25,  -- Fast attack
        swing_radius = 30,

        damage = 20,  -- Lower damage
        range = 75,
        knockback = 80,

        hit_start = 0.25,
        hit_end = 0.65
    },

    staff = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 288,  -- 19x1: Column 19 (x coordinate)
        sprite_y = 0,    -- 19x1: Row 1 (y coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.2,  -- Very fast attack
        swing_radius = 25,      -- Short swing radius

        damage = 15,      -- Low damage
        range = 100,      -- Long reach
        knockback = 60,   -- Weak knockback

        hit_start = 0.2,
        hit_end = 0.6
    }
}

-- Weapon effects (shared across all weapon types)
entity_types.weapon_effects = {
    slash_sprite = "assets/images/sprites/effects/effect-slash.png"
}

return entity_types
