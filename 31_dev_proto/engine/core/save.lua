-- systems/save.lua
-- Save/Load system with multiple save slots and Continue feature

local save = {}
local save_codec = require "engine.core.save_codec"

save.MAX_SLOTS = 3
save.SAVE_DIRECTORY = "saves"
save.RECENT_SLOT_FILE = "recent_slot.txt"

function save:init()
    local success = love.filesystem.createDirectory(self.SAVE_DIRECTORY)
    if not success then
        print("Warning: Could not create save directory")
    end
end

function save:parseMapPath(map_path)
    if not map_path then
        return nil, nil
    end

    local level = map_path:match("level(%d+)")
    local area = map_path:match("area(%d+)")

    return tonumber(level), tonumber(area)
end

function save:formatMapInfo(map_path)
    local level, area = self:parseMapPath(map_path)

    if level and area then
        return string.format("Level %d - Area %d", level, area)
    else
        return "Unknown Location"
    end
end

function save:saveRecentSlot(slot)
    love.filesystem.write(self.RECENT_SLOT_FILE, tostring(slot))
end

function save:loadRecentSlot()
    local contents = love.filesystem.read(self.RECENT_SLOT_FILE)
    if contents then
        local slot = tonumber(contents)
        if slot and slot >= 1 and slot <= self.MAX_SLOTS then
            return slot
        end
    end
    return nil
end

function save:hasSaveFiles()
    for i = 1, self.MAX_SLOTS do
        local filepath = self:getSlotPath(i)
        if love.filesystem.getInfo(filepath) then
            return true
        end
    end
    return false
end

function save:getMostRecentSlot()
    local recent_slot = self:loadRecentSlot()
    if recent_slot then
        local filepath = self:getSlotPath(recent_slot)
        if love.filesystem.getInfo(filepath) then
            return recent_slot
        end
    end

    local most_recent = nil
    local latest_time = 0

    for i = 1, self.MAX_SLOTS do
        local data = self:loadGame(i, false)
        if data and data.timestamp and data.timestamp > latest_time then
            latest_time = data.timestamp
            most_recent = i
        end
    end

    return most_recent
end

function save:getSlotPath(slot)
    return self.SAVE_DIRECTORY .. "/save_" .. slot .. ".lua"
end

function save:serialize(value)
    return save_codec.encode(value)
end

-- Deserialize string to Lua table
function save:deserialize(str)
    local result, err = save_codec.decode(str)
    if type(result) ~= "table" then
        print("ERROR: Failed to deserialize: " .. tostring(err))
        return nil
    end
    return result
end

function save:saveGame(slot, data)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return false
    end

    data.timestamp = os.time()
    data.slot = slot

    local serialized, serialize_error = self:serialize(data)
    if not serialized then
        print("ERROR: Failed to serialize save data: " ..
              tostring(serialize_error))
        return false
    end

    local filepath = self:getSlotPath(slot)
    local success, message = love.filesystem.write(filepath, serialized)

    if success then
        self:saveRecentSlot(slot)
        return true
    else
        print("ERROR: Failed to save game: " .. tostring(message))
        return false
    end
end

function save:loadGame(slot, mark_recent)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return nil
    end

    local filepath = self:getSlotPath(slot)

    if not love.filesystem.getInfo(filepath) then
        return nil  -- No save file - normal case, no need to print
    end

    local contents, size = love.filesystem.read(filepath)
    if not contents then
        print("ERROR: Failed to read save file")
        return nil
    end

    local data = self:deserialize(contents)
    if not data then
        print("ERROR: Failed to deserialize save data")
        return nil
    end

    if mark_recent ~= false then
        self:saveRecentSlot(slot)
    end
    return data
end

function save:getSlotInfo(slot)
    local data = self:loadGame(slot, false)
    if not data then
        return {
            exists = false,
            slot = slot
        }
    end

    local level, area = self:parseMapPath(data.map)
    local map_display = self:formatMapInfo(data.map)

    return {
        exists = true,
        slot = slot,
        hp = data.hp,
        max_hp = data.max_hp,
        map = data.map,
        level = level,
        area = area,
        map_display = map_display,
        x = data.x,
        y = data.y,
        timestamp = data.timestamp,
        time_string = os.date("%Y-%m-%d %H:%M:%S", data.timestamp)
    }
end

function save:getAllSlotsInfo()
    local slots = {}
    for i = 1, self.MAX_SLOTS do
        slots[i] = self:getSlotInfo(i)
    end
    return slots
end

function save:deleteSlot(slot)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return false
    end

    local filepath = self:getSlotPath(slot)
    return love.filesystem.remove(filepath)
end

function save:deleteAllSlots()
    local deleted_count = 0

    for i = 1, self.MAX_SLOTS do
        if self:deleteSlot(i) then
            deleted_count = deleted_count + 1
        end
    end

    love.filesystem.remove(self.RECENT_SLOT_FILE)
    return deleted_count
end

function save:getSaveDirectory()
    return love.filesystem.getSaveDirectory()
end

function save:openSaveFolder()
    local save_dir = love.filesystem.getSaveDirectory()
    local os_name = love.system.getOS()

    if os_name == "Windows" then
        os.execute('explorer "' .. save_dir .. '"')
    elseif os_name == "Linux" then
        os.execute('xdg-open "' .. save_dir .. '"')
    elseif os_name == "OS X" then
        os.execute('open "' .. save_dir .. '"')
    else
        print("Cannot open folder on this OS: " .. os_name)
        print("Save directory: " .. save_dir)
    end
end

-- Mark an intro as viewed (adds to current session's viewed_intros)
function save:markIntroAsViewed(intro_id)
    if not intro_id then return end

    -- Ensure viewed_intros table exists in current save
    if not self.current_save then
        self.current_save = {}
    end
    if not self.current_save.viewed_intros then
        self.current_save.viewed_intros = {}
    end

    self.current_save.viewed_intros[intro_id] = true
end

-- Check if an intro has been viewed
function save:hasViewedIntro(intro_id)
    if not intro_id then return false end
    if not self.current_save then return false end
    if not self.current_save.viewed_intros then return false end

    return self.current_save.viewed_intros[intro_id] or false
end

function save:printStatus()
    dprint("=== Save System Status ===")
    dprint("Directory: " .. love.filesystem.getSaveDirectory())
    dprint("Has saves: " .. tostring(self:hasSaveFiles()))
    dprint("Recent slot: " .. tostring(self:loadRecentSlot()))

    for i = 1, self.MAX_SLOTS do
        local info = self:getSlotInfo(i)
        if info.exists then
            dprint(string.format("Slot %d: %s (HP: %d/%d)",
                i, info.map_display, info.hp, info.max_hp))
        else
            dprint(string.format("Slot %d: Empty", i))
        end
    end
    dprint("========================")
end

save:init()

return save
