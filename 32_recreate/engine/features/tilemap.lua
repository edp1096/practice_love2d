local util = require "engine.core.util"

local feature = {
    id = "tilemap",
    requires = {
        "engine.features.world",
        "engine.features.assets",
    },
}

local FLIP_HORIZONTAL = 2147483648
local FLIP_VERTICAL = 1073741824
local FLIP_DIAGONAL = 536870912

local function decodeGid(encoded)
    local gid = encoded
    local horizontal = false
    local vertical = false
    local diagonal = false
    if gid >= FLIP_HORIZONTAL then
        gid = gid - FLIP_HORIZONTAL
        horizontal = true
    end
    if gid >= FLIP_VERTICAL then
        gid = gid - FLIP_VERTICAL
        vertical = true
    end
    if gid >= FLIP_DIAGONAL then
        gid = gid - FLIP_DIAGONAL
        diagonal = true
    end
    return gid, horizontal, vertical, diagonal
end

local function validateInteger(value, validator, path, required)
    value = validator:number(value, path, required)
    if value and value % 1 ~= 0 then
        validator:error(path, "must be an integer")
        return nil
    end
    return value
end

local function validatePositiveInteger(value, validator, path)
    value = validateInteger(value, validator, path, true)
    if value and value <= 0 then
        validator:error(path, "must be greater than zero")
        return nil
    end
    return value
end

local function validateTileset(tileset, validator, path)
    if not validator:table(tileset, path, true) then return end
    validator:keys(
        tileset,
        {
            "id", "first_gid", "tile_count", "columns",
            "tile_width", "tile_height", "asset",
        },
        path
    )
    validator:string(tileset.id, path .. ".id", true)
    validatePositiveInteger(
        tileset.first_gid,
        validator,
        path .. ".first_gid"
    )
    validatePositiveInteger(
        tileset.tile_count,
        validator,
        path .. ".tile_count"
    )
    validatePositiveInteger(
        tileset.columns,
        validator,
        path .. ".columns"
    )
    validator:positive(
        tileset.tile_width,
        path .. ".tile_width",
        true
    )
    validator:positive(
        tileset.tile_height,
        path .. ".tile_height",
        true
    )
    validator:reference(tileset.asset, "asset", path .. ".asset")
end

local function tilesetFor(tilesets, gid)
    local match = nil
    for _, tileset in ipairs(tilesets) do
        if gid >= tileset.first_gid and
           gid < tileset.first_gid + tileset.tile_count then
            match = tileset
        end
    end
    return match
end

local function validateTilemap(tilemap, validator, path)
    if tilemap == nil then return end
    if not validator:table(tilemap, path, true) then return end
    validator:keys(
        tilemap,
        {"source", "tile_width", "tile_height", "tilesets", "layers"},
        path
    )
    validator:string(tilemap.source, path .. ".source", false)
    validatePositiveInteger(
        tilemap.tile_width,
        validator,
        path .. ".tile_width"
    )
    validatePositiveInteger(
        tilemap.tile_height,
        validator,
        path .. ".tile_height"
    )

    local tilesets = validator:array(
        tilemap.tilesets,
        path .. ".tilesets",
        true
    )
    if tilesets and #tilesets == 0 then
        validator:error(path .. ".tilesets", "must not be empty")
    end
    local seen_tilesets = {}
    for index, tileset in ipairs(tilesets or {}) do
        local tileset_path =
            string.format("%s.tilesets[%d]", path, index)
        validateTileset(tileset, validator, tileset_path)
        if type(tileset) == "table" and tileset.id then
            if seen_tilesets[tileset.id] then
                validator:error(
                    tileset_path .. ".id",
                    "duplicates another tileset id"
                )
            end
            seen_tilesets[tileset.id] = true
        end
    end
    for left_index = 1, #(tilesets or {}) - 1 do
        local left = tilesets[left_index]
        for right_index = left_index + 1, #(tilesets or {}) do
            local right = tilesets[right_index]
            local valid_ranges =
                type(left) == "table" and
                type(right) == "table" and
                type(left.first_gid) == "number" and
                left.first_gid % 1 == 0 and
                left.first_gid > 0 and
                type(left.tile_count) == "number" and
                left.tile_count % 1 == 0 and
                left.tile_count > 0 and
                type(right.first_gid) == "number" and
                right.first_gid % 1 == 0 and
                right.first_gid > 0 and
                type(right.tile_count) == "number" and
                right.tile_count % 1 == 0 and
                right.tile_count > 0
            if valid_ranges then
                local left_last =
                    left.first_gid + left.tile_count - 1
                local right_last =
                    right.first_gid + right.tile_count - 1
                if left.first_gid <= right_last and
                   right.first_gid <= left_last then
                    validator:error(
                        string.format(
                            "%s.tilesets[%d].first_gid",
                            path,
                            right_index
                        ),
                        string.format(
                            "gid range overlaps tileset '%s'",
                            tostring(left.id or left_index)
                        )
                    )
                end
            end
        end
    end

    local layers = validator:array(
        tilemap.layers,
        path .. ".layers",
        true
    )
    local seen_layers = {}
    for index, layer in ipairs(layers or {}) do
        local layer_path = string.format("%s.layers[%d]", path, index)
        if validator:table(layer, layer_path, true) then
            validator:keys(
                layer,
                {
                    "id", "name", "width", "height", "visible",
                    "opacity", "offset_x", "offset_y", "data",
                },
                layer_path
            )
            local id = validator:string(
                layer.id,
                layer_path .. ".id",
                true
            )
            if id and seen_layers[id] then
                validator:error(
                    layer_path .. ".id",
                    "duplicates another tile layer id"
                )
            elseif id then
                seen_layers[id] = true
            end
            validator:string(
                layer.name,
                layer_path .. ".name",
                false
            )
            local width = validatePositiveInteger(
                layer.width,
                validator,
                layer_path .. ".width"
            )
            local height = validatePositiveInteger(
                layer.height,
                validator,
                layer_path .. ".height"
            )
            validator:boolean(
                layer.visible,
                layer_path .. ".visible",
                false
            )
            local opacity = validator:number(
                layer.opacity,
                layer_path .. ".opacity",
                false
            )
            if opacity and (opacity < 0 or opacity > 1) then
                validator:error(
                    layer_path .. ".opacity",
                    "must be between 0 and 1"
                )
            end
            validator:number(
                layer.offset_x,
                layer_path .. ".offset_x",
                false
            )
            validator:number(
                layer.offset_y,
                layer_path .. ".offset_y",
                false
            )
            local data = validator:array(
                layer.data,
                layer_path .. ".data",
                true
            )
            if data and width and height and #data ~= width * height then
                validator:error(
                    layer_path .. ".data",
                    string.format(
                        "contains %d gids, expected %d",
                        #data,
                        width * height
                    )
                )
            end
            for tile_index, encoded in ipairs(data or {}) do
                local gid_path = string.format(
                    "%s.data[%d]",
                    layer_path,
                    tile_index
                )
                encoded = validateInteger(
                    encoded,
                    validator,
                    gid_path,
                    true
                )
                if encoded and (encoded < 0 or encoded >= 4294967296) then
                    validator:error(gid_path, "must be an unsigned 32-bit gid")
                elseif encoded and encoded ~= 0 then
                    local gid = decodeGid(encoded)
                    if not tilesetFor(tilesets or {}, gid) then
                        validator:error(
                            gid_path,
                            "does not belong to a declared tileset"
                        )
                    end
                end
            end
        end
    end
end

local function transformedTile(encoded)
    local gid, flip_x, flip_y, flip_diagonal = decodeGid(encoded)
    local rotation = 0
    local scale_x = 1
    local scale_y = 1
    if flip_x then
        if flip_y and flip_diagonal then
            rotation = math.rad(-90)
            scale_y = -1
        elseif flip_y then
            scale_x = -1
            scale_y = -1
        elseif flip_diagonal then
            rotation = math.rad(90)
        else
            scale_x = -1
        end
    elseif flip_y then
        if flip_diagonal then
            rotation = math.rad(-90)
        else
            scale_y = -1
        end
    elseif flip_diagonal then
        rotation = math.rad(90)
        scale_y = -1
    end
    return gid, rotation, scale_x, scale_y
end

local function compensate(
    x,
    y,
    rotation,
    scale_x,
    scale_y,
    tile_width,
    tile_height
)
    local compensate_x = scale_x < 0 and tile_width or 0
    local compensate_y = scale_y < 0 and tile_height or 0
    if rotation > 0 then
        x = x + tile_height - compensate_y
        y = y + tile_height + compensate_x - tile_width
    elseif rotation < 0 then
        x = x + compensate_y
        y = y - compensate_x + tile_height
    else
        x = x + compensate_x
        y = y + compensate_y
    end
    return x, y
end

local tilemap_system = {
    id = "tilemap.render",
    draw_order = -100,
}

function tilemap_system:draw(world)
    local tilemap = world.feature_state.tilemap
    if not tilemap then return end
    local view = world:view()
    local assets = world.host.assets

    for _, layer in ipairs(tilemap.layers) do
        if layer.visible ~= false and (layer.opacity or 1) > 0 then
            local offset_x = layer.offset_x or 0
            local offset_y = layer.offset_y or 0
            local minimum_column = util.clamp(
                math.floor(
                    (view.x - offset_x) / tilemap.tile_width
                ) + 1,
                1,
                layer.width
            )
            local maximum_column = util.clamp(
                math.floor(
                    (view.x + view.width - offset_x) /
                    tilemap.tile_width
                ) + 1,
                1,
                layer.width
            )
            local minimum_row = util.clamp(
                math.floor(
                    (view.y - offset_y) / tilemap.tile_height
                ) + 1,
                1,
                layer.height
            )
            local maximum_row = util.clamp(
                math.floor(
                    (view.y + view.height - offset_y) /
                    tilemap.tile_height
                ) + 1,
                1,
                layer.height
            )

            love.graphics.setColor(1, 1, 1, layer.opacity or 1)
            for row = minimum_row, maximum_row do
                for column = minimum_column, maximum_column do
                    local encoded =
                        layer.data[(row - 1) * layer.width + column]
                    if encoded and encoded ~= 0 then
                        local gid, rotation, scale_x, scale_y =
                            transformedTile(encoded)
                        local tileset = tilesetFor(
                            tilemap.tilesets,
                            gid
                        )
                        local local_id = gid - tileset.first_gid
                        local quad = assets:quad(
                            tileset.asset,
                            tileset.tile_width,
                            tileset.tile_height,
                            local_id % tileset.columns + 1,
                            math.floor(local_id / tileset.columns) + 1
                        )
                        local x =
                            (column - 1) * tilemap.tile_width +
                            offset_x
                        local y =
                            row * tilemap.tile_height -
                            tileset.tile_height +
                            offset_y
                        x, y = compensate(
                            x,
                            y,
                            rotation,
                            scale_x,
                            scale_y,
                            tilemap.tile_width,
                            tilemap.tile_height
                        )
                        love.graphics.draw(
                            assets:image(tileset.asset),
                            quad,
                            x,
                            y,
                            rotation,
                            scale_x,
                            scale_y
                        )
                    end
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function feature:register(host)
    host:registerStageSection("tilemap", {
        priority = 5,
        validate = validateTilemap,
        load = function(world, tilemap)
            world.feature_state.tilemap =
                tilemap and util.deepCopy(tilemap) or nil
            return true
        end,
    })
    host:registerWorldInspector("tilemap", function(world)
        local tilemap = world.feature_state.tilemap
        return {
            tilemap = {
                available = tilemap ~= nil,
                layer_count = tilemap and #tilemap.layers or 0,
                tileset_count = tilemap and #tilemap.tilesets or 0,
                source = tilemap and tilemap.source or nil,
            },
        }
    end)
    host:registerSystem(tilemap_system)
end

return feature
