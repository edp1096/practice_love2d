-- entities/npc/init.lua
-- Base NPC class: stationary, interactive entities

local anim8 = require "vendor.anim8"
local prompt = require "engine.ui.prompt"
local entity_base = require "engine.entities.base.entity"

local npc = {}
npc.__index = npc

-- Inherit base entity methods
npc.getColliderCenter = entity_base.getColliderCenter
npc.getSpritePosition = entity_base.getSpritePosition
npc.getColliderBounds = entity_base.getColliderBounds

-- Class-level type registry (injected from game)
npc.type_registry = {}

function npc:new(x, y, npc_type, npc_id, config)
    local instance = setmetatable({}, npc)

    -- If no config provided, try loading from type registry
    if not config then
        npc_type = npc_type or "merchant"
        config = self.type_registry[npc_type]

        if not config then
            error("Unknown NPC type: " .. tostring(npc_type) .. " (type registry not initialized?)")
        end
    end

    -- Position
    instance.x = x or 100
    instance.y = y or 100
    instance.type = npc_type or "custom"
    instance.id = npc_id or ("npc_" .. math.random(10000))

    -- Properties from config
    instance.name = config.name
    instance.interaction_range = config.interaction_range or 80
    instance.dialogue = config.dialogue or { "Hello!" }

    -- Initialize collision and sprite properties using base class
    entity_base.initializeCollider(instance, config)
    entity_base.initializeSprite(instance, config)

    -- Animation setup using base class
    instance.grid, instance.spriteSheet = entity_base.createAnimationGrid(config)

    instance.animations = {}
    -- 4-direction idle animations
    instance.animations.idle_down = anim8.newAnimation(instance.grid(config.idle_down or "1-4", config.idle_row_down or 1), 0.2)
    instance.animations.idle_left = anim8.newAnimation(instance.grid(config.idle_left or "1-4", config.idle_row_left or 2), 0.2)
    instance.animations.idle_right = anim8.newAnimation(instance.grid(config.idle_right or "1-4", config.idle_row_right or 3), 0.2)
    instance.animations.idle_up = anim8.newAnimation(instance.grid(config.idle_up or "1-4", config.idle_row_up or 4), 0.2)

    instance.anim = instance.animations.idle_down
    instance.direction = "down"

    -- Interaction state
    instance.can_interact = false

    -- Collider (set by world)
    instance.collider = nil
    instance.width = instance.collider_width
    instance.height = instance.collider_height

    return instance
end

function npc:getColliderBounds()
    return {
        x = self.x + self.collider_offset_x,
        y = self.y + self.collider_offset_y,
        width = self.collider_width,
        height = self.collider_height
    }
end

function npc:update(dt, player_x, player_y)
    self.anim:update(dt)

    -- Check if player is in interaction range (using collider center)
    local collider_center_x, collider_center_y = self:getColliderCenter()
    local dx = player_x - collider_center_x
    local dy = player_y - collider_center_y
    local distance = math.sqrt(dx * dx + dy * dy)

    self.can_interact = (distance < self.interaction_range)

    -- Face the player when in interaction range
    if self.can_interact then
        local abs_dx = math.abs(dx)
        local abs_dy = math.abs(dy)

        local new_direction = self.direction

        if abs_dx > abs_dy then
            -- Horizontal direction dominant
            if dx > 0 then
                new_direction = "right"
            else
                new_direction = "left"
            end
        else
            -- Vertical direction dominant
            if dy > 0 then
                new_direction = "down"
            else
                new_direction = "up"
            end
        end

        -- Update animation if direction changed
        if new_direction ~= self.direction then
            self.direction = new_direction
            self.anim = self.animations["idle_" .. self.direction]
        end
    end

    return 0, 0 -- NPCs don't move
end

function npc:interact()
    return self.dialogue
end

function npc:draw()
    -- Use base class helpers for positions
    local collider_center_x, collider_center_y = self:getColliderCenter()
    local sprite_draw_x, sprite_draw_y = self:getSpritePosition()

    -- Shadow (at bottom of collider)
    local shadow_y = collider_center_y + (self.collider_height / 2) - 2
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", collider_center_x, shadow_y, 28, 8)
    love.graphics.setColor(1, 1, 1, 1)

    -- NPC sprite
    love.graphics.setColor(1, 1, 1, 1)
    self.anim:draw(
        self.spriteSheet,
        sprite_draw_x,
        sprite_draw_y,
        0,
        self.sprite_scale,
        self.sprite_scale,
        0,  -- origin x = 0 (top-left), offset handled by sprite_draw_offset
        0   -- origin y = 0 (top-left), offset handled by sprite_draw_offset
    )

    -- Draw interaction indicator (using collider center)
    if self.can_interact then
        prompt:draw("interact", collider_center_x, collider_center_y, -60)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function npc:drawDebug()
    local collider_center_x, collider_center_y = self:getColliderCenter()

    -- Draw interaction range (using collider center)
    love.graphics.setColor(0, 1, 1, 0.3)
    love.graphics.circle("line", collider_center_x, collider_center_y, self.interaction_range)

    -- Draw collider bounds
    local bounds = self:getColliderBounds()
    love.graphics.setColor(0, 1, 1, 1)
    love.graphics.rectangle("line", bounds.x - (bounds.width / 2), bounds.y - (bounds.height / 2), bounds.width, bounds.height)

    -- Draw name (using collider center)
    text_ui:draw(self.name, collider_center_x - 20, collider_center_y - 70, {0, 1, 1, 1})

    love.graphics.setColor(1, 1, 1, 1)
end

return npc
