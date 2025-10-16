-- systems/save.lua
-- Save/Load system with multiple save slots

local save = {}

-- Save slot configuration (3 slots)
save.MAX_SLOTS = 3
save.SAVE_DIRECTORY = "saves"

-- Initialize save system
function save:init()
    -- Ensure save directory exists
    local success = love.filesystem.createDirectory(self.SAVE_DIRECTORY)
    if success then
        print("Save system initialized: " .. love.filesystem.getSaveDirectory())
    else
        print("Warning: Could not create save directory")
    end
end

-- Get save file path for a slot
function save:getSlotPath(slot)
    return self.SAVE_DIRECTORY .. "/save_" .. slot .. ".json"
end

-- Save game to slot
function save:saveGame(slot, data)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return false
    end

    -- Add metadata
    data.timestamp = os.time()
    data.slot = slot

    -- Encode to JSON
    local json_data = self:encodeJSON(data)
    if not json_data then
        print("ERROR: Failed to encode save data")
        return false
    end

    -- Write to file
    local filepath = self:getSlotPath(slot)
    local success, message = love.filesystem.write(filepath, json_data)

    if success then
        print("Game saved to slot " .. slot)
        return true
    else
        print("ERROR: Failed to save game: " .. tostring(message))
        return false
    end
end

-- Load game from slot
function save:loadGame(slot)
    if slot < 1 or slot > self.MAX_SLOTS then
        print("ERROR: Invalid save slot: " .. slot)
        return nil
    end

    local filepath = self:getSlotPath(slot)

    -- Check if file exists
    if not love.filesystem.getInfo(filepath) then
        print("No save file found for slot " .. slot)
        return nil
    end

    -- Read file
    local contents, size = love.filesystem.read(filepath)
    if not contents then
        print("ERROR: Failed to read save file")
        return nil
    end

    -- Decode JSON
    local data = self:decodeJSON(contents)
    if not data then
        print("ERROR: Failed to decode save data")
        return nil
    end

    print("Game loaded from slot " .. slot)
    return data
end

-- Get save slot info (for displaying in load menu)
function save:getSlotInfo(slot)
    local data = self:loadGame(slot)
    if not data then
        return {
            exists = false,
            slot = slot
        }
    end

    return {
        exists = true,
        slot = slot,
        hp = data.hp,
        max_hp = data.max_hp,
        map = data.map,
        x = data.x,
        y = data.y,
        timestamp = data.timestamp,
        time_string = os.date("%Y-%m-%d %H:%M:%S", data.timestamp)
    }
end

-- Get all save slots info
function save:getAllSlotsInfo()
    local slots = {}
    for i = 1, self.MAX_SLOTS do
        slots[i] = self:getSlotInfo(i)
    end
    return slots
end

-- Delete save slot
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

-- Simple JSON encoder (minimal implementation)
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

-- Simple JSON decoder (minimal implementation)
function save:decodeJSON(json_string)
    local data = {}

    -- Remove outer braces and whitespace
    json_string = json_string:gsub("^%s*{%s*", ""):gsub("%s*}%s*$", "")

    -- Split by comma (simple approach)
    for line in json_string:gmatch("[^\n]+") do
        local key, value = line:match('"([^"]+)"%s*:%s*(.+)')
        if key and value then
            -- Remove trailing comma
            value = value:gsub(",%s*$", "")

            -- Parse value
            if value:match('^".*"$') then
                -- String
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

-- Initialize on require
save:init()

return save
