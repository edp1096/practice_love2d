-- game/data/entities/monsters/slimes.lua
-- Slime monster variants

-- Common slime config (16x32 frame, 16x16 character at bottom)
-- sprite_draw_offset is auto-calculated based on scale
local function slime_config(overrides)
    local scale = overrides.sprite_scale or 2
    local collider_offset_y = overrides.collider_offset_y or 0

    local base = {
        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = scale,
        character_width = 16,
        character_height = 16,
        collider_offset_x = 0,
        collider_offset_y = collider_offset_y,
        -- Auto-calculated: sprite is 16x32, character is bottom 16x16
        -- offset_x: center sprite over collider (sprite_width / 2 * scale)
        -- offset_y: sprite top is (sprite_height - character_height / 2) * scale above collider center
        sprite_draw_offset_x = -8 * scale,                            -- -sprite_width/2 * scale
        sprite_draw_offset_y = -(16 + 8) * scale + collider_offset_y, -- -24 * scale + offset
        sprite_origin_x = 0,
        sprite_origin_y = 0,
        loot_category = "slime",
    }

    for k, v in pairs(overrides) do base[k] = v end
    return base
end

local sprite_path = "assets/images/sprites/enemies/enemy-sheet-slime-red.png"

return {
    red_slime = slime_config({
        sprite_sheet = sprite_path,
        health = 100,
        damage = 10,
        speed = 100,
        attack_cooldown = 1.0,
        detection_range = 180,
        attack_range = 50,
        sprite_scale = 2.5,
    }),

    green_slime = slime_config({
        sprite_sheet = sprite_path,
        health = 80,
        damage = 8,
        speed = 120,
        attack_cooldown = 0.8,
        detection_range = 150,
        attack_range = 50,
        sprite_scale = 3.5,
        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 1.0, 0.0 },
    }),

    blue_slime = slime_config({
        sprite_sheet = sprite_path,
        health = 120,
        damage = 12,
        speed = 80,
        attack_cooldown = 1.2,
        detection_range = 260,
        attack_range = 50,
        sprite_scale = 2,
        collider_offset_y = 5,
        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 0.5, 1.0 },
    }),

    purple_slime = slime_config({
        sprite_sheet = sprite_path,
        health = 150,
        damage = 15,
        speed = 90,
        attack_cooldown = 1.5,
        detection_range = 290,
        attack_range = 60,
        sprite_scale = 2,
        collider_offset_y = 5,
        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.8, 0.0, 1.0 },
    }),
}
