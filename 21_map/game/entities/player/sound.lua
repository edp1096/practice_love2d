-- entities/player/sound.lua

local sound_sys = require "engine.sound"

local player_sound = {}

player_sound.footstep_timer = 0
player_sound.footstep_interval = 0.4

function player_sound.initialize()
    dprint("Initializing player sounds...")
    sound_sys:createPool("player", "footstep", "assets/sound/player/footstep.wav", 4, "footstep")
    dprint("Player sounds initialized")
end

function player_sound.update(dt, player)
    if not player then return end

    if player.state == "walking" and not player.dodge_active then
        player_sound.footstep_timer = player_sound.footstep_timer + dt

        if player_sound.footstep_timer >= player_sound.footstep_interval then
            player_sound.playFootstep()
            player_sound.footstep_timer = 0
        end
    else
        player_sound.footstep_timer = 0
    end
end

function player_sound.playFootstep() sound_sys:playPooled("player", "footstep") end

-- All combat sounds now use automatic pitch variation from config
function player_sound.playAttack() sound_sys:playSFX("combat", "sword_swing") end

function player_sound.playWeaponHit() sound_sys:playSFX("combat", "sword_hit") end

function player_sound.playParry(is_perfect)
    if is_perfect then
        sound_sys:playSFX("combat", "parry_perfect")
    else
        sound_sys:playSFX("combat", "parry")
    end
end

function player_sound.playDodge() sound_sys:playSFX("combat", "dodge") end

function player_sound.playHurt() sound_sys:playSFX("combat", "player_hurt") end

function player_sound.playWeaponDraw() sound_sys:playSFX("combat", "weapon_draw") end

function player_sound.playWeaponSheath() sound_sys:playSFX("combat", "weapon_sheath") end

function player_sound.playLand() sound_sys:playPooled("player", "footstep", nil, 0.5) end

return player_sound
