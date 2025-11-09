-- engine/entities/base/entity.lua
-- Base entity class for common initialization patterns

local anim8 = require "vendor.anim8"

local entity_base = {}

-- Initialize collider properties
function entity_base.initializeCollider(instance, config)
    instance.collider_width = config.collider_width or 32
    instance.collider_height = config.collider_height or 32
    instance.collider_offset_x = config.collider_offset_x or 0
    instance.collider_offset_y = config.collider_offset_y or 0

    -- Legacy width/height (some code still uses these)
    instance.width = instance.collider_width
    instance.height = instance.collider_height
end

-- Initialize sprite properties
function entity_base.initializeSprite(instance, config)
    instance.sprite_width = config.sprite_width or 16
    instance.sprite_height = config.sprite_height or 32
    instance.sprite_scale = config.sprite_scale or 4

    -- Calculate draw offsets (centered by default)
    local default_offset_x = -(instance.sprite_width * instance.sprite_scale - instance.collider_width) / 2
    local default_offset_y = -(instance.sprite_height * instance.sprite_scale - instance.collider_height)

    instance.sprite_draw_offset_x = config.sprite_draw_offset_x or default_offset_x
    instance.sprite_draw_offset_y = config.sprite_draw_offset_y or default_offset_y

    -- Sprite origin (for rotation, default top-left)
    instance.sprite_origin_x = config.sprite_origin_x or 0
    instance.sprite_origin_y = config.sprite_origin_y or 0
end

-- Create animation grid from sprite sheet
function entity_base.createAnimationGrid(config)
    local sheet = love.graphics.newImage(config.sprite_sheet)
    local grid = anim8.newGrid(
        config.sprite_width or 16,
        config.sprite_height or 32,
        sheet:getWidth(),
        sheet:getHeight()
    )
    return grid, sheet
end

-- Get collider center position
function entity_base:getColliderCenter()
    return self.x + self.collider_offset_x,
           self.y + self.collider_offset_y
end

-- Get sprite draw position
function entity_base:getSpritePosition()
    local cx, cy = self:getColliderCenter()
    return cx + self.sprite_draw_offset_x,
           cy + self.sprite_draw_offset_y
end

-- Get collider bounds (for rendering, debugging)
function entity_base:getColliderBounds()
    local cx, cy = self:getColliderCenter()
    return {
        x = cx,
        y = cy,
        width = self.collider_width,
        height = self.collider_height,
        left = cx - self.collider_width / 2,
        right = cx + self.collider_width / 2,
        top = cy - self.collider_height / 2,
        bottom = cy + self.collider_height / 2
    }
end

return entity_base
