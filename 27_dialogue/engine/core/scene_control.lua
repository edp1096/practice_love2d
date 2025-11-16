-- engine/scene_control.lua
-- Simple scene control system with sound system integration

local scene_control = {}

scene_control.current = nil
scene_control.previous = nil

-- Scene cache (loaded lazily)
local scene_cache = {}

-- Scene loader function (injected from game code)
scene_control.scene_loader = nil

-- Lazy load sound system
local sound

local function get_sound()
    if not sound then
        local success, result = pcall(require, "engine.core.sound")
        if success then
            sound = result
        end
    end
    return sound
end

-- Load scene by name (string) or use existing scene object
local function load_scene(scene_or_name)
    -- If it's already a scene object, return it
    if type(scene_or_name) == "table" then
        return scene_or_name
    end

    -- If it's a string, load from cache or use injected loader
    if type(scene_or_name) == "string" then
        if not scene_cache[scene_or_name] then
            if not scene_control.scene_loader then
                error("scene_control.scene_loader not configured! Set it in main.lua before loading scenes.")
            end
            -- Use injected scene loader
            scene_cache[scene_or_name] = scene_control.scene_loader(scene_or_name)
        end
        return scene_cache[scene_or_name]
    end

    error("Invalid scene: must be table or string")
end

-- Switch to a new scene (accepts scene object or string name)
function scene_control.switch(scene_or_name, ...)
    local scene = load_scene(scene_or_name)

    -- Call exit callback on current scene
    if scene_control.current and scene_control.current.exit then
        scene_control.current:exit()
    end

    scene_control.previous = scene_control.current -- Store previous scene
    scene_control.current = scene                  -- Switch to new scene

    -- Call enter callback on new scene
    if scene_control.current and scene_control.current.enter then
        scene_control.current:enter(scene_control.previous, ...)
    else
        print("WARNING: New scene has no enter callback")
    end
end

-- Push a scene (keeps current scene in background, like pause menu)
function scene_control.push(scene_or_name, ...)
    local scene = load_scene(scene_or_name)

    -- Don't exit current scene, just call pause
    if scene_control.current and scene_control.current.pause then
        scene_control.current:pause()
    end

    scene_control.previous = scene_control.current
    scene_control.current = scene

    if scene_control.current and scene_control.current.enter then
        scene_control.current:enter(scene_control.previous, ...)
    end
end

-- Pop back to previous scene (return from pause menu)
function scene_control.pop()
    if not scene_control.previous then return end

    -- Call exit on current scene
    if scene_control.current and scene_control.current.exit then
        scene_control.current:exit()
    end

    -- Restore previous scene
    scene_control.current = scene_control.previous
    scene_control.previous = nil

    -- Resume the scene
    if scene_control.current and scene_control.current.resume then
        scene_control.current:resume()
    end
end

-- Route LÖVE callbacks to current scene
function scene_control.update(dt)
    -- Update sound system (cleanup, memory monitoring)
    local snd = get_sound()
    if snd and snd.update then
        snd:update(dt)
    end

    if scene_control.current and scene_control.current.update then
        scene_control.current:update(dt)
    end
end

function scene_control.draw()
    if scene_control.current and scene_control.current.draw then
        scene_control.current:draw()
    end
end

function scene_control.keypressed(key)
    if scene_control.current and scene_control.current.keypressed then
        scene_control.current:keypressed(key)
    end
end

function scene_control.keyreleased(key)
    if scene_control.current and scene_control.current.keyreleased then
        scene_control.current:keyreleased(key)
    end
end

function scene_control.mousepressed(x, y, button)
    if scene_control.current and scene_control.current.mousepressed then
        scene_control.current:mousepressed(x, y, button)
    end
end

function scene_control.mousereleased(x, y, button)
    if scene_control.current and scene_control.current.mousereleased then
        scene_control.current:mousereleased(x, y, button)
    end
end

function scene_control.mousemoved(x, y, dx, dy)
    if scene_control.current and scene_control.current.mousemoved then
        scene_control.current:mousemoved(x, y, dx, dy)
    end
end

function scene_control.gamepadpressed(joystick, button)
    if scene_control.current and scene_control.current.gamepadpressed then
        scene_control.current:gamepadpressed(joystick, button)
    end
end

function scene_control.gamepadreleased(joystick, button)
    if scene_control.current and scene_control.current.gamepadreleased then
        scene_control.current:gamepadreleased(joystick, button)
    end
end

function scene_control.gamepadaxis(joystick, axis, value)
    if scene_control.current and scene_control.current.gamepadaxis then
        scene_control.current:gamepadaxis(joystick, axis, value)
    end
end

function scene_control.resize(w, h)
    if scene_control.current and scene_control.current.resize then
        scene_control.current:resize(w, h)
    end
end

return scene_control
