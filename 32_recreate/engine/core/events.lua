local Events = {}
Events.__index = Events

function Events.new(history_limit)
    return setmetatable({
        listeners = {},
        history = {},
        history_limit = history_limit or 100,
        sequence = 0,
    }, Events)
end

function Events:on(name, handler)
    assert(type(name) == "string" and name ~= "", "event name is required")
    assert(type(handler) == "function", "event handler must be a function")

    local listeners = self.listeners[name]
    if not listeners then
        listeners = {}
        self.listeners[name] = listeners
    end
    listeners[#listeners + 1] = handler

    local active = true
    return function()
        if not active then return end
        active = false
        for index, candidate in ipairs(listeners) do
            if candidate == handler then
                table.remove(listeners, index)
                return
            end
        end
    end
end

function Events:emit(name, payload)
    self.sequence = self.sequence + 1
    local record = {
        sequence = self.sequence,
        name = name,
        payload = payload or {},
    }
    self.history[#self.history + 1] = record
    if #self.history > self.history_limit then
        table.remove(self.history, 1)
    end

    local listeners = self.listeners[name]
    if not listeners then return record end

    local snapshot = {}
    for index, handler in ipairs(listeners) do
        snapshot[index] = handler
    end
    for _, handler in ipairs(snapshot) do
        handler(record.payload, record)
    end
    return record
end

function Events:recent(limit)
    limit = math.max(0, math.floor(limit or 20))
    local first = math.max(1, #self.history - limit + 1)
    local result = {}
    for index = first, #self.history do
        result[#result + 1] = self.history[index]
    end
    return result
end

return Events
