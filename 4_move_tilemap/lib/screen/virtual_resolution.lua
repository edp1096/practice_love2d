-- Virtual Resolution for LÖVE2D

local virtual_resolution = {}
virtual_resolution.__index = virtual_resolution

-- Constructor
function virtual_resolution:Set(virtualWidth, virtualHeight)
    -- self = setmetatable({}, virtual_resolution)

    -- Virtual resolution (base resolution for game logic)
    self.virtualWidth = tonumber(virtualWidth) or 1280
    self.virtualHeight = tonumber(virtualHeight) or 1080

    -- Actual screen dimensions
    self.screenWidth = love.graphics.getWidth()
    self.screenHeight = love.graphics.getHeight()

    -- Scaling and offset values
    self.scale = 1
    self.offsetX = 0
    self.offsetY = 0

    -- Scale mode: "fit", "stretch", or "fill"
    self.scaleMode = "fit"

    -- Supported aspect ratios (for reference)
    self.aspectRatios = {
        ["4:3"] = 4 / 3,
        ["16:9"] = 16 / 9,
        ["21:9"] = 21 / 9,
        ["32:9"] = 32 / 9
    }

    self:calculateScale()

    -- return self
end

-- Calculate scaling and offset based on current screen size
function virtual_resolution:calculateScale()
    self.screenWidth = love.graphics.getWidth()
    self.screenHeight = love.graphics.getHeight()

    local virtualAspect = self.virtualWidth / self.virtualHeight
    local screenAspect = self.screenWidth / self.screenHeight

    if self.scaleMode == "stretch" then
        -- Stretch to fill entire screen (may distort)
        self.scale = math.min(self.screenWidth / self.virtualWidth, self.screenHeight / self.virtualHeight)
        self.offsetX = 0
        self.offsetY = 0
    elseif self.scaleMode == "fill" then
        -- Fill entire screen (may crop content)
        if screenAspect > virtualAspect then
            self.scale = self.screenWidth / self.virtualWidth
        else
            self.scale = self.screenHeight / self.virtualHeight
        end
        self.offsetX = (self.screenWidth - self.virtualWidth * self.scale) / 2
        self.offsetY = (self.screenHeight - self.virtualHeight * self.scale) / 2
    else
        -- Fit mode (default) - letterbox/pillarbox
        if screenAspect > virtualAspect then
            -- Screen is wider than virtual (pillarbox - black bars on sides)
            self.scale = self.screenHeight / self.virtualHeight
            self.offsetX = (self.screenWidth - self.virtualWidth * self.scale) / 2
            self.offsetY = 0
        else
            -- Screen is taller than virtual (letterbox - black bars on top/bottom)
            self.scale = self.screenWidth / self.virtualWidth
            self.offsetX = 0
            self.offsetY = (self.screenHeight - self.virtualHeight * self.scale) / 2
        end
    end
end

-- Set scaling mode
function virtual_resolution:setScaleMode(mode)
    self.scaleMode = mode or "fit"
    self:calculateScale()
end

-- Get current scaling mode
function virtual_resolution:getScaleMode()
    return self.scaleMode
end

-- Apply transformation to render in virtual coordinates
function virtual_resolution:Attatch()
    self:drawLetterbox()
    love.graphics.push()
    love.graphics.translate(self.offsetX, self.offsetY)
    love.graphics.scale(self.scale, self.scale)
end

-- Remove transformation
function virtual_resolution:Detatch()
    love.graphics.pop()
end

-- Convert screen coordinates to virtual coordinates
function virtual_resolution:toVirtualCoords(x, y)
    local virtualX = (x - self.offsetX) / self.scale
    local virtualY = (y - self.offsetY) / self.scale
    return virtualX, virtualY
end

-- Convert virtual coordinates to screen coordinates
function virtual_resolution:toScreenCoords(x, y)
    local screenX = x * self.scale + self.offsetX
    local screenY = y * self.scale + self.offsetY
    return screenX, screenY
end

-- Get mouse position in virtual coordinates
function virtual_resolution:getVirtualMousePosition()
    local mx, my = love.mouse.getPosition()
    local vmx, vmy = self:toVirtualCoords(mx, my)
    -- return self:toVirtualCoords(mx, my)
    return vmx, vmy, mx, my
end

-- Check if virtual coordinates are within bounds
function virtual_resolution:isPointInVirtualBounds(x, y)
    return x >= 0 and x <= self.virtualWidth and y >= 0 and y <= self.virtualHeight
end

-- Get current screen aspect ratio
function virtual_resolution:getCurrentAspectRatio()
    return self.screenWidth / self.screenHeight
end

-- Get closest matching aspect ratio name
function virtual_resolution:getAspectRatioName()
    local currentRatio = self:getCurrentAspectRatio()
    local closestName = "Custom"
    local closestDiff = math.huge

    for name, ratio in pairs(self.aspectRatios) do
        local diff = math.abs(currentRatio - ratio)
        if diff < closestDiff then
            closestDiff = diff
            closestName = name
        end
    end

    -- Consider it a match if within 0.1 difference
    if closestDiff < 0.1 then
        return closestName
    else
        return "Custom (" .. string.format("%.2f", currentRatio) .. ":1)"
    end
end

-- Draw black bars for letterbox/pillarbox effect
function virtual_resolution:drawLetterbox(r, g, b, a)
    -- Use custom color or default to black
    r = r or 0
    g = g or 0
    b = b or 0
    a = a or 1

    love.graphics.setColor(r, g, b, a)

    if self.offsetX > 0 then
        -- Pillarbox (black bars on sides)
        love.graphics.rectangle("fill", 0, 0, self.offsetX, self.screenHeight)
        love.graphics.rectangle("fill", self.screenWidth - self.offsetX, 0, self.offsetX, self.screenHeight)
    end

    if self.offsetY > 0 then
        -- Letterbox (black bars on top/bottom)
        love.graphics.rectangle("fill", 0, 0, self.screenWidth, self.offsetY)
        love.graphics.rectangle("fill", 0, self.screenHeight - self.offsetY, self.screenWidth, self.offsetY)
    end

    love.graphics.setColor(1, 1, 1, 1) -- Reset color
end

-- Get virtual dimensions
function virtual_resolution:getVirtualDimensions()
    return self.virtualWidth, self.virtualHeight
end

-- Get screen dimensions
function virtual_resolution:getScreenDimensions()
    return self.screenWidth, self.screenHeight
end

-- Get current scale factor
function virtual_resolution:getScale()
    return self.scale
end

-- Get current offset values
function virtual_resolution:getOffset()
    return self.offsetX, self.offsetY
end

-- Update screen dimensions
function virtual_resolution:resize(w, h)
    self:calculateScale()
end

-- Debug information (drawn in screen coordinates)
function virtual_resolution:ShowDebugInfo()
    -- Get current values
    local sw, sh = self:getScreenDimensions()
    local vw, vh = self:getVirtualDimensions()
    local scale = self:getScale()
    local offsetX, offsetY = self:getOffset()

    -- Background for debug info area only
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 280, 220)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Screen: " .. sw .. "x" .. sh, 10, 10)
    love.graphics.print("Virtual: " .. vw .. "x" .. vh, 10, 30)
    love.graphics.print("Scale: " .. string.format("%.2f", scale), 10, 50)
    love.graphics.print("Aspect: " .. self:getAspectRatioName(), 10, 70)
    love.graphics.print("Offset: " .. string.format("%.1f", offsetX) .. ", " .. string.format("%.1f", offsetY), 10, 90)
    love.graphics.print("Mode: " .. self:getScaleMode(), 10, 110)

    -- Instructions
    love.graphics.print("F11: Toggle Fullscreen", 10, 150)
    love.graphics.print("1: Fit Mode  2: Stretch Mode  3: Fill Mode", 10, 170)

    -- Virtual mouse coordinates
    local vmx, vmy, mx, my = self:getVirtualMousePosition()
    love.graphics.print("Virtual Mouse: " .. string.format("%.1f", vmx) .. ", " .. string.format("%.1f", vmy), 10, 190)
    if self:isPointInVirtualBounds(vmx, vmy) then
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("fill", mx, my, 10)

        -- Draw crosshair
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.line(mx - 20, my, mx + 20, my)
        love.graphics.line(mx, my - 20, mx, my + 20)
    end

    -- Draw background
    love.graphics.setColor(0.2, 0.6, 1, 0.3)
    local x0, y0 = self:toScreenCoords(100, 100)
    local x1, y1 = self:toScreenCoords(vw - 100, vh - 100)
    x1, y1 = x1 - x0, y1 - y0
    love.graphics.rectangle("fill", x0, y0, x1, y1)

    -- Draw a grid to visualize virtual space
    love.graphics.setColor(1, 0, 1, 0.3)
    for x = 100, vw, 100 do
        local gx, gy = self:toScreenCoords(x, 100)
        local gw, gh = self:toScreenCoords(x, vh - 100)
        if x > vw - 100 then break end
        love.graphics.line(gx, gy, gx, gh)
    end
    for y = 100, vh, 100 do
        local gx, gy = self:toScreenCoords(100, y)
        local gw, gh = self:toScreenCoords(vw - 100, y)
        if y > vh - 100 then break end
        love.graphics.line(gx, gy, gw, gy)
    end

    -- Draw some example text in virtual coordinates
    local cx1, cy1 = self:toScreenCoords(vw / 2 - 75, 50)
    local cx2, cy2 = self:toScreenCoords(vw / 2 - 75, 70)
    love.graphics.setColor(1, 0, 1, 0.3)
    love.graphics.print("Virtual Coordinate Space", cx1, cy1)
    love.graphics.print("Resolution: " .. vw .. " x " .. vh, cx2, cy2)
end

return virtual_resolution
