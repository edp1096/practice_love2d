-- engine/systems/hud/vehicles.lua
-- HUD display for owned vehicles

local entity_registry = require "engine.core.entity_registry"
local display = require "engine.core.display"
local vehicle_summon = require "engine.systems.vehicle_summon"

local vehicles_hud = {}

-- Draw owned vehicles indicator
function vehicles_hud:draw()
    -- Don't show HUD if summoning is disabled
    if not vehicle_summon.settings or not vehicle_summon.settings.allow_summon then
        return
    end

    local owned = entity_registry:getOwnedVehicles()
    if #owned == 0 then return end

    local vw, vh = display:GetVirtualDimensions()

    -- Position: bottom-left, above quickslots
    local x = 20
    local y = vh - 100

    -- Background box
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - 5, y - 5, 120, 50, 5, 5)

    -- Title
    love.graphics.setColor(0.5, 1, 0.5, 1)
    love.graphics.print("Vehicles [V]", x, y)

    -- Vehicle list (just show count if many)
    love.graphics.setColor(1, 1, 1, 1)
    if #owned <= 2 then
        love.graphics.print(table.concat(owned, ", "), x, y + 20)
    else
        love.graphics.print(#owned .. " owned", x, y + 20)
    end

    -- Show if summoned
    local summoned = entity_registry:getSummonedVehicle()
    if summoned then
        love.graphics.setColor(0.5, 1, 1, 1)
        love.graphics.print("* " .. summoned.type, x + 60, y + 20)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return vehicles_hud
