-- engine/display/init.lua
-- Virtual screen system with scaling, letterboxing, and multi-platform support
--
-- PUBLIC API (frequently used):
--   GetVirtualDimensions() - Get virtual resolution (960x540)
--   GetScreenDimensions() - Get physical screen size
--   Attach() / Detach() - Begin/end virtual coordinate rendering
--   ToVirtualCoords(x, y) - Convert screen coords to virtual coords
--   GetVirtualMousePosition() - Get mouse/touch position in virtual coords
--   ToggleFullScreen() - Toggle fullscreen (desktop only)
--   Resize(w, h) - Handle window resize events
--
-- INTERNAL API (used by module or debug only):
--   GetAllTouches() - Get all touch points (mobile debug)
--   ShowVirtualMouse() - Debug virtual mouse cursor overlay
--   GetOffset() / GetScale() - Internal coordinate transform data
--   SetScaleMode(mode) - Internal use during initialization
--   GetVisibleVirtualBounds() - Internal coordinate calculations

local screen = {
    is_fullscreen = false,
    scale_mode = "fit",
    render_wh = { w = 960, h = 540 },
    screen_wh = { w = 0, h = 0 },
    previous_screen_wh = { w = 0, h = 0 },
    previous_xy = { x = 0, y = 0 },
    physical_bounds = { x = 0, y = 0, w = 0, h = 0 },
    window = {
        fullscreen = false,
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
    },
    scale = 1,
    offset_x = 0,
    offset_y = 0,
    -- Android/Mobile detection
    is_mobile = false,
    is_android = false,
    dpi_scale = 1
}

-- Detect platform
function screen:DetectPlatform()
    local os_name = love.system.getOS()
    self.is_android = (os_name == "Android")
    self.is_mobile = (os_name == "Android" or os_name == "iOS")

    -- Get DPI scale for high-resolution displays
    if self.is_mobile then
        local dpi_scale = love.window.getDPIScale()
        if dpi_scale and dpi_scale > 0 then
            self.dpi_scale = dpi_scale
        end
    end
end

function screen:Initialize(config)
    self:DetectPlatform()

    love.graphics.setDefaultFilter(self.filter.min, self.filter.mag, self.filter.anisotropy)

    -- Get initial dimensions
    self.screen_wh.w, self.screen_wh.h = love.graphics.getDimensions()
    self.previous_screen_wh.w, self.previous_screen_wh.h = self.screen_wh.w, self.screen_wh.h

    if not self.is_mobile then
        -- Desktop: normal window handling
        self.window.display = config.monitor or 1

        local success, dx, dy = pcall(love.window.getDesktopDimensions, self.window.display)
        if success and dx and dy then
            self.window.x = dx / 2 - self.render_wh.w / 2
            self.window.y = dy / 2 - self.render_wh.h / 2
        end

        local success2, x, y = pcall(love.window.getPosition)
        if success2 and x and y then
            self.previous_xy.x, self.previous_xy.y = x, y
        end

        if self.window.display ~= 1 then
            pcall(love.window.updateMode, self.screen_wh.w, self.screen_wh.h, self.window)
        end

        if config.fullscreen then
            self:EnableFullScreen()
        end
    else
        -- Mobile: always fullscreen
        self.is_fullscreen = true
        print("Running on mobile platform: " .. love.system.getOS())
        print("Screen dimensions: " .. self.screen_wh.w .. "x" .. self.screen_wh.h)
        print("DPI scale: " .. self.dpi_scale)
    end

    self:CalculateScale()
end

function screen:EnableFullScreen()
    if self.is_mobile then return end -- Already fullscreen on mobile
    if self.is_fullscreen then return end

    local success, x, y = pcall(love.window.getPosition)
    if success and x and y then
        self.previous_xy.x, self.previous_xy.y = x, y
    end

    self.previous_screen_wh.w, self.previous_screen_wh.h = self.screen_wh.w, self.screen_wh.h

    local success2, w, h = pcall(love.window.getDesktopDimensions, self.window.display)
    if success2 and w and h then
        self.screen_wh.w, self.screen_wh.h = w, h
    else
        self.screen_wh.w, self.screen_wh.h = love.graphics.getDimensions()
    end

    self.window.x, self.window.y = 0, 0
    self.window.resizable = false
    self.window.borderless = false

    pcall(love.window.updateMode, self.screen_wh.w, self.screen_wh.h, self.window)
    self.is_fullscreen = true

    self:CalculateScale()
end

function screen:DisableFullScreen()
    if self.is_mobile then return end -- Can't exit fullscreen on mobile
    if not self.is_fullscreen then return end

    if self.previous_screen_wh.w == self.screen_wh.w and self.previous_screen_wh.h == self.screen_wh.h then
        self.window.x = self.screen_wh.w / 2 - self.render_wh.w / 2
        self.window.y = self.screen_wh.h / 2 - self.render_wh.h / 2
        self.screen_wh.w, self.screen_wh.h = self.render_wh.w, self.render_wh.h
        self.window.resizable = true
        self.window.borderless = false
        self.window.centered = true
    else
        self.window.x, self.window.y = self.previous_xy.x, self.previous_xy.y
        self.screen_wh.w, self.screen_wh.h = self.previous_screen_wh.w, self.previous_screen_wh.h
        self.window.resizable = true
        self.window.borderless = false
    end

    pcall(love.window.updateMode, self.screen_wh.w, self.screen_wh.h, self.window)
    self.is_fullscreen = false

    self:CalculateScale()
end

function screen:ToggleFullScreen()
    if self.is_mobile then return end -- Can't toggle on mobile

    if self.is_fullscreen then
        self:DisableFullScreen()
    else
        self:EnableFullScreen()
    end
end

function screen:GetScale()
    return self.scale
end

function screen:GetOffset()
    return self.offset_x, self.offset_y
end

function screen:GetVirtualDimensions()
    return self.render_wh.w, self.render_wh.h
end

function screen:GetScreenDimensions()
    return self.screen_wh.w, self.screen_wh.h
end

function screen:CalculateScale()
    self.screen_wh.w = love.graphics.getWidth()
    self.screen_wh.h = love.graphics.getHeight()

    local virtual_aspect = self.render_wh.w / self.render_wh.h
    local screen_aspect = self.screen_wh.w / self.screen_wh.h

    if self.scale_mode == "stretch" then
        self.scale = math.min(self.screen_wh.w / self.render_wh.w, self.screen_wh.h / self.render_wh.h)
        self.offset_x = 0
        self.offset_y = 0
    elseif self.scale_mode == "fill" then
        if screen_aspect > virtual_aspect then
            self.scale = self.screen_wh.w / self.render_wh.w
        else
            self.scale = self.screen_wh.h / self.render_wh.h
        end
        self.offset_x = (self.screen_wh.w - self.render_wh.w * self.scale) / 2
        self.offset_y = (self.screen_wh.h - self.render_wh.h * self.scale) / 2
    else -- "fit" mode (default for mobile)
        if screen_aspect > virtual_aspect then
            self.scale = self.screen_wh.h / self.render_wh.h
            self.offset_x = (self.screen_wh.w - self.render_wh.w * self.scale) / 2
            self.offset_y = 0
        else
            self.scale = self.screen_wh.w / self.render_wh.w
            self.offset_x = 0
            self.offset_y = (self.screen_wh.h - self.render_wh.h * self.scale) / 2
        end
    end

    self.physical_bounds = self:GetVisibleVirtualBounds()
end

function screen:Attach()
    self:DrawLetterbox()
    love.graphics.push()
    love.graphics.translate(self.offset_x, self.offset_y)
    love.graphics.scale(self.scale, self.scale)
end

function screen:Detach()
    love.graphics.pop()
end

function screen:DrawLetterbox(r, g, b, a)
    r = r or 0
    g = g or 0
    b = b or 0
    a = a or 1

    love.graphics.setColor(r, g, b, a)

    if self.offset_x > 0 then
        love.graphics.rectangle("fill", 0, 0, self.offset_x, self.screen_wh.h)
        love.graphics.rectangle("fill", self.screen_wh.w - self.offset_x, 0, self.offset_x, self.screen_wh.h)
    end

    if self.offset_y > 0 then
        love.graphics.rectangle("fill", 0, 0, self.screen_wh.w, self.offset_y)
        love.graphics.rectangle("fill", 0, self.screen_wh.h - self.offset_y, self.screen_wh.w, self.offset_y)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function screen:ToVirtualCoords(x, y)
    local virtual_x = (x - self.offset_x) / self.scale
    local virtual_y = (y - self.offset_y) / self.scale
    return virtual_x, virtual_y
end

function screen:ToScreenCoords(x, y)
    local screen_x = x * self.scale + self.offset_x
    local screen_y = y * self.scale + self.offset_y
    return screen_x, screen_y
end

-- Get mouse position (works for both mouse and touch)
function screen:GetVirtualMousePosition()
    local mx, my

    if self.is_mobile then
        -- On mobile, use touch if available, otherwise mouse
        local touches = love.touch.getTouches()
        if #touches > 0 then
            mx, my = love.touch.getPosition(touches[1])
        else
            mx, my = love.mouse.getPosition()
        end
    else
        mx, my = love.mouse.getPosition()
    end

    local vmx, vmy = self:ToVirtualCoords(mx, my)
    return vmx, vmy, mx, my
end

-- Get all touch positions (Android multi-touch support)
function screen:GetAllTouches()
    if not self.is_mobile then
        return {}
    end

    local touches = {}
    local touch_ids = love.touch.getTouches()

    for i, id in ipairs(touch_ids) do
        local x, y = love.touch.getPosition(id)
        local vx, vy = self:ToVirtualCoords(x, y)
        table.insert(touches, {
            id = id,
            x = x,
            y = y,
            virtual_x = vx,
            virtual_y = vy
        })
    end

    return touches
end

function screen:Resize(w, h)
    self:CalculateScale()
end

function screen:GetVisibleVirtualBounds()
    if self.scale_mode == "fill" then
        local virtual_aspect = self.render_wh.w / self.render_wh.h
        local screen_aspect = self.screen_wh.w / self.screen_wh.h

        local x, y, w, h

        if screen_aspect > virtual_aspect then
            local visible_h = self.screen_wh.h / self.scale
            x = 0
            y = self.render_wh.h / 2 - visible_h / 2
            w = self.render_wh.w
            h = self.render_wh.h / 2 + visible_h / 2
        else
            local visible_w = self.screen_wh.w / self.scale
            x = self.render_wh.w / 2 - visible_w / 2
            y = 0
            w = self.render_wh.w / 2 + visible_w / 2
            h = self.render_wh.h
        end

        return { x = x, y = y, w = w, h = h }
    else
        return { x = 0, y = 0, w = self.render_wh.w, h = self.render_wh.h }
    end
end

-- ShowDebugInfo moved to engine/debug.lua (better architecture)
-- lib should not depend on engine modules

function screen:ShowGridVisualization()
    local debug = require "engine.debug"
    if not debug.show_colliders then return end

    -- Get virtual dimensions
    local vw, vh = self:GetVirtualDimensions()

    -- Draw sky blue background in center area
    love.graphics.setColor(0.2, 0.6, 1, 0.2)
    local margin = 100
    local grid_x, grid_y = self:ToScreenCoords(margin, margin)
    local grid_x2, grid_y2 = self:ToScreenCoords(vw - margin, vh - margin)
    local grid_width = grid_x2 - grid_x
    local grid_height = grid_y2 - grid_y
    love.graphics.rectangle("fill", grid_x, grid_y, grid_width, grid_height)

    -- Draw purple grid lines
    love.graphics.setColor(1, 0, 1, 0.25)
    love.graphics.setLineWidth(1)

    -- Vertical lines (every 100 virtual pixels)
    for x = margin, vw - margin, 100 do
        local sx, sy = self:ToScreenCoords(x, margin)
        local _, ey = self:ToScreenCoords(x, vh - margin)
        love.graphics.line(sx, sy, sx, ey)
    end

    -- Horizontal lines (every 100 virtual pixels)
    for y = margin, vh - margin, 100 do
        local sx, sy = self:ToScreenCoords(margin, y)
        local ex, _ = self:ToScreenCoords(vw - margin, y)
        love.graphics.line(sx, sy, ex, sy)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function screen:ShowVirtualMouse()
    local debug = require "engine.debug"
    if not debug.show_virtual_mouse then return end

    local vmx, vmy, mx, my = self:GetVirtualMousePosition()

    -- Check if point is in virtual bounds OR screen bounds
    local in_virtual_bounds = (vmx >= 0 and vmx <= self.render_wh.w and vmy >= 0 and vmy <= self.render_wh.h)
    local in_screen_bounds = (mx >= 0 and mx <= self.screen_wh.w and my >= 0 and my <= self.screen_wh.h)

    if in_virtual_bounds or in_screen_bounds then
        love.graphics.setColor(0, 0, 0, 0.3)
        love.graphics.circle("fill", mx, my, 16)

        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", mx, my, 14)

        love.graphics.setColor(1, 0, 0, 0.7)
        love.graphics.circle("fill", mx, my, 10)

        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.circle("fill", mx, my, 6)

        love.graphics.setColor(0.2, 0.6, 0.8, 0.8)
        love.graphics.circle("fill", mx, my, 2)

        love.graphics.setLineWidth(2)

        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.line(mx - 24, my, mx - 16, my)
        love.graphics.line(mx + 16, my, mx + 24, my)
        love.graphics.line(mx, my - 24, mx, my - 16)
        love.graphics.line(mx, my + 16, mx, my + 24)

        love.graphics.setColor(0.2, 0.8, 1, 0.9)
        love.graphics.line(mx - 22, my, mx - 17, my)
        love.graphics.line(mx + 17, my, mx + 22, my)
        love.graphics.line(mx, my - 22, mx, my - 17)
        love.graphics.line(mx, my + 17, mx, my + 22)

        love.graphics.setLineWidth(1)
    end

    -- Show all touch points on mobile
    if self.is_mobile then
        local touches = self:GetAllTouches()
        for _, touch in ipairs(touches) do
            love.graphics.setColor(0, 1, 0, 0.5)
            love.graphics.circle("fill", touch.x, touch.y, 30)
            love.graphics.setColor(0, 1, 0, 1)
            love.graphics.circle("line", touch.x, touch.y, 30)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return screen
