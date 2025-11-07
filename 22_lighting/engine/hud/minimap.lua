-- systems/minimap.lua
-- Minimap system for displaying a small overview of the current map

local minimap = {}

function minimap:new()
    local instance = {
        enabled = true,

        -- Minimap display settings
        size = 180,           -- Minimap size (width and height)
        padding = 10,         -- Padding from screen edge
        border_width = 2,

        -- Colors
        bg_color = { 0, 0, 0, 0.7 },
        border_color = { 0.3, 0.3, 0.3, 0.9 },
        wall_color = { 0.4, 0.4, 0.4, 1 },
        ground_color = { 0.1, 0.15, 0.2, 1 },
        player_color = { 1, 1, 0, 1 },
        enemy_color = { 1, 0.2, 0.2, 0.8 },
        npc_color = { 0.2, 0.8, 1, 0.8 },
        portal_color = { 0.5, 1, 0.5, 0.6 },

        -- Canvas for rendering minimap
        canvas = nil,
        needs_update = true,

        -- Map data
        map_width = 0,
        map_height = 0,
        scale = 1,
    }

    setmetatable(instance, { __index = minimap })
    return instance
end

function minimap:setMap(world)
    if not world or not world.map then return end

    self.world = world
    self.map_width = world.map.width * world.map.tilewidth
    self.map_height = world.map.height * world.map.tileheight

    -- Calculate scale to fit map in minimap size
    local scale_x = self.size / self.map_width
    local scale_y = self.size / self.map_height
    self.scale = math.min(scale_x, scale_y)

    -- Calculate actual canvas size based on map aspect ratio
    self.canvas_width = math.floor(self.map_width * self.scale)
    self.canvas_height = math.floor(self.map_height * self.scale)

    -- Create canvas for minimap with actual dimensions
    self.canvas = love.graphics.newCanvas(self.canvas_width, self.canvas_height)
    self.needs_update = true

    self:updateMinimapCanvas()
end

function minimap:updateMinimapCanvas()
    if not self.canvas or not self.world then return end

    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(self.ground_color)

    -- Draw walls on minimap
    if self.world.walls then
        love.graphics.setColor(self.wall_color)
        for _, wall in ipairs(self.world.walls) do
            if wall.body then
                -- Draw all fixtures (polygon may be split into multiple triangles)
                local fixtures = wall.body:getFixtures()
                for _, fixture in ipairs(fixtures) do
                    local shape = fixture:getShape()
                    local shape_type = shape:getType()

                    if shape_type == "polygon" or shape_type == "chain" then
                        -- Get polygon points in local coordinates
                        local points = {shape:getPoints()}
                        local scaled_points = {}

                        -- Convert to world coordinates
                        for i = 1, #points, 2 do
                            local wx, wy = wall.body:getWorldPoints(points[i], points[i + 1])
                            table.insert(scaled_points, wx * self.scale)
                            table.insert(scaled_points, wy * self.scale)
                        end

                        if #scaled_points >= 6 then  -- Need at least 3 points (6 coordinates)
                            love.graphics.polygon("fill", scaled_points)
                        end
                    else
                        -- Rectangle or other shapes: use bounding box
                        local x1, y1, x2, y2 = fixture:getBoundingBox()
                        local x = x1 * self.scale
                        local y = y1 * self.scale
                        local w = (x2 - x1) * self.scale
                        local h = (y2 - y1) * self.scale
                        love.graphics.rectangle("fill", x, y, w, h)
                    end
                end
            end
        end
    end

    -- Draw portals on minimap
    if self.world.transitions then
        love.graphics.setColor(self.portal_color)
        for _, transition in ipairs(self.world.transitions) do
            local x = transition.x * self.scale
            local y = transition.y * self.scale
            local w = transition.width * self.scale
            local h = transition.height * self.scale
            love.graphics.rectangle("fill", x, y, w, h)
        end
    end

    love.graphics.setCanvas()
    self.needs_update = false
end

function minimap:update(dt)
    -- Could add animations or dynamic updates here
end

function minimap:draw(screen_width, screen_height, player_x, player_y, enemies, npcs)
    if not self.enabled or not self.canvas then return end

    -- Calculate minimap position (top-right corner)
    local x = screen_width - self.canvas_width - self.padding
    local y = self.padding

    -- Draw background
    love.graphics.setColor(self.bg_color)
    love.graphics.rectangle("fill", x, y, self.canvas_width, self.canvas_height)

    -- Draw static minimap (walls, portals, etc.)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, x, y)

    -- Draw NPCs
    if npcs then
        love.graphics.setColor(self.npc_color)
        for _, npc in ipairs(npcs) do
            if npc.x and npc.y then
                local nx = x + (npc.x * self.scale)
                local ny = y + (npc.y * self.scale)
                love.graphics.circle("fill", nx, ny, 2)
            end
        end
    end

    -- Draw enemies
    if enemies then
        love.graphics.setColor(self.enemy_color)
        for _, enemy in ipairs(enemies) do
            if enemy.x and enemy.y and enemy.health > 0 then
                local ex = x + (enemy.x * self.scale)
                local ey = y + (enemy.y * self.scale)
                love.graphics.circle("fill", ex, ey, 2)
            end
        end
    end

    -- Draw player
    if player_x and player_y then
        love.graphics.setColor(self.player_color)
        local px = x + (player_x * self.scale)
        local py = y + (player_y * self.scale)
        love.graphics.circle("fill", px, py, 3)

        -- Draw direction indicator
        love.graphics.setLineWidth(1)
        love.graphics.line(px, py, px, py - 5)
    end

    -- Draw border
    love.graphics.setColor(self.border_color)
    love.graphics.setLineWidth(self.border_width)
    love.graphics.rectangle("line", x, y, self.canvas_width, self.canvas_height)
end

return minimap
