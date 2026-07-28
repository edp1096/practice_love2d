local feature = {
    id = "control",
}

local function validateController(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"slot"}, path)
    local slot = validator:positive(config.slot, path .. ".slot", false)
    if slot and slot % 1 ~= 0 then
        validator:error(path .. ".slot", "must be an integer")
    end
end

function feature:register(host)
    host:registerComponent("control.player", {
        validate = validateController,
        create = function(config)
            return {slot = config.slot or 1}
        end,
    })
end

return feature
