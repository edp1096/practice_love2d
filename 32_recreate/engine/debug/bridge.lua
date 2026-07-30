local json = require "engine.debug.json"
local debug_socket = require "engine.debug.socket"
local util = require "engine.core.util"

local Bridge = {}
Bridge.__index = Bridge

local MAX_INPUT_BYTES = 1024 * 1024
local MAX_OUTPUT_BYTES = 32 * 1024 * 1024

function Bridge.new(app)
    return setmetatable({
        app = app,
        host = "127.0.0.1",
        port = tonumber(os.getenv("RECREATE_DEBUG_PORT")) or 19832,
        server_fd = nil,
        client_fd = nil,
        client_generation = 0,
        input_buffer = "",
        output_buffer = "",
        screenshot_request = nil,
        screenshot_in_flight = false,
        quit_when_flushed = false,
        simulation_paused = false,
        step_frames = 0,
        step_dt = app.fixed_dt,
        simulated_frames = 0,
    }, Bridge)
end

local function requestId(line)
    return json.getNumber(line, "id") or 0
end

local function findSnapshotEntity(app, entity_id)
    if not app.world then return nil end
    for _, entity in ipairs(app.world:snapshot().entities) do
        if entity.id == entity_id then return entity end
    end
    return nil
end

function Bridge:_queue(id, result, error_message)
    local response = {id = id}
    if error_message then
        response.error = {message = error_message}
    else
        response.result = result or {}
    end
    local encoded = json.encode(response) .. "\n"
    if #self.output_buffer + #encoded > MAX_OUTPUT_BYTES then
        self:_closeClient()
        return
    end
    self.output_buffer = self.output_buffer .. encoded
end

function Bridge:_runtimeState()
    local state = self.app:state()
    state.simulation = {
        paused = self.simulation_paused,
        pending_frames = self.step_frames,
        stepped_frames = self.simulated_frames,
        step_dt = self.step_dt,
    }
    return state
end

function Bridge:_handle(line)
    local request, decode_error = json.decode(line)
    if not request or type(request) ~= "table" then
        self:_queue(0, nil, "invalid JSON request: " .. tostring(decode_error))
        return
    end
    line = request
    local id = requestId(line)
    local method = json.getString(line, "method")
    if not method then
        self:_queue(id, nil, "missing method")
        return
    end
    local params = request.params
    if params == nil or params == json.null then params = {} end
    if type(params) ~= "table" then
        self:_queue(id, nil, "params must be a JSON object")
        return
    end
    line = params

    if method == "Runtime.ping" then
        self:_queue(id, {
            pong = true,
            protocol = 9,
            semantic_world = true,
            content_validation = true,
            canonical_maps = true,
            transactional_saves = true,
            physical_gamepad_injection = true,
        })
    elseif method == "Runtime.getProtocol" then
        self:_queue(id, {
            version = 9,
            methods = {
                "Runtime.ping",
                "Runtime.getState",
                "Runtime.getProtocol",
                "Content.getSummary",
                "Content.getDefinition",
                "Content.validateDefinition",
                "Content.getGraph",
                "World.getSnapshot",
                "World.worldToScreen",
                "Entity.get",
                "Entity.spawn",
                "Entity.remove",
                "Entity.setPosition",
                "Entity.setHealth",
                "Entity.requestAbility",
                "Dialogue.start",
                "Inventory.give",
                "Economy.add",
                "Save.export",
                "Save.write",
                "Save.load",
                "Input.action",
                "Input.gamepad",
                "Test.setPaused",
                "Test.step",
                "Overlay.set",
                "Page.captureScreenshot",
                "App.startNewGame",
                "App.returnToTitle",
                "App.loadStage",
                "App.reloadContent",
                "App.reloadStage",
                "App.quit",
            },
        })
    elseif method == "Runtime.getState" then
        self:_queue(id, self:_runtimeState())
    elseif method == "Content.getSummary" then
        self:_queue(id, self.app.host.catalog:summary())
    elseif method == "Content.getDefinition" then
        local content_id = json.getString(line, "contentId")
        local definition =
            content_id and self.app.host.catalog:get(content_id)
        if not definition then
            self:_queue(
                id,
                nil,
                "unknown content '" .. tostring(content_id) .. "'"
            )
        else
            self:_queue(id, {
                id = definition.id,
                kind = definition.kind,
                source = self.app.host.catalog.sources[definition.id],
                definition = util.deepCopy(definition),
            })
        end
    elseif method == "Content.validateDefinition" then
        local content_id = json.getString(line, "contentId")
        local definition = line.definition
        if not content_id then
            self:_queue(id, nil, "missing contentId")
        elseif type(definition) ~= "table" or
               definition == json.null then
            self:_queue(id, nil, "definition must be a JSON object")
        else
            local result, validation_error =
                self.app:validateContentDefinition(
                    content_id,
                    definition
                )
            self:_queue(id, result, validation_error)
        end
    elseif method == "Content.getGraph" then
        self:_queue(id, self.app.host.catalog:dependencyGraph())
    elseif method == "World.getSnapshot" then
        self:_queue(
            id,
            self.app.world and self.app.world:snapshot() or
                {available = false}
        )
    elseif method == "World.worldToScreen" then
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        if x == nil or y == nil then
            self:_queue(id, nil, "missing world coordinates")
        else
            self:_queue(id, self.app:worldToScreen(x, y))
        end
    elseif method == "Entity.get" then
        local entity_id = json.getString(line, "entityId")
        local entity = entity_id and findSnapshotEntity(self.app, entity_id)
        if not entity then
            self:_queue(id, nil, "unknown entity '" .. tostring(entity_id) .. "'")
        else
            self:_queue(id, entity)
        end
    elseif method == "Entity.spawn" then
        local actor_id = json.getString(line, "actorId")
        local entity_id = json.getString(line, "entityId")
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        local actor = actor_id and self.app.host.catalog:get(actor_id)
        if not actor or actor.kind ~= "actor" then
            self:_queue(
                id,
                nil,
                "unknown actor '" .. tostring(actor_id) .. "'"
            )
        elseif (x == nil) ~= (y == nil) then
            self:_queue(id, nil, "x and y must be provided together")
        else
            if x == nil then
                local view = self.app.world:view()
                x = view.x + view.width / 2
                y = view.y + view.height / 2
            end
            local entity, spawn_error = self.app.world:spawn(
                actor_id,
                {
                    id = entity_id,
                    position = {x = x, y = y},
                }
            )
            self:_queue(
                id,
                entity and findSnapshotEntity(self.app, entity.id) or nil,
                spawn_error
            )
        end
    elseif method == "Entity.remove" then
        local entity_id = json.getString(line, "entityId")
        local entity =
            entity_id and self.app.world:get(entity_id)
        if not entity then
            self:_queue(
                id,
                nil,
                "unknown entity '" .. tostring(entity_id) .. "'"
            )
        else
            self.app.world:remove(entity, "debug")
            self:_queue(id, {
                entity_id = entity.id,
                queued = true,
            })
        end
    elseif method == "Entity.setPosition" then
        local entity_id = json.getString(line, "entityId")
        local x = json.getNumber(line, "x")
        local y = json.getNumber(line, "y")
        local entity = entity_id and self.app.world:get(entity_id)
        local transform = entity and entity.components.transform
        if not transform or x == nil or y == nil then
            self:_queue(id, nil, "missing entity or coordinates")
        else
            transform.x, transform.y = x, y
            self:_queue(id, findSnapshotEntity(self.app, entity_id))
        end
    elseif method == "Entity.setHealth" then
        local entity_id = json.getString(line, "entityId")
        local value = json.getNumber(line, "value")
        local entity = entity_id and self.app.world:get(entity_id)
        local health = entity and entity.components["action.health"]
        if not health or value == nil then
            self:_queue(id, nil, "missing entity health or value")
        else
            local result, health_error =
                self.app.world:service("lifecycle"):setHealth(
                    self.app.world,
                    entity,
                    value
                )
            if not result then
                self:_queue(id, nil, health_error)
            else
                self:_queue(id, findSnapshotEntity(self.app, entity_id))
            end
        end
    elseif method == "Entity.requestAbility" then
        local entity_id = json.getString(line, "entityId")
        local ability_id = json.getString(line, "abilityId")
        local entity =
            entity_id and self.app.world:get(entity_id)
        local combat = entity and
            entity.components["action.combat"]
        if not combat then
            self:_queue(id, nil, "entity has no action.combat component")
        elseif not combat.ability_set[ability_id] then
            self:_queue(
                id,
                nil,
                "ability '" .. tostring(ability_id) ..
                    "' is not in entity loadout"
            )
        else
            entity.commands.ability = ability_id
            self:_queue(id, {
                entity_id = entity.id,
                ability_id = ability_id,
                queued = true,
            })
        end
    elseif method == "Dialogue.start" then
        local dialogue_id = json.getString(line, "dialogueId")
        local speaker_id = json.getString(line, "speakerId")
        local dialogue = self.app.world:service("dialogue")
        local interactor = self.app.world:findByTag("player")[1]
        local speaker =
            speaker_id and self.app.world:get(speaker_id) or nil
        if not dialogue then
            self:_queue(id, nil, "rpg.dialogue is not loaded")
        elseif not interactor then
            self:_queue(id, nil, "world has no player interactor")
        elseif speaker_id and not speaker then
            self:_queue(
                id,
                nil,
                "unknown speaker entity '" .. speaker_id .. "'"
            )
        else
            local result, dialogue_error = dialogue:start(
                self.app.world,
                dialogue_id,
                interactor,
                speaker
            )
            self:_queue(id, result, dialogue_error)
        end
    elseif method == "Inventory.give" then
        local item_id = json.getString(line, "itemId")
        local amount = json.getNumber(line, "amount") or 1
        local inventory = self.app.world:service("inventory")
        if not inventory then
            self:_queue(id, nil, "rpg.inventory is not loaded")
        elseif not item_id then
            self:_queue(id, nil, "missing itemId")
        else
            local result, inventory_error = inventory:give(
                self.app.world,
                item_id,
                amount
            )
            self:_queue(id, result, inventory_error)
        end
    elseif method == "Economy.add" then
        local amount = json.getNumber(line, "amount")
        local economy = self.app.world:service("economy")
        if not economy then
            self:_queue(id, nil, "rpg.economy is not loaded")
        elseif amount == nil then
            self:_queue(id, nil, "missing amount")
        else
            local result, economy_error = economy:add(
                self.app.world,
                amount,
                "debug"
            )
            self:_queue(id, result, economy_error)
        end
    elseif method == "Save.export" then
        local result, save_error = self.app:exportSave()
        self:_queue(id, result, save_error)
    elseif method == "Save.write" then
        local slot = json.getString(line, "slot")
        if not slot then
            self:_queue(id, nil, "missing slot")
        else
            local result, save_error = self.app:save(slot)
            self:_queue(id, result, save_error)
        end
    elseif method == "Save.load" then
        local slot = json.getString(line, "slot")
        if not slot then
            self:_queue(id, nil, "missing slot")
        else
            local result, save_error = self.app:loadSave(slot)
            self:_queue(id, result, save_error)
        end
    elseif method == "Input.action" then
        local action = json.getString(line, "action")
        local value = json.getNumber(line, "value") or 1
        local frames = math.floor(json.getNumber(line, "frames") or 1)
        if not action or not self.app.host.input:hasAction(action) then
            self:_queue(id, nil, "unknown input action '" .. tostring(action) .. "'")
        elseif frames < 1 or frames > 3600 then
            self:_queue(id, nil, "frames must be between 1 and 3600")
        else
            self.app.host.input:setAction(action, value, frames)
            self:_queue(id, {
                action = action,
                value = value,
                frames = frames,
            })
        end
    elseif method == "Input.gamepad" then
        local button = json.getString(line, "button")
        local frames = math.floor(json.getNumber(line, "frames") or 1)
        if not button then
            self:_queue(id, nil, "missing gamepad button")
        elseif frames < 1 or frames > 3600 then
            self:_queue(id, nil, "frames must be between 1 and 3600")
        else
            local actions, input_error =
                self.app.host.input:tapGamepad(button, frames)
            self:_queue(id, actions and {
                button = button,
                actions = actions,
                frames = frames,
            } or nil, input_error)
        end
    elseif method == "Test.setPaused" then
        local enabled = json.getBoolean(line, "enabled")
        if enabled == nil then
            self:_queue(id, nil, "missing boolean enabled")
        else
            self.simulation_paused = enabled
            if not enabled then self.step_frames = 0 end
            self:_queue(id, {
                paused = self.simulation_paused,
                pending_frames = self.step_frames,
            })
        end
    elseif method == "Test.step" then
        local frames = math.floor(json.getNumber(line, "frames") or 1)
        local requested_dt = json.getNumber(line, "dt")
        if frames < 1 or frames > 3600 then
            self:_queue(id, nil, "frames must be between 1 and 3600")
        elseif requested_dt and
               math.abs(requested_dt - self.app.fixed_dt) > 1e-9 then
            self:_queue(
                id,
                nil,
                string.format(
                    "Test.step uses the fixed simulation dt %.12g",
                    self.app.fixed_dt
                )
            )
        else
            self.simulation_paused = true
            self.step_frames = self.step_frames + frames
            self.step_dt = self.app.fixed_dt
            self:_queue(id, {
                paused = true,
                pending_frames = self.step_frames,
                dt = self.step_dt,
            })
        end
    elseif method == "Overlay.set" then
        for _, property in ipairs({"enabled", "entities", "labels"}) do
            local value = json.getBoolean(line, property)
            if value ~= nil then
                self.app.debug_overlay[property] = value
            end
        end
        self:_queue(id, util.deepCopy(self.app.debug_overlay))
    elseif method == "Page.captureScreenshot" then
        if self.screenshot_request or self.screenshot_in_flight then
            self:_queue(id, nil, "screenshot already in progress")
        else
            self.screenshot_request = {
                id = id,
                generation = self.client_generation,
            }
        end
    elseif method == "App.reloadStage" then
        local loaded, load_error = self.app:reloadStage()
        self:_queue(
            id,
            loaded and self:_runtimeState() or nil,
            load_error
        )
    elseif method == "App.startNewGame" then
        local stage_id = json.getString(line, "stageId")
        local spawn_id = json.getString(line, "spawnId")
        local started, start_error =
            self.app:startNewGame(stage_id, spawn_id)
        self:_queue(
            id,
            started and self:_runtimeState() or nil,
            start_error
        )
    elseif method == "App.returnToTitle" then
        local returned, return_error = self.app:returnToTitle()
        self:_queue(
            id,
            returned and self:_runtimeState() or nil,
            return_error
        )
    elseif method == "App.loadStage" then
        local stage_id = json.getString(line, "stageId")
        local spawn_id = json.getString(line, "spawnId")
        if not stage_id then
            self:_queue(id, nil, "missing stageId")
        else
            local loaded, load_error =
                self.app:loadStage(stage_id, spawn_id)
            self:_queue(
                id,
                loaded and self:_runtimeState() or nil,
                load_error
            )
        end
    elseif method == "App.reloadContent" then
        local loaded, load_error = self.app:reloadContent()
        self:_queue(
            id,
            loaded and self:_runtimeState() or nil,
            load_error
        )
    elseif method == "App.quit" then
        self:_queue(id, {quitting = true})
        self.quit_when_flushed = true
    else
        self:_queue(id, nil, "unknown method: " .. method)
    end
end

function Bridge:_closeClient()
    debug_socket.close(self.client_fd)
    self.client_fd = nil
    self.screenshot_request = nil
    self.client_generation = self.client_generation + 1
    self.input_buffer = ""
    self.output_buffer = ""
end

function Bridge:_acceptClient()
    if self.client_fd then return end
    local client, accept_error = debug_socket.accept(self.server_fd)
    if accept_error then print("[recreate debug] " .. accept_error) end
    if client then
        self.client_fd = client
        self.client_generation = self.client_generation + 1
    end
end

function Bridge:_receive()
    if not self.client_fd then return end
    while true do
        local received, status =
            debug_socket.receive(self.client_fd, 8192)
        if received then
            self.input_buffer = self.input_buffer .. received
            if #self.input_buffer > MAX_INPUT_BYTES then
                print("[recreate debug] request exceeds input limit")
                self:_closeClient()
                return
            end
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
        if not newline then break end
        local line = self.input_buffer:sub(1, newline - 1)
        self.input_buffer = self.input_buffer:sub(newline + 1)
        if line ~= "" then
            local success, handle_error = pcall(self._handle, self, line)
            if not success then
                self:_queue(requestId(line), nil, tostring(handle_error))
            end
        end
    end
end

function Bridge:_flush()
    if not self.client_fd or self.output_buffer == "" then return end
    local size = math.min(#self.output_buffer, 65536)
    local sent, status =
        debug_socket.send(self.client_fd, self.output_buffer:sub(1, size))
    if sent and sent > 0 then
        self.output_buffer = self.output_buffer:sub(sent + 1)
    elseif status ~= "wait" then
        self:_closeClient()
    end
end

function Bridge:start()
    if self.server_fd then return true end
    if self.port < 1 or self.port > 65535 then
        return nil, "invalid RECREATE_DEBUG_PORT"
    end
    local server, start_error = debug_socket.startServer(self.port)
    if not server then return nil, start_error end
    self.server_fd = server
    print(string.format(
        "[recreate debug] listening on %s:%d",
        self.host,
        self.port
    ))
    return true
end

function Bridge:update()
    if not self.server_fd then return end
    self:_acceptClient()
    self:_receive()
    self:_flush()
    if self.quit_when_flushed and self.output_buffer == "" then
        self.quit_when_flushed = false
        love.event.quit()
    end
end

function Bridge:getSimulationDelta(real_dt)
    if not self.simulation_paused then return real_dt end
    if self.step_frames <= 0 then return nil end
    self.step_frames = self.step_frames - 1
    self.simulated_frames = self.simulated_frames + 1
    return self.step_dt
end

function Bridge:afterDraw()
    if not self.screenshot_request or self.screenshot_in_flight then return end
    local request = self.screenshot_request
    self.screenshot_request = nil
    self.screenshot_in_flight = true

    local success, capture_error = pcall(
        love.graphics.captureScreenshot,
        function(image_data)
            local encoded = image_data:encode("png")
            local base64 = love.data.encode(
                "string",
                "base64",
                encoded:getString()
            )
            if self.client_fd and
               request.generation == self.client_generation then
                self:_queue(request.id, {
                    data = base64,
                    format = "png",
                    width = image_data:getWidth(),
                    height = image_data:getHeight(),
                })
            end
            self.screenshot_in_flight = false
        end
    )
    if not success then
        self.screenshot_in_flight = false
        self:_queue(request.id, nil, tostring(capture_error))
    end
end

function Bridge:stop()
    self.screenshot_request = nil
    self.screenshot_in_flight = false
    self.quit_when_flushed = false
    self:_closeClient()
    debug_socket.close(self.server_fd)
    self.server_fd = nil
    debug_socket.cleanup()
end

return Bridge
