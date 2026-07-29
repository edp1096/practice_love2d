local feature = {
    id = "assets",
}

local function validateAsset(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name",
            "asset_type", "path", "width", "height", "filter",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    local asset_type = validator:enum(
        definition.asset_type,
        {"image", "font", "audio"},
        "asset_type",
        true
    )
    local path = validator:string(definition.path, "path", true)
    if path then
        local info = host.filesystem:info(path)
        if not info or info.type ~= "file" then
            validator:error("path", "file does not exist: " .. path)
        end
    end
    if asset_type == "image" then
        local width =
            validator:positive(definition.width, "width", true)
        local height =
            validator:positive(definition.height, "height", true)
        validator:enum(
            definition.filter,
            {"nearest", "linear"},
            "filter",
            false
        )
        if path and width and height and
           host.filesystem.imageDimensions then
            local actual_width, actual_height, image_error =
                host.filesystem:imageDimensions(path)
            if not actual_width then
                validator:error(
                    "path",
                    "could not read image metadata: " ..
                        tostring(image_error)
                )
            elseif actual_width ~= width or actual_height ~= height then
                validator:error(
                    "width",
                    string.format(
                        "image is %dx%d but content declares %dx%d",
                        actual_width,
                        actual_height,
                        width,
                        height
                    )
                )
            end
        end
    elseif asset_type == "font" or asset_type == "audio" then
        if definition.width ~= nil or definition.height ~= nil or
           definition.filter ~= nil then
            validator:error(
                "content",
                "non-image assets do not use width, height, or filter"
            )
        end
    end
end

function feature:register(host)
    host:registerContentKind("asset", {validate = validateAsset})
end

return feature
