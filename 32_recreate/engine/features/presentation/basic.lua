local util = require "engine.core.util"

local feature = {
    id = "presentation.basic",
    requires = {"engine.features.world"},
}

local notice_tones = {
    info = {
        fill = {0.04, 0.09, 0.14, 0.94},
        outline = {0.35, 0.72, 0.92, 1},
        text = {0.9, 0.97, 1, 1},
    },
    success = {
        fill = {0.035, 0.13, 0.09, 0.94},
        outline = {0.35, 0.88, 0.57, 1},
        text = {0.88, 1, 0.92, 1},
    },
    warning = {
        fill = {0.16, 0.095, 0.025, 0.94},
        outline = {1, 0.7, 0.24, 1},
        text = {1, 0.95, 0.82, 1},
    },
}

local function noticeState(world)
    local state = world.feature_state.presentation_basic
    if not state then
        state = {notice = nil}
        world.feature_state.presentation_basic = state
    end
    return state
end

local function noticeText(world, notice)
    if not notice then return nil end
    local locale = world:service("locale")
    if notice.text_key and locale then
        return locale:text(notice.text_key, notice.text or notice.text_key)
    end
    return notice.text or notice.text_key
end

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

local function inputHints(world)
    local input = world.host.input
    local locale = world:service("locale")
    local function text(key, fallback)
        return locale and locale:text(key, fallback) or fallback
    end
    local hints = {}
    if input:hasAction("move_up") and
       input:hasAction("move_down") and
       input:hasAction("move_left") and
       input:hasAction("move_right") then
        hints[#hints + 1] = text(
            "ui.input.move",
            "Move: WASD/arrows"
        )
    end
    local optional = {
        {
            "jump", "ui.input.jump", "Jump: W/Up",
            world.stage.mode == "platformer",
        },
        {"attack", "ui.input.attack", "Attack: Space"},
        {"special", "ui.input.special", "Special: F"},
        {"technique", "ui.input.technique", "Technique: Q"},
        {"dodge", "ui.input.dodge", "Dodge: Shift"},
        {"parry", "ui.input.parry", "Parry: C"},
        {"interact", "ui.input.interact", "Interact: E"},
        {"restart", "ui.input.restart", "Restart: R"},
        {"debug_overlay", "ui.input.debug", "Debug: F1"},
    }
    for _, entry in ipairs(optional) do
        if input:hasAction(entry[1]) and entry[4] ~= false then
            hints[#hints + 1] = text(entry[2], entry[3])
        end
    end
    return table.concat(hints, "  ")
end

function hud_system:draw(world)
    local view = world:view()
    local panel_width = math.min(390, math.max(0, view.width - 24))
    love.graphics.setColor(0.02, 0.025, 0.04, 0.82)
    love.graphics.rectangle("fill", 12, 12, panel_width, 62, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    local locale = world:service("locale")
    local stage_name = world.stage.name or world.stage.id
    if locale and world.stage.name_key then
        stage_name = locale:text(world.stage.name_key, stage_name)
    end
    love.graphics.print(stage_name, 24, 20)

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
    local hints = inputHints(world)
    if hints == "" then return end
    local font = love.graphics.getFont()
    local _, wrapped = font:getWrap(hints, math.max(1, view.width - 36))
    local hint_height = math.max(
        42,
        #wrapped * font:getHeight() + 16
    )
    love.graphics.setColor(0.02, 0.025, 0.04, 0.82)
    love.graphics.rectangle(
        "fill",
        0,
        view.height - hint_height,
        view.width,
        hint_height
    )
    love.graphics.setColor(0.78, 0.82, 0.9, 1)
    love.graphics.printf(
        hints,
        18,
        view.height - hint_height + 8,
        view.width - 36,
        "left"
    )
end

local notice_system = {
    id = "presentation.basic.notice",
    phase = "presentation",
    order = 1000,
    draw_order = 9000,
    draw_space = "screen",
}

function notice_system:updateUnscaled(world, raw_dt)
    local state = noticeState(world)
    local notice = state.notice
    if not notice then return end
    local dialogue = world.feature_state.dialogue
    local shop = world.feature_state.shop
    if (dialogue and dialogue.active) or (shop and shop.active) then
        return
    end
    notice.remaining = math.max(0, notice.remaining - raw_dt)
    if notice.remaining == 0 then state.notice = nil end
end

function notice_system:draw(world)
    local notice = noticeState(world).notice
    if not notice then return end
    local dialogue = world.feature_state.dialogue
    local shop = world.feature_state.shop
    if (dialogue and dialogue.active) or (shop and shop.active) then
        return
    end
    local text = noticeText(world, notice)
    if not text or text == "" then return end

    local view = world:view()
    local width = math.min(620, math.max(0, view.width - 48))
    if width <= 0 then return end
    local font = love.graphics.getFont()
    local _, wrapped = font:getWrap(text, math.max(1, width - 40))
    local height = math.max(50, #wrapped * font:getHeight() + 24)
    local x = (view.width - width) / 2
    local y = math.max(12, view.height - height - 72)
    local tone = notice_tones[notice.tone] or notice_tones.info

    setColor(tone.fill)
    love.graphics.rectangle("fill", x, y, width, height, 9, 9)
    setColor(tone.outline)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, width, height, 9, 9)
    love.graphics.setLineWidth(1)
    setColor(tone.text)
    love.graphics.printf(
        text,
        x + 20,
        y + (height - #wrapped * font:getHeight()) / 2,
        width - 40,
        "center"
    )
    love.graphics.setColor(1, 1, 1, 1)
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
    host.rules:registerAction("show_notice", {
        validate = function(action, validator, path)
            validator:keys(
                action,
                {"type", "text", "text_key", "duration", "tone"},
                path
            )
            local text = validator:string(
                action.text,
                path .. ".text",
                false
            )
            local text_key = validator:string(
                action.text_key,
                path .. ".text_key",
                false
            )
            if not text and not text_key then
                validator:error(path, "requires text or text_key")
            end
            validator:positive(
                action.duration,
                path .. ".duration",
                false
            )
            validator:enum(
                action.tone,
                {"info", "success", "warning"},
                path .. ".tone",
                false
            )
        end,
        execute = function(action, context)
            local duration = action.duration or 3
            local accessibility =
                context.world:service("accessibility")
            if accessibility then
                duration = duration * accessibility:noticeScale()
            end
            local state = noticeState(context.world)
            state.notice = {
                text = action.text,
                text_key = action.text_key,
                tone = action.tone or "info",
                duration = duration,
                remaining = duration,
            }
            return {
                applied = true,
                text = noticeText(context.world, state.notice),
                tone = state.notice.tone,
                duration = duration,
            }
        end,
    })
    host:registerWorldInspector("presentation.basic.notice", function(world)
        local notice = noticeState(world).notice
        if not notice then
            return {
                notice = {
                    active = false,
                },
            }
        end
        return {
            notice = {
                active = true,
                text = noticeText(world, notice),
                text_key = notice.text_key,
                tone = notice.tone,
                duration = notice.duration,
                remaining = notice.remaining,
            },
        }
    end)
    host:registerSystem(background_system)
    host:registerSystem(render_system)
    host:registerSystem(hud_system)
    host:registerSystem(notice_system)
end

return feature
