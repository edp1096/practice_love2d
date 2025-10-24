-- systems/save.lua
-- Save/Load system with multiple save slots and Continue feature

local save = {}

save.MAX_SLOTS = 3
save.SAVE_DIRECTORY = "saves"
save.RECENT_SLOT_FILE = "recent_slot.txt"

function save:init()
    local success = love.filesystem.createDirectory(self.SAVE_DIRECTORY)
    if success then
        print("Save system initialized: " .. love.filesystem.getSaveDirectory())
    else
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
    local success = love.filesystem.write(self.RECENT_SLOT_FILE, tostring(slot))
    if success then
        print("Recent slot saved: " .. slot)
    end
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
        local data = self:loadGame(i)
        if data and data.timestamp and data.timestamp > latest_time then
            latest_time = data.timestamp
            most_recent = i
        end
    end

    return most_recent
end

function save:getSlotPath(slot)
    return self.SAVE_DIRECTORY .. "/save_" .. slot .. ".json"
end

function save:saveGame(slot, data)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return false
    end

    data.timestamp = os.time()
    data.slot = slot

    local json_data = self:encodeJSON(data)
    if not json_data then
        print("ERROR: Failed to encode save data")
        return false
    end

    local filepath = self:getSlotPath(slot)
    local success, message = love.filesystem.write(filepath, json_data)

    if success then
        print("Game saved to slot " .. slot)
        self:saveRecentSlot(slot)
        return true
    else
        print("ERROR: Failed to save game: " .. tostring(message))
        return false
    end
end

function save:loadGame(slot)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return nil
    end

    local filepath = self:getSlotPath(slot)

    if not love.filesystem.getInfo(filepath) then
        print("No save file found for slot " .. slot)
        return nil
    end

    local contents, size = love.filesystem.read(filepath)
    if not contents then
        print("ERROR: Failed to read save file")
        return nil
    end

    local data = self:decodeJSON(contents)
    if not data then
        print("ERROR: Failed to decode save data")
        return nil
    end

    print("Game loaded from slot " .. slot)
    self:saveRecentSlot(slot)
    return data
end

function save:getSlotInfo(slot)
    local data = self:loadGame(slot)
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
    local success = love.filesystem.remove(filepath)

    if success then
        print("Deleted save slot " .. slot)
        return true
    else
        print("Failed to delete save slot " .. slot)
        return false
    end
end

function save:deleteAllSlots()
    local deleted_count = 0

    for i = 1, self.MAX_SLOTS do
        if self:deleteSlot(i) then
            deleted_count = deleted_count + 1
        end
    end

    love.filesystem.remove(self.RECENT_SLOT_FILE)

    print("Deleted " .. deleted_count .. " save files")
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

function save:printStatus()
    print("=== Save System Status ===")
    print("Directory: " .. love.filesystem.getSaveDirectory())
    print("Has saves: " .. tostring(self:hasSaveFiles()))
    print("Recent slot: " .. tostring(self:loadRecentSlot()))

    for i = 1, self.MAX_SLOTS do
        local info = self:getSlotInfo(i)
        if info.exists then
            print(string.format("Slot %d: %s (HP: %d/%d)",
                i, info.map_display, info.hp, info.max_hp))
        else
            print(string.format("Slot %d: Empty", i))
        end
    end
    print("========================")
end

function save:encodeJSON(data)
    local json = "{\n"
    local items = {}

    for k, v in pairs(data) do
        local key = '"' .. tostring(k) .. '"'
        local value

        if type(v) == "string" then
            value = '"' .. v .. '"'
        elseif type(v) == "number" then
            value = tostring(v)
        elseif type(v) == "boolean" then
            value = tostring(v)
        else
            value = '"' .. tostring(v) .. '"'
        end

        table.insert(items, '  ' .. key .. ': ' .. value)
    end

    json = json .. table.concat(items, ',\n') .. '\n}'
    return json
end

function save:decodeJSON(json_string)
    local data = {}

    json_string = json_string:gsub("^%s*{%s*", ""):gsub("%s*}%s*$", "")

    for line in json_string:gmatch("[^\n]+") do
        local key, value = line:match('"([^"]+)"%s*:%s*(.+)')
        if key and value then
            value = value:gsub(",%s*$", "")

            if value:match('^".*"$') then
                data[key] = value:match('^"(.*)"$')
            elseif value == "true" then
                data[key] = true
            elseif value == "false" then
                data[key] = false
            elseif tonumber(value) then
                data[key] = tonumber(value)
            end
        end
    end

    return data
end

save:init()

return save
