local feature = {
    id = "presentation.font",
    requires = {
        "engine.features.assets",
        "engine.features.world",
    },
}

function feature:register(host)
    local config = host.manifest.font or {}
    local asset_id = config.asset
    local size = config.size or 16

    host:registerBootValidator(
        "presentation.font",
        function()
            local definition = asset_id and host.catalog:get(asset_id)
            if not definition or definition.kind ~= "asset" or
               definition.asset_type ~= "font" then
                return nil, "font.asset references missing font asset '" ..
                    tostring(asset_id) .. "'"
            end
            if type(size) ~= "number" or size <= 0 then
                return nil, "font.size must be a positive number"
            end
            return true
        end
    )

    host:registerSystem({
        id = "presentation.font.apply",
        draw_order = -10000,
        draw = function()
            love.graphics.setFont(host.assets:font(asset_id, size))
        end,
    })
end

return feature
