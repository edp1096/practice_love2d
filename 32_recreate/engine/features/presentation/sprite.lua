local util = require "engine.core.util"

local feature = {
    id = "presentation.sprite",
    requires = {
        "engine.features.world",
        "engine.features.assets",
        "engine.features.motion",
    },
}

local state_names = {
    "idle_up", "idle_down", "idle_left", "idle_right",
    "move_up", "move_down", "move_left", "move_right",
    "attack_up", "attack_down", "attack_left", "attack_right",
}

local function validateColor(color, validator, path)
    color = validator:array(color, path, false)
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

local function validateClip(
    name,
    clip,
    validator,
    path,
    columns,
    rows
)
    if not validator:table(clip, path, true) then return end
    validator:keys(clip, {"frames", "fps", "loop"}, path)
    validator:positive(clip.fps, path .. ".fps", true)
    validator:boolean(clip.loop, path .. ".loop", false)

    local frames = validator:array(clip.frames, path .. ".frames", true)
    if frames and #frames == 0 then
        validator:error(path .. ".frames", "must contain at least one frame")
    end
    for index, frame in ipairs(frames or {}) do
        local frame_path = string.format("%s.frames[%d]", path, index)
        frame = validator:array(frame, frame_path, true)
        if frame and #frame ~= 2 then
            validator:error(frame_path, "must be {column, row}")
        elseif frame then
            local column =
                validator:positive(frame[1], frame_path .. "[1]", true)
            local row =
                validator:positive(frame[2], frame_path .. "[2]", true)
            if column and column % 1 ~= 0 then
                validator:error(frame_path .. "[1]", "must be an integer")
            elseif column and column > columns then
                validator:error(frame_path .. "[1]", "is outside the sheet")
            end
            if row and row % 1 ~= 0 then
                validator:error(frame_path .. "[2]", "must be an integer")
            elseif row and row > rows then
                validator:error(frame_path .. "[2]", "is outside the sheet")
            end
        end
    end
end

local function validateSprite(definition, validator)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "asset",
            "frame_width", "frame_height", "scale",
            "origin_x", "origin_y", "tint", "clips",
            "default_clip", "state_map",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    local asset = validator:reference(definition.asset, "asset", "asset")
    if asset and asset.asset_type ~= "image" then
        validator:error("asset", "sprite requires an image asset")
    end

    local frame_width =
        validator:positive(definition.frame_width, "frame_width", true)
    local frame_height =
        validator:positive(definition.frame_height, "frame_height", true)
    validator:positive(definition.scale, "scale", false)
    validator:number(definition.origin_x, "origin_x", false)
    validator:number(definition.origin_y, "origin_y", false)
    validateColor(definition.tint, validator, "tint")

    local columns = asset and frame_width and
        math.floor(asset.width / frame_width) or 0
    local rows = asset and frame_height and
        math.floor(asset.height / frame_height) or 0
    if asset and frame_width and asset.width % frame_width ~= 0 then
        validator:error("frame_width", "does not divide the image width")
    end
    if asset and frame_height and asset.height % frame_height ~= 0 then
        validator:error("frame_height", "does not divide the image height")
    end

    local clips = validator:table(definition.clips, "clips", true)
    for name, clip in pairs(clips or {}) do
        if type(name) ~= "string" or name == "" then
            validator:error("clips", "clip names must be non-empty strings")
        else
            validateClip(
                name,
                clip,
                validator,
                "clips." .. name,
                columns,
                rows
            )
        end
    end

    local default_clip =
        validator:string(definition.default_clip, "default_clip", true)
    if default_clip and clips and not clips[default_clip] then
        validator:error(
            "default_clip",
            "references missing clip '" .. default_clip .. "'"
        )
    end

    local state_map =
        validator:table(definition.state_map, "state_map", true)
    validator:keys(state_map, state_names, "state_map")
    for _, state_name in ipairs(state_names) do
        local clip_name = state_map and state_map[state_name]
        if clip_name then
            validator:string(
                clip_name,
                "state_map." .. state_name,
                true
            )
            if clips and not clips[clip_name] then
                validator:error(
                    "state_map." .. state_name,
                    "references missing clip '" .. clip_name .. "'"
                )
            end
        end
    end
end

local function validateComponent(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"sprite", "scale", "tint"}, path)
    validator:reference(config.sprite, "sprite", path .. ".sprite")
    validator:positive(config.scale, path .. ".scale", false)
    validateColor(config.tint, validator, path .. ".tint")
end

local function directionFor(facing)
    if not facing then return "down" end
    if math.abs(facing.x) > math.abs(facing.y) then
        return facing.x < 0 and "left" or "right"
    end
    return facing.y < 0 and "up" or "down"
end

local function chooseClip(entity, sprite_definition)
    local facing = entity.components["motion.facing"]
    local kinematics = entity.components["motion.kinematics"]
    local combat = entity.components["action.combat"]
    local prefix = "idle"
    if combat and combat.active then
        prefix = "attack"
    elseif kinematics and kinematics.moving then
        prefix = "move"
    end
    local state = prefix .. "_" .. directionFor(facing)
    return sprite_definition.state_map[state] or
        sprite_definition.default_clip
end

local animation_system = {
    id = "presentation.sprite.animate",
    phase = "presentation",
    order = 0,
}

function animation_system:update(world, dt)
    for _, entity in ipairs(world:query("render.sprite")) do
        local sprite = entity.components["render.sprite"]
        local definition = world.host.catalog:get(sprite.sprite)
        local clip_name = chooseClip(entity, definition)
        if sprite.clip ~= clip_name then
            sprite.clip = clip_name
            sprite.frame = 1
            sprite.elapsed = 0
        end

        local clip = definition.clips[sprite.clip]
        sprite.elapsed = sprite.elapsed + dt
        local frame_duration = 1 / clip.fps
        while sprite.elapsed >= frame_duration do
            sprite.elapsed = sprite.elapsed - frame_duration
            if sprite.frame < #clip.frames then
                sprite.frame = sprite.frame + 1
            elseif clip.loop ~= false then
                sprite.frame = 1
            else
                sprite.frame = #clip.frames
            end
        end
    end
end

local draw_system = {
    id = "presentation.sprite.draw",
    draw_order = 10,
}

function draw_system:draw(world)
    local entities = world:query("transform", "render.sprite")
    table.sort(entities, function(left, right)
        local left_transform = left.components.transform
        local right_transform = right.components.transform
        if left_transform.y ~= right_transform.y then
            return left_transform.y < right_transform.y
        end
        return left.id < right.id
    end)

    for _, entity in ipairs(entities) do
        local transform = entity.components.transform
        local sprite = entity.components["render.sprite"]
        local definition = world.host.catalog:get(sprite.sprite)
        local clip = definition.clips[sprite.clip]
        local frame = clip.frames[sprite.frame]
        local image = world.host.assets:image(definition.asset)
        local quad = world.host.assets:quad(
            definition.asset,
            definition.frame_width,
            definition.frame_height,
            frame[1],
            frame[2]
        )
        local body = entity.components.body

        if body then
            love.graphics.setColor(0, 0, 0, entity.dead and 0.12 or 0.3)
            love.graphics.ellipse(
                "fill",
                transform.x,
                transform.y + (body.radius or 8) * 0.75,
                (body.radius or 10) * 1.15,
                (body.radius or 10) * 0.45
            )
        end

        local tint = sprite.tint or definition.tint or {1, 1, 1, 1}
        love.graphics.setColor(
            tint[1],
            tint[2],
            tint[3],
            entity.dead and 0.35 or (tint[4] or 1)
        )
        local scale = sprite.scale or definition.scale or 1
        love.graphics.draw(
            image,
            quad,
            transform.x,
            transform.y,
            0,
            scale,
            scale,
            definition.origin_x or definition.frame_width / 2,
            definition.origin_y or definition.frame_height / 2
        )
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function feature:register(host)
    host:registerContentKind("sprite", {validate = validateSprite})
    host:registerComponent("render.sprite", {
        validate = validateComponent,
        create = function(config)
            local definition = host.catalog:get(config.sprite)
            return {
                sprite = config.sprite,
                scale = config.scale,
                tint = config.tint and util.deepCopy(config.tint) or nil,
                clip = definition and definition.default_clip or nil,
                frame = 1,
                elapsed = 0,
            }
        end,
    })
    host:registerSystem(animation_system)
    host:registerSystem(draw_system)
end

return feature
