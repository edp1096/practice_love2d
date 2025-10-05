-- scenes/play.lua
-- Main gameplay scene: manages world, player, and camera

local play = {}

local player = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local debug = require "systems.debug"

function play:enter(previous, ...)
    -- Initialize
    self.cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)
    self.world = world:new("assets/maps/level1/test_map.lua")
    self.player = player:new("assets/images/player-sheet.png", 400, 250)

    -- Register player with world's collision system
    self.world:addEntity(self.player)
end

function play:exit()
    if self.world then
        self.world:destroy()
    end
end

-- Called when pause scene is pushed
function play:pause() end

-- Called when returning from pause
function play:resume() end

function play:update(dt)
    local vx, vy = self.player:update(dt)

    self.world:moveEntity(self.player, vx, vy, dt)
    self.world:update(dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)
end

function play:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    self.world:drawLayer("Ground")
    self.player:draw()
    self.world:drawLayer("Trees")

    if debug.debug_mode then
        self.world:drawDebug()
    end

    self.cam:detach()

    if debug.show_fps then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 0, 0, 200, 100)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        love.graphics.print(string.format("Player: %.1f, %.1f", self.player.x, self.player.y), 10, 30)
        love.graphics.print("Press P to pause", 10, 50)
    end
end

function play:resize(w, h)
    self.cam:zoomTo(w / 960)
end

function play:keypressed(key)
    if key == "p" then
        local pause = require "scenes.pause"
        scene_control.push(pause)
    end
end

return play
