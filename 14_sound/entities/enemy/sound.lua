-- entities/enemy/sound.lua
-- Enemy-specific sound effects

local sound_sys = require "systems.sound"

local enemy_sound = {}

function enemy_sound.initialize()
    print("Initializing enemy sounds...")

    -- Load slime sounds
    sound_sys:createPool("enemy", "slime_move", "assets/sound/enemy/slime_move.wav", 3)
    sound_sys:loadSFX("combat", "slime_attack", "assets/sound/enemy/slime_attack.wav")
    sound_sys:loadSFX("combat", "slime_hurt", "assets/sound/enemy/slime_hurt.wav")
    sound_sys:loadSFX("combat", "slime_death", "assets/sound/enemy/slime_death.wav")
    sound_sys:loadSFX("combat", "slime_stunned", "assets/sound/enemy/slime_stunned.wav")
    sound_sys:loadSFX("combat", "enemy_detect", "assets/sound/enemy/detect.wav")

    print("Enemy sounds initialized")
end

function enemy_sound.playMove(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.8 + math.random() * 0.4

    if enemy_type:find("slime") then
        sound_sys:playPooled("enemy", "slime_move", pitch, 0.2)
    end
end

function enemy_sound.playAttack(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.9 + math.random() * 0.2

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_attack", pitch, 0.6)
    end
end

function enemy_sound.playHurt(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.85 + math.random() * 0.3

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_hurt", pitch, 0.7)
    end
end

function enemy_sound.playDeath(enemy_type)
    enemy_type = enemy_type or "slime"

    local pitch = 0.8 + math.random() * 0.4

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_death", pitch, 0.8)
    end
end

function enemy_sound.playStunned(enemy_type)
    enemy_type = enemy_type or "slime"

    if enemy_type:find("slime") then
        sound_sys:playSFX("combat", "slime_stunned", 1.0, 0.6)
    end
end

function enemy_sound.playDetect()
    local pitch = 0.95 + math.random() * 0.1
    sound_sys:playSFX("combat", "enemy_detect", pitch, 0.5)
end

return enemy_sound
