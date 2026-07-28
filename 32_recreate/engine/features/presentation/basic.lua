local util = require "engine.core.util"

local feature = {
    id = "presentation.basic",
    requires = {"engine.features.world"},
}

local function validateColor(color, validator, path, required)
    color = validator:array(color, path, required)
    if not color then return end
    if #color < 3 or #color > 4 then
        validator:error(path, "must contain RGB or RGBA values")
    end
    for index, value in ipairs(color) do
        value = validator:number(
            value,
            string.format("%s[%d]", path, index),
            true
        )
        if value and (value < 0 or value > 1) then
            validator:error(
                string.format("%s[%d]", path, index),
                "must be between 0 and 1"
            )
        end
    end
end

local function validateAppearance(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "shape", "color", "outline", "layer", "label",
            "width", "height", "radius", "points",
        },
        path
    )
    validator:enum(
        config.shape,
        {"circle", "rectangle", "polygon"},
        path .. ".shape",
        not partial
    )
    validateColor(config.color, validator, path .. ".color", not partial)
    validateColor(config.outline, validator, path .. ".outline", false)
    validator:number(config.layer, path .. ".layer", false)
    validator:string(config.label, path .. ".label", false)
    validator:positive(config.width, path .. ".width", false)
    validator:positive(config.height, path .. ".height", false)
    validator:positive(config.radius, path .. ".radius", false)
    local points = validator:array(config.points, path .. ".points", false)
    for index, point in ipairs(points or {}) do
        local point_path = string.format("%s.points[%d]", path, index)
        if validator:table(point, point_path, true) then
            validator:keys(point, {"x", "y"}, point_path)
            validator:number(point.x, point_path .. ".x", true)
            validator:number(point.y, point_path .. ".y", true)
        end
    end
end

local function setColor(color, fallback_alpha)
    love.graphics.setColor(
        color[1],
        color[2],
        color[3],
        color[4] or fallback_alpha or 1
    )
end

local function drawEntity(entity)
    local transform = entity.components.transform
    local appearance = entity.components["render.shape"]
    local body = entity.components.body
    local color = util.deepCopy(appearance.color)
    if entity.dead then color[4] = 0.35 end
    setColor(color)

    local shape = appearance.shape or (body and body.shape) or "circle"
    if shape == "rectangle" then
        local width = appearance.width or (body and body.width) or 24
        local height = appearance.height or (body and body.height) or 24
        love.graphics.rectangle(
            "fill",
            transform.x - width / 2,
            transform.y - height / 2,
            width,
            height
        )
        if appearance.outline then
            setColor(appearance.outline)
            love.graphics.rectangle(
                "line",
                transform.x - width / 2,
                transform.y - height / 2,
                width,
                height
            )
        end
    elseif shape == "polygon" then
        local points = appearance.points or (body and body.points) or {}
        local coordinates = {}
        for _, point in ipairs(points) do
            coordinates[#coordinates + 1] = transform.x + point.x
            coordinates[#coordinates + 1] = transform.y + point.y
        end
        if #coordinates >= 6 then
            love.graphics.polygon("fill", coordinates)
            if appearance.outline then
                setColor(appearance.outline)
                love.graphics.polygon("line", coordinates)
            end
        end
    else
        local radius = appearance.radius or (body and body.radius) or 12
        love.graphics.circle("fill", transform.x, transform.y, radius)
        if appearance.outline then
            setColor(appearance.outline)
            love.graphics.circle("line", transform.x, transform.y, radius)
        end
    end

    if appearance.label then
        love.graphics.setColor(1, 1, 1, entity.dead and 0.4 or 0.9)
        love.graphics.printf(
            appearance.label,
            transform.x - 60,
            transform.y + (body and body.radius or 12) + 7,
            120,
            "center"
        )
    end
end

local background_system = {
    id = "presentation.basic.background",
    draw_order = -200,
}

function background_system:draw(world)
    local background = world.stage.background or {0.08, 0.09, 0.12, 1}
    setColor(background)
    love.graphics.rectangle(
        "fill",
        0,
        0,
        world.stage.width,
        world.stage.height
    )

    love.graphics.setColor(1, 1, 1, 0.035)
    for x = 0, world.stage.width, 32 do
        love.graphics.line(x, 0, x, world.stage.height)
    end
    for y = 0, world.stage.height, 32 do
        love.graphics.line(0, y, world.stage.width, y)
    end
end

local render_system = {
    id = "presentation.basic.world",
    draw_order = 0,
}

function render_system:draw(world)
    local entities = world:query("transform", "render.shape")
    table.sort(entities, function(left, right)
        local left_appearance = left.components["render.shape"]
        local right_appearance = right.components["render.shape"]
        local left_layer = left_appearance.layer or 0
        local right_layer = right_appearance.layer or 0
        if left_layer ~= right_layer then return left_layer < right_layer end
        local left_y = left.components.transform.y
        local right_y = right.components.transform.y
        if left_y ~= right_y then return left_y < right_y end
        return left.id < right.id
    end)
    for _, entity in ipairs(entities) do drawEntity(entity) end
end

local hud_system = {
    id = "presentation.basic.hud",
    draw_order = 100,
    draw_space = "screen",
}

function hud_system:draw(world)
    love.graphics.setColor(0.02, 0.025, 0.04, 0.82)
    love.graphics.rectangle("fill", 12, 12, 390, 62, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(world.stage.name or world.stage.id, 24, 20)

    local player = world:findByTag("player")[1]
    local status = "No active player"
    if player then
        local health = player.components["action.health"]
        status = health and string.format(
            "HP %d / %d",
            math.floor(health.current + 0.5),
            math.floor(health.max + 0.5)
        ) or "Player ready"
        if player.dead then status = status .. " - DEFEATED" end
    end
    love.graphics.print(status, 24, 42)
    love.graphics.setColor(0.78, 0.82, 0.9, 1)
    local view = world:view()
    love.graphics.printf(
        "Move: WASD/arrows  Jump: W/Up  Attack: Space  Skills: F/Q\n" ..
            "Dodge: Shift  Parry: C  Interact: E  Restart: R  Debug: F1",
        18,
        view.height - 42,
        view.width - 36,
        "left"
    )
end

function feature:register(host)
    host:registerComponent("render.shape", {
        validate = validateAppearance,
        create = function(config)
            return util.merge({
                shape = "circle",
                color = {1, 1, 1, 1},
                layer = 0,
            }, config)
        end,
    })
    host:registerSystem(background_system)
    host:registerSystem(render_system)
    host:registerSystem(hud_system)
end

return feature
