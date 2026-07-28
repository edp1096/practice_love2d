-- entities/enemy/sound.lua

local sound_sys = require "engine.core.sound"

local enemy_sound = {}

-- Sound configuration (injected from game)
enemy_sound.sounds_config = {}

-- Helper function to extract base enemy type for sound lookup
-- e.g., "red_slime" or "green_slime" → "slime"
local function getBaseSoundType(enemy_type)
    if not enemy_type then return nil end

    -- Check each sound type pattern in config
    local enemy_sounds = enemy_sound.sounds_config.enemy_sounds
    if not enemy_sounds then return nil end

    for base_type, _ in pairs(enemy_sounds) do
        if enemy_type:find(base_type) then
            return base_type
        end
    end

    return nil
end

function enemy_sound.initialize()
    -- Initialize all enemy sound pools from config
    local pools = enemy_sound.sounds_config.pools and enemy_sound.sounds_config.pools.enemy
    if not pools then return end

    for pool_name, pool_config in pairs(pools) do
        sound_sys:createPool("enemy", pool_name, pool_config.path, pool_config.size, pool_config.pitch_variation)
    end
end

-- All sounds now use automatic pitch variation from config
function enemy_sound.playMove(enemy_type)
    if not enemy_type then return end

    local base_type = getBaseSoundType(enemy_type)
    if not base_type then return end

    local sound_map = enemy_sound.sounds_config.enemy_sounds[base_type]
    if sound_map and sound_map.move then
        sound_sys:playPooled("enemy", sound_map.move)
    end
end

function enemy_sound.playAttack(enemy_type)
    if not enemy_type then return end

    local base_type = getBaseSoundType(enemy_type)
    if not base_type then return end

    local sound_map = enemy_sound.sounds_config.enemy_sounds[base_type]
    if sound_map and sound_map.attack then
        sound_sys:playSFX("combat", sound_map.attack)
    end
end

function enemy_sound.playHurt(enemy_type)
    if not enemy_type then return end

    local base_type = getBaseSoundType(enemy_type)
    if not base_type then return end

    local sound_map = enemy_sound.sounds_config.enemy_sounds[base_type]
    if sound_map and sound_map.hurt then
        sound_sys:playSFX("combat", sound_map.hurt)
    end
end

function enemy_sound.playDeath(enemy_type)
    if not enemy_type then return end

    local base_type = getBaseSoundType(enemy_type)
    if not base_type then return end

    local sound_map = enemy_sound.sounds_config.enemy_sounds[base_type]
    if sound_map and sound_map.death then
        sound_sys:playSFX("combat", sound_map.death)
    end
end

function enemy_sound.playStunned(enemy_type)
    if not enemy_type then return end

    local base_type = getBaseSoundType(enemy_type)
    if not base_type then return end

    local sound_map = enemy_sound.sounds_config.enemy_sounds[base_type]
    if sound_map and sound_map.stunned then
        sound_sys:playSFX("combat", sound_map.stunned)
    end
end

function enemy_sound.playDetect() sound_sys:playSFX("combat", "enemy_detect") end

return enemy_sound
