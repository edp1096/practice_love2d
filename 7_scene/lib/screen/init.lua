local screen = {
    is_fullscreen = false,
    scale_mode = "fit",
    -- render_wh = { w = 1280, h = 720 },     -- Rendering size
    render_wh = { w = 960, h = 540 },      -- Rendering size (virtual resolution)
    screen_wh = { w = 0, h = 0 },          -- Window screen size (actual screen)
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
    },
    -- Calculated values for virtual resolution
    scale = 1,
    offset_x = 0,
    offset_y = 0,
    -- Supported aspect ratios (for reference)
    aspect_ratios = {
        ["1:1"] = 1 / 1,
        ["3:4"] = 3 / 4,
        ["4:3"] = 4 / 3,
        ["9:16"] = 9 / 16,
        ["16:9"] = 16 / 9,
        ["21:9"] = 21 / 9,
        ["9:21"] = 9 / 21,
        ["9:32"] = 9 / 32
    },
    -- Debug flags
    show_debug_info = false,
    show_virtual_mouse_pointer = false
}

function screen:Initialize(config)
    self.window.display = config.monitor

    local dx, dy = love.window.getDesktopDimensions(config.monitor)
    self.window.x, self.window.y = dx / 2 - self.render_wh.w / 2, dy / 2 - self.render_wh.h / 2

    love.graphics.setDefaultFilter(self.filter.min, self.filter.mag, self.filter.anisotropy)

    self.screen_wh.w, self.screen_wh.h = love.graphics.getDimensions()
    self.previous_screen_wh.w, self.previous_screen_wh.h = love.graphics.getDimensions()
    self.previous_xy.x, self.previous_xy.y = love.window.getPosition()

    if self.window.display ~= 1 then
        -- love.window.setMode(self.screen_wh.w, self.screen_wh.h, self.window)
        love.window.updateMode(self.screen_wh.w, self.screen_wh.h, self.window)
    end

    if config.scale_mode then self:SetScaleMode(config.scale_mode) end
    if config.fullscreen then self:EnableFullScreen() end

    -- Calculate initial scale and offset
    self:CalculateScale()
end

function screen:EnableFullScreen()
    if self.is_fullscreen then return end

    -- Save current window position and size
    self.previous_xy.x, self.previous_xy.y = love.window.getPosition()
    self.previous_screen_wh.w, self.previous_screen_wh.h = self.screen_wh.w, self.screen_wh.h

    -- Set to desktop dimensions
    self.screen_wh.w, self.screen_wh.h = love.window.getDesktopDimensions(self.window.display)
    self.window.x, self.window.y = 0, 0
    self.window.resizable = false
    self.window.borderless = false

    -- love.window.setMode(self.screen_wh.w, self.screen_wh.h, self.window)
    love.window.updateMode(self.screen_wh.w, self.screen_wh.h, self.window)
    self.is_fullscreen = true

    -- Recalculate scale and offset after fullscreen enable
    self:CalculateScale()
end

function screen:DisableFullScreen()
    if not self.is_fullscreen then return end

    -- Restore window size and position
    -- If window position is 0,0 and screen size is the same as fullscreen, use 960 x 540 and make centered
    if self.previous_screen_wh.w == self.screen_wh.w and self.previous_screen_wh.h == self.screen_wh.h then
        self.window.x, self.window.y = self.screen_wh.w / 2 - self.render_wh.w / 2, self.screen_wh.h / 2 - self.render_wh.h / 2
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

    -- love.window.setMode(self.screen_wh.w, self.screen_wh.h, self.window)
    love.window.updateMode(self.screen_wh.w, self.screen_wh.h, self.window)
    self.is_fullscreen = false

    -- Recalculate scale and offset after fullscreen disable
    self:CalculateScale()
end

function screen:ToggleFullScreen()
    if self.is_fullscreen then
        self:DisableFullScreen()
    else
        self:EnableFullScreen()
    end
end

function screen:SetScaleMode(mode)
    self.scale_mode = mode
    self:CalculateScale()
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

-- Calculate scaling and offset based on current screen size and scale mode
function screen:CalculateScale()
    self.screen_wh.w = love.graphics.getWidth()
    self.screen_wh.h = love.graphics.getHeight()

    local virtual_aspect = self.render_wh.w / self.render_wh.h
    local screen_aspect = self.screen_wh.w / self.screen_wh.h

    if self.scale_mode == "stretch" then
        -- Stretch to fill entire screen (may distort)
        self.scale = math.min(self.screen_wh.w / self.render_wh.w, self.screen_wh.h / self.render_wh.h)
        self.offset_x = 0
        self.offset_y = 0
    elseif self.scale_mode == "fill" then
        -- Fill entire screen (may crop content)
        if screen_aspect > virtual_aspect then
            self.scale = self.screen_wh.w / self.render_wh.w
        else
            self.scale = self.screen_wh.h / self.render_wh.h
        end
        self.offset_x = (self.screen_wh.w - self.render_wh.w * self.scale) / 2
        self.offset_y = (self.screen_wh.h - self.render_wh.h * self.scale) / 2
    else
        -- Fit mode (default) - letterbox/pillarbox
        if screen_aspect > virtual_aspect then
            -- Screen is wider than virtual (pillarbox - black bars on sides)
            self.scale = self.screen_wh.h / self.render_wh.h
            self.offset_x = (self.screen_wh.w - self.render_wh.w * self.scale) / 2
            self.offset_y = 0
        else
            -- Screen is taller than virtual (letterbox - black bars on top/bottom)
            self.scale = self.screen_wh.w / self.render_wh.w
            self.offset_x = 0
            self.offset_y = (self.screen_wh.h - self.render_wh.h * self.scale) / 2
        end
    end
end

-- Get current screen aspect ratio
function screen:GetCurrentAspectRatio()
    return self.screen_wh.w / self.screen_wh.h
end

-- Get closest matching aspect ratio name
function screen:GetAspectRatioName()
    local current_ratio = self:GetCurrentAspectRatio()
    local closest_name = "Custom"
    local closest_diff = math.huge

    for name, ratio in pairs(self.aspect_ratios) do
        local diff = math.abs(current_ratio - ratio)
        if diff < closest_diff then
            closest_diff = diff
            closest_name = name
        end
    end

    -- Consider it a match if within 0.1 difference
    if closest_diff < 0.1 then
        return closest_name
    else
        return "Custom (" .. string.format("%.2f", current_ratio) .. ":1)"
    end
end

-- Apply transformation to render in virtual coordinates
function screen:Attach()
    self:DrawLetterbox()
    love.graphics.push()
    love.graphics.translate(self.offset_x, self.offset_y)
    love.graphics.scale(self.scale, self.scale)
end

-- Remove transformation
function screen:Detach()
    love.graphics.pop()
end

-- Draw black bars for letterbox/pillarbox effect
function screen:DrawLetterbox(r, g, b, a)
    -- Use custom color or default to black
    r = r or 0
    g = g or 0
    b = b or 0
    a = a or 1

    love.graphics.setColor(r, g, b, a)

    if self.offset_x > 0 then
        -- Pillarbox (black bars on sides)
        love.graphics.rectangle("fill", 0, 0, self.offset_x, self.screen_wh.h)
        love.graphics.rectangle("fill", self.screen_wh.w - self.offset_x, 0, self.offset_x, self.screen_wh.h)
    end

    if self.offset_y > 0 then
        -- Letterbox (black bars on top/bottom)
        love.graphics.rectangle("fill", 0, 0, self.screen_wh.w, self.offset_y)
        love.graphics.rectangle("fill", 0, self.screen_wh.h - self.offset_y, self.screen_wh.w, self.offset_y)
    end

    love.graphics.setColor(1, 1, 1, 1) -- Reset color
end

-- Convert screen coordinates to virtual coordinates
function screen:ToVirtualCoords(x, y)
    local virtual_x = (x - self.offset_x) / self.scale
    local virtual_y = (y - self.offset_y) / self.scale
    return virtual_x, virtual_y
end

-- Convert virtual coordinates to screen coordinates
function screen:ToScreenCoords(x, y)
    local screen_x = x * self.scale + self.offset_x
    local screen_y = y * self.scale + self.offset_y
    return screen_x, screen_y
end

-- Get mouse position in virtual coordinates
function screen:GetVirtualMousePosition()
    local mx, my = love.mouse.getPosition()
    local vmx, vmy = self:ToVirtualCoords(mx, my)
    return vmx, vmy, mx, my
end

-- Check if virtual coordinates are within bounds
function screen:IsPointInVirtualBounds(x, y)
    return x >= 0 and x <= self.render_wh.w and y >= 0 and y <= self.render_wh.h
end

-- Check if real screen coordinates are within bounds
function screen:IsPointInScreenBounds(x, y)
    return x >= 0 and x <= self.screen_wh.w and y >= 0 and y <= self.screen_wh.h
end

-- Update screen dimensions (call this in love.resize)
function screen:Resize(w, h)
    self:CalculateScale()
end

-- Enable debug info display
function screen:EnableDebugInfo()
    self.show_debug_info = true
end

-- Disable debug info display
function screen:DisableDebugInfo()
    self.show_debug_info = false
end

-- Toggle debug info display
function screen:ToggleDebugInfo()
    self.show_debug_info = not self.show_debug_info
end

-- Enable virtual mouse visualization
function screen:EnableVirtualMouse()
    self.show_virtual_mouse_pointer = true
end

-- Disable virtual mouse visualization
function screen:DisableVirtualMouse()
    self.show_virtual_mouse_pointer = false
end

-- Toggle virtual mouse visualization
function screen:ToggleVirtualMouse()
    self.show_virtual_mouse_pointer = not self.show_virtual_mouse_pointer
end

function screen:ShowDebugInfo()
    if not self.show_debug_info then return end

    -- Get current values
    local sw, sh = self:GetScreenDimensions()
    local vw, vh = self:GetVirtualDimensions()
    local scale = self:GetScale()
    local offset_x, offset_y = self:GetOffset()
    local vmx, vmy, mx, my = self:GetVirtualMousePosition()

    -- Background for debug info area only
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 280, 250)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Screen: " .. sw .. "x" .. sh, 10, 10)
    love.graphics.print("Virtual: " .. vw .. "x" .. vh, 10, 30)
    love.graphics.print("Scale: " .. string.format("%.2f", scale), 10, 50)
    love.graphics.print("Aspect: " .. self:GetAspectRatioName(), 10, 70)
    love.graphics.print("Offset: " .. string.format("%.1f", offset_x) .. ", " .. string.format("%.1f", offset_y), 10, 90)
    love.graphics.print("Mode: " .. self.scale_mode, 10, 110)
    love.graphics.print("Virtual Mouse: " .. string.format("%.1f", vmx) .. ", " .. string.format("%.1f", vmy), 10, 130)

    -- Instructions
    love.graphics.print("F11: Toggle Fullscreen", 10, 170)
    love.graphics.print("1: Fit Mode  2: Stretch Mode  3: Fill Mode", 10, 190)
    love.graphics.print("F1: Debug Info  F2: Mouse Pointer", 10, 210)

    -- FPS
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 230)

    -- Draw background area to visualize virtual space
    love.graphics.setColor(0.2, 0.6, 1, 0.3)
    local x0, y0 = self:ToScreenCoords(100, 100)
    local x1, y1 = self:ToScreenCoords(vw - 100, vh - 100)
    x1, y1 = x1 - x0, y1 - y0
    love.graphics.rectangle("fill", x0, y0, x1, y1)

    -- Draw a grid to visualize virtual space
    love.graphics.setColor(1, 0, 1, 0.3)
    for x = 100, vw - 100, 100 do
        local gx, gy = self:ToScreenCoords(x, 100)
        local gw, gh = self:ToScreenCoords(x, vh - 100)
        love.graphics.line(gx, gy, gx, gh)
    end
    for y = 100, vh - 100, 100 do
        local gx, gy = self:ToScreenCoords(100, y)
        local gw, gh = self:ToScreenCoords(vw - 100, y)
        love.graphics.line(gx, gy, gw, gy)
    end

    -- Draw some example text in virtual coordinates
    love.graphics.setColor(1, 0, 1, 1)
    local cx1, cy1 = self:ToScreenCoords(vw / 2 - 75, 50)
    local cx2, cy2 = self:ToScreenCoords(vw / 2 - 75, 70)
    love.graphics.print("Virtual Coordinate Space", cx1, cy1)
    love.graphics.print("Resolution: " .. vw .. " x " .. vh, cx2, cy2)

    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

function screen:ShowVirtualMouse()
    if not self.show_virtual_mouse_pointer then return end

    local vmx, vmy, mx, my = self:GetVirtualMousePosition()

    -- If mouse is within virtual bounds, draw cursor and crosshair
    if self:IsPointInVirtualBounds(vmx, vmy) or self:IsPointInScreenBounds(mx, my) then
        -- Draw outer glow (shadow effect)
        love.graphics.setColor(0, 0, 0, 0.3)
        love.graphics.circle("fill", mx, my, 16)

        -- Draw outer ring (white with transparency)
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", mx, my, 14)

        -- Draw middle ring (red)
        love.graphics.setColor(1, 0, 0, 0.7)
        love.graphics.circle("fill", mx, my, 10)

        -- Draw inner circle (bright center)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.circle("fill", mx, my, 6)

        -- Draw center dot
        love.graphics.setColor(0.2, 0.6, 0.8, 0.8)
        love.graphics.circle("fill", mx, my, 2)

        -- Draw crosshair with gradient effect
        love.graphics.setLineWidth(2)

        -- Outer crosshair (white with glow)
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.line(mx - 24, my, mx - 16, my)
        love.graphics.line(mx + 16, my, mx + 24, my)
        love.graphics.line(mx, my - 24, mx, my - 16)
        love.graphics.line(mx, my + 16, mx, my + 24)

        -- Inner crosshair (cyan/blue)
        love.graphics.setColor(0.2, 0.8, 1, 0.9)
        love.graphics.line(mx - 22, my, mx - 17, my)
        love.graphics.line(mx + 17, my, mx + 22, my)
        love.graphics.line(mx, my - 22, mx, my - 17)
        love.graphics.line(mx, my + 17, mx, my + 22)

        -- Reset line width
        love.graphics.setLineWidth(1)
    end

    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

return screen