-- systems/world/rendering.lua
-- Contains drawing and rendering functions

local effects = require "systems.effects"

local rendering = {}

function rendering.draw(self)
    self.map:draw()
end

function rendering.drawLayer(self, layer_name)
    local layer = self.map.layers[layer_name]
    if not layer then return end

    self.map:drawLayer(layer)
end

function rendering.drawEntitiesYSorted(self, player)
    local drawables = {}

    -- Collect all entities
    table.insert(drawables, player)

    for _, enemy in ipairs(self.enemies) do
        table.insert(drawables, enemy)
    end

    for _, npc in ipairs(self.npcs) do
        table.insert(drawables, npc)
    end

    -- Sort by Y coordinate (foot position for accurate depth)
    table.sort(drawables, function(a, b)
        local a_y = a.y
        local b_y = b.y

        -- Use foot position if collider info is available
        if a.collider_offset_y and a.collider_height then
            a_y = a_y + a.collider_offset_y + a.collider_height / 2
        end
        if b.collider_offset_y and b.collider_height then
            b_y = b_y + b.collider_offset_y + b.collider_height / 2
        end

        return a_y < b_y
    end)

    -- Draw in sorted order
    for _, entity in ipairs(drawables) do
        if entity == player then
            entity:drawAll()
        else
            entity:draw()
        end
    end
end

function rendering.drawSavePoints(self)
    for _, savepoint in ipairs(self.savepoints) do
        if savepoint.can_interact then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.circle("line", savepoint.center_x, savepoint.center_y - 30, 20)
            love.graphics.print("F", savepoint.center_x - 5, savepoint.center_y - 35)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function rendering.drawHealingPoints(self)
    for _, hp in ipairs(self.healing_points) do
        hp:draw()
    end
end

function rendering.drawHealingPointsDebug(self)
    for _, hp in ipairs(self.healing_points) do
        hp:drawDebug()
    end
end

function rendering.drawDebug(self)
    if not self.physicsWorld then return end
    local success, err = pcall(function() self.physicsWorld:draw() end)
    if not success then return end

    if self.transitions then
        for _, transition in ipairs(self.transitions) do
            if transition.transition_type == "gameclear" then
                love.graphics.setColor(1, 1, 0, 0.3)
            else
                love.graphics.setColor(0, 1, 0, 0.3)
            end
            love.graphics.rectangle("fill", transition.x, transition.y, transition.width, transition.height)

            if transition.transition_type == "gameclear" then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(0, 1, 0, 1)
            end
            love.graphics.rectangle("line", transition.x, transition.y, transition.width, transition.height)
        end
    end

    if self.savepoints then
        for _, savepoint in ipairs(self.savepoints) do
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.rectangle("fill", savepoint.x, savepoint.y, savepoint.width, savepoint.height)
            love.graphics.setColor(0, 0.5, 1, 1)
            love.graphics.rectangle("line", savepoint.x, savepoint.y, savepoint.width, savepoint.height)
            love.graphics.print("SAVE", savepoint.x + 5, savepoint.y + 5)

            love.graphics.setColor(0, 1, 1, 0.3)
            love.graphics.circle("line", savepoint.center_x, savepoint.center_y, savepoint.interaction_range)
        end
    end

    if self.npcs then
        for _, npc in ipairs(self.npcs) do
            if npc and npc.drawDebug then npc:drawDebug() end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return rendering
