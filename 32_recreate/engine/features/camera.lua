local util = require "engine.core.util"

local feature = {
    id = "camera",
    requires = {"engine.features.world"},
}

local function validateCamera(config, validator, path)
    if config == nil then return end
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {"viewport_width", "viewport_height", "follow_tag"},
        path
    )
    validator:positive(
        config.viewport_width,
        path .. ".viewport_width",
        true
    )
    validator:positive(
        config.viewport_height,
        path .. ".viewport_height",
        true
    )
    validator:string(config.follow_tag, path .. ".follow_tag", false)
end

local camera = {}

local function centeredAxis(position, viewport_size, stage_size)
    if stage_size <= viewport_size then
        return (stage_size - viewport_size) / 2
    end
    return util.clamp(
        position - viewport_size / 2,
        0,
        stage_size - viewport_size
    )
end

function camera:snap(world)
    local state = world.feature_state.camera
    if not state then return end
    local target = world:findByTag(state.follow_tag)[1]
    local transform = target and target.components.transform
    local target_x = transform and transform.x or world.stage.width / 2
    local target_y = transform and transform.y or world.stage.height / 2
    state.x = centeredAxis(
        target_x,
        state.width,
        world.stage.width
    )
    state.y = centeredAxis(
        target_y,
        state.height,
        world.stage.height
    )
    state.target_id = target and target.id or nil
end

function camera:view(world)
    local state = world.feature_state.camera
    if not state then
        return {
            x = 0,
            y = 0,
            width = world.stage.width,
            height = world.stage.height,
        }
    end
    return {
        x = state.x,
        y = state.y,
        width = state.width,
        height = state.height,
        target_id = state.target_id,
    }
end

local camera_system = {
    id = "camera.follow",
    phase = "presentation",
    order = 100,
}

function camera_system:update(world)
    camera:snap(world)
end

function feature:register(host)
    host:registerService("camera", camera)
    host:registerStageSection("camera", {
        priority = 90,
        validate = validateCamera,
        load = function(world, config, stage)
            config = config or {}
            world.feature_state.camera = {
                x = 0,
                y = 0,
                width = config.viewport_width or stage.width,
                height = config.viewport_height or stage.height,
                follow_tag = config.follow_tag or "player",
                target_id = nil,
            }
            camera:snap(world)
            return true
        end,
    })
    host:registerWorldInspector("camera", function(world)
        return {camera = camera:view(world)}
    end)
    host:registerSystem(camera_system)
end

return feature
