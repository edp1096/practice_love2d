-- systems/minimap.lua
-- Minimap system for displaying a small overview of the current map

local minimap = {}
minimap.__index = minimap

function minimap:new()
    local instance = setmetatable({
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
    }, minimap)
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
    love.graphics.clear(0, 0, 0, 1)  -- Clear to black

    -- Save current graphics state
    love.graphics.push()

    -- Apply scale transformation
    love.graphics.scale(self.scale, self.scale)

    -- Draw actual map layers using world's drawLayer method
    self.world:drawLayer("Background_Near")
    self.world:drawLayer("Ground")
    self.world:drawLayer("Trees")

    love.graphics.pop()

    -- Draw portals on top (already scaled)
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

function minimap:draw(screen_width, screen_height, player, enemies, npcs)
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

    -- Draw player as arrow pointing in facing direction
    if player and player.x and player.y then
        love.graphics.setColor(self.player_color)
        local px = x + (player.x * self.scale)
        local py = y + (player.y * self.scale)

        -- Arrow shape
        local arrow_size = 5
        local angle = player.facing_angle or 0

        -- Arrow vertices (pointing right by default)
        local points = {
            arrow_size, 0,      -- tip
            -arrow_size, -arrow_size * 0.6,   -- top back
            -arrow_size * 0.5, 0,  -- middle back
            -arrow_size, arrow_size * 0.6    -- bottom back
        }

        -- Transform and draw arrow
        love.graphics.push()
        love.graphics.translate(px, py)
        love.graphics.rotate(angle)
        love.graphics.polygon("fill", points)
        love.graphics.pop()
    end

    -- Draw border
    love.graphics.setColor(self.border_color)
    love.graphics.setLineWidth(self.border_width)
    love.graphics.rectangle("line", x, y, self.canvas_width, self.canvas_height)
end

return minimap
