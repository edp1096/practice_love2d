local Events = {}
Events.__index = Events

function Events.new(history_limit)
    return setmetatable({
        listeners = {},
        history = {},
        history_limit = history_limit or 100,
        sequence = 0,
        transactions = {},
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

local function dispatch(self, record)
    local listeners = self.listeners[record.name]
    if not listeners then return end

    local snapshot = {}
    for index, handler in ipairs(listeners) do
        snapshot[index] = handler
    end
    for _, handler in ipairs(snapshot) do
        handler(record.payload, record)
    end
end

local function appendHistory(self, record)
    self.history[#self.history + 1] = record
    if #self.history > self.history_limit then
        table.remove(self.history, 1)
    end
end

function Events:beginTransaction()
    local transaction = {
        events = {},
    }
    self.transactions[#self.transactions + 1] = transaction
    return transaction
end

function Events:_requireTop(transaction)
    assert(
        self.transactions[#self.transactions] == transaction,
        "event transactions must finish in reverse order"
    )
end

function Events:commitTransaction(transaction)
    self:_requireTop(transaction)
    if #self.transactions > 1 then
        table.remove(self.transactions)
        local parent = self.transactions[#self.transactions]
        for _, pending in ipairs(transaction.events) do
            parent.events[#parent.events + 1] = pending
        end
        return true
    end

    local index = 1
    while index <= #transaction.events do
        local pending = transaction.events[index]
        local record = {
            sequence = self.sequence + index,
            name = pending.name,
            payload = pending.payload,
        }
        pending.record = record
        dispatch(self, record)
        index = index + 1
    end

    table.remove(self.transactions)
    for _, pending in ipairs(transaction.events) do
        self.sequence = self.sequence + 1
        local record = pending.record or {
            sequence = self.sequence,
            name = pending.name,
            payload = pending.payload,
        }
        record.sequence = self.sequence
        appendHistory(self, record)
    end
    return true
end

function Events:rollbackTransaction(transaction)
    self:_requireTop(transaction)
    table.remove(self.transactions)
    return true
end

function Events:emit(name, payload)
    assert(type(name) == "string" and name ~= "", "event name is required")
    local transaction = self.transactions[#self.transactions]
    if transaction then
        local pending = {
            name = name,
            payload = payload or {},
        }
        transaction.events[#transaction.events + 1] = pending
        return {
            pending = true,
            name = name,
            payload = pending.payload,
        }
    end

    self.sequence = self.sequence + 1
    local record = {
        sequence = self.sequence,
        name = name,
        payload = payload or {},
    }
    dispatch(self, record)
    appendHistory(self, record)
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
