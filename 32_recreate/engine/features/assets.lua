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
        {"image", "font"},
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
        validator:positive(definition.width, "width", true)
        validator:positive(definition.height, "height", true)
        validator:enum(
            definition.filter,
            {"nearest", "linear"},
            "filter",
            false
        )
    elseif asset_type == "font" then
        if definition.width ~= nil or definition.height ~= nil or
           definition.filter ~= nil then
            validator:error(
                "content",
                "font assets do not use width, height, or filter"
            )
        end
    end
end

function feature:register(host)
    host:registerContentKind("asset", {validate = validateAsset})
end

return feature
