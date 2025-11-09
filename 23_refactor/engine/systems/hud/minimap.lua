-- systems/minimap.lua
-- Minimap system for displaying a small overview of the current map

-- Module dependencies (loaded once at module load time)
local lighting = require "engine.systems.lighting"

local minimap = {}
minimap.__index = minimap

-- Configuration constants
local ZOOM_FACTOR = 2                    -- Minimap zoom level (2x = more detail, smaller area)
local MINIMAP_LIGHTING_BRIGHTNESS = 0.2  -- How much to brighten lighting for minimap visibility (0 = full dark, 1 = no lighting)

-- Color swap shader for enemy sprites (same as enemy/render.lua)
local color_swap_shader = nil
local outline_shader = nil

local function initialize_shader()
    if not color_swap_shader then
        local shader_code = [[
            extern vec3 target_color;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 pixel = Texel(texture, texture_coords);

                if (pixel.a > 0.0 && pixel.r > 0.1) {
                    if (pixel.r > pixel.g * 1.5 && pixel.r > pixel.b * 1.5) {
                        float original_brightness = max(max(pixel.r, pixel.g), pixel.b);
                        pixel.rgb = target_color * (original_brightness * 0.8);
                    }
                }

                return pixel * color;
            }
        ]]
        color_swap_shader = love.graphics.newShader(shader_code)
    end

    if not outline_shader then
        local outline_code = [[
            extern vec3 outline_color;
            extern vec2 stepSize;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 pixel = Texel(texture, texture_coords);

                // If pixel is already opaque, return it as-is
                if (pixel.a > 0.1) {
                    return pixel * color;
                }

                // Check neighboring pixels for outline
                float outline = 0.0;
                for (float x = -2.0; x <= 2.0; x += 1.0) {
                    for (float y = -2.0; y <= 2.0; y += 1.0) {
                        if (x != 0.0 || y != 0.0) {
                            vec2 offset = vec2(x, y) * stepSize;
                            float alpha = Texel(texture, texture_coords + offset).a;
                            if (alpha > 0.1) {
                                outline = 1.0;
                            }
                        }
                    }
                }

                if (outline > 0.0) {
                    return vec4(outline_color, 0.8);
                }

                return vec4(0.0);
            }
        ]]
        outline_shader = love.graphics.newShader(outline_code)
    end
end

function minimap:new()
    local instance = setmetatable({
        enabled = true,

        -- Minimap display settings
        size = 126,           -- Minimap size (width and height) - 70% of original 180
        padding = 10,         -- Padding from screen edge
        border_width = 2,
        zoom_factor = ZOOM_FACTOR,
        lighting_brightness = MINIMAP_LIGHTING_BRIGHTNESS,

        -- Colors
        bg_color = { 0, 0, 0, 0.7 },
        border_color = { 0.3, 0.3, 0.3, 0.9 },
        player_color = { 1, 1, 0, 1 },
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

    -- Calculate scale to fit map in minimap size, then apply zoom
    local scale_x = self.size / self.map_width
    local scale_y = self.size / self.map_height
    self.scale = math.min(scale_x, scale_y) * self.zoom_factor

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

    -- Save current graphics state
    local prev_canvas = love.graphics.getCanvas()
    local prev_color = {love.graphics.getColor()}
    local prev_blend_mode, prev_blend_alpha = love.graphics.getBlendMode()

    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 1)  -- Clear to black

    -- Reset graphics state to avoid lighting effects
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "alphamultiply")

    -- Save current graphics state
    love.graphics.push()

    -- Apply scale transformation
    love.graphics.scale(self.scale, self.scale)

    -- Draw actual map layers using world's drawLayer method
    self.world:drawLayer("Background_Near")
    self.world:drawLayer("Ground")
    self.world:drawLayer("Trees")

    -- Draw portals before pop (inside scale transformation)
    if self.world.transitions then
        love.graphics.setColor(self.portal_color)
        for _, transition in ipairs(self.world.transitions) do
            love.graphics.rectangle("fill", transition.x, transition.y, transition.width, transition.height)
        end
    end

    love.graphics.pop()

    -- Restore graphics state
    love.graphics.setColor(prev_color)
    love.graphics.setBlendMode(prev_blend_mode, prev_blend_alpha)

    love.graphics.setCanvas()
    self.needs_update = false
end

function minimap:update(dt)
    -- Could add animations or dynamic updates here
end

function minimap:draw(screen_width, screen_height, player, enemies, npcs)
    if not self.enabled or not self.canvas then return end

    -- Minimap display size is fixed
    local display_size = self.size

    -- Calculate minimap position (top-right corner)
    local x = screen_width - display_size - self.padding
    local y = self.padding

    -- Calculate offset to center player on minimap
    local center_x = display_size / 2
    local center_y = display_size / 2
    local canvas_offset_x = 0
    local canvas_offset_y = 0

    if player and player.x and player.y then
        canvas_offset_x = center_x - (player.x * self.scale)
        canvas_offset_y = center_y - (player.y * self.scale)
    end

    -- Draw background
    love.graphics.setColor(self.bg_color)
    love.graphics.rectangle("fill", x, y, display_size, display_size)

    -- Use stencil to clip minimap area
    local function stencilFunc()
        love.graphics.rectangle("fill", x, y, display_size, display_size)
    end

    love.graphics.stencil(stencilFunc, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    -- Draw static minimap (walls, portals, etc.) with offset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, x + canvas_offset_x, y + canvas_offset_y)

    -- Apply lighting effect with multiply blend (brightened for minimap visibility)
    local ambient = lighting.ambient_color or {1, 1, 1}

    -- Brighten ambient color for minimap (lerp towards white)
    local brightness = self.lighting_brightness
    local brightened_r = ambient[1] + (1 - ambient[1]) * brightness
    local brightened_g = ambient[2] + (1 - ambient[2]) * brightness
    local brightened_b = ambient[3] + (1 - ambient[3]) * brightness

    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(brightened_r, brightened_g, brightened_b, 1)
    love.graphics.rectangle("fill", x, y, display_size, display_size)
    love.graphics.setBlendMode("alpha")

    -- Draw NPCs with offset
    if npcs then
        -- Ensure shader is initialized
        initialize_shader()

        for _, npc in ipairs(npcs) do
            if npc.x and npc.y and npc.spriteSheet and npc.grid then
                local nx = x + canvas_offset_x + (npc.x * self.scale)
                local ny = y + canvas_offset_y + (npc.y * self.scale)

                -- Draw first frame of sprite (1,1)
                -- grid(1,1) returns a table, so get the first element
                local frames = npc.grid(1, 1)
                local quad = frames[1]
                local sprite_scale = self.scale * npc.sprite_scale

                -- Draw green outline using shader
                if outline_shader then
                    love.graphics.setShader(outline_shader)
                    local w, h = npc.spriteSheet:getDimensions()
                    outline_shader:send("outline_color", {0.2, 1, 0.3})
                    outline_shader:send("stepSize", {1/w, 1/h})

                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(
                        npc.spriteSheet,
                        quad,
                        nx,
                        ny,
                        0,
                        sprite_scale,
                        sprite_scale,
                        npc.sprite_width / 2,
                        npc.sprite_height / 2
                    )
                    love.graphics.setShader()
                end

                -- Draw main sprite
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(
                    npc.spriteSheet,
                    quad,
                    nx,
                    ny,
                    0,
                    sprite_scale,
                    sprite_scale,
                    npc.sprite_width / 2,
                    npc.sprite_height / 2
                )
            end
        end
    end

    -- Draw enemies with offset
    if enemies then
        -- Ensure shader is initialized
        initialize_shader()

        for _, enemy in ipairs(enemies) do
            if enemy.x and enemy.y and enemy.health > 0 and enemy.spriteSheet and enemy.grid then
                local ex = x + canvas_offset_x + (enemy.x * self.scale)
                local ey = y + canvas_offset_y + (enemy.y * self.scale)

                -- Draw first frame of sprite (1,1)
                -- grid(1,1) returns a table, so get the first element
                local frames = enemy.grid(1, 1)
                local quad = frames[1]
                local sprite_scale = self.scale * enemy.sprite_scale

                -- Draw red outline using shader
                if outline_shader then
                    love.graphics.setShader(outline_shader)
                    local w, h = enemy.spriteSheet:getDimensions()
                    outline_shader:send("outline_color", {1, 0.2, 0.2})
                    outline_shader:send("stepSize", {1/w, 1/h})

                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(
                        enemy.spriteSheet,
                        quad,
                        ex,
                        ey,
                        0,
                        sprite_scale,
                        sprite_scale,
                        enemy.sprite_width / 2,
                        enemy.sprite_height / 2
                    )
                    love.graphics.setShader()
                end

                -- Draw main sprite
                -- Apply color swap shader if enemy has target_color (e.g., green slime)
                if enemy.target_color and color_swap_shader then
                    love.graphics.setShader(color_swap_shader)
                    color_swap_shader:send("target_color", enemy.target_color)
                end

                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(
                    enemy.spriteSheet,
                    quad,
                    ex,
                    ey,
                    0,
                    sprite_scale,
                    sprite_scale,
                    enemy.sprite_width / 2,
                    enemy.sprite_height / 2
                )

                -- Reset shader
                love.graphics.setShader()
            end
        end
    end

    -- Draw player as arrow at center
    if player and player.x and player.y then
        love.graphics.setColor(self.player_color)
        local px = x + center_x
        local py = y + center_y

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

    -- Disable stencil test
    love.graphics.setStencilTest()

    -- Draw border
    love.graphics.setColor(self.border_color)
    love.graphics.setLineWidth(self.border_width)
    love.graphics.rectangle("line", x, y, display_size, display_size)
end

return minimap
