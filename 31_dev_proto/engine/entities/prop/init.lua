-- engine/entities/prop/init.lua
-- Prop entity: movable/breakable objects (furniture, crates, etc.)

local prop = {}
prop.__index = prop

-- Counter for unique IDs
local id_counter = 0

-- Create a new Prop from grouped Tiled objects
-- tiles: array of tile objects (gid present)
-- collider_obj: the collider object (type="collider")
-- map: STI map reference for tile rendering
function prop:new(tiles, collider_obj, map)
    local instance = setmetatable({}, prop)

    -- Generate unique ID
    id_counter = id_counter + 1
    instance.id = "prop_" .. id_counter

    -- Store map reference for tile rendering
    instance.map = map

    -- Properties from collider object
    local props = collider_obj.properties or {}
    instance.group = props.group or ("single_" .. id_counter)
    instance.movable = props.movable or false
    instance.breakable = props.breakable or false
    instance.hp = props.hp or 1
    instance.max_hp = instance.hp
    instance.respawn = props.respawn or false  -- Default: no respawn (like enemy)

    -- Map ID for persistence (set by loader)
    instance.map_id = nil

    -- Collider shape data
    instance.collider_x = collider_obj.x
    instance.collider_y = collider_obj.y
    instance.collider_width = collider_obj.width
    instance.collider_height = collider_obj.height

    -- Current position (center of collider)
    instance.x = collider_obj.x + collider_obj.width / 2
    instance.y = collider_obj.y + collider_obj.height / 2

    -- Store tile data with relative offsets from collider center
    instance.tiles = {}
    for _, tile_obj in ipairs(tiles) do
        -- Tile Object y is bottom-left in Tiled
        local tile_draw_x = tile_obj.x
        local tile_draw_y = tile_obj.y - tile_obj.height  -- Convert to top-left

        table.insert(instance.tiles, {
            gid = tile_obj.gid,
            -- Offset from prop center
            offset_x = tile_draw_x - instance.x,
            offset_y = tile_draw_y - instance.y,
            width = tile_obj.width,
            height = tile_obj.height,
        })
    end

    -- Sort tiles by y for correct draw order (top tiles first)
    table.sort(instance.tiles, function(a, b)
        return a.offset_y < b.offset_y
    end)

    -- Calculate bounding box for all tiles (for Y-sorting)
    instance.bounds = instance:calculateBounds()

    -- Physics collider (set by collision system)
    instance.collider = nil

    -- State
    instance.dead = false
    instance.death_timer = 0
    instance.hit_flash = 0  -- Visual feedback when hit

    return instance
end

-- Calculate bounding box encompassing all tiles
function prop:calculateBounds()
    if #self.tiles == 0 then
        return {
            min_x = self.collider_x,
            min_y = self.collider_y,
            max_x = self.collider_x + self.collider_width,
            max_y = self.collider_y + self.collider_height,
        }
    end

    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge

    for _, tile in ipairs(self.tiles) do
        local tx = self.x + tile.offset_x
        local ty = self.y + tile.offset_y
        min_x = math.min(min_x, tx)
        min_y = math.min(min_y, ty)
        max_x = math.max(max_x, tx + tile.width)
        max_y = math.max(max_y, ty + tile.height)
    end

    return {
        min_x = min_x,
        min_y = min_y,
        max_x = max_x,
        max_y = max_y,
    }
end

function prop:update(dt)
    -- Sync position with physics collider
    if self.collider and not self.collider:isDestroyed() then
        self.x, self.y = self.collider:getPosition()
    end

    -- Update hit flash timer
    if self.hit_flash > 0 then
        self.hit_flash = self.hit_flash - dt
    end

    -- Handle death
    if self.dead then
        self.death_timer = self.death_timer + dt
    end
end

-- Take damage (for breakable props)
function prop:takeDamage(amount)
    if not self.breakable then return false end

    self.hp = self.hp - amount
    if self.hp <= 0 then
        self:destroy()
        return true  -- Destroyed
    end
    return false
end

-- Destroy the prop
function prop:destroy()
    self.dead = true
    self.hp = 0

    -- Destroy physics collider
    if self.collider and not self.collider:isDestroyed() then
        self.collider:destroy()
    end
    self.collider = nil
end

-- Get Y position for sorting (bottom of collider)
function prop:getSortY()
    return self.y + self.collider_height / 2
end

function prop:draw()
    if self.dead then return end

    -- Apply hit flash effect (bright white)
    if self.hit_flash > 0 then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("add")  -- Additive blend for bright flash
    else
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Draw all tiles at their offset positions
    for _, tile in ipairs(self.tiles) do
        local tile_info = self.map.tiles[tile.gid]
        if tile_info then
            local tileset = self.map.tilesets[tile_info.tileset]
            if tileset and tileset.image then
                local draw_x = self.x + tile.offset_x
                local draw_y = self.y + tile.offset_y

                -- Handle animated tiles
                local quad = tile_info.quad
                local current_tile = self.map.tiles[tile.gid]
                if current_tile and current_tile.animation then
                    local frame_tileid = current_tile.animation[current_tile.frame].tileid
                    local frame_gid = frame_tileid + self.map.tilesets[current_tile.tileset].firstgid
                    local frame_tile = self.map.tiles[frame_gid]
                    if frame_tile then
                        quad = frame_tile.quad
                    end
                end

                love.graphics.draw(tileset.image, quad, draw_x, draw_y)
            end
        end
    end

    -- Reset blend mode and color
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

-- Debug draw
function prop:drawDebug()
    if self.dead then return end

    -- Draw collider bounds
    love.graphics.setColor(0, 1, 1, 0.5)
    love.graphics.rectangle("line",
        self.x - self.collider_width / 2,
        self.y - self.collider_height / 2,
        self.collider_width,
        self.collider_height
    )

    -- Draw tile bounds
    love.graphics.setColor(1, 1, 0, 0.3)
    for _, tile in ipairs(self.tiles) do
        love.graphics.rectangle("line",
            self.x + tile.offset_x,
            self.y + tile.offset_y,
            tile.width,
            tile.height
        )
    end

    -- Draw center point
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.circle("fill", self.x, self.y, 3)

    -- Draw group name
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(self.group, self.x - 20, self.y - self.collider_height / 2 - 15)

    love.graphics.setColor(1, 1, 1, 1)
end

return prop
