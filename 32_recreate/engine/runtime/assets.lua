local Assets = {}
Assets.__index = Assets

function Assets.new(host)
    return setmetatable({
        host = host,
        images = {},
        quads = {},
        fonts = {},
    }, Assets)
end

function Assets:image(asset_id)
    if self.images[asset_id] then return self.images[asset_id] end

    local definition = self.host.catalog:get(asset_id)
    if not definition or definition.kind ~= "asset" or
       definition.asset_type ~= "image" then
        error("unknown image asset '" .. tostring(asset_id) .. "'")
    end

    local image = love.graphics.newImage(definition.path)
    local actual_width, actual_height = image:getDimensions()
    if actual_width ~= definition.width or
       actual_height ~= definition.height then
        error(string.format(
            "asset '%s' is %dx%d, content declares %dx%d",
            asset_id,
            actual_width,
            actual_height,
            definition.width,
            definition.height
        ))
    end
    local filter = definition.filter or "nearest"
    image:setFilter(filter, filter)
    self.images[asset_id] = image
    return image
end

function Assets:font(asset_id, size)
    size = size or 16
    local key = asset_id .. ":" .. tostring(size)
    if self.fonts[key] then return self.fonts[key] end

    local definition = self.host.catalog:get(asset_id)
    if not definition or definition.kind ~= "asset" or
       definition.asset_type ~= "font" then
        error("unknown font asset '" .. tostring(asset_id) .. "'")
    end
    local font = love.graphics.newFont(definition.path, size)
    self.fonts[key] = font
    return font
end

function Assets:quad(asset_id, frame_width, frame_height, column, row)
    local key = table.concat({
        asset_id,
        frame_width,
        frame_height,
        column,
        row,
    }, ":")
    if self.quads[key] then return self.quads[key] end

    local image = self:image(asset_id)
    local width, height = image:getDimensions()
    local quad = love.graphics.newQuad(
        (column - 1) * frame_width,
        (row - 1) * frame_height,
        frame_width,
        frame_height,
        width,
        height
    )
    self.quads[key] = quad
    return quad
end

function Assets:clear()
    self.images = {}
    self.quads = {}
    self.fonts = {}
end

return Assets
