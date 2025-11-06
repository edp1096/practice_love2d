local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and " .. _VERSION)

local screen = require "lib.screen"

local logo


function love.load()
    -- Initialize screen system with config
    local config = {
        fullscreen = false,
        monitor = 1
    }
    screen:Initialize(config)

    logo = love.graphics.newImage("assets/images/logo.png")
end

function love.draw()
    screen:Attach()
    love.graphics.draw(logo, 0, 0)
    screen:Detach()

    if is_debug then
        screen:ShowDebugInfo()
        screen:ShowGridVisualization()
        screen:ShowVirtualMouse()
    end
end

function love.resize(w, h)
    screen:Resize(w, h)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f10" then
        local scale_mode = screen:GetScaleMode()
        print("ScaleMode: " .. scale_mode)
        if scale_mode == "fit" then
            screen:SetScaleMode("fill")
            print("Switched to fill mode")
        elseif scale_mode == "fill" then
            screen:SetScaleMode("stretch")
            print("Switched to stretch mode")
        else
            screen:SetScaleMode("fit")
            print("Switched to fit mode")
        end
    elseif key == "f11" then
        screen:ToggleFullScreen()
    elseif key == "f12" then
        is_debug = not is_debug
        print("Debug mode: " .. tostring(is_debug))
    end
end
