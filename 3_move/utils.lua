local utils = {}

function utils:DeepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) == "table" then
                self:DeepMerge(target[k], v)
            else
                target[k] = v
            end
        else
            target[k] = v
        end
    end

    return target
end

-- https://stackoverflow.com/a/26367080/31289713
function utils:DeepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end

    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res

    for k, v in pairs(obj) do
        res[self:DeepCopy(k, s)] = self:DeepCopy(v, s)
    end

    return res
end

return utils