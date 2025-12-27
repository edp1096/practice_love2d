-- systems/minimap.lua
-- Minimap system for displaying a small overview of the current map

-- Module dependencies (loaded once at module load time)
local lighting = require "engine.systems.lighting"
local colors = require "engine.utils.colors"
local parallax = require "engine.systems.parallax"
local constants = require "engine.core.constants"

local minimap = {}
minimap.__index = minimap

-- Helper: Find start position for tiling (extends left/up to cover entire area)
local function getTileStart(offset, size)
    while offset > -size do
        offset = offset - size
    end
    return offset
end

-- Color swap shader for enemy sprites (same as enemy/render.lua)
local color_swap_shader = nil
local outline_shader = nil

local function initialize_shader()
    if not color_swap_shader then
        local shader_code = [[
            uniform vec3 target_color;

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
            uniform vec3 outline_color;
            uniform vec2 stepSize;

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
        size = 126,   -- Minimap size (width and height) - 70% of original 180
        padding = 10, -- Padding from screen edge
        border_width = 2,
        zoom_factor = constants.MINIMAP.ZOOM_FACTOR,
        lighting_brightness = constants.MINIMAP.LIGHTING_BRIGHTNESS,

        -- Colors (from colors.lua)
        bg_color = colors.for_minimap_bg,
        border_color = colors.for_minimap_border,
        player_color = nil, -- Unused (using gradient mesh)
        player_outline_color = colors.for_minimap_player_outline,
        portal_color = colors.for_minimap_portal,

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
    local raw_scale = math.min(scale_x, scale_y) * self.zoom_factor

    -- Round scale to prevent subpixel rendering artifacts
    -- This ensures tiles are rendered at integer pixel positions
    local tile_size = world.map.tilewidth -- assuming square tiles
    self.scale = math.floor(raw_scale * tile_size + 0.5) / tile_size

    -- Calculate actual canvas size based on map aspect ratio
    self.canvas_width = math.floor(self.map_width * self.scale)
    self.canvas_height = math.floor(self.map_height * self.scale)

    -- Create canvas for minimap with actual dimensions
    self.canvas = love.graphics.newCanvas(self.canvas_width, self.canvas_height)
    -- Use nearest filter to prevent interpolation artifacts (grid lines)
    self.canvas:setFilter("nearest", "nearest")
    self.needs_update = true

    self:updateMinimapCanvas()
end

function minimap:updateMinimapCanvas()
    if not self.canvas or not self.world then return end

    -- Save current graphics state
    local prev_canvas = love.graphics.getCanvas()
    local prev_color = { love.graphics.getColor() }
    local prev_blend_mode, prev_blend_alpha = love.graphics.getBlendMode()

    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 1) -- Clear to black

    -- Reset graphics state to avoid lighting effects
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "alphamultiply")

    -- Save current graphics state
    love.graphics.push()

    -- Apply scale transformation
    love.graphics.scale(self.scale, self.scale)

    -- Draw parallax backgrounds FIRST
    if parallax and parallax:isActive() and parallax.layers then
        love.graphics.setColor(1, 1, 1, 0.95) -- High opacity

        for _, layer in ipairs(parallax.layers) do
            if layer and layer.image then
                -- For minimap: scale offset by parallax_factor to show depth
                -- Higher parallax_factor (closer layers) → offset reduced toward center
                -- Lower parallax_factor (distant layers) → offset preserved
                local base_offset_x = (layer.scroll_offset_x or 0) + (layer.offset_x or 0)
                local base_offset_y = (layer.scroll_offset_y or 0) + (layer.offset_y or 0)

                local factor = layer.parallax_factor or 0
                local offset_x = base_offset_x * (1 - factor)
                local offset_y = base_offset_y * (1 - factor)

                -- Draw with tiling if enabled
                if layer.repeat_x or layer.repeat_y then
                    local img_w, img_h = layer.image:getWidth(), layer.image:getHeight()
                    if img_w > 0 and img_h > 0 then
                        local start_x = layer.repeat_x and getTileStart(offset_x, img_w) or offset_x
                        local start_y = layer.repeat_y and getTileStart(offset_y, img_h) or offset_y
                        local end_x = layer.repeat_x and self.map_width or (start_x + img_w)
                        local end_y = layer.repeat_y and self.map_height or (start_y + img_h)

                        local y = start_y
                        while y < end_y do
                            local x = start_x
                            while x < end_x do
                                love.graphics.draw(layer.image, x, y)
                                x = x + img_w
                                if not layer.repeat_x then break end
                            end
                            y = y + img_h
                            if not layer.repeat_y then break end
                        end
                    end
                else
                    love.graphics.draw(layer.image, offset_x, offset_y)
                end
            end
        end

        love.graphics.setColor(1, 1, 1, 1) -- Reset color
    end

    -- Draw actual map layers using world's drawLayer method
    self.world:drawLayer("Background_Near")
    self.world:drawLayer("Ground")
    self.world:drawLayer("GroundDeco")
    self.world:drawLayer("Decos")

    -- Draw portals before pop (inside scale transformation)
    if self.world.transitions then
        colors:apply(self.portal_color)
        for _, transition in ipairs(self.world.transitions) do
            love.graphics.rectangle("fill",
                math.floor(transition.x),
                math.floor(transition.y),
                math.floor(transition.width),
                math.floor(transition.height))
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

-- Helper: Draw NPCs on minimap with outline
local function drawMinimapNPCs(self, x, y, canvas_offset_x, canvas_offset_y, npcs)
    if not npcs then return end

    -- Ensure shader is initialized
    initialize_shader()

    for _, npc in ipairs(npcs) do
        if npc.x and npc.y and npc.spriteSheet and npc.grid then
            -- Use getSpritePosition (same as in-game npc/init.lua:194,206)
            local sprite_x, sprite_y = npc:getSpritePosition()
            local nx = math.floor(x + canvas_offset_x + (sprite_x * self.scale))
            local ny = math.floor(y + canvas_offset_y + (sprite_y * self.scale))

            -- Draw first frame of sprite (1,1)
            -- grid(1,1) returns a table, so get the first element
            local frames = npc.grid(1, 1)
            local quad = frames[1]
            local sprite_scale = self.scale * npc.sprite_scale

            -- Draw green outline using shader
            if outline_shader then
                love.graphics.setShader(outline_shader)
                local w, h = npc.spriteSheet:getDimensions()
                local r, g, b = colors:unpackRGB(colors.for_minimap_npc_outline)
                outline_shader:send("outline_color", { r, g, b })
                outline_shader:send("stepSize", { 1 / w, 1 / h })

                colors:apply(colors.WHITE, 0.85)
                -- Use anim:draw with origin 0,0 (same as in-game npc/init.lua:204-213)
                npc.anim:draw(
                    npc.spriteSheet,
                    nx,
                    ny,
                    0,
                    sprite_scale,
                    sprite_scale,
                    0,
                    0
                )
                love.graphics.setShader()
            end

            -- Draw main sprite using anim:draw (same as in-game)
            colors:apply(colors.WHITE, 0.85)
            npc.anim:draw(
                npc.spriteSheet,
                nx,
                ny,
                0,
                sprite_scale,
                sprite_scale,
                0,
                0
            )
        end
    end
end

-- Helper: Draw enemies on minimap with outline and color swap
local function drawMinimapEnemies(self, x, y, canvas_offset_x, canvas_offset_y, enemies)
    if not enemies then return end

    -- Ensure shader is initialized
    initialize_shader()

    for _, enemy in ipairs(enemies) do
        if enemy.x and enemy.y and enemy.health > 0 and enemy.spriteSheet and enemy.grid then
            -- Use getSpritePosition (same as in-game enemy/render.lua:58,118)
            local sprite_x, sprite_y = enemy:getSpritePosition()
            local ex = math.floor(x + canvas_offset_x + (sprite_x * self.scale))
            local ey = math.floor(y + canvas_offset_y + (sprite_y * self.scale))

            local sprite_scale = self.scale * enemy.sprite_scale

            -- Draw red outline using shader
            if outline_shader then
                love.graphics.setShader(outline_shader)
                local w, h = enemy.spriteSheet:getDimensions()
                local r, g, b = colors:unpackRGB(colors.for_minimap_enemy_outline)
                outline_shader:send("outline_color", { r, g, b })
                outline_shader:send("stepSize", { 1 / w, 1 / h })

                colors:apply(colors.WHITE, 0.85)
                -- Use anim:draw with origin 0,0 (same as in-game enemy/render.lua:118-127)
                enemy.anim:draw(
                    enemy.spriteSheet,
                    ex,
                    ey,
                    nil,
                    sprite_scale,
                    sprite_scale,
                    enemy.sprite_origin_x,
                    enemy.sprite_origin_y
                )
                love.graphics.setShader()
            end

            -- Draw main sprite using anim:draw (same as in-game)
            -- Apply color swap shader if enemy has target_color (e.g., green slime)
            if enemy.target_color and color_swap_shader then
                love.graphics.setShader(color_swap_shader)
                color_swap_shader:send("target_color", enemy.target_color)
            end

            colors:apply(colors.WHITE, 0.85)
            enemy.anim:draw(
                enemy.spriteSheet,
                ex,
                ey,
                nil,
                sprite_scale,
                sprite_scale,
                enemy.sprite_origin_x,
                enemy.sprite_origin_y
            )

            -- Reset shader
            love.graphics.setShader()
        end
    end
end

-- Helper: Draw player arrow on minimap with gradient
local function drawMinimapPlayer(self, x, y, center_x, center_y, player)
    if not player or not player.x or not player.y then return end

    local px = x + center_x
    local py = y + center_y

    -- Arrow shape (shorter length, wider width)
    local arrow_length = 5 * 1.3 * 0.8      -- 4/5 of original length (80%)
    local arrow_width = 5 * 1.3 * 0.6 * 1.3 -- 1.3x wider
    local angle = player.facing_angle or 0

    -- Arrow vertices (pointing right by default)
    local points = {
        arrow_length, 0,             -- tip
        -arrow_length, -arrow_width, -- top back
        -arrow_length * 0.5, 0,      -- middle back
        -arrow_length, arrow_width   -- bottom back
    }

    -- Transform and draw arrow with metallic gradient
    love.graphics.push()
    love.graphics.translate(px, py)
    love.graphics.rotate(angle)

    -- Draw metallic gradient (vertical: bright on top, dark on bottom)
    local r1, g1, b1, a1 = colors:toVertex(colors.for_minimap_player_mid, 0.85)
    local r2, g2, b2, a2 = colors:toVertex(colors.for_minimap_player_bright, 0.85)
    local r3, g3, b3, a3 = colors:toVertex(colors.for_minimap_player_dim, 0.85)
    local r4, g4, b4, a4 = colors:toVertex(colors.for_minimap_player_shadow, 0.85)

    local mesh = love.graphics.newMesh({
        { arrow_length,        0,            0, 0, r1, g1, b1, a1 }, -- tip (mid-tone)
        { -arrow_length,       -arrow_width, 0, 0, r2, g2, b2, a2 }, -- top back (bright highlight)
        { -arrow_length * 0.5, 0,            0, 0, r3, g3, b3, a3 }, -- middle (mid-tone)
        { -arrow_length,       arrow_width,  0, 0, r4, g4, b4, a4 }, -- bottom back (dark shadow)
    }, "fan", "static")
    love.graphics.draw(mesh, 0, 0)

    -- Draw thin outline
    colors:apply(self.player_outline_color, 0.85)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", points)

    love.graphics.pop()
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
        canvas_offset_x = math.floor(center_x - (player.x * self.scale))
        canvas_offset_y = math.floor(center_y - (player.y * self.scale))
    end

    -- Draw background
    colors:apply(self.bg_color)
    love.graphics.rectangle("fill", x, y, display_size, display_size)

    -- Use stencil to clip minimap area (LÖVE 12.0 API - setStencilState)
    love.graphics.setStencilState("replace", "always", 1)
    love.graphics.rectangle("fill", x, y, display_size, display_size)
    love.graphics.setStencilState()

    love.graphics.setStencilState("keep", "greater", 0)

    -- Draw static minimap (walls, portals, etc.) with offset
    colors:apply(colors.WHITE, 0.75)
    love.graphics.draw(self.canvas, math.floor(x + canvas_offset_x), math.floor(y + canvas_offset_y))

    -- Apply lighting effect with multiply blend (brightened for minimap visibility)
    local ambient = lighting.ambient_color or { 1, 1, 1 }

    -- Brighten ambient color for minimap (lerp towards white)
    local brightness = self.lighting_brightness
    local brightened_r = ambient[1] + (1 - ambient[1]) * brightness
    local brightened_g = ambient[2] + (1 - ambient[2]) * brightness
    local brightened_b = ambient[3] + (1 - ambient[3]) * brightness

    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(brightened_r, brightened_g, brightened_b, 1)
    love.graphics.rectangle("fill", x, y, display_size, display_size)
    love.graphics.setBlendMode("alpha")

    -- Draw NPCs, enemies, and player using helper functions
    drawMinimapNPCs(self, x, y, canvas_offset_x, canvas_offset_y, npcs)
    drawMinimapEnemies(self, x, y, canvas_offset_x, canvas_offset_y, enemies)
    drawMinimapPlayer(self, x, y, center_x, center_y, player)

    -- Disable stencil state
    love.graphics.setStencilState()

    -- Draw border
    colors:apply(self.border_color)
    love.graphics.setLineWidth(self.border_width)
    love.graphics.rectangle("line", x, y, display_size, display_size)

    -- Reset graphics state
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return minimap
