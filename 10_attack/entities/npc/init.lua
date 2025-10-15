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
    instance.dialogue = config.dialogue or {"Hello!"}

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
    instance.animations.idle = anim8.newAnimation(instance.grid(config.idle_frames or "1-1", 1), 0.5)
    instance.anim = instance.animations.idle
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

    return 0, 0 -- NPCs don't move
end

function npc:interact()
    print("Interacting with " .. self.name .. " (id=" .. self.id .. ")")
    -- TODO: Trigger dialogue system here
    return self.dialogue
end

function npc:draw()
    local draw_x = self.x + self.sprite_draw_offset_x
    local draw_y = self.y + self.sprite_draw_offset_y

    love.graphics.setColor(1, 1, 1, 1)
    self.anim:draw(
        self.spriteSheet,
        draw_x,
        draw_y,
        0,
        self.sprite_scale,
        self.sprite_scale
    )

    -- Draw interaction indicator
    if self.can_interact then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.circle("line", self.x, self.y - 50, 20)
        love.graphics.print("F", self.x - 5, self.y - 55)
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
