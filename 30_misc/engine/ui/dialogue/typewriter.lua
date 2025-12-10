-- engine/ui/dialogue/typewriter.lua
-- Typewriter effect system for dialogue

local utf8 = require "utf8"

local typewriter = {}

-- Update typewriter effect
-- Returns: true if still typing, false if complete
function typewriter:update(dialogue, dt)
    if dialogue.typewriter_complete then
        return false
    end

    local current_text = dialogue.current_text or ""
    if dialogue.showing_paged_text and dialogue.current_pages then
        current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
    end

    local text_length = utf8.len(current_text) or 0
    local prev_pos = math.floor(dialogue.typewriter_position)
    dialogue.typewriter_position = dialogue.typewriter_position + (dt / dialogue.typewriter_speed)
    local new_pos = math.floor(dialogue.typewriter_position)

    -- Play typing sound at intervals (skip if typing_sound is "none" or "")
    if new_pos > prev_pos and dialogue.typing_sound and dialogue.typing_sound ~= "" and dialogue.typing_sound ~= "none" then
        local sound_pos = math.floor(new_pos / dialogue.typewriter_sound_interval)
        local last_sound_pos = math.floor(dialogue.typewriter_last_sound_pos / dialogue.typewriter_sound_interval)
        if sound_pos > last_sound_pos then
            local sound_sys = require "engine.core.sound"
            sound_sys:playSFX("ui", dialogue.typing_sound)
            dialogue.typewriter_last_sound_pos = new_pos
        end
    end

    if dialogue.typewriter_position >= text_length then
        dialogue.typewriter_position = text_length
        dialogue.typewriter_complete = true
        return false
    end

    return true
end

-- Skip typewriter to completion
function typewriter:skip(dialogue)
    if dialogue.typewriter_complete then
        return false
    end

    dialogue.typewriter_complete = true
    local current_text = dialogue.current_text or ""
    if dialogue.showing_paged_text and dialogue.current_pages then
        current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
    end
    dialogue.typewriter_position = utf8.len(current_text) or 0
    return true
end

-- Reset typewriter state
function typewriter:reset(dialogue)
    dialogue.typewriter_position = 0
    dialogue.typewriter_complete = false
    dialogue.typewriter_last_sound_pos = 0
end

-- Get current visible text (truncated by typewriter position)
function typewriter:getVisibleText(dialogue)
    local current_text = dialogue.current_text or ""
    if dialogue.showing_paged_text and dialogue.current_pages then
        current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
    end

    if dialogue.typewriter_complete then
        return current_text
    end

    -- Truncate to current position using UTF-8 aware substring
    local pos = math.floor(dialogue.typewriter_position)
    if pos <= 0 then
        return ""
    end

    -- UTF-8 safe substring
    local byte_pos = utf8.offset(current_text, pos + 1)
    if byte_pos then
        return current_text:sub(1, byte_pos - 1)
    end

    return current_text
end

-- Check if typewriter is complete
function typewriter:isComplete(dialogue)
    return dialogue.typewriter_complete
end

return typewriter
