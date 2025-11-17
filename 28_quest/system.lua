-- system.lua
-- System-level runtime handlers (hotkeys, locker, etc.)
-- Keeps main.lua clean by handling system-level events

local system = {}

-- Instance lock (prevents duplicate game instances)
local instance_lock = nil

-- Handle system-level hotkeys
-- Returns true if key was handled, false otherwise
function system.handleHotkey(key, is_mobile, modules)
    -- F11: Toggle fullscreen
    if key == "f11" and not is_mobile then
        -- ToggleFullScreen now handles windowed resolution management internally
        modules.display:ToggleFullScreen()
        pcall(modules.utils.SaveConfig, modules.utils, APP_CONFIG, modules.sound.settings, modules.input.settings, nil)
        modules.lifecycle:resize(love.graphics.getWidth(), love.graphics.getHeight())
        return true
    end

    -- Future system hotkeys can be added here:
    -- F12: Screenshot
    -- Alt+F4: Quit
    -- Ctrl+Q: Quit
    -- etc.

    return false  -- Key not handled
end

-- Prevent duplicate game instances
function system.preventDuplicateInstance(is_mobile)
    if is_mobile or _VERSION ~= "Lua 5.1" then
        return
    end

    local success, result = pcall(require, "locker")
    if success then
        instance_lock = result
        -- Acquire instance lock to prevent duplicate instances
        local lock_success, err = pcall(instance_lock.ProcInit, instance_lock)
        if not lock_success then
            print("Warning: Instance lock failed: " .. tostring(err))
        end
    else
        print("Warning: Could not load locker module: " .. tostring(result))
    end
end

-- Release instance lock on quit
function system.releaseInstanceLock()
    if instance_lock then
        pcall(instance_lock.ProcQuit, instance_lock)
    end
end

-- Cleanup on application quit
function system.cleanup(lifecycle)
    system.releaseInstanceLock()
    lifecycle:quit()
end

return system
