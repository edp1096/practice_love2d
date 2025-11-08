-- engine/effects/screen/init.lua
-- Screen-space effect manager (damage flash, vignette, overlays)

local shaders = require "engine.effects.screen.shaders"
local presets = require "engine.effects.screen.presets"

local screen = {}

screen.active_effects = {}
screen.canvas = nil

-- Initialize screen effects system
function screen:init()
    shaders.init()

    -- Create canvas for screen effects
    local width, height = love.graphics.getDimensions()
    self.canvas = love.graphics.newCanvas(width, height)

    dprint("Screen effects system initialized")
end

-- Add a screen effect
function screen:addEffect(effect)
    -- Set defaults
    effect.time = 0
    effect.priority = effect.priority or 10  -- Higher = more important

    -- Validate effect type
    if effect.type ~= "flash" and effect.type ~= "vignette" and effect.type ~= "overlay" then
        dprint("WARNING: Unknown screen effect type: " .. tostring(effect.type))
        return
    end

    table.insert(self.active_effects, effect)

    -- Sort by priority (higher priority = drawn last = more visible)
    table.sort(self.active_effects, function(a, b)
        return a.priority < b.priority
    end)
end

-- Remove effects by type or all
function screen:clearEffects(effect_type)
    if effect_type then
        for i = #self.active_effects, 1, -1 do
            if self.active_effects[i].type == effect_type then
                table.remove(self.active_effects, i)
            end
        end
    else
        self.active_effects = {}
    end
end

-- Update all active effects
function screen:update(dt)
    for i = #self.active_effects, 1, -1 do
        local effect = self.active_effects[i]

        effect.time = effect.time + dt

        -- Update pulsing effects
        if effect.pulse then
            local pulse_speed = effect.pulse_speed or 1.0
            effect.current_intensity = effect.intensity * (0.5 + 0.5 * math.sin(effect.time * pulse_speed * math.pi))
        else
            -- Update fading effects
            if effect.fade_out then
                local progress = effect.time / effect.duration
                effect.current_intensity = effect.intensity * (1.0 - progress)
            elseif effect.fade_in then
                local progress = math.min(1.0, effect.time / effect.duration)
                effect.current_intensity = effect.intensity * progress
            else
                effect.current_intensity = effect.intensity
            end
        end

        -- Remove expired effects (duration -1 means infinite)
        if effect.duration > 0 and effect.time >= effect.duration then
            table.remove(self.active_effects, i)
        end
    end
end

-- Draw all active effects (call AFTER rendering game scene)
function screen:draw()
    if #self.active_effects == 0 then
        return
    end

    -- Get screen dimensions
    local screen_width, screen_height = love.graphics.getDimensions()

    -- Draw each effect as a full-screen quad
    for _, effect in ipairs(self.active_effects) do
        local intensity = effect.current_intensity or effect.intensity

        if intensity > 0 then
            love.graphics.push()
            love.graphics.origin()

            -- Select appropriate shader
            local shader = nil
            if effect.type == "flash" then
                shader = shaders.flash
                shader:send("flash_color", effect.color)
                shader:send("intensity", intensity)
            elseif effect.type == "vignette" then
                shader = shaders.vignette
                shader:send("vignette_color", effect.color)
                shader:send("intensity", intensity)
                shader:send("radius", effect.radius or 0.7)
            elseif effect.type == "overlay" then
                shader = shaders.overlay
                shader:send("overlay_color", effect.color)
                shader:send("intensity", intensity)
            end

            if shader then
                love.graphics.setShader(shader)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.rectangle("fill", 0, 0, screen_width, screen_height)
                love.graphics.setShader()
            end

            love.graphics.pop()
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Get active effect count (for debugging)
function screen:getCount()
    return #self.active_effects
end

-- Resize screen effects canvas (call on window resize)
function screen:resize(width, height)
    if self.canvas then
        self.canvas:release()
    end
    self.canvas = love.graphics.newCanvas(width, height)
    dprint("Screen effects canvas resized: " .. width .. "x" .. height)
end

-- Attach preset methods
screen.damage = function(self, duration, intensity)
    presets.damage(self, duration, intensity)
end

screen.heal = function(self, duration, intensity)
    presets.heal(self, duration, intensity)
end

screen.poison = function(self, duration)
    presets.poison(self, duration)
end

screen.death = function(self, duration)
    presets.death(self, duration)
end

screen.invincible = function(self, duration)
    presets.invincible(self, duration)
end

screen.low_health = function(self)
    presets.low_health(self)
end

screen.stun = function(self, duration)
    presets.stun(self, duration)
end

screen.teleport = function(self)
    presets.teleport(self)
end

-- Initialize on require
screen:init()

return screen
