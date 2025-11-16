-- engine/effects/particles/presets.lua
-- Preset combinations for common scenarios

local presets = {}

-- Preset combinations for common scenarios
function presets.spawnHitEffect(particles, x, y, target_type, angle)
    if target_type == "enemy" or target_type == "player" then
        particles:spawn("blood", x, y, angle, 35)
        particles:spawn("dust", x, y, nil, 20)
    elseif target_type == "wall" then
        particles:spawn("dust", x, y, nil, 40)
    end
end

function presets.spawnParryEffect(particles, x, y, angle, is_perfect)
    local particle_count = is_perfect and 50 or 35
    particles:spawn("spark", x, y, angle, particle_count)
end

function presets.spawnWeaponTrail(particles, x, y, angle)
    particles:spawn("slash", x, y, angle, 20)
end

-- Test function - spawn effects at position
function presets.test(particles, x, y)
    particles:spawn("blood", x, y - 40, 0, 40)
    particles:spawn("spark", x, y + 40, math.pi / 4, 40)
    particles:spawn("dust", x - 40, y, math.pi / 2, 40)
    particles:spawn("slash", x + 40, y, 0, 40)
end

return presets
