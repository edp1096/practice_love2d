local Schema = require "engine.runtime.session_schema"
local util = require "engine.core.util"

local feature = {
    id = "accessibility",
    requires = {
        "engine.features.session",
        "engine.features.world",
    },
}

local motion_values = {"full", "reduced", "off"}
local notice_values = {"normal", "long"}

local function contains(values, candidate)
    for _, value in ipairs(values) do
        if value == candidate then return true end
    end
    return false
end

local function nextValue(values, current, direction)
    local index = 1
    for candidate, value in ipairs(values) do
        if value == current then
            index = candidate
            break
        end
    end
    direction = direction and direction < 0 and -1 or 1
    return values[(index - 1 + direction) % #values + 1]
end

function feature:register(host)
    local settings = host.services.session:registerSection(
        "accessibility.settings",
        {
            version = 1,
            persistent = true,
            defaults = {
                motion = "full",
                hit_flash = true,
                notice_duration = "normal",
            },
            validate = function(value)
                local valid, value_error = Schema.object(
                    value,
                    "accessibility.settings",
                    {"motion", "hit_flash", "notice_duration"},
                    {"motion", "hit_flash", "notice_duration"}
                )
                if not valid then return nil, value_error end
                if not contains(motion_values, value.motion) then
                    return nil, "accessibility.settings.motion must be " ..
                        "full, reduced, or off"
                end
                if type(value.hit_flash) ~= "boolean" then
                    return nil,
                        "accessibility.settings.hit_flash must be a boolean"
                end
                if not contains(notice_values, value.notice_duration) then
                    return nil,
                        "accessibility.settings.notice_duration must be " ..
                        "normal or long"
                end
                return true
            end,
        }
    )

    local accessibility = {}

    function accessibility:motion()
        return settings.motion
    end

    function accessibility:motionScale()
        if settings.motion == "off" then return 0 end
        if settings.motion == "reduced" then return 0.35 end
        return 1
    end

    function accessibility:hitFlashEnabled()
        return settings.hit_flash
    end

    function accessibility:noticeScale()
        return settings.notice_duration == "long" and 2 or 1
    end

    function accessibility:inspect()
        return util.deepCopy(settings)
    end

    function accessibility:cycle(name, direction)
        if name == "motion" then
            settings.motion =
                nextValue(motion_values, settings.motion, direction)
        elseif name == "hit_flash" then
            settings.hit_flash = not settings.hit_flash
        elseif name == "notice_duration" then
            settings.notice_duration =
                nextValue(
                    notice_values,
                    settings.notice_duration,
                    direction
                )
        else
            return nil, "unknown accessibility setting '" ..
                tostring(name) .. "'"
        end
        return self:inspect()
    end

    host:registerService("accessibility", accessibility)
    host:registerWorldInspector("accessibility", function()
        return {
            accessibility = accessibility:inspect(),
        }
    end)
end

return feature
