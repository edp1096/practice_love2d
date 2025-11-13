-- entities/world_item/init.lua
-- World item entity (dropped items on the ground)

local anim8 = require "vendor.anim8"
local item_class = require "engine.entities.item"

local world_item = {}
world_item.__index = world_item

-- Counter for unique IDs
local id_counter = 0

function world_item:new(x, y, item_type, quantity, map_id, respawn)
    local instance = setmetatable({}, world_item)

    -- Generate unique ID
    id_counter = id_counter + 1
    instance.id = "world_item_" .. id_counter

    -- Position
    instance.x = x
    instance.y = y

    -- Item data
    instance.item_type = item_type
    instance.quantity = quantity or 1

    -- Persistence data
    instance.map_id = map_id  -- Unique identifier for this item in the map (e.g., "level1_area1_obj_123")
    instance.respawn = (respawn == nil) and true or respawn  -- Default: true (respawns)

    -- Load item configuration from registry
    local item_config = item_class.type_registry[item_type]
    if not item_config then
        error(string.format("Unknown item type: %s (item registry not initialized?)", item_type))
    end
    instance.config = item_config
    instance.name = item_config.name

    -- Sprite and animation
    if item_config.sprite then
        instance.sprite_sheet = love.graphics.newImage(item_config.sprite.file)
        instance.sprite_width = item_config.sprite.w or item_config.sprite.width
        instance.sprite_height = item_config.sprite.h or item_config.sprite.height
        instance.sprite_scale = item_config.sprite.scale or 1

        -- Check if this is an animated sprite (has frames) or static image
        if item_config.sprite.frames then
            -- Animated sprite (like fruits)
            local grid = anim8.newGrid(
                instance.sprite_width,
                instance.sprite_height,
                instance.sprite_sheet:getWidth(),
                instance.sprite_sheet:getHeight()
            )

            -- Create animation
            local frame_range = '1-' .. item_config.sprite.frames
            instance.animation = anim8.newAnimation(
                grid(frame_range, 1),
                item_config.sprite.duration or 0.1
            )
            instance.quad = nil
        else
            -- Static sprite - create quad for specific region
            instance.animation = nil
            instance.quad = love.graphics.newQuad(
                item_config.sprite.x or 0,
                item_config.sprite.y or 0,
                instance.sprite_width,
                instance.sprite_height,
                instance.sprite_sheet:getWidth(),
                instance.sprite_sheet:getHeight()
            )
        end
    else
        -- Fallback: no sprite
        instance.sprite_sheet = nil
        instance.animation = nil
        instance.quad = nil
    end

    -- Floating animation
    instance.float_offset = 0
    instance.float_timer = math.random() * math.pi * 2  -- Random start phase

    -- Pickup detection
    instance.pickup_range = 32  -- pixels

    -- Collider (set by world system)
    instance.collider = nil

    return instance
end

function world_item:update(dt)
    -- Update animation
    if self.animation then
        self.animation:update(dt)
    end

    -- Floating animation (sine wave)
    self.float_timer = self.float_timer + dt * 2
    self.float_offset = math.sin(self.float_timer) * 4  -- ±4 pixels
end

function world_item:canPickup(player_x, player_y, game_mode)
    local dx = player_x - self.x
    local dy = player_y - self.y

    if game_mode == "platformer" then
        -- In platformer mode, only check horizontal distance
        -- (vertical distance ignored because player can be in the air)
        return math.abs(dx) <= self.pickup_range
    else
        -- Topdown mode: use full 2D distance
        local distance = math.sqrt(dx * dx + dy * dy)
        return distance <= self.pickup_range
    end
end

function world_item:draw()
    if not self.sprite_sheet then
        -- Fallback: draw colored circle
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.circle("fill", self.x, self.y + self.float_offset, 8)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    if self.animation then
        -- Draw animated sprite with floating effect
        self.animation:draw(
            self.sprite_sheet,
            self.x,
            self.y + self.float_offset,
            0,  -- rotation
            self.sprite_scale,  -- scale x
            self.sprite_scale,  -- scale y
            self.sprite_width / 2,  -- offset x (center)
            self.sprite_height / 2  -- offset y (center)
        )
    else
        -- Draw static sprite with floating effect (using quad)
        love.graphics.draw(
            self.sprite_sheet,
            self.quad,
            self.x,
            self.y + self.float_offset,
            0,  -- rotation
            self.sprite_scale,  -- scale x
            self.sprite_scale,  -- scale y
            self.sprite_width / 2,  -- offset x (center)
            self.sprite_height / 2  -- offset y (center)
        )
    end
end

return world_item
