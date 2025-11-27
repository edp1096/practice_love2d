-- systems/world/rendering.lua
-- Contains drawing and rendering functions

local effects = require "engine.systems.effects"
local prompt = require "engine.systems.prompt"
local text_ui = require "engine.utils.text"

local rendering = {}

-- Helper: Calculate Y position for sorting (foot bottom edge)
local function getEntitySortY(entity, game_mode)
    local y = entity.y

    -- Check if foot_collider exists and is valid
    if game_mode == "topdown" and entity.foot_collider and entity.foot_collider.body then
        -- Use foot_collider bottom edge
        local foot_height
        if entity.is_humanoid ~= nil then
            -- Enemy
            foot_height = entity.is_humanoid and (entity.collider_height * 0.125) or (entity.collider_height * 0.6)
        else
            -- Player (18.75% height)
            -- foot_height = entity.collider_height * 0.1875
            foot_height = entity.collider_height * 0.26
        end
        y = entity.foot_collider:getY() + foot_height / 2
    elseif entity.collider_offset_y and entity.collider_height then
        -- Fallback: collider bottom
        y = y + entity.collider_offset_y + entity.collider_height
    elseif entity.collider_height then
        -- Simple collider
        y = y + entity.collider_height / 2
    end

    return y
end

function rendering.draw(self)
    self.map:draw()
end

-- Draw parallax backgrounds
-- camera: camera object (optional, can pass nil)
-- display: display system for virtual coordinate transform
function rendering.drawParallax(self, camera, display)
    local parallax = require "engine.systems.parallax"
    if parallax:isActive() then
        parallax:draw(camera, display)
    end
end

function rendering.drawLayer(self, layer_name)
    local layer = self.map.layers[layer_name]
    if not layer then return end

    self.map:drawLayer(layer)
end

function rendering.drawEntitiesYSorted(self, player)
    -- Draw stair tiles FIRST (always behind all entities)
    -- This prevents stairs from occluding the player
    if self.stair_tiles then
        for _, tile in ipairs(self.stair_tiles) do
            tile:draw()
        end
    end

    local drawables = {}

    -- Collect all entities
    table.insert(drawables, player)

    for _, enemy in ipairs(self.enemies) do
        table.insert(drawables, enemy)
    end

    for _, npc in ipairs(self.npcs) do
        table.insert(drawables, npc)
    end

    -- Add world items for Y-sorting
    for _, item in ipairs(self.world_items) do
        table.insert(drawables, item)
    end

    -- Include drawable walls for Y-sorting (topdown mode only)
    if self.drawable_walls then
        for _, wall in ipairs(self.drawable_walls) do
            table.insert(drawables, wall)
        end
    end

    -- Include drawable tiles (Decos layer) for Y-sorting (topdown mode only)
    -- Note: stair_tiles are excluded and drawn above
    if self.drawable_tiles then
        for _, tile in ipairs(self.drawable_tiles) do
            table.insert(drawables, tile)
        end
    end

    -- Sort by Y coordinate (foot position for accurate depth)
    table.sort(drawables, function(a, b)
        return getEntitySortY(a, self.game_mode) < getEntitySortY(b, self.game_mode)
    end)

    -- Draw in sorted order
    for _, entity in ipairs(drawables) do
        if entity == player then
            entity:drawAll()
        elseif entity.draw then
            entity:draw()
        end
    end
end

function rendering.drawSavePoints(self)
    for _, savepoint in ipairs(self.savepoints) do
        if savepoint.can_interact then
            prompt:draw("interact", savepoint.center_x, savepoint.center_y, -30)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function rendering.drawHealingPoints(self)
    for _, hp in ipairs(self.healing_points) do
        hp:draw()
    end
end

-- Draw world item prompts only (items are drawn in drawEntitiesYSorted for proper Y-sorting)
function rendering.drawWorldItemPrompts(self, player_x, player_y, game_mode)
    -- Draw pickup prompts for nearby items
    for _, item in ipairs(self.world_items) do
        if item:canPickup(player_x, player_y, game_mode) then
            -- Show pickup prompt above item
            prompt:draw("interact", item.x, item.y, -40)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function rendering.drawHealingPointsDebug(self)
    for _, hp in ipairs(self.healing_points) do
        hp:drawDebug()
    end
end

function rendering.drawDebug(self)
    local debug = require "engine.core.debug"

    -- F2: Draw physics grid (blue lines) only if show_colliders is enabled
    if debug.show_colliders and self.physicsWorld then
        local success, err = pcall(function() self.physicsWorld:draw() end)
        if not success then return end
    end

    -- F2: Draw stairs debug (visible with physics grid for easy testing)
    if debug.show_colliders and self.stairs and #self.stairs > 0 then
        for _, stair in ipairs(self.stairs) do
            love.graphics.setColor(1, 0.5, 0, 0.3)  -- Orange fill

            if stair.shape == "polygon" and stair.polygon then
                -- Draw polygon
                local vertices = {}
                for _, p in ipairs(stair.polygon) do
                    table.insert(vertices, p.x)
                    table.insert(vertices, p.y)
                end
                if #vertices >= 6 then  -- At least 3 points
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(1, 0.5, 0, 1)
                    love.graphics.polygon("line", vertices)
                end

                -- Draw hill direction arrow at center of bounds
                local b = stair.bounds
                local cx = (b.min_x + b.max_x) / 2
                local cy = (b.min_y + b.max_y) / 2
                local arrow_len = 20
                local dx, dy = 0, 0
                if stair.hill_direction == "left" then dx = -arrow_len
                elseif stair.hill_direction == "right" then dx = arrow_len
                elseif stair.hill_direction == "up" then dy = -arrow_len
                elseif stair.hill_direction == "down" then dy = arrow_len
                end
                love.graphics.setColor(1, 1, 0, 1)  -- Yellow arrow
                love.graphics.setLineWidth(3)
                love.graphics.line(cx, cy, cx + dx, cy + dy)
                -- Arrowhead
                love.graphics.circle("fill", cx + dx, cy + dy, 5)
                love.graphics.setLineWidth(1)

                text_ui:draw(stair.hill_direction or "auto", b.min_x + 2, b.min_y + 2, {1, 0.5, 0, 1})
            else
                -- Draw rectangle
                love.graphics.rectangle("fill", stair.x, stair.y, stair.width, stair.height)
                love.graphics.setColor(1, 0.5, 0, 1)
                love.graphics.rectangle("line", stair.x, stair.y, stair.width, stair.height)

                -- Draw hill direction arrow
                local cx, cy = stair.x + stair.width / 2, stair.y + stair.height / 2
                local arrow_len = 15
                local dx, dy = 0, 0
                if stair.hill_direction == "left" then dx = -arrow_len
                elseif stair.hill_direction == "right" then dx = arrow_len
                elseif stair.hill_direction == "up" then dy = -arrow_len
                elseif stair.hill_direction == "down" then dy = arrow_len
                end
                love.graphics.setColor(1, 1, 0, 1)  -- Yellow arrow
                love.graphics.setLineWidth(2)
                love.graphics.line(cx, cy, cx + dx, cy + dy)
                love.graphics.setLineWidth(1)

                text_ui:draw(stair.hill_direction or "?", stair.x + 2, stair.y + 2, {1, 0.5, 0, 1})
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- F1: Draw hitboxes/collision boxes if debug.show_bounds is enabled
    if not debug.show_bounds then
        return  -- Skip remaining debug drawing if bounds not enabled
    end

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
            text_ui:draw("SAVE", savepoint.x + 5, savepoint.y + 5, {0, 0.5, 1, 1})

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
