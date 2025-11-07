-- engine/coords.lua
-- Unified coordinate system management for all engine systems
--
-- COORDINATE SYSTEMS:
-- 1. WORLD: Game world coordinates (Tiled maps, entities, physics)
--    - Origin: Map origin (0,0)
--    - Unit: Pixels in game world
--    - Used by: Entities, colliders, map tiles
--
-- 2. CAMERA: Camera-transformed coordinates (world rendered to canvas)
--    - Origin: Canvas center
--    - Transform: camera:attach() applies translation, scale, rotation
--    - Used by: Rendering within canvas
--
-- 3. VIRTUAL: Virtual screen coordinates (960x540 default)
--    - Origin: Top-left (0,0)
--    - Fixed resolution regardless of physical screen
--    - Used by: UI, HUD, menus
--
-- 4. PHYSICAL: Physical screen pixel coordinates
--    - Origin: Top-left (0,0)
--    - Actual device screen resolution
--    - Used by: Window, raw input events
--
-- 5. CANVAS: Canvas pixel coordinates (rendered content)
--    - Origin: Top-left (0,0) of canvas
--    - May differ from screen due to letterboxing
--    - Used by: Shaders, low-level rendering

local coords = {}

-- Cache dependencies (set externally)
coords.camera = nil
coords.screen = nil

-----------------------------------------------------------
-- WORLD ↔ CAMERA COORDINATES
-----------------------------------------------------------

-- Convert world coordinates to camera space
-- Camera space is where things are drawn on canvas after camera:attach()
function coords:worldToCamera(wx, wy, camera)
    camera = camera or self.camera
    if not camera then
        return wx, wy
    end

    -- Use camera's built-in conversion
    if camera.cameraCoords then
        return camera:cameraCoords(wx, wy)
    end

    -- Manual calculation if needed
    local cam_x = camera.x or 0
    local cam_y = camera.y or 0
    local scale = camera.scale or 1.0
    local rot = camera.rot or 0

    -- Camera transform (simplified, no rotation)
    local dx = (wx - cam_x) * scale
    local dy = (wy - cam_y) * scale

    -- Get canvas dimensions
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    return dx + w/2, dy + h/2
end

-- Convert camera coordinates back to world space
function coords:cameraToWorld(cx, cy, camera)
    camera = camera or self.camera
    if not camera then
        return cx, cy
    end

    -- Use camera's built-in conversion
    if camera.worldCoords then
        return camera:worldCoords(cx, cy)
    end

    -- Manual calculation
    local cam_x = camera.x or 0
    local cam_y = camera.y or 0
    local scale = camera.scale or 1.0

    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    local dx = (cx - w/2) / scale
    local dy = (cy - h/2) / scale

    return dx + cam_x, dy + cam_y
end

-----------------------------------------------------------
-- VIRTUAL ↔ PHYSICAL COORDINATES
-----------------------------------------------------------

-- Convert virtual coordinates to physical screen pixels
function coords:virtualToPhysical(vx, vy, screen)
    screen = screen or self.screen
    if not screen then
        return vx, vy
    end

    if screen.ToScreenCoords then
        return screen:ToScreenCoords(vx, vy)
    end

    -- Manual calculation
    local scale = screen.scale or 1.0
    local offset_x = screen.offset_x or 0
    local offset_y = screen.offset_y or 0

    return vx * scale + offset_x, vy * scale + offset_y
end

-- Convert physical screen pixels to virtual coordinates
function coords:physicalToVirtual(px, py, screen)
    screen = screen or self.screen
    if not screen then
        return px, py
    end

    if screen.ToVirtualCoords then
        return screen:ToVirtualCoords(px, py)
    end

    -- Manual calculation
    local scale = screen.scale or 1.0
    local offset_x = screen.offset_x or 0
    local offset_y = screen.offset_y or 0

    return (px - offset_x) / scale, (py - offset_y) / scale
end

-----------------------------------------------------------
-- COMPOSITE TRANSFORMATIONS
-----------------------------------------------------------

-- World → Virtual (through camera and screen transforms)
function coords:worldToVirtual(wx, wy, camera, screen)
    -- This is complex because world renders in camera space to canvas,
    -- which is then scaled to physical screen, which maps to virtual screen
    -- In practice, this is rarely needed directly

    -- For UI positioning relative to world objects:
    local cx, cy = self:worldToCamera(wx, wy, camera)

    -- Camera canvas is same size as physical screen in current setup
    -- So camera coords ≈ physical coords (with letterbox offset)

    screen = screen or self.screen
    if screen then
        return self:physicalToVirtual(cx, cy, screen)
    end

    return cx, cy
end

-- Virtual → World (inverse of above)
function coords:virtualToWorld(vx, vy, camera, screen)
    local px, py = self:virtualToPhysical(vx, vy, screen)
    return self:cameraToWorld(px, py, camera)
end

-----------------------------------------------------------
-- UTILITY FUNCTIONS
-----------------------------------------------------------

-- Get all coordinate representations of a point
function coords:debugPoint(x, y, camera, screen, label)
    label = label or "Point"

    print(string.format("=== %s Coordinates ===", label))
    print(string.format("  World:    (%.1f, %.1f)", x, y))

    if camera or self.camera then
        local cx, cy = self:worldToCamera(x, y, camera)
        print(string.format("  Camera:   (%.1f, %.1f)", cx, cy))
    end

    if screen or self.screen then
        screen = screen or self.screen
        local vx, vy = self:physicalToVirtual(x, y, screen)
        print(string.format("  Virtual:  (%.1f, %.1f)", vx, vy))

        local px, py = self:virtualToPhysical(vx, vy, screen)
        print(string.format("  Physical: (%.1f, %.1f)", px, py))
    end

    print("==========================")
end

-- Check if world point is visible in camera view
function coords:isVisibleInCamera(wx, wy, camera, margin)
    margin = margin or 0
    camera = camera or self.camera

    if not camera then
        return true
    end

    local cx, cy = self:worldToCamera(wx, wy, camera)
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    return cx >= -margin and cx <= w + margin and
           cy >= -margin and cy <= h + margin
end

-- Check if virtual point is on screen
function coords:isVisibleInVirtual(vx, vy, screen)
    screen = screen or self.screen
    if not screen then
        return true
    end

    local vw, vh = screen:GetVirtualDimensions()
    return vx >= 0 and vx <= vw and vy >= 0 and vy <= vh
end

-----------------------------------------------------------
-- DISTANCE CALCULATIONS
-----------------------------------------------------------

-- Distance in world space
function coords:distanceWorld(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Distance in camera space (accounts for camera scale)
function coords:distanceCamera(x1, y1, x2, y2, camera)
    camera = camera or self.camera
    local scale = (camera and camera.scale) or 1.0

    local dx = (x2 - x1) * scale
    local dy = (y2 - y1) * scale
    return math.sqrt(dx * dx + dy * dy)
end

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------

-- Set dependencies (call from main.lua after modules are loaded)
function coords:init(camera, screen)
    self.camera = camera
    self.screen = screen
    dprint("Coordinate system initialized")
end

return coords
