-- engine/effects/screen/presets.lua
-- Preset screen effects for common scenarios

local presets = {}

-- Damage flash effect (red flash)
function presets.damage(screen, duration, intensity)
    duration = duration or 0.3
    intensity = intensity or 0.6

    screen:addEffect({
        type = "flash",
        color = {1, 0, 0},  -- Red
        intensity = intensity,
        duration = duration,
        fade_out = true
    })
end

-- Heal flash effect (green flash)
function presets.heal(screen, duration, intensity)
    duration = duration or 0.4
    intensity = intensity or 0.5

    screen:addEffect({
        type = "flash",
        color = {0, 1, 0.3},  -- Green
        intensity = intensity,
        duration = duration,
        fade_out = true
    })
end

-- Poison vignette effect (green edges)
function presets.poison(screen, duration)
    duration = duration or 5.0

    screen:addEffect({
        type = "vignette",
        color = {0.3, 1, 0.3},  -- Green
        intensity = 0.4,
        radius = 0.7,
        duration = duration,
        pulse = true,
        pulse_speed = 2.0
    })
end

-- Death vignette effect (red edges, gradually increasing)
function presets.death(screen, duration)
    duration = duration or 2.0

    screen:addEffect({
        type = "vignette",
        color = {0.5, 0, 0},  -- Dark red
        intensity = 0.8,
        radius = 0.5,
        duration = duration,
        fade_in = true
    })
end

-- Invincibility pulse effect (white pulse)
function presets.invincible(screen, duration)
    duration = duration or 2.0

    screen:addEffect({
        type = "flash",
        color = {1, 1, 1},  -- White
        intensity = 0.3,
        duration = duration,
        pulse = true,
        pulse_speed = 8.0
    })
end

-- Low health warning (red vignette pulse)
function presets.low_health(screen)
    -- Continuous effect, remove manually
    screen:addEffect({
        type = "vignette",
        color = {1, 0, 0},  -- Red
        intensity = 0.3,
        radius = 0.8,
        duration = -1,  -- Infinite
        pulse = true,
        pulse_speed = 1.5,
        priority = 1  -- Low priority
    })
end

-- Hit stun effect (white flash + desaturate)
function presets.stun(screen, duration)
    duration = duration or 0.5

    screen:addEffect({
        type = "overlay",
        color = {0.8, 0.8, 0.8},  -- Gray (desaturate)
        intensity = 0.4,
        duration = duration,
        fade_out = true
    })
end

-- Teleport effect (white flash)
function presets.teleport(screen)
    screen:addEffect({
        type = "flash",
        color = {1, 1, 1},  -- White
        intensity = 1.0,
        duration = 0.2,
        fade_out = true
    })
end

return presets
