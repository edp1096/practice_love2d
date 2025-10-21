-- entities/player/sound.lua

local sound_sys = require "systems.sound"

local player_sound = {}

-- Footstep timing
player_sound.footstep_timer = 0
player_sound.footstep_interval = 0.4

-- Initialize player sounds
function player_sound.initialize()
    print("Initializing player sounds...")

    -- Create footstep pool (frequent use)
    sound_sys:createPool("player", "footstep", "assets/sound/player/footstep.wav", 4)

    -- Load combat sounds (already loaded in main sound system via data/sounds.lua)
    -- No need to reload here - they're available as combat category

    print("Player sounds initialized")
end

-- Update footstep sounds based on player state
function player_sound.update(dt, player)
    if not player then return end

    -- Automatic footstep sounds during walking
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

-- Play footstep sound with pitch variation
function player_sound.playFootstep()
    local pitch = 0.9 + math.random() * 0.2
    sound_sys:playPooled("player", "footstep", pitch, 0.3)
end

-- Combat sound wrappers (cleaner API)
function player_sound.playAttack()
    local pitch = 0.95 + math.random() * 0.1
    sound_sys:playSFX("combat", "sword_swing", pitch, 0.7)
end

function player_sound.playWeaponHit()
    local pitch = 0.9 + math.random() * 0.2
    sound_sys:playSFX("combat", "sword_hit", pitch, 0.8)
end

function player_sound.playParry(is_perfect)
    if is_perfect then
        sound_sys:playSFX("combat", "parry_perfect", 1.0, 1.0)
    else
        sound_sys:playSFX("combat", "parry", 1.0, 0.9)
    end
end

function player_sound.playDodge()
    local pitch = 0.95 + math.random() * 0.1
    sound_sys:playSFX("combat", "dodge", pitch, 0.6)
end

function player_sound.playHurt()
    local pitch = 0.9 + math.random() * 0.2
    sound_sys:playSFX("combat", "player_hurt", pitch, 0.8)
end

function player_sound.playWeaponDraw()
    sound_sys:playSFX("combat", "weapon_draw", 1.0, 0.5)
end

function player_sound.playWeaponSheath()
    sound_sys:playSFX("combat", "weapon_sheath", 1.0, 0.4)
end

function player_sound.playLand()
    local pitch = 0.8 + math.random() * 0.3
    sound_sys:playPooled("player", "footstep", pitch, 0.5)
end

return player_sound
