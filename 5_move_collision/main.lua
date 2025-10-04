local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and " .. _VERSION)


local locker
if _VERSION == "Lua 5.1" then locker = require "locker" end

local screen = require "lib.screen"
local sti = require "vendor.sti"
local camera = require "vendor.hump.camera"
local windfield = require "vendor.windfield"
local player = require "entities.player"
local utils = require "utils.util"

local cwd = love.filesystem.getWorkingDirectory()
local world, walls
local cam, game_map


function love.load()
    if locker then locker:ProcInit() end

    world = windfield.newWorld(0, 0)

    screen:Initialize(GameConfig)
    screen:DisableVirtualMouse()

    cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)

    love.graphics.setDefaultFilter("nearest", "nearest")
    game_map = sti "assets/maps/level1/test_map.lua"
    player:New("assets/images/player-sheet.png")

    player.collider = world:newBSGRectangleCollider(400, 250, 50, 100, 10)
    player.collider:setFixedRotation(true)

    walls = {}
    if game_map.layers["Walls"] then
        for i, o in ipairs(game_map.layers["Walls"].objects) do
            local wall = world:newRectangleCollider(o.x, o.y, o.width, o.height)
            wall:setType("static")
            walls[i] = wall
        end
    end
end

function love.update(dt)
    local vx, vy = player:Update(dt)

    player.collider:setLinearVelocity(vx, vy)

    world:update(dt)
    player.x = player.collider:getX()
    player.y = player.collider:getY()

    cam:lookAt(player.x, player.y)
    cam:lockBounds(game_map.width * game_map.tilewidth, game_map.height * game_map.tileheight)
end

function love.draw()
    cam:attach()

    game_map:drawLayer(game_map.layers["Ground"])
    player.anim:draw(player.spriteSheet, player.x, player.y, nil, 6, nil, 6, 9)
    game_map:drawLayer(game_map.layers["Trees"])

    if is_debug then
        world:draw()
    end

    cam:detach()

    if is_debug then
        screen:ShowDebugInfo()
        screen:ShowVirtualMouse()
    end
end

function love.resize(w, h)
    GameConfig.width = w
    GameConfig.height = h
    cam:zoomTo(w / 960)
    utils:SaveConfig(GameConfig)
    screen:CalculateScale()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f11" then
        screen:ToggleFullScreen()
        cam:zoomTo(love.graphics.getWidth() / 960)
        GameConfig.fullscreen = screen.is_fullscreen
        utils:SaveConfig(GameConfig)
    elseif key == "f12" then
        is_debug = not is_debug
        screen:ToggleDebugInfo()
        if is_debug then
            screen:EnableVirtualMouse()
        else
            screen:DisableVirtualMouse()
        end
    end
end

function love.quit()
    local current_w, current_h, current_flags = love.window.getMode()
    if not screen.is_fullscreen then
        GameConfig.width = current_w
        GameConfig.height = current_h
    end
    GameConfig.monitor = current_flags.display
    utils:SaveConfig(GameConfig)

    if locker then locker:ProcQuit() end
end
