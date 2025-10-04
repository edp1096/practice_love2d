-- Performance benchmark for tween libraries
-- You need to have flux.lua, tween.lua, and hump installed

local flux = require "vendor.flux"
local tween = require "vendor.tween"
local Timer = require "vendor.hump.timer"

local results = {}
local testCount = 1000 -- Number of objects to animate
local testDuration = 5 -- Seconds to run test

function love.load()
    -- Test 1: flux
    local fluxObjects = {}
    local startTime = love.timer.getTime()

    for i = 1, testCount do
        local obj = { x = 0, y = 0 }
        fluxObjects[i] = obj
        flux.to(obj, 2, { x = 100, y = 100 }):ease("quadout")
    end

    for i = 1, 60 do -- Simulate 60 frames
        flux.update(1 / 60)
    end

    results.flux = love.timer.getTime() - startTime

    -- Test 2: tween.lua
    local tweenObjects = {}
    local tweenInstances = {}
    startTime = love.timer.getTime()

    for i = 1, testCount do
        local obj = { x = 0, y = 0 }
        tweenObjects[i] = obj
        tweenInstances[i] = tween.new(2, obj, { x = 100, y = 100 }, 'inOutQuad')
    end

    for i = 1, 60 do
        for j = 1, testCount do
            tweenInstances[j]:update(1 / 60)
        end
    end

    results.tween = love.timer.getTime() - startTime

    -- Test 3: hump
    local humpObjects = {}
    startTime = love.timer.getTime()

    for i = 1, testCount do
        local obj = { x = 0, y = 0 }
        humpObjects[i] = obj
        Timer.tween(2, obj, { x = 100, y = 100 }, 'in-out-quad')
    end

    for i = 1, 60 do
        Timer.update(1 / 60)
    end

    results.hump = love.timer.getTime() - startTime

    -- Print results
    print("=== Performance Test Results ===")
    print(string.format("flux:      %.4f seconds", results.flux))
    print(string.format("tween.lua: %.4f seconds", results.tween))
    print(string.format("hump:      %.4f seconds", results.hump))
    print("\nNote: Differences are usually negligible in real games")
end

function love.draw()
    love.graphics.print("Benchmark Results:", 10, 10)
    love.graphics.print(string.format("flux:      %.4fms", results.flux * 1000), 10, 30)
    love.graphics.print(string.format("tween.lua: %.4fms", results.tween * 1000), 10, 50)
    love.graphics.print(string.format("hump:      %.4fms", results.hump * 1000), 10, 70)
    love.graphics.print("\nAll libraries are fast enough for games!", 10, 110)
end
