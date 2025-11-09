-- entities/enemy/sound.lua

local sound_sys = require "engine.core.sound"

local enemy_sound = {}

-- Sound configuration (injected from game)
enemy_sound.sounds_config = {}

function enemy_sound.initialize()
    local slime_move = enemy_sound.sounds_config.pools.enemy.slime_move
    sound_sys:createPool("enemy", "slime_move", slime_move.path, slime_move.size, slime_move.pitch_variation)
end

-- All sounds now use automatic pitch variation from config
function enemy_sound.playMove(enemy_type)
    enemy_type = enemy_type or "slime"
    if enemy_type:find("slime") then sound_sys:playPooled("enemy", "slime_move") end
end

function enemy_sound.playAttack(enemy_type)
    enemy_type = enemy_type or "slime"
    if enemy_type:find("slime") then sound_sys:playSFX("combat", "slime_attack") end
end

function enemy_sound.playHurt(enemy_type)
    enemy_type = enemy_type or "slime"
    if enemy_type:find("slime") then sound_sys:playSFX("combat", "slime_hurt") end
end

function enemy_sound.playDeath(enemy_type)
    enemy_type = enemy_type or "slime"
    if enemy_type:find("slime") then sound_sys:playSFX("combat", "slime_death") end
end

function enemy_sound.playStunned(enemy_type)
    enemy_type = enemy_type or "slime"
    if enemy_type:find("slime") then sound_sys:playSFX("combat", "slime_stunned") end
end

function enemy_sound.playDetect() sound_sys:playSFX("combat", "enemy_detect") end

return enemy_sound
