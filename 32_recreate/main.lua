local App = require "engine.core.app"
local filesystem = require "engine.adapters.love.filesystem"
local manifest = require "game.game"

local app = App.new(manifest, filesystem)
local debug_bridge = nil
local graph_mode = os.getenv("RECREATE_GRAPH") == "1"
local check_mode =
    os.getenv("RECREATE_CHECK") == "1" or graph_mode

local function fail(message)
    io.stderr:write("[recreate] " .. tostring(message) .. "\n")
    if check_mode then
        love.event.quit(1)
        return
    end
    error(message)
end

function love.load()
    local loaded, load_error = app:load({validate_only = check_mode})
    if not loaded then
        fail(load_error)
        return
    end

    local summary = app.host.catalog:summary()
    print(string.format(
        "[recreate] content valid: %d definitions",
        summary.total
    ))

    if graph_mode then
        local json = require "engine.debug.json"
        print(
            "RECREATE_GRAPH_JSON:" ..
                json.encode(app.host.catalog:dependencyGraph())
        )
        love.event.quit(0)
        return
    end

    if check_mode then
        print("[recreate] content check passed")
        love.event.quit(0)
        return
    end

    if os.getenv("RECREATE_DEBUG_BRIDGE") == "1" then
        local Bridge = require "engine.debug.bridge"
        debug_bridge = Bridge.new(app)
        local started, bridge_error = debug_bridge:start()
        if not started then
            fail("debug bridge: " .. tostring(bridge_error))
        end
    end
end

function love.update(dt)
    if debug_bridge then debug_bridge:update() end
    local simulation_dt = dt
    if debug_bridge then
        simulation_dt = debug_bridge:getSimulationDelta(dt)
    end
    if simulation_dt then app:update(simulation_dt) end
end

function love.draw()
    app:draw()
    if debug_bridge then debug_bridge:afterDraw() end
end

function love.keypressed(key)
    app:keypressed(key)
end

function love.keyreleased(key)
    app:keyreleased(key)
end

function love.gamepadpressed(_, button)
    app:gamepadpressed(button)
end

function love.gamepadreleased(_, button)
    app:gamepadreleased(button)
end

function love.gamepadaxis(_, axis, value)
    app:gamepadaxis(axis, value)
end

function love.quit()
    if debug_bridge then debug_bridge:stop() end
end
