local Host = require "engine.runtime.host"
local serializer = require "engine.core.serializer"
local util = require "engine.core.util"

local App = {}
App.__index = App

local SAVE_SCHEMA_VERSION = 1

local function newSessionStore()
    return {
        values = {},
        versions = {},
    }
end

local function validateManifest(manifest)
    local errors = {}
    local function expect(value, expected, name)
        if type(value) ~= expected then
            errors[#errors + 1] =
                string.format("game manifest %s must be %s", name, expected)
        end
    end

    expect(manifest.id, "string", "id")
    expect(manifest.title, "string", "title")
    expect(manifest.initial_stage, "string", "initial_stage")
    expect(manifest.features, "table", "features")
    expect(manifest.content_roots, "table", "content_roots")
    expect(manifest.input, "table", "input")
    if manifest.input then
        expect(manifest.input.actions, "table", "input.actions")
    end
    if manifest.fixed_dt ~= nil and
       (type(manifest.fixed_dt) ~= "number" or manifest.fixed_dt <= 0) then
        errors[#errors + 1] =
            "game manifest fixed_dt must be a positive number"
    end

    if #errors > 0 then return nil, table.concat(errors, "\n") end
    return true
end

function App.new(manifest, filesystem)
    return setmetatable({
        manifest = manifest,
        filesystem = filesystem,
        host = nil,
        world = nil,
        session = newSessionStore(),
        accumulator = 0,
        fixed_dt = manifest.fixed_dt or 1 / 60,
        maximum_steps = manifest.maximum_steps or 8,
        simulation_steps = 0,
        debug_overlay = {
            enabled = false,
            entities = true,
            labels = true,
        },
        view = {
            scale = 1,
            x = 0,
            y = 0,
            width = 0,
            height = 0,
            camera_x = 0,
            camera_y = 0,
        },
        current_stage_id = nil,
        current_spawn_id = nil,
        transitions = 0,
    }, App)
end

function App:_bootHost(session)
    local valid, manifest_error = validateManifest(self.manifest)
    if not valid then return nil, manifest_error end

    local host = Host.new(
        self.manifest,
        self.filesystem,
        session or self.session
    )
    local booted, boot_error = host:boot()
    if not booted then return nil, boot_error end

    local initial_stage = host.catalog:get(self.manifest.initial_stage)
    if not initial_stage or initial_stage.kind ~= "stage" then
        return nil, "initial_stage references missing stage '" ..
            tostring(self.manifest.initial_stage) .. "'"
    end
    return host
end

function App:load(options)
    options = options or {}
    local host, boot_error = self:_bootHost(self.session)
    if not host then return nil, boot_error end

    if options.validate_only then
        self.host = host
        return true
    end

    self.host = host
    return self:loadStage(self.manifest.initial_stage)
end

local function findSpawnPoint(stage, spawn_id)
    for _, spawn_point in ipairs(stage.spawn_points or {}) do
        if spawn_point.id == spawn_id then return spawn_point end
    end
    return nil
end

local function createEnteredWorld(host, stage_id, spawn_id)
    local world, world_error = host:createWorld(stage_id)
    if not world then return nil, world_error end
    if spawn_id then
        local spawn_point = findSpawnPoint(world.stage, spawn_id)
        if not spawn_point then
            return nil, string.format(
                "stage '%s' has no spawn point '%s'",
                stage_id,
                spawn_id
            )
        end
        local player = world:findByTag("player")[1]
        local transform = player and player.components.transform
        if not transform then
            return nil, string.format(
                "stage '%s' needs a tagged player for spawn point '%s'",
                stage_id,
                spawn_id
            )
        end
        transform.x = spawn_point.x
        transform.y = spawn_point.y
        world.events:emit("stage.spawn_applied", {
            stage_id = stage_id,
            spawn_id = spawn_id,
            entity_id = player.id,
        })
    end
    local camera = host.services.camera
    if camera and camera.snap then camera:snap(world) end
    return world
end

function App:loadStage(stage_id, spawn_id)
    local world, world_error =
        createEnteredWorld(self.host, stage_id, spawn_id)
    if not world then return nil, world_error end
    self.world = world
    self.current_stage_id = stage_id
    self.current_spawn_id = spawn_id
    self.accumulator = 0
    return true
end

function App:reloadStage()
    return self:loadStage(
        self.current_stage_id or self.manifest.initial_stage,
        self.current_spawn_id
    )
end

function App:reloadContent()
    local candidate_session = util.deepCopy(self.session)
    local host, boot_error = self:_bootHost(candidate_session)
    if not host then return nil, boot_error end
    local stage_id = self.current_stage_id or self.manifest.initial_stage
    local world, world_error =
        createEnteredWorld(host, stage_id, self.current_spawn_id)
    if not world then return nil, world_error end

    -- Swap only after the replacement has fully validated and loaded. A typo
    -- therefore leaves the running world intact for inspection and correction.
    self.session = candidate_session
    self.host = host
    self.world = world
    self.current_stage_id = stage_id
    self.accumulator = 0
    return true
end

local function validateSlot(slot)
    if type(slot) ~= "string" or
       #slot < 1 or #slot > 64 or
       not slot:match("^[a-z0-9_-]+$") then
        return nil, "save slot must use 1-64 lowercase letters, " ..
            "digits, underscores, or hyphens"
    end
    return true
end

local function validateKeys(value, allowed, path)
    local known = {}
    for _, key in ipairs(allowed) do known[key] = true end
    for key in pairs(value) do
        if not known[key] then
            return nil, path .. " contains unknown field '" ..
                tostring(key) .. "'"
        end
    end
    return true
end

local function validateSaveEnvelope(snapshot, project_id)
    local pure, pure_error = serializer.validate(snapshot)
    if not pure then return nil, pure_error end
    if type(snapshot) ~= "table" then
        return nil, "save data must be a table"
    end
    local keys_valid, keys_error = validateKeys(
        snapshot,
        {"schema_version", "project", "stage", "sections"},
        "save"
    )
    if not keys_valid then return nil, keys_error end
    if snapshot.schema_version ~= SAVE_SCHEMA_VERSION then
        return nil, string.format(
            "unsupported save schema version '%s' (expected %d)",
            tostring(snapshot.schema_version),
            SAVE_SCHEMA_VERSION
        )
    end
    if snapshot.project ~= project_id then
        return nil, "save belongs to project '" ..
            tostring(snapshot.project) .. "', not '" .. project_id .. "'"
    end
    if type(snapshot.stage) ~= "table" then
        return nil, "save.stage must be a table"
    end
    keys_valid, keys_error = validateKeys(
        snapshot.stage,
        {"id", "spawn"},
        "save.stage"
    )
    if not keys_valid then return nil, keys_error end
    if type(snapshot.stage.id) ~= "string" or
       snapshot.stage.id == "" then
        return nil, "save.stage.id must be a non-empty string"
    end
    if snapshot.stage.spawn ~= nil and
       (type(snapshot.stage.spawn) ~= "string" or
        snapshot.stage.spawn == "") then
        return nil, "save.stage.spawn must be a non-empty string"
    end
    if type(snapshot.sections) ~= "table" then
        return nil, "save.sections must be a table"
    end

    local store = newSessionStore()
    for name, section in pairs(snapshot.sections) do
        if type(name) ~= "string" or name == "" then
            return nil, "save section names must be non-empty strings"
        end
        if type(section) ~= "table" then
            return nil, "save section '" .. name .. "' must be a table"
        end
        keys_valid, keys_error = validateKeys(
            section,
            {"version", "data"},
            "save.sections." .. name
        )
        if not keys_valid then return nil, keys_error end
        if type(section.version) ~= "number" or
           section.version < 1 or section.version % 1 ~= 0 then
            return nil, "save section '" .. name ..
                "' version must be a positive integer"
        end
        if type(section.data) ~= "table" then
            return nil, "save section '" .. name ..
                "' data must be a table"
        end
        store.values[name] = util.deepCopy(section.data)
        store.versions[name] = section.version
    end
    return {
        stage_id = snapshot.stage.id,
        spawn_id = snapshot.stage.spawn,
        store = store,
    }
end

function App:exportSave()
    if not self.host or not self.world then
        return nil, "game must be loaded before it can be saved"
    end
    local session = self.host.services.session
    local sections = {}
    if session then
        local exported, export_error = session:exportSections()
        if not exported then return nil, export_error end
        sections = exported
    elseif next(self.session.values) ~= nil then
        return nil, "session data exists but session feature is not loaded"
    end
    return {
        schema_version = SAVE_SCHEMA_VERSION,
        project = self.manifest.id,
        stage = {
            id = self.current_stage_id or self.world.stage.id,
            spawn = self.current_spawn_id,
        },
        sections = sections,
    }
end

function App:importSave(snapshot)
    local decoded, decode_error =
        validateSaveEnvelope(snapshot, self.manifest.id)
    if not decoded then return nil, decode_error end

    local host, boot_error = self:_bootHost(decoded.store)
    if not host then return nil, boot_error end
    if not host.services.session and
       next(decoded.store.values) ~= nil then
        return nil, "save contains session data but session feature " ..
            "is not loaded"
    end
    local world, world_error = createEnteredWorld(
        host,
        decoded.stage_id,
        decoded.spawn_id
    )
    if not world then return nil, world_error end

    -- Loading is transactional: only a completely validated, migrated, and
    -- entered candidate can replace the currently running state.
    self.session = decoded.store
    self.host = host
    self.world = world
    self.current_stage_id = decoded.stage_id
    self.current_spawn_id = decoded.spawn_id
    self.accumulator = 0
    world.events:emit("save.loaded", {
        stage_id = decoded.stage_id,
        spawn_id = decoded.spawn_id,
    })
    return self:state()
end

function App:save(slot)
    local valid, slot_error = validateSlot(slot)
    if not valid then return nil, slot_error end
    if type(self.filesystem.writeAtomic) ~= "function" then
        return nil, "filesystem does not support save writes"
    end
    local snapshot, snapshot_error = self:exportSave()
    if not snapshot then return nil, snapshot_error end
    local encoded, encode_error = serializer.encode(snapshot)
    if not encoded then return nil, encode_error end
    local path = "saves/" .. slot .. ".lua"
    local written, write_error =
        self.filesystem:writeAtomic(path, encoded)
    if not written then return nil, write_error end
    self.world.events:emit("save.written", {
        slot = slot,
        path = path,
        stage_id = snapshot.stage.id,
    })
    return {
        slot = slot,
        path = path,
        stage_id = snapshot.stage.id,
        schema_version = SAVE_SCHEMA_VERSION,
    }
end

function App:loadSave(slot)
    local valid, slot_error = validateSlot(slot)
    if not valid then return nil, slot_error end
    local snapshot, load_error =
        self.filesystem:loadTable("saves/" .. slot .. ".lua")
    if not snapshot then return nil, load_error end
    return self:importSave(snapshot)
end

function App:_handleWorldRequests(source_world)
    for _, request in ipairs(source_world:drainRequests()) do
        if request.type == "stage_transition" then
            local loaded, load_error = self:loadStage(
                request.target_stage,
                request.target_spawn
            )
            if not loaded then return nil, load_error end
            self.transitions = self.transitions + 1
            return true
        end
    end
    return false
end

function App:update(dt)
    if not self.world then return end
    dt = util.clamp(dt, 0, 0.25)
    self.accumulator = self.accumulator + dt

    local steps = 0
    while self.accumulator >= self.fixed_dt and
          steps < self.maximum_steps do
        if self.host.input:consumePressed("restart") then
            local reloaded, reload_error = self:reloadStage()
            if not reloaded then error(reload_error) end
        end
        if self.host.input:consumePressed("debug_overlay") then
            self.debug_overlay.enabled = not self.debug_overlay.enabled
        end

        local updated_world = self.world
        local advanced = updated_world:update(self.fixed_dt)
        if advanced then self.host.input:endFrame() end
        self.accumulator = self.accumulator - self.fixed_dt
        self.simulation_steps = self.simulation_steps + 1
        steps = steps + 1
        local transitioned, transition_error =
            self:_handleWorldRequests(updated_world)
        if transition_error then error(transition_error) end
        if transitioned then break end
    end

    if steps == self.maximum_steps then
        self.accumulator = math.min(self.accumulator, self.fixed_dt)
    end
end

function App:_updateView()
    if not self.world then return end
    local width, height = love.graphics.getDimensions()
    local camera = self.world:view()
    local scale = math.min(
        width / camera.width,
        height / camera.height
    )
    self.view.scale = scale
    self.view.x = (width - camera.width * scale) / 2
    self.view.y = (height - camera.height * scale) / 2
    self.view.width = camera.width
    self.view.height = camera.height
    self.view.camera_x = camera.x
    self.view.camera_y = camera.y
end

function App:draw()
    if not self.world then return end
    self:_updateView()

    love.graphics.clear(0.015, 0.018, 0.028, 1)
    love.graphics.setScissor(
        self.view.x,
        self.view.y,
        self.view.width * self.view.scale,
        self.view.height * self.view.scale
    )
    love.graphics.push()
    love.graphics.translate(self.view.x, self.view.y)
    love.graphics.scale(self.view.scale)
    love.graphics.translate(-self.view.camera_x, -self.view.camera_y)
    self.world:draw("world")
    self:drawDebugOverlay()
    love.graphics.pop()
    love.graphics.setScissor()

    love.graphics.push()
    love.graphics.translate(self.view.x, self.view.y)
    love.graphics.scale(self.view.scale)
    self.world:draw("screen")
    love.graphics.pop()
end

function App:drawDebugOverlay()
    if not self.debug_overlay.enabled or not self.world then return end

    love.graphics.setLineWidth(1 / self.view.scale)
    for _, entity in ipairs(self.world:query("transform")) do
        local transform = entity.components.transform
        local body = entity.components.body
        if self.debug_overlay.entities and body then
            love.graphics.setColor(0.2, 0.95, 1, 0.9)
            if body.shape == "circle" then
                love.graphics.circle(
                    "line",
                    transform.x,
                    transform.y,
                    body.radius
                )
            elseif body.shape == "polygon" then
                local coordinates = {}
                for _, point in ipairs(body.points or {}) do
                    coordinates[#coordinates + 1] =
                        transform.x + point.x
                    coordinates[#coordinates + 1] =
                        transform.y + point.y
                end
                if #coordinates >= 6 then
                    love.graphics.polygon("line", coordinates)
                end
            else
                love.graphics.rectangle(
                    "line",
                    transform.x - body.width / 2,
                    transform.y - body.height / 2,
                    body.width,
                    body.height
                )
            end
        end
        if self.debug_overlay.labels then
            local font = love.graphics.getFont()
            local width = font:getWidth(entity.id)
            local body_extent =
                body and body.shape == "rectangle" and body.width / 2 or
                (body and body.radius or 10)
            local label_x
            if entity.tag_set.player then
                label_x = transform.x - body_extent - width - 6
            elseif body and body.static then
                label_x = transform.x - width / 2
            else
                label_x = transform.x + body_extent + 6
            end
            local label_y =
                transform.y -
                (body and body.shape == "rectangle" and body.height / 2 or
                 (body and body.radius or 10)) - 18
            love.graphics.setColor(0.2, 0.95, 1, 1)
            love.graphics.print(entity.id, label_x, label_y)
        end

    end
    self.world:drawDebug(self.debug_overlay)
    love.graphics.setLineWidth(1)
end

function App:worldToScreen(x, y)
    self:_updateView()
    return {
        x = self.view.x +
            (x - self.view.camera_x) * self.view.scale,
        y = self.view.y +
            (y - self.view.camera_y) * self.view.scale,
        scale = self.view.scale,
    }
end

function App:state()
    local love_version = nil
    if love and love.getVersion then
        local major, minor, revision = love.getVersion()
        love_version =
            string.format("%d.%d.%d", major, minor, revision)
    end
    return {
        project = self.manifest.id,
        title = self.manifest.title,
        love_version = love_version,
        lua_version = _VERSION,
        jit_version = jit and jit.version or nil,
        stage_id = self.world and self.world.stage.id or nil,
        spawn_id = self.current_spawn_id,
        transitions = self.transitions,
        simulation_steps = self.simulation_steps,
        fixed_dt = self.fixed_dt,
        save_schema_version = SAVE_SCHEMA_VERSION,
        overlay = util.deepCopy(self.debug_overlay),
        content = self.host and self.host.catalog:summary() or nil,
    }
end

function App:keypressed(key)
    self.host.input:keypressed(key)
end

function App:keyreleased(key)
    self.host.input:keyreleased(key)
end

function App:gamepadpressed(button)
    self.host.input:gamepadpressed(button)
end

function App:gamepadreleased(button)
    self.host.input:gamepadreleased(button)
end

function App:gamepadaxis(axis, value)
    self.host.input:gamepadaxis(axis, value)
end

return App
