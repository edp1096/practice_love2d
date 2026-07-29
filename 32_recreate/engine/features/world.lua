local util = require "engine.core.util"

local feature = {
    id = "world",
}

local function validateTags(tags, validator, path)
    tags = validator:array(tags, path, false)
    for index, tag in ipairs(tags or {}) do
        validator:string(tag, string.format("%s[%d]", path, index), true)
    end
end

local function validateTransform(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"x", "y"}, path)
    validator:number(config.x, path .. ".x", false)
    validator:number(config.y, path .. ".y", false)
end

local function validateBody(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "shape", "radius", "width", "height", "points",
            "static", "solid", "collision_layer", "collision_mask",
        },
        path
    )
    local shape = validator:enum(
        config.shape,
        {"circle", "rectangle", "polygon"},
        path .. ".shape",
        not partial
    )
    shape = shape or config.shape
    validator:positive(config.radius, path .. ".radius", false)
    validator:positive(config.width, path .. ".width", false)
    validator:positive(config.height, path .. ".height", false)
    if shape == "circle" then
        validator:positive(config.radius, path .. ".radius", not partial)
    elseif shape == "rectangle" then
        validator:positive(config.width, path .. ".width", not partial)
        validator:positive(config.height, path .. ".height", not partial)
    elseif shape == "polygon" then
        local points = validator:array(
            config.points,
            path .. ".points",
            not partial
        )
        if points and #points < 3 then
            validator:error(path .. ".points", "requires at least 3 points")
        end
        for index, point in ipairs(points or {}) do
            local point_path =
                string.format("%s.points[%d]", path, index)
            if validator:table(point, point_path, true) then
                validator:keys(point, {"x", "y"}, point_path)
                validator:number(point.x, point_path .. ".x", true)
                validator:number(point.y, point_path .. ".y", true)
            end
        end
    end
    validator:boolean(config.static, path .. ".static", false)
    validator:boolean(config.solid, path .. ".solid", false)
    validator:string(
        config.collision_layer,
        path .. ".collision_layer",
        false
    )
    local collision_mask = validator:array(
        config.collision_mask,
        path .. ".collision_mask",
        false
    )
    local seen_masks = {}
    for index, layer in ipairs(collision_mask or {}) do
        local item_path =
            string.format("%s.collision_mask[%d]", path, index)
        layer = validator:string(layer, item_path, true)
        if layer and seen_masks[layer] then
            validator:error(item_path, "duplicates another collision layer")
        elseif layer then
            seen_masks[layer] = true
        end
    end
end

local function validateActor(definition, validator, host)
    validator:keys(
        definition,
        {"schema_version", "kind", "id", "name", "tags", "components"},
        "content"
    )
    validator:string(definition.name, "name", false)
    validateTags(definition.tags, validator, "tags")
    local components =
        validator:table(definition.components, "components", true)
    if components and not components.transform then
        validator:error(
            "components.transform",
            "spawnable actors require a transform component"
        )
    end
    for name, config in pairs(components or {}) do
        local component = host.components[name]
        if not component then
            validator:error(
                "components." .. name,
                "unknown component; enable or implement its feature"
            )
        elseif component.validate then
            component.validate(
                config,
                validator,
                "components." .. name,
                false
            )
        end
    end
    for name in pairs(components or {}) do
        local component = host.components[name]
        for _, required in ipairs(
            component and component.requires or {}
        ) do
            if not components[required] then
                validator:error(
                    "components." .. name,
                    "requires component '" .. required .. "'"
                )
            end
        end
        if component and component.validateEntity then
            component.validateEntity(
                components[name],
                components,
                validator,
                "components." .. name
            )
        end
    end
end

local function validateActorInstance(
    spawn,
    validator,
    host,
    path,
    seen_ids
)
    if not validator:table(spawn, path, true) then return end
    validator:keys(
        spawn,
        {"id", "actor", "name", "tags", "position", "components"},
        path
    )

    local id = validator:string(spawn.id, path .. ".id", true)
    if id and seen_ids and seen_ids[id] then
        validator:error(path .. ".id", "duplicates another spawn id")
    elseif id and seen_ids then
        seen_ids[id] = true
    end
    local actor =
        validator:reference(spawn.actor, "actor", path .. ".actor")
    validateTags(spawn.tags, validator, path .. ".tags")

    local position = validator:table(spawn.position, path .. ".position", true)
    if position then
        validator:keys(position, {"x", "y"}, path .. ".position")
        validator:number(position.x, path .. ".position.x", true)
        validator:number(position.y, path .. ".position.y", true)
    end

    local overrides =
        validator:table(spawn.components, path .. ".components", false)
    for name, config in pairs(overrides or {}) do
        local component = host.components[name]
        if not component then
            validator:error(
                path .. ".components." .. name,
                "unknown component override"
            )
        elseif component.validate then
            component.validate(
                config,
                validator,
                path .. ".components." .. name,
                true
            )
        end
    end
    local final_components =
        util.merge(actor and actor.components or {}, overrides or {})
    for name in pairs(final_components) do
        local component = host.components[name]
        for _, required in ipairs(
            component and component.requires or {}
        ) do
            if not final_components[required] then
                validator:error(
                    path .. ".components." .. name,
                    "requires component '" .. required .. "'"
                )
            end
        end
        if component and component.validateEntity then
            component.validateEntity(
                final_components[name],
                final_components,
                validator,
                path .. ".components." .. name
            )
        end
    end
end

local function validateStage(definition, validator, host)
    local allowed = {
        "schema_version", "kind", "id", "name", "name_key",
        "width", "height", "mode", "background", "spawns", "metadata",
    }
    for _, section in ipairs(host.stage_section_order) do
        allowed[#allowed + 1] = section.name
    end
    validator:keys(
        definition,
        allowed,
        "content"
    )
    validator:string(definition.name, "name", false)
    validator:string(definition.name_key, "name_key", false)
    validator:positive(definition.width, "width", true)
    validator:positive(definition.height, "height", true)
    validator:string(definition.mode, "mode", false)
    validator:table(definition.metadata, "metadata", false)

    local background =
        validator:array(definition.background, "background", false)
    if background and (#background < 3 or #background > 4) then
        validator:error("background", "must contain RGB or RGBA values")
    end
    for index, value in ipairs(background or {}) do
        value = validator:number(
            value,
            string.format("background[%d]", index),
            true
        )
        if value and (value < 0 or value > 1) then
            validator:error(
                string.format("background[%d]", index),
                "must be between 0 and 1"
            )
        end
    end

    local spawns = validator:array(definition.spawns, "spawns", true)
    local seen_ids = {}
    for index, spawn in ipairs(spawns or {}) do
        validateActorInstance(
            spawn,
            validator,
            host,
            string.format("spawns[%d]", index),
            seen_ids
        )
    end

    for _, section in ipairs(host.stage_section_order) do
        local section_definition = host.stage_sections[section.name]
        if section_definition.validate then
            section_definition.validate(
                definition[section.name],
                validator,
                section.name,
                definition
            )
        end
    end
end

function feature:register(host)
    host:registerService("actor", {
        validateInstance = function(
            _,
            instance,
            validator,
            path,
            seen_ids
        )
            validateActorInstance(
                instance,
                validator,
                host,
                path,
                seen_ids
            )
        end,
    })

    host:registerComponent("transform", {
        validate = validateTransform,
        create = function(config)
            return {
                x = config.x or 0,
                y = config.y or 0,
            }
        end,
    })

    host:registerComponent("body", {
        validate = validateBody,
        validateEntity = function(
            config,
            _,
            validator,
            path
        )
            if config.shape and config.shape ~= "circle" and
               config.static ~= true and config.solid ~= false then
                validator:error(
                    path .. ".static",
                    "dynamic solid bodies must use shape 'circle'; " ..
                        "set static = true or solid = false"
                )
            end
        end,
        create = function(config)
            local body = util.merge({
                shape = "circle",
                radius = 12,
                static = false,
                solid = true,
            }, config)
            body.collision_layer = body.collision_layer or
                (body.static and "world" or "actor")
            body.collision_mask = body.collision_mask or
                (body.static and
                    {"actor", "projectile"} or
                    {"world", "actor"})
            body.collision_mask_set = {}
            for _, layer in ipairs(body.collision_mask) do
                body.collision_mask_set[layer] = true
            end
            return body
        end,
    })

    host:registerEntityInspector("body", function(entity)
        local body = entity.components.body
        if not body then return end
        return {
            body_shape = body.shape,
            body_static = body.static,
            body_solid = body.solid,
            collision_layer = body.collision_layer,
            collision_mask = util.deepCopy(body.collision_mask),
        }
    end)

    host:registerContentKind("actor", {validate = validateActor})
    host:registerContentKind("stage", {validate = validateStage})
end

return feature
