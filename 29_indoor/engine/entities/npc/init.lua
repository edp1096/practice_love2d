-- entities/npc/init.lua
-- Base NPC class: stationary, interactive entities

local anim8 = require "vendor.anim8"
local prompt = require "engine.systems.prompt"
local entity_base = require "engine.entities.base.entity"
local text_ui = require "engine.utils.text"

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

    -- Dialogue: support both old (dialogue array) and new (dialogue_id)
    instance.dialogue = config.dialogue or { "Hello!" }
    instance.dialogue_id = config.dialogue_id  -- Optional: dialogue tree ID

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
    -- Return dialogue_id if available (for tree-based dialogue)
    -- Otherwise return legacy dialogue array
    if self.dialogue_id then
        return { type = "tree", dialogue_id = self.dialogue_id }
    else
        return { type = "simple", messages = self.dialogue }
    end
end

-- Draw quest indicator above NPC (? for completable quests only)
function npc:drawQuestIndicator(center_x, sprite_y)
    local quest_system = require "engine.core.quest"

    -- Check if this NPC has completable quests
    local has_completable = false

    -- Check all quests
    for quest_id, quest_def in pairs(quest_system.quest_registry) do
        local state = quest_system:getState(quest_id)

        -- Check if this NPC receives completed quests
        local receiver = quest_def.receiver_npc or quest_def.giver_npc
        if receiver == self.id and state and state.state == quest_system.STATE.COMPLETED then
            has_completable = true
            break
        end
    end

    -- Draw indicator (? for completable quests only)
    local indicator = nil
    local color = {1, 1, 0, 1}  -- Yellow

    if has_completable then
        indicator = "?"
    end

    if indicator then
        -- Draw indicator above NPC head
        local indicator_y = sprite_y - 5
        local font = love.graphics.newFont(20)
        love.graphics.setFont(font)

        -- Text with outline for visibility
        local text_w = font:getWidth(indicator)
        local text_x = center_x - text_w / 2

        -- Outline (black)
        love.graphics.setColor(0, 0, 0, 1)
        for ox = -1, 1 do
            for oy = -1, 1 do
                if ox ~= 0 or oy ~= 0 then
                    love.graphics.print(indicator, text_x + ox, indicator_y + oy)
                end
            end
        end

        -- Main text (yellow)
        love.graphics.setColor(color)
        love.graphics.print(indicator, text_x, indicator_y)

        love.graphics.setColor(1, 1, 1, 1)
    end
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

    -- Draw quest indicators
    self:drawQuestIndicator(collider_center_x, sprite_draw_y)

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
