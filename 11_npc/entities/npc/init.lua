-- entities/npc/init.lua
-- Base NPC class: stationary, interactive entities

local anim8 = require "vendor.anim8"
local npc_types = require "entities.npc.types.villager"

local npc = {}
npc.__index = npc

function npc:new(x, y, npc_type, npc_id)
    local instance = setmetatable({}, npc)

    npc_type = npc_type or "merchant"
    local config = npc_types.NPC_TYPES[npc_type]

    if not config then
        error("Unknown NPC type: " .. tostring(npc_type))
    end

    -- Position
    instance.x = x or 100
    instance.y = y or 100
    instance.type = npc_type
    instance.id = npc_id or "npc_" .. math.random(10000)

    print("Creating NPC: " .. npc_type .. " at (" .. x .. ", " .. y .. ") id=" .. instance.id)

    -- Properties from config
    instance.name = config.name
    instance.interaction_range = config.interaction_range or 80
    instance.dialogue = config.dialogue or { "Hello!" }

    -- Collision properties
    instance.collider_width = config.collider_width or 32
    instance.collider_height = config.collider_height or 32
    instance.collider_offset_x = config.collider_offset_x or 0
    instance.collider_offset_y = config.collider_offset_y or 0

    -- Sprite properties
    instance.sprite_width = config.sprite_width or 16
    instance.sprite_height = config.sprite_height or 32
    instance.sprite_scale = config.sprite_scale or 4
    instance.sprite_draw_offset_x = config.sprite_draw_offset_x or (-(instance.sprite_width * instance.sprite_scale / 2))
    instance.sprite_draw_offset_y = config.sprite_draw_offset_y or (-(instance.sprite_height * instance.sprite_scale))

    -- Animation setup
    instance.spriteSheet = love.graphics.newImage(config.sprite_sheet)
    instance.grid = anim8.newGrid(
        instance.sprite_width,
        instance.sprite_height,
        instance.spriteSheet:getWidth(),
        instance.spriteSheet:getHeight()
    )

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

    -- Check if player is in interaction range
    local dx = player_x - self.x
    local dy = player_y - self.y
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
    print("Interacting with " .. self.name .. " (id=" .. self.id .. ")")
    -- TODO: Trigger dialogue system here
    return self.dialogue
end

function npc:draw()
    local draw_x = self.x
    local draw_y = self.y

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", draw_x, draw_y + 50, 28, 8)
    love.graphics.setColor(1, 1, 1, 1)

    -- NPC sprite
    love.graphics.setColor(1, 1, 1, 1)
    self.anim:draw(
        self.spriteSheet,
        draw_x,
        draw_y,
        0,
        self.sprite_scale,
        self.sprite_scale,
        24,
        24
    )

    -- Draw interaction indicator
    if self.can_interact then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.circle("line", self.x, self.y - 60, 20)
        love.graphics.print("F", self.x - 5, self.y - 65)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function npc:drawDebug()
    -- Draw interaction range
    love.graphics.setColor(0, 1, 1, 0.3)
    love.graphics.circle("line", self.x, self.y, self.interaction_range)

    -- Draw collider bounds
    local bounds = self:getColliderBounds()
    love.graphics.setColor(0, 1, 1, 1)
    love.graphics.rectangle("line", bounds.x, bounds.y, bounds.width, bounds.height)

    -- Draw name
    love.graphics.setColor(0, 1, 1, 1)
    love.graphics.print(self.name, self.x - 20, self.y - 70)

    love.graphics.setColor(1, 1, 1, 1)
end

return npc
