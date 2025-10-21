-- entities/enemy/sound.lua

local sound_sys = require "systems.sound"

local enemy_sound = {}

-- Initialize enemy sounds
function enemy_sound.initialize()
    print("Initializing enemy sounds...")

    -- Create slime movement pool (frequent use)
    sound_sys:createPool("enemy", "slime_move", "assets/sound/enemy/slime_move.wav", 3)

    -- Other enemy sounds already loaded in main system via data/sounds.lua

    print("Enemy sounds initialized")
end

-- Play movement sound with type detection
function enemy_sound.playMove(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.8 + math.random() * 0.4

    if enemy_type:find("slime") then
        sound_sys:playPooled("enemy", "slime_move", pitch, 0.2)
    end
    -- Add other enemy types here as needed
end

-- Play attack sound
function enemy_sound.playAttack(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.9 + math.random() * 0.2

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_attack", pitch, 0.6)
    end
end

-- Play hurt sound
function enemy_sound.playHurt(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.85 + math.random() * 0.3

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_hurt", pitch, 0.7)
    end
end

-- Play death sound
function enemy_sound.playDeath(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.8 + math.random() * 0.4

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_death", pitch, 0.8)
    end
end

-- Play stunned sound
function enemy_sound.playStunned(enemy_type)
    enemy_type = enemy_type or "slime"

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_stunned", 1.0, 0.6)
    end
end

-- Play detection sound
function enemy_sound.playDetect()
    local pitch = 0.95 + math.random() * 0.1
    sound_sys:playSFX("combat", "enemy_detect", pitch, 0.5)
end

return enemy_sound
