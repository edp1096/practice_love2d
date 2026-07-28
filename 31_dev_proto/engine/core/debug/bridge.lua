-- engine/core/debug/bridge.lua
-- Opt-in localhost debug bridge for visual automation.
-- Enable with LOVE2D_DEBUG_BRIDGE=1. Production runs do not load this module.

local bridge = {
    host = "127.0.0.1",
    port = tonumber(os.getenv("LOVE2D_DEBUG_PORT")) or 19785,
    server_fd = nil,
    client_fd = nil,
    input_buffer = "",
    output_buffer = "",
    screenshot_request = nil,
    screenshot_in_flight = false,
    pending_click = nil,
    quit_when_flushed = false,
    simulation_paused = false,
    step_frames = 0,
    step_dt = 1 / 60,
    simulated_frames = 0,
    overlay = {
        enabled = false,
        entities = true,
        walls = true,
        labels = true,
    },
}

local json = require "engine.core.debug.json"
local inspector = require "engine.core.debug.inspector"
local debug_socket = require "engine.core.debug.socket"

local function getRequestId(line)
    return json.getNumber(line, "id") or 0
end

local function findSceneModule(scene)
    for module_name, module in pairs(package.loaded) do
        if module == scene and
           (module_name:match("^engine%.") or module_name:match("^game%.")) then
            return module_name
        end
    end
    return nil
end

local function getSceneState()
    local scene_control = require "engine.core.scene_control"
    local scene = scene_control.current
    local state = {
        love_version = love.getVersion and table.concat({love.getVersion()}, ".") or nil,
        lua_version = _VERSION,
        jit_version = jit and jit.version or nil,
        scene = "unknown",
        has_previous_scene = scene_control.previous ~= nil,
        simulation = {
            paused = bridge.simulation_paused,
            pending_frames = bridge.step_frames,
            stepped_frames = bridge.simulated_frames,
            step_dt = bridge.step_dt,
        },
        overlay = bridge.overlay,
        window = {
            width = love.graphics.getWidth(),
            height = love.graphics.getHeight(),
            focused = love.window.hasFocus(),
        },
    }

    if not scene then
        state.scene = "none"
        return state
    end

    local scene_module = findSceneModule(scene)
    if scene_module then
        state.scene_module = scene_module
        state.scene = scene_module:match("([^.]+)$") or scene_module
    elseif scene.player and scene.world then
        state.scene = "gameplay"
    elseif scene.title then
        state.scene = "menu"
    end

    if scene.title then
        state.title = scene.title
        state.selected = scene.selected
    end

    if scene.current_map_path then
        state.map_path = scene.current_map_path
    end

    if scene.world and scene.world.map and scene.world.map.properties then
        state.map_name = scene.world.map.properties.name
        state.game_mode = scene.world.game_mode
    end

    if scene.player then
        state.player = {
            x = scene.player.x,
            y = scene.player.y,
            health = scene.player.health,
            max_health = scene.player.max_health,
            state = scene.player.state,
            direction = scene.player.direction,
            is_boarded = scene.player.is_boarded or false,
        }
    end

    local dialogue = package.loaded["engine.ui.dialogue"]
    local vehicle_select = package.loaded["engine.ui.screens.vehicle_select"]
    local shop = package.loaded["engine.ui.screens.shop"]
    state.overlays = {
        dialogue = dialogue and dialogue.active or false,
        vehicle_select = vehicle_select and vehicle_select.is_open or false,
        shop = shop and shop.is_open or false,
    }

    return state
end

function bridge:_queueResponse(id, result, error_message)
    local response = {id = id}
    if error_message then
        response.error = {message = error_message}
    else
        response.result = result or {}
    end
    self.output_buffer = self.output_buffer .. json.encode(response) .. "\n"
end

function bridge:_handleRequest(line)
    local id = getRequestId(line)
    local method = json.getString(line, "method")

    if not method then
        self:_queueResponse(id, nil, "Missing method")
        return
    end

    if method == "Runtime.ping" then
        self:_queueResponse(id, {
            pong = true,
            protocol = 1,
            semantic_world = true,
        })
    elseif method == "Runtime.getState" then
        self:_queueResponse(id, getSceneState())
    elseif method == "Runtime.getProtocol" then
        self:_queueResponse(id, {
            version = 1,
            methods = {
                "Runtime.ping",
                "Runtime.getState",
                "Runtime.getProtocol",
                "Input.key",
                "Input.mouseMove",
                "Input.mouseClick",
                "Page.captureScreenshot",
                "World.getSnapshot",
                "World.worldToScreen",
                "Entity.get",
                "Entity.setPosition",
                "Entity.setHealth",
                "Entity.setProperty",
                "Game.startNew",
                "Test.setPaused",
                "Test.step",
                "Overlay.set",
                "App.quit",
            },
        })
    elseif method == "Input.key" then
        local key = json.getString(line, "key")
        if not key then
            self:_queueResponse(id, nil, "Missing key")
            return
        end
        love.keypressed(key, key, false)
        love.keyreleased(key, key)
        self:_queueResponse(id, {key = key})
    elseif method == "Input.mouseMove" then
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        if not x or not y then
            self:_queueResponse(id, nil, "Missing mouse coordinates")
            return
        end
        local old_x, old_y = love.mouse.getPosition()
        love.mouse.setPosition(x, y)
        love.mousemoved(x, y, x - old_x, y - old_y, false)
        self:_queueResponse(id, {x = x, y = y})
    elseif method == "Input.mouseClick" then
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        local button = json.getNumber(line, "button") or 1
        if not x or not y then
            self:_queueResponse(id, nil, "Missing mouse coordinates")
            return
        end
        if self.pending_click then
            self:_queueResponse(id, nil, "Mouse click already in progress")
            return
        end
        local old_x, old_y = love.mouse.getPosition()
        love.mouse.setPosition(x, y)
        love.mousemoved(x, y, x - old_x, y - old_y, false)
        -- Menus calculate hover during update(), so dispatch the click next frame.
        self.pending_click = {
            id = id,
            x = x,
            y = y,
            button = button,
        }
    elseif method == "World.getSnapshot" then
        self:_queueResponse(id, inspector:snapshot())
    elseif method == "World.worldToScreen" then
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        if not x or not y then
            self:_queueResponse(id, nil, "Missing world coordinates")
            return
        end
        self:_queueResponse(id, inspector:worldToScreen(x, y))
    elseif method == "Entity.get" then
        local entity_id = json.getString(line, "entityId")
        if not entity_id then
            self:_queueResponse(id, nil, "Missing entityId")
            return
        end
        local result, err = inspector:get(entity_id)
        self:_queueResponse(id, result, err)
    elseif method == "Entity.setPosition" then
        local entity_id = json.getString(line, "entityId")
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        local stop_velocity = json.getBoolean(line, "stopVelocity")
        if not entity_id or not x or not y then
            self:_queueResponse(id, nil, "Missing entityId or coordinates")
            return
        end
        if stop_velocity == nil then stop_velocity = true end
        local result, err =
            inspector:setPosition(entity_id, x, y, stop_velocity)
        self:_queueResponse(id, result, err)
    elseif method == "Entity.setHealth" then
        local entity_id = json.getString(line, "entityId")
        local value = json.getNumber(line, "value")
        if not entity_id or value == nil then
            self:_queueResponse(id, nil, "Missing entityId or value")
            return
        end
        local result, err = inspector:setHealth(entity_id, value)
        self:_queueResponse(id, result, err)
    elseif method == "Entity.setProperty" then
        local entity_id = json.getString(line, "entityId")
        local property = json.getString(line, "property")
        local value = json.getPrimitive(line, "value")
        if not entity_id or not property or value == nil then
            self:_queueResponse(
                id,
                nil,
                "Missing entityId, property, or primitive value"
            )
            return
        end
        local result, err =
            inspector:setProperty(entity_id, property, value)
        self:_queueResponse(id, result, err)
    elseif method == "Game.startNew" then
        local constants = require "engine.core.constants"
        local scene_control = require "engine.core.scene_control"
        local gameplay = require "engine.scenes.gameplay"
        local map_path =
            json.getString(line, "mapPath") or constants.GAME_START.DEFAULT_MAP
        local x =
            json.getNumber(line, "x") or constants.GAME_START.DEFAULT_SPAWN_X
        local y =
            json.getNumber(line, "y") or constants.GAME_START.DEFAULT_SPAWN_Y
        local save_slot = json.getNumber(line, "saveSlot") or 1
        scene_control.switch(
            gameplay,
            map_path,
            x,
            y,
            save_slot,
            true,
            false,
            false
        )
        self:_queueResponse(id, {
            started = true,
            map_path = map_path,
            x = x,
            y = y,
        })
    elseif method == "Test.setPaused" then
        local enabled = json.getBoolean(line, "enabled")
        if enabled == nil then
            self:_queueResponse(id, nil, "Missing boolean enabled")
            return
        end
        self.simulation_paused = enabled
        if not enabled then self.step_frames = 0 end
        self:_queueResponse(id, {
            paused = self.simulation_paused,
            pending_frames = self.step_frames,
        })
    elseif method == "Test.step" then
        local frames = math.floor(json.getNumber(line, "frames") or 1)
        local dt = json.getNumber(line, "dt") or self.step_dt
        if frames < 1 or frames > 600 then
            self:_queueResponse(id, nil, "frames must be between 1 and 600")
            return
        end
        if dt <= 0 or dt > 0.25 then
            self:_queueResponse(id, nil, "dt must be > 0 and <= 0.25")
            return
        end
        self.simulation_paused = true
        self.step_frames = self.step_frames + frames
        self.step_dt = dt
        self:_queueResponse(id, {
            paused = true,
            pending_frames = self.step_frames,
            dt = self.step_dt,
        })
    elseif method == "Overlay.set" then
        for _, property in ipairs({"enabled", "entities", "walls", "labels"}) do
            local value = json.getBoolean(line, property)
            if value ~= nil then self.overlay[property] = value end
        end
        self:_queueResponse(id, self.overlay)
    elseif method == "Page.captureScreenshot" then
        if self.screenshot_request or self.screenshot_in_flight then
            self:_queueResponse(id, nil, "Screenshot already in progress")
            return
        end
        self.screenshot_request = {id = id}
    elseif method == "App.quit" then
        self:_queueResponse(id, {quitting = true})
        self.quit_when_flushed = true
    else
        self:_queueResponse(id, nil, "Unknown method: " .. method)
    end
end

function bridge:_closeClient()
    debug_socket.close(self.client_fd)
    self.client_fd = nil
    self.input_buffer = ""
    self.output_buffer = ""
end

function bridge:_acceptClient()
    if self.client_fd then return end
    local client_fd, err = debug_socket.accept(self.server_fd)
    if err then print("[DebugBridge] " .. err) end
    if client_fd then self.client_fd = client_fd end
end

function bridge:_receiveRequests()
    if not self.client_fd then return end

    while true do
        local received, status = debug_socket.receive(self.client_fd, 8192)
        if received then
            self.input_buffer = self.input_buffer .. received
        elseif status == "closed" then
            self:_closeClient()
            return
        else
            if status ~= "wait" then self:_closeClient() end
            break
        end
    end

    while self.client_fd do
        local newline = self.input_buffer:find("\n", 1, true)
        if not newline then
            break
        end

        local line = self.input_buffer:sub(1, newline - 1)
        self.input_buffer = self.input_buffer:sub(newline + 1)

        if line ~= "" then
            local success, err = pcall(self._handleRequest, self, line)
            if not success then
                self:_queueResponse(getRequestId(line), nil, tostring(err))
            end
        end
    end
end

function bridge:_dispatchPendingClick()
    if not self.pending_click then
        return
    end

    local click = self.pending_click
    self.pending_click = nil
    love.mousepressed(click.x, click.y, click.button, false, 1)
    love.mousereleased(click.x, click.y, click.button, false, 1)
    self:_queueResponse(click.id, {
        x = click.x,
        y = click.y,
        button = click.button,
    })
end

function bridge:_flushResponses()
    if not self.client_fd or self.output_buffer == "" then
        return
    end

    local chunk_size = math.min(#self.output_buffer, 65536)
    local sent, status = debug_socket.send(
        self.client_fd,
        self.output_buffer:sub(1, chunk_size)
    )

    if sent and sent > 0 then
        self.output_buffer = self.output_buffer:sub(sent + 1)
    elseif status ~= "wait" then
        self:_closeClient()
    end
end

function bridge:start()
    if self.server_fd then return true end

    if self.port < 1 or self.port > 65535 then
        return false, "Invalid LOVE2D_DEBUG_PORT"
    end

    local server_fd, err = debug_socket.startServer(self.port)
    if not server_fd then return false, err end

    self.server_fd = server_fd
    print(string.format(
        "[DebugBridge] Listening on %s:%d",
        self.host,
        self.port
    ))
    return true
end

function bridge:update()
    if not self.server_fd then return end

    self:_dispatchPendingClick()
    self:_acceptClient()
    self:_receiveRequests()
    self:_flushResponses()

    if self.quit_when_flushed and self.output_buffer == "" then
        self.quit_when_flushed = false
        love.event.quit()
    end
end

function bridge:getSimulationDelta(real_dt)
    if not self.simulation_paused then
        return real_dt
    end
    if self.step_frames <= 0 then
        return nil
    end

    self.step_frames = self.step_frames - 1
    self.simulated_frames = self.simulated_frames + 1
    return self.step_dt
end

function bridge:afterDraw()
    inspector:drawOverlay(self.overlay)

    if not self.screenshot_request or self.screenshot_in_flight then
        return
    end

    local request = self.screenshot_request
    self.screenshot_request = nil
    self.screenshot_in_flight = true

    local success, err = pcall(love.graphics.captureScreenshot, function(image_data)
        local encoded = image_data:encode("png")
        local base64 = love.data.encode("string", "base64", encoded:getString())
        self:_queueResponse(request.id, {
            data = base64,
            format = "png",
            width = image_data:getWidth(),
            height = image_data:getHeight(),
        })
        self.screenshot_in_flight = false
    end)

    if not success then
        self.screenshot_in_flight = false
        self:_queueResponse(request.id, nil, tostring(err))
    end
end

function bridge:stop()
    self.screenshot_request = nil
    self.screenshot_in_flight = false
    self.pending_click = nil
    self.quit_when_flushed = false
    self.simulation_paused = false
    self.step_frames = 0
    self.overlay.enabled = false
    self:_closeClient()
    debug_socket.close(self.server_fd)
    self.server_fd = nil
    debug_socket.cleanup()
end

return bridge
