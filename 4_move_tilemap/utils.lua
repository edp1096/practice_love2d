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


function utils:SaveConfig(GameConfig)
    local file = io.open("config.ini", "w")
    if file then
        file:write("Title = " .. GameConfig.title .. "\n")
        file:write("Author = " .. GameConfig.author .. "\n")
        file:write("\n")
        file:write("[Window]\n")
        file:write("Width = " .. GameConfig.width .. "\n")
        file:write("Height = " .. GameConfig.height .. "\n")
        file:write("Resizable = " .. tostring(GameConfig.resizable) .. "\n")
        file:write("FullScreen = " .. tostring(GameConfig.fullscreen) .. "\n")
        file:write("Monitor = " .. GameConfig.monitor .. "\n")
        file:write("ScaleMode = " .. GameConfig.scale_mode .. "\n")
        file:close()
    end
end


return utils