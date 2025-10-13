-- scenes/play.lua
-- Main gameplay scene: manages world, player, and camera

local play = {}

local player = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local debug = require "systems.debug"

function play:enter(previous, ...)
    -- Initialize camera
    self.cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)

    -- Initialize world system (map + collision)
    self.world = world:new("assets/maps/level1/test_map.lua")

    -- Initialize player
    self.player = player:new("assets/images/player-sheet.png", 400, 250)

    -- Register player with world's collision system
    self.world:addEntity(self.player)
end

function play:exit()
    -- Cleanup when leaving scene
    if self.world then
        self.world:destroy()
    end
end

function play:pause()
    -- Called when pause scene is pushed
end

function play:resume()
    -- Called when returning from pause
end

function play:update(dt)
    -- 1. Update player (get movement intent)
    local vx, vy = self.player:update(dt)

    -- 2. Apply movement through collision system
    self.world:moveEntity(self.player, vx, vy, dt)

    -- 3. Update world physics
    self.world:update(dt)

    -- 4. Sync player position from collider
    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    -- 5. Update camera
    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)
end

function play:draw()
    -- ⭐ Reset graphics state at the start of draw
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1) -- Clear with black background

    self.cam:attach()

    -- Draw layers in correct order
    self.world:drawLayer("Ground")
    self.player:draw()
    self.world:drawLayer("Trees")

    -- Debug collision visualization
    if debug.debug_mode then self.world:drawDebug() end

    self.cam:detach()

    -- Draw UI overlay (not affected by camera)
    if debug.show_fps then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 0, 0, 200, 100)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        love.graphics.print(string.format("Player: %.1f, %.1f",
            self.player.x, self.player.y), 10, 30)
        love.graphics.print("Press P to pause", 10, 50)
    end
end

function play:resize(w, h)
    self.cam:zoomTo(w / 960)
end

function play:keypressed(key)
    -- Scene-specific keys
    if key == "p" then
        local pause = require "scenes.pause"
        scene_control.push(pause)
    end
end

return play
