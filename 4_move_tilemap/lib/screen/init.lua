-- local virtual_resolution = require "lib.virtual_resolution"
local cwd = (...) .. "."
local virtual_resolution = require(cwd .. "virtual_resolution")

local screen = {
    is_fullscreen = false,
    scale_mode = "fit",
    render_wh = { w = 1280, h = 720 },     -- Rendering size
    screen_wh = { w = 0, h = 0 },          -- Window screen size
    previous_screen_wh = { w = 0, h = 0 }, -- Previous screen size
    previous_xy = { x = 0, y = 0 },        -- Previous window position
    window = {
        fullscreen = false,                -- Not use
        fullscreentype = "desktop",
        vsync = true,
        resizable = true,
        borderless = false,
        centered = true,
        display = 1,
        highdpi = false,
        minwidth = 640,
        minheight = 360,
        x = 0,
        y = 0
    },
    filter = {
        min = "nearest",
        mag = "nearest",
        anisotropy = 1
    }
}

function screen:Initialize(config)
    self.window.display = config.Monitor

    local dx, dy = love.window.getDesktopDimensions(config.Monitor)
    self.window.x, self.window.y = dx / 2 - self.render_wh.w / 2, dy / 2 - self.render_wh.h / 2

    virtual_resolution:Set(self.render_wh.w, self.render_wh.h)
    self.scale_mode = config.scale_mode
    virtual_resolution:setScaleMode(self.scale_mode)

    love.graphics.setDefaultFilter(self.filter.min, self.filter.mag, self.filter.anisotropy)

    self.screen_wh.w, self.screen_wh.h = love.graphics.getDimensions()
    self.previous_screen_wh.w, self.previous_screen_wh.h = love.graphics.getDimensions()
    self.previous_xy.x, self.previous_xy.y = love.window.getPosition()

    if config.fullscreen then self:ToggleFullScreen() end
end

function screen:ToggleFullScreen()
    if not self.is_fullscreen then
        self.previous_xy.x, self.previous_xy.y = love.window.getPosition()

        self.screen_wh.w, self.screen_wh.h = love.window.getDesktopDimensions(self.window.display)
        self.window.x, self.window.y = 0, 0
        self.window.resizable = false
        self.window.borderless = true
    else
        self.window.x, self.window.y = self.previous_xy.x, self.previous_xy.y
        self.previous_xy.x, self.previous_xy.y = love.window.getPosition()
        self.screen_wh.w, self.screen_wh.h = self.previous_screen_wh.w, self.previous_screen_wh.h
        self.window.resizable = true
        self.window.borderless = false
    end

    love.window.setMode(self.screen_wh.w, self.screen_wh.h, self.window)
    virtual_resolution:Set(self.render_wh.w, self.render_wh.h)
    virtual_resolution:setScaleMode(self.scale_mode)

    self.is_fullscreen = not self.is_fullscreen
end

function screen:Resize()
    virtual_resolution:resize()
end

function screen:Attatch()
    virtual_resolution:Attatch()
end

function screen:Detatch()
    virtual_resolution:Detatch()
end

function screen:GetScaleMode()
    return virtual_resolution:getScaleMode()
end

function screen:SetScaleMode(mode)
    self.scale_mode = mode
    virtual_resolution:setScaleMode(mode)
end

function screen:ShowDebugInfo()
    virtual_resolution:ShowDebugInfo()
end

return screen
