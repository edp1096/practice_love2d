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
local vehicles = require "game.data.entities.vehicles"

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
    villager_01 = humans.common.villager_01,
    villager_02 = humans.common.villager_02,
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
        scale = 2,

        attack_duration = 0.3,
        swing_radius = 23,  -- 35 * (2/3) for scale 2

        damage = 25,
        range = 53,  -- 80 * (2/3) for scale 2
        knockback = 100,

        hit_start = 0.3,
        hit_end = 0.7
    },

    axe = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 0,   -- 1x11: Row 1 (y coordinate)
        sprite_y = 160, -- 1x11: Column 11 (x coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 2,

        attack_duration = 0.4,
        swing_radius = 27,  -- 40 * (2/3) for scale 2

        damage = 35,
        range = 57,  -- 85 * (2/3) for scale 2
        knockback = 150,

        hit_start = 0.35,
        hit_end = 0.75
    },

    club = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 48,  -- 4x11: Row 4 (y coordinate)
        sprite_y = 160, -- 4x11: Column 11 (x coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 2,

        attack_duration = 0.25, -- Fast attack
        swing_radius = 20,  -- 30 * (2/3) for scale 2

        damage = 10, -- Lower damage
        range = 50,  -- 75 * (2/3) for scale 2
        knockback = 80,

        hit_start = 0.25,
        hit_end = 0.65
    },

    staff = {
        sprite_file = "assets/images/sprites/weapons/weapon-steel.png",
        sprite_x = 288, -- 19x1: Column 19 (x coordinate)
        sprite_y = 0,   -- 19x1: Row 1 (y coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 2,

        attack_duration = 0.2, -- Very fast attack
        swing_radius = 17,     -- 25 * (2/3) for scale 2

        damage = 5,           -- Low damage
        range = 67,            -- 100 * (2/3) for scale 2 - Long reach
        knockback = 60,        -- Weak knockback

        hit_start = 0.2,
        hit_end = 0.6
    }
}

-- Weapon effects (shared across all weapon types)
local slash_size = 1.4
entity_types.weapon_effects = {
    slash_sprite = "assets/images/sprites/effects/effect-slash.png",

    -- Slash sprite properties (effect-slash.png is 46x39, 2 frames = 23x39 per frame)
    slash_frame_width = 23,
    slash_frame_height = 39,
    slash_sprite_width = 46,   -- Total sprite sheet width
    slash_sprite_height = 39,  -- Total sprite sheet height
    slash_scale = 2,           -- Render scale (matches weapon scale)

    -- Slash origin (pivot point for rotation)
    slash_origin_x = 11.5,     -- Center X of 23px frame
    slash_origin_y = 19.5,     -- Center Y of 39px frame

    -- Sheath particles configuration
    particle_size = 12,              -- Particle image size (12x12)
    particle_sizes = {3, 3.5, 4, 3, 0},  -- Particle size sequence
    particle_speed_min = 30,         -- Minimum particle speed
    particle_speed_max = 80,         -- Maximum particle speed

    -- Optional: Direction-specific transforms for slash effect
    -- If not specified, defaults to flip_x=1, flip_y=1
    slash_transforms = {
        down = { flip_x = slash_size, flip_y = -1 * slash_size },
        up = { flip_x = slash_size, flip_y = -1 * slash_size },
        left = { flip_x = slash_size, flip_y = -1 * slash_size },
        right = { flip_x = slash_size, flip_y = slash_size }
    }
}

-- Vehicle type definitions
entity_types.vehicles = {
    horse = vehicles.horse,
    donkey = vehicles.donkey,
    boat = vehicles.boat,
}

return entity_types
