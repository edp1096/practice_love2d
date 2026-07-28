-- engine/core/debug/helpers.lua
-- Helper functions for debug system

local helpers = {}

-- Get quest debug information
function helpers.getQuestDebugInfo(quest_sys)
    local info = {}

    if not quest_sys or not quest_sys.quest_states then
        table.insert(info, "No quest system")
        return info
    end

    -- Count quests by state
    local counts = {
        available = 0,
        active = 0,
        completed = 0,
        turned_in = 0
    }

    for quest_id, state in pairs(quest_sys.quest_states) do
        if state and state.state then
            counts[state.state] = (counts[state.state] or 0) + 1
        end
    end

    table.insert(info, string.format("AVA:%d ACT:%d CMP:%d TIN:%d",
        counts.available, counts.active, counts.completed, counts.turned_in))

    -- Show specific quest states (limited to 5 most relevant)
    local shown = 0
    local max_show = 5

    -- Priority 1: Active quests
    for quest_id, state in pairs(quest_sys.quest_states) do
        if shown >= max_show then break end
        if state.state == quest_sys.STATE.ACTIVE then
            local def = quest_sys.quest_registry[quest_id]
            local title = def and def.title or quest_id
            table.insert(info, string.format("ACT: %s", title:sub(1, 20)))
            shown = shown + 1
        end
    end

    -- Priority 2: Completed quests
    for quest_id, state in pairs(quest_sys.quest_states) do
        if shown >= max_show then break end
        if state.state == quest_sys.STATE.COMPLETED then
            local def = quest_sys.quest_registry[quest_id]
            local title = def and def.title or quest_id
            table.insert(info, string.format("CMP: %s", title:sub(1, 20)))
            shown = shown + 1
        end
    end

    -- Priority 3: Show tutorial_talk specifically
    if shown < max_show then
        local tutorial_state = quest_sys.quest_states["tutorial_talk"]
        if tutorial_state then
            table.insert(info, string.format("tutorial: %s", tutorial_state.state))
            shown = shown + 1
        end
    end

    return info
end

-- Format angle to readable math expression
function helpers.formatAngle(angle)
    if not angle then return "nil" end

    local pi = math.pi
    local tolerance = 0.01

    local angles = {
        { value = 0,           str = "0" },
        { value = pi / 6,      str = "math.pi / 6" },
        { value = pi / 4,      str = "math.pi / 4" },
        { value = pi / 3,      str = "math.pi / 3" },
        { value = pi / 2,      str = "math.pi / 2" },
        { value = pi * 2 / 3,  str = "math.pi * 2 / 3" },
        { value = pi * 3 / 4,  str = "math.pi * 3 / 4" },
        { value = pi * 5 / 6,  str = "math.pi * 5 / 6" },
        { value = pi,          str = "math.pi" },
        { value = -pi / 6,     str = "-math.pi / 6" },
        { value = -pi / 4,     str = "-math.pi / 4" },
        { value = -pi / 3,     str = "-math.pi / 3" },
        { value = -pi / 2,     str = "-math.pi / 2" },
        { value = pi * 5 / 12, str = "math.pi * 5 / 12" },
        { value = pi * 7 / 12, str = "math.pi * 7 / 12" },
    }

    for _, entry in ipairs(angles) do
        if math.abs(angle - entry.value) < tolerance then
            return entry.str
        end
    end

    return string.format("%.4f", angle)
end

-- Get frame count for animation
function helpers.getFrameCount(anim_name)
    local counts = {
        idle_right = 4,
        idle_left = 4,
        idle_up = 4,
        idle_down = 4,
        walk_right = 6,
        walk_left = 6,
        walk_up = 4,
        walk_down = 4,
        attack_right = 4,
        attack_left = 4,
        attack_up = 4,
        attack_down = 4
    }
    return counts[anim_name] or 4
end

return helpers
