local root = arg[1] or "."
package.path =
    root .. "/?.lua;" ..
    root .. "/?/init.lua;" ..
    package.path

local passed = 0
local failed = 0

local function test(name, body)
    local success, message = pcall(body)
    if success then
        passed = passed + 1
        print("[PASS] " .. name)
    else
        failed = failed + 1
        io.stderr:write("[FAIL] " .. name .. ": " .. tostring(message) .. "\n")
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(
            (message or "values differ") ..
            string.format(": got %s, expected %s", actual, expected),
            2
        )
    end
end

local function truthy(value, message)
    if not value then error(message or "expected truthy value", 2) end
end

local function fakeFilesystem(files)
    local filesystem = {files = files}

    function filesystem:list(path)
        local prefix = path .. "/"
        local seen = {}
        local result = {}
        for file_path in pairs(self.files) do
            if file_path:sub(1, #prefix) == prefix then
                local remainder = file_path:sub(#prefix + 1)
                local name = remainder:match("^([^/]+)")
                if name and not seen[name] then
                    seen[name] = true
                    result[#result + 1] = name
                end
            end
        end
        if #result == 0 then return nil, "missing directory" end
        table.sort(result)
        return result
    end

    function filesystem:info(path)
        if self.files[path] then return {type = "file"} end
        local prefix = path .. "/"
        for file_path in pairs(self.files) do
            if file_path:sub(1, #prefix) == prefix then
                return {type = "directory"}
            end
        end
        return nil
    end

    function filesystem:loadTable(path)
        local util = require "engine.core.util"
        local value = self.files[path]
        if not value then return nil, "missing file" end
        if type(value) == "string" then
            local chunk, load_error =
                loadstring(value, "@" .. path)
            if not chunk then return nil, load_error end
            setfenv(chunk, {})
            local loaded, result = pcall(chunk)
            if not loaded then return nil, result end
            if type(result) ~= "table" then
                return nil, "content file must return one table"
            end
            return result
        end
        return util.deepCopy(value)
    end

    function filesystem:writeAtomic(path, data)
        self.files[path] = data
        return true
    end

    return filesystem
end

test("event subscriptions can be removed", function()
    local Events = require "engine.core.events"
    local events = Events.new(3)
    local count = 0
    local unsubscribe = events:on("hit", function(payload)
        count = count + payload.amount
    end)
    events:emit("hit", {amount = 2})
    unsubscribe()
    events:emit("hit", {amount = 5})
    equal(count, 2)
    equal(#events:recent(10), 2)
end)

test("event transactions buffer commits and discard rollbacks", function()
    local Events = require "engine.core.events"
    local events = Events.new(10)
    local trace = {}
    events:on("first", function()
        trace[#trace + 1] = "first"
        events:emit("second")
    end)
    events:on("second", function()
        trace[#trace + 1] = "second"
    end)

    local discarded = events:beginTransaction()
    events:emit("first")
    equal(#trace, 0)
    equal(#events:recent(10), 0)
    events:rollbackTransaction(discarded)
    equal(#trace, 0)
    equal(#events:recent(10), 0)

    local committed = events:beginTransaction()
    events:emit("first")
    events:commitTransaction(committed)
    equal(table.concat(trace, ","), "first,second")
    local history = events:recent(10)
    equal(#history, 2)
    equal(history[1].name, "first")
    equal(history[1].sequence, 1)
    equal(history[2].name, "second")
    equal(history[2].sequence, 2)
end)

test("debug JSON parser honors top-level fields and Unicode", function()
    local json = require "engine.debug.json"
    local decoded, decode_error = json.decode(
        '{"method":"Runtime.ping",' ..
        '"params":{"method":"spoof"},' ..
        '"label":"\\uc548\\ub155"}'
    )
    truthy(decoded, decode_error)
    equal(json.getString(decoded, "method"), "Runtime.ping")
    equal(json.getString(decoded, "label"), "안녕")
    local numbers, number_error =
        json.decode('[0,-12,3.5,6e2,-7.25E-1]')
    truthy(numbers, number_error)
    equal(numbers[1], 0)
    equal(numbers[2], -12)
    equal(numbers[3], 3.5)
    equal(numbers[4], 600)
    equal(numbers[5], -0.725)

    local invalid, invalid_error =
        json.decode('{"method":"first","method":"second"}')
    equal(invalid, nil)
    truthy(invalid_error:match("duplicate object key"))
    for _, source in ipairs({
        "01", "-01", "1.", "1.e2", "1e", "1e+", "--1",
    }) do
        local value = json.decode(source)
        equal(value, nil, "accepted invalid JSON number " .. source)
    end
end)

test("debug bridge reads command arguments only from params", function()
    local Bridge = require "engine.debug.bridge"
    local json = require "engine.debug.json"
    local bridge = Bridge.new({fixed_dt = 1 / 60})
    bridge:_handle(
        '{"id":7,"method":"Test.setPaused","enabled":false,' ..
        '"params":{"enabled":true}}'
    )
    truthy(bridge.simulation_paused)
    local response, response_error =
        json.decode(bridge.output_buffer:match("([^\n]+)"))
    truthy(response, response_error)
    equal(response.id, 7)
    truthy(response.result.paused)

    bridge.output_buffer = ""
    bridge:_handle(
        '{"id":8,"method":"Test.setPaused","params":"bad"}'
    )
    response, response_error =
        json.decode(bridge.output_buffer:match("([^\n]+)"))
    truthy(response, response_error)
    equal(response.id, 8)
    equal(response.error.message, "params must be a JSON object")
end)

test("world action batches roll back state, spawns, and events", function()
    local Rules = require "engine.core.rules"
    local World = require "engine.runtime.world"
    local session = {currency = 0}
    local actor = {
        kind = "actor",
        id = "actor.marker",
        components = {},
    }
    local host = {
        systems = {},
        rules = Rules.new(),
        components = {},
        services = {},
        gates = {},
        time_filters = {},
        entity_inspectors = {},
        world_inspectors = {},
        debug_drawers = {},
        session_store = {
            values = {test = session},
            versions = {test = 1},
        },
        catalog = {
            get = function(_, id)
                if id == actor.id then return actor end
                return nil
            end,
        },
    }
    host.rules:registerAction("grant", {
        execute = function(_, context)
            session.currency = session.currency + 10
            context.world:spawn("actor.marker", {id = "temporary"})
            context.world.events:emit("reward.granted")
            return {applied = true}
        end,
    })
    host.rules:registerAction("fail", {
        execute = function()
            return nil, "expected failure"
        end,
    })
    local world = World.new(host, {
        id = "stage.test",
        width = 100,
        height = 100,
    })
    local result, batch_error = world:executeActions({
        {type = "grant"},
        {type = "fail"},
    })
    equal(result, nil)
    truthy(batch_error:match("action%[2%]"))
    equal(session.currency, 0)
    equal(world:get("temporary"), nil)
    equal(#world.entity_order, 0)
    equal(world.spawn_sequence, 0)
    equal(#world.events:recent(10), 0)
end)

test("successful world action batches execute each action exactly once", function()
    local Rules = require "engine.core.rules"
    local World = require "engine.runtime.world"
    local state = {count = 0}
    local host = {
        systems = {},
        rules = Rules.new(),
        components = {},
        services = {},
        gates = {},
        time_filters = {},
        entity_inspectors = {},
        world_inspectors = {},
        debug_drawers = {},
        session_store = {
            values = {test = state},
            versions = {test = 1},
        },
        catalog = {get = function() return nil end},
    }
    host.rules:registerAction("increment", {
        execute = function(action, context)
            state.count = state.count + action.amount
            context.world.events:emit("counter.incremented", {
                amount = action.amount,
            })
            return {applied = true}
        end,
    })
    local world = World.new(host, {
        id = "stage.test",
        width = 100,
        height = 100,
    })
    local result, batch_error = world:executeActions({
        {type = "increment", amount = 2},
        {type = "increment", amount = 3},
    })
    truthy(result, batch_error)
    equal(state.count, 5)
    local events = world.events:recent(10)
    equal(#events, 2)
    equal(events[1].payload.amount, 2)
    equal(events[2].payload.amount, 3)
end)

test("world removal compacts order and emits in spawn order", function()
    local Rules = require "engine.core.rules"
    local World = require "engine.runtime.world"
    local actor = {
        kind = "actor",
        id = "actor.marker",
        components = {},
    }
    local host = {
        systems = {},
        rules = Rules.new(),
        components = {},
        services = {},
        gates = {},
        time_filters = {},
        entity_inspectors = {},
        world_inspectors = {},
        debug_drawers = {},
        session_store = {values = {}, versions = {}},
        catalog = {
            get = function() return actor end,
        },
    }
    local world = World.new(host, {
        id = "stage.test",
        width = 100,
        height = 100,
    })
    world:spawn(actor.id, {id = "first"})
    world:spawn(actor.id, {id = "second"})
    world:spawn(actor.id, {id = "third"})
    local duplicate = world:spawn(actor.id, {id = "third"})
    equal(duplicate, nil)
    equal(world.spawn_sequence, 3)
    world:remove("second", "test")
    world:remove("first", "test")
    world:update(1 / 60)

    equal(#world.entity_order, 1)
    equal(world.entity_order[1], "third")
    local removed = {}
    for _, event in ipairs(world.events:recent(10)) do
        if event.name == "entity.removed" then
            removed[#removed + 1] = event.payload.entity_id
        end
    end
    equal(table.concat(removed, ","), "first,second")
end)

test("world action recursion is bounded and resets after failure", function()
    local Rules = require "engine.core.rules"
    local World = require "engine.runtime.world"
    local host = {
        manifest = {maximum_action_depth = 4},
        systems = {},
        rules = Rules.new(),
        components = {},
        services = {},
        gates = {},
        time_filters = {},
        entity_inspectors = {},
        world_inspectors = {},
        debug_drawers = {},
        session_store = {values = {}, versions = {}},
        catalog = {get = function() return nil end},
    }
    host.rules:registerAction("recurse", {
        execute = function(action, context)
            return context.world:execute(action, context)
        end,
    })
    host.rules:registerAction("ok", {
        execute = function()
            return {applied = true}
        end,
    })
    local world = World.new(host, {
        id = "stage.test",
        width = 100,
        height = 100,
    })
    local result, recursion_error =
        world:execute({type = "recurse"})
    equal(result, nil)
    truthy(recursion_error:match("maximum depth 4"))
    equal(world.action_depth, 0)
    truthy(world:execute({type = "ok"}).applied)
end)

test("spawn and remove stress leaves no entity-order tombstones", function()
    local Rules = require "engine.core.rules"
    local World = require "engine.runtime.world"
    local actor = {
        kind = "actor",
        id = "actor.marker",
        components = {},
    }
    local host = {
        systems = {},
        rules = Rules.new(),
        components = {},
        services = {},
        gates = {},
        time_filters = {},
        entity_inspectors = {},
        world_inspectors = {},
        debug_drawers = {},
        session_store = {values = {}, versions = {}},
        catalog = {get = function() return actor end},
    }
    local world = World.new(host, {
        id = "stage.test",
        width = 100,
        height = 100,
    })
    local total = 0
    for batch = 1, 100 do
        for index = 1, 50 do
            total = total + 1
            local entity = world:spawn(
                actor.id,
                {id = string.format("marker.%d.%d", batch, index)}
            )
            truthy(entity)
            world:remove(entity, "stress")
        end
        world:update(1 / 60)
        equal(#world.entity_order, 0)
        equal(#world:query(), 0)
    end
    equal(world.spawn_sequence, total)
    equal(#world.entities, 0)
end)

test("rule actions and nested conditions are extensible", function()
    local Rules = require "engine.core.rules"
    local rules = Rules.new()
    rules:registerAction("remember", {
        execute = function(action, context)
            context.values[#context.values + 1] = action.value
            return true
        end,
    })
    rules:registerCondition("flag", {
        evaluate = function(condition, context)
            return context.flags[condition.name] == true
        end,
    })

    local context = {values = {}, flags = {ready = true}}
    truthy(rules:execute({type = "remember", value = 7}, context))
    equal(context.values[1], 7)
    truthy(rules:evaluate({
        type = "all",
        conditions = {
            {type = "flag", name = "ready"},
            {type = "not", condition = {type = "flag", name = "blocked"}},
        },
    }, context))
end)

test("action interceptors compose in deterministic order", function()
    local Rules = require "engine.core.rules"
    local rules = Rules.new()
    local trace = {}
    rules:registerAction("run", {
        execute = function()
            trace[#trace + 1] = "action"
            return {applied = true}
        end,
    })
    rules:registerActionInterceptor("run", "late", 20, function(
        _, _, nextHandler
    )
        trace[#trace + 1] = "late.before"
        local result = nextHandler()
        trace[#trace + 1] = "late.after"
        return result
    end)
    rules:registerActionInterceptor("run", "early", 10, function(
        _, _, nextHandler
    )
        trace[#trace + 1] = "early.before"
        local result = nextHandler()
        trace[#trace + 1] = "early.after"
        return result
    end)

    truthy(rules:execute({type = "run"}).applied)
    equal(
        table.concat(trace, ","),
        "early.before,late.before,action,late.after,early.after"
    )
end)

test("action interceptors can replace immutable action data", function()
    local Rules = require "engine.core.rules"
    local rules = Rules.new()
    rules:registerAction("amount", {
        execute = function(action)
            return {amount = action.amount}
        end,
    })
    rules:registerActionInterceptor(
        "amount",
        "double",
        10,
        function(action, _, nextHandler)
            return nextHandler({
                type = action.type,
                amount = action.amount * 2,
            })
        end
    )
    local original = {type = "amount", amount = 4}
    equal(rules:execute(original).amount, 8)
    equal(original.amount, 4)
end)

test("catalog recursively discovers pure content", function()
    local Catalog = require "engine.content.catalog"
    local files = {
        ["content/actors/hero.lua"] = {
            schema_version = 1,
            kind = "sample",
            id = "sample.hero",
        },
        ["content/stages/room.lua"] = {
            schema_version = 1,
            kind = "sample",
            id = "sample.room",
        },
    }
    local catalog = Catalog.new(fakeFilesystem(files))
    catalog:loadRoots({"content"})

    local host = {
        content_kinds = {
            sample = {validate = function() end},
        },
    }
    local valid, errors = catalog:validate(host)
    truthy(valid, table.concat(errors or {}, "\n"))
    equal(catalog:summary().total, 2)
    equal(catalog:all()[1].id, "sample.hero")
end)

test("catalog rejects executable values", function()
    local Catalog = require "engine.content.catalog"
    local catalog = Catalog.new(fakeFilesystem({}))
    catalog:addForTest({
        schema_version = 1,
        kind = "sample",
        id = "sample.bad",
        callback = function() end,
    }, "bad.lua")
    local valid, errors = catalog:validate({
        content_kinds = {
            sample = {validate = function() end},
        },
    })
    equal(valid, false)
    truthy(table.concat(errors, "\n"):match("forbidden function"))
end)

test("asset validation compares declared and runtime image dimensions", function()
    local files = {
        ["content/assets/icon.lua"] = {
            schema_version = 1,
            kind = "asset",
            id = "image.icon",
            asset_type = "image",
            path = "assets/icon.png",
            width = 16,
            height = 8,
        },
        ["assets/icon.png"] = "image bytes",
    }
    local filesystem = fakeFilesystem(files)
    function filesystem:imageDimensions()
        return 12, 8
    end
    local Host = require "engine.runtime.host"
    local host = Host.new({
        content_roots = {"content"},
        features = {"engine.features.assets"},
        input = {actions = {}},
    }, filesystem)
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("image is 12x8"))

    files["content/assets/icon.lua"].width = 12
    host = Host.new({
        content_roots = {"content"},
        features = {"engine.features.assets"},
        input = {actions = {}},
    }, filesystem)
    truthy(host:boot())
end)

test("object validators reject numeric keys and condition typos", function()
    local Validator = require "engine.content.validator"
    local Rules = require "engine.core.rules"
    local rules = Rules.new()
    local validator = Validator.new({get = function() end}, {})
    validator:setSource("test")
    rules:validateCondition(
        {type = "always", typo = true},
        validator,
        "condition"
    )
    validator:keys({[1] = "unexpected"}, {}, "object")
    local valid, errors = validator:finish()
    equal(valid, false)
    local message = table.concat(errors, "\n")
    truthy(message:match("condition%.typo"))
    truthy(message:match("object%[1%]"))
end)

test("catalog exposes validated dependency paths in both directions", function()
    local Catalog = require "engine.content.catalog"
    local files = {
        ["content/sample/target.lua"] = {
            schema_version = 1,
            kind = "sample",
            id = "sample.target",
        },
        ["content/sample/source.lua"] = {
            schema_version = 1,
            kind = "sample",
            id = "sample.source",
            target = "sample.target",
        },
    }
    local catalog = Catalog.new(fakeFilesystem(files))
    catalog:loadRoots({"content"})
    local valid, errors = catalog:validate({
        content_kinds = {
            sample = {
                validate = function(definition, validator)
                    if definition.target then
                        validator:reference(
                            definition.target,
                            "sample",
                            "target"
                        )
                    end
                end,
            },
        },
    })
    truthy(valid, table.concat(errors or {}, "\n"))
    local graph = catalog:dependencyGraph()
    equal(graph.total, 2)
    equal(graph.edge_count, 1)
    local source = graph.nodes[1]
    local target = graph.nodes[2]
    equal(source.id, "sample.source")
    equal(source.dependencies[1].id, "sample.target")
    equal(source.dependencies[1].path, "target")
    equal(target.id, "sample.target")
    equal(target.dependents[1].id, "sample.source")
    equal(target.dependents[1].path, "target")
end)

local function runtimeDefinitions()
    return {
        ["content/statuses/burning.lua"] = {
            schema_version = 1,
            kind = "status",
            id = "status.burning",
            duration = 0.6,
            stacking = "stack",
            max_stacks = 3,
            tick_interval = 0.2,
            tick_actions = {
                {type = "damage", amount = 2},
            },
            modifiers = {
                move_speed = 0.5,
            },
        },
        ["content/statuses/vulnerable.lua"] = {
            schema_version = 1,
            kind = "status",
            id = "status.vulnerable",
            duration = 1,
            modifiers = {
                damage_taken = 1.5,
            },
        },
        ["content/abilities/hit.lua"] = {
            schema_version = 1,
            kind = "ability",
            id = "ability.hit",
            hitbox = {
                shape = "arc",
                reach = 30,
                arc_degrees = 100,
            },
            cooldown = 0.2,
            duration = 0.05,
            recovery = 0.1,
            lock_movement = true,
            effects = {
                {type = "damage", amount = 10},
                {type = "stagger", duration = 0.2},
            },
        },
        ["content/actors/player.lua"] = {
            schema_version = 1,
            kind = "actor",
            id = "actor.player",
            tags = {"player"},
            components = {
                transform = {},
                body = {
                    shape = "circle",
                    radius = 10,
                    solid = true,
                },
                ["action.hurtbox"] = {radius = 10},
                ["motion.facing"] = {},
                ["motion.kinematics"] = {},
                ["movement.topdown"] = {speed = 120},
                ["control.player"] = {},
                ["action.health"] = {
                    max = 50,
                    remove_on_death = false,
                },
                ["action.reaction"] = {
                    hit_invulnerability = 0.3,
                },
                ["action.status"] = {},
                ["action.knockback"] = {},
                ["action.combat"] = {
                    team = "player",
                    abilities = {"ability.hit"},
                },
                ["action.combat_input"] = {},
                ["action.dodge"] = {
                    input = "dodge",
                    duration = 0.2,
                    distance = 60,
                    invulnerability = 0.15,
                    cooldown = 0.4,
                },
                ["action.parry"] = {
                    input = "parry",
                    window = 0.32,
                    perfect_window = 0.12,
                },
            },
        },
        ["content/actors/enemy.lua"] = {
            schema_version = 1,
            kind = "actor",
            id = "actor.enemy",
            tags = {"enemy"},
            components = {
                transform = {},
                body = {
                    shape = "circle",
                    radius = 10,
                    solid = true,
                },
                ["action.hurtbox"] = {radius = 10},
                ["action.health"] = {max = 30},
                ["action.reaction"] = {
                    hit_invulnerability = 0.1,
                },
                ["action.status"] = {},
                ["action.knockback"] = {},
                ["action.combat"] = {
                    team = "enemy",
                    abilities = {"ability.hit"},
                },
            },
        },
        ["content/stages/test.lua"] = {
            schema_version = 1,
            kind = "stage",
            id = "stage.test",
            width = 400,
            height = 300,
            spawns = {
                {
                    id = "player",
                    actor = "actor.player",
                    position = {x = 100, y = 100},
                },
                {
                    id = "enemy",
                    actor = "actor.enemy",
                    position = {x = 142, y = 100},
                },
            },
        },
    }
end

local function runtimeManifest()
    return {
        id = "test.runtime",
        title = "Test Runtime",
        initial_stage = "stage.test",
        features = {
            "engine.features.movement.topdown",
            "engine.features.movement.platformer",
            "engine.features.action.combat",
            "engine.features.action.hitstop",
            "engine.features.action.knockback",
            "engine.features.action.projectile",
            "engine.features.action.status",
            "engine.features.action.encounter",
            "engine.features.action.dodge",
            "engine.features.action.parry",
        },
        content_roots = {"content"},
        input = {
            actions = {
                move_up = {keys = {}},
                move_down = {keys = {}},
                move_left = {keys = {}},
                move_right = {keys = {}},
                attack = {keys = {}},
                special = {keys = {}},
                jump = {keys = {}},
                dodge = {keys = {}},
                parry = {keys = {}},
                restart = {keys = {}},
                debug_overlay = {keys = {}},
            },
        },
    }
end

local function addProjectileDefinitions(files, speed)
    files["content/actors/bolt.lua"] = {
        schema_version = 1,
        kind = "actor",
        id = "actor.bolt",
        components = {
            transform = {},
            body = {
                shape = "circle",
                radius = 3,
                solid = true,
                collision_layer = "projectile",
                collision_mask = {"world"},
            },
            ["motion.facing"] = {},
            ["motion.kinematics"] = {},
        },
    }
    files["content/projectiles/bolt.lua"] = {
        schema_version = 1,
        kind = "projectile",
        id = "projectile.bolt",
        actor = "actor.bolt",
        speed = speed or 600,
        lifetime = 1,
        spawn_offset = 12,
        pierce = 0,
        effects = {
            {type = "damage", amount = 7},
        },
    }
    files["content/abilities/bolt.lua"] = {
        schema_version = 1,
        kind = "ability",
        id = "ability.bolt",
        cooldown = 0.1,
        duration = 0.05,
        recovery = 0.05,
        activation = {
            {
                type = "spawn_projectile",
                projectile = "projectile.bolt",
            },
        },
    }
    local player = files["content/actors/player.lua"]
    player.components["action.combat"].abilities[2] =
        "ability.bolt"
    player.components["action.combat_input"] = {
        bindings = {
            {input = "attack", ability = "ability.hit"},
            {input = "special", ability = "ability.bolt"},
        },
    }
end

local function addMultiHitDefinition(files)
    files["content/abilities/multi.lua"] = {
        schema_version = 1,
        kind = "ability",
        id = "ability.multi",
        hitbox = {
            shape = "arc",
            reach = 30,
            arc_degrees = 360,
            repeat_interval = 0.15,
            max_hits = 3,
        },
        cooldown = 0.5,
        duration = 0.4,
        effects = {
            {type = "damage", amount = 2},
        },
    }
    local combat =
        files["content/actors/player.lua"].components["action.combat"]
    combat.abilities[#combat.abilities + 1] = "ability.multi"
end

local function addEncounterDefinition(files)
    files["content/encounters/trial.lua"] = {
        schema_version = 1,
        kind = "encounter",
        id = "encounter.trial",
        waves = {
            {
                id = "first",
                spawns = {
                    {
                        id = "scout",
                        actor = "actor.enemy",
                        position = {x = 200, y = 100},
                    },
                },
            },
            {
                id = "boss",
                spawns = {
                    {
                        id = "champion",
                        actor = "actor.enemy",
                        tags = {"boss"},
                        position = {x = 250, y = 100},
                    },
                },
                boss_phases = {
                    {
                        id = "vulnerable",
                        spawn = "champion",
                        health_ratio_at_most = 0.5,
                        actions = {
                            {
                                type = "apply_status",
                                status = "status.vulnerable",
                            },
                        },
                    },
                },
            },
        },
    }
    files["content/stages/test.lua"].encounters = {
        {
            id = "trial",
            encounter = "encounter.trial",
            position = {x = 0, y = 0},
            auto_start = true,
        },
    }
end

local function addPlatformerDefinition(files)
    files["content/actors/runner.lua"] = {
        schema_version = 1,
        kind = "actor",
        id = "actor.runner",
        tags = {"player"},
        components = {
            transform = {},
            body = {
                shape = "circle",
                radius = 10,
                solid = true,
            },
            ["motion.facing"] = {},
            ["motion.kinematics"] = {},
            ["movement.platformer"] = {
                speed = 180,
                gravity = 1200,
                jump_speed = 480,
            },
            ["control.player"] = {},
        },
    }
    local stage = files["content/stages/test.lua"]
    stage.spawns = {
        {
            id = "runner",
            actor = "actor.runner",
            position = {x = 100, y = 250},
        },
    }
    stage.walls = {
        {
            id = "floor",
            shape = {
                type = "rectangle",
                x = 200,
                y = 280,
                width = 400,
                height = 40,
            },
        },
    }
end

test("combat input ability must belong to actor loadout", function()
    local files = runtimeDefinitions()
    addProjectileDefinitions(files, 600)
    files["content/actors/player.lua"].components[
        "action.combat"
    ].abilities[2] = nil

    local Host = require "engine.runtime.host"
    local host = Host.new(runtimeManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(
        boot_error:match("must also appear in action%.combat%.abilities")
    )
end)

local function createRuntime(files, manifest)
    local Host = require "engine.runtime.host"
    manifest = manifest or runtimeManifest()
    local host = Host.new(manifest, fakeFilesystem(files))
    local booted, boot_error = host:boot()
    truthy(booted, boot_error)
    local world, world_error = host:createWorld("stage.test")
    truthy(world, world_error)
    return host, world
end

test("projectile ability sweeps targets and removes on hit", function()
    local files = runtimeDefinitions()
    addProjectileDefinitions(files, 6000)
    local host, world = createRuntime(files)
    local enemy = world:get("enemy")
    enemy.components.transform.x = 180
    local before = enemy.components["action.health"].current

    host.input:setAction("special", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()

    equal(enemy.components["action.health"].current, before - 7)
    equal(#world:findByTag("projectile"), 0)
    local events = world.events:recent(10)
    local hit = false
    for _, event in ipairs(events) do
        if event.name == "projectile.hit" then hit = true end
    end
    truthy(hit, "projectile.hit should be emitted")
end)

test("projectile is destroyed by canonical stage wall", function()
    local files = runtimeDefinitions()
    addProjectileDefinitions(files, 600)
    files["content/stages/test.lua"].walls = {
        {
            id = "wall.projectile",
            shape = {
                type = "rectangle",
                x = 145,
                y = 100,
                width = 8,
                height = 80,
            },
        },
    }
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.geometry")
    local host, world = createRuntime(files, manifest)
    local enemy = world:get("enemy")
    enemy.components.transform.x = 220
    local before = enemy.components["action.health"].current

    host.input:setAction("special", 1, 1)
    for _ = 1, 12 do
        world:update(1 / 60)
        host.input:endFrame()
    end

    equal(enemy.components["action.health"].current, before)
    equal(#world:findByTag("projectile"), 0)
    local blocked = false
    for _, event in ipairs(world.events:recent(20)) do
        if event.name == "projectile.blocked" then blocked = true end
    end
    truthy(blocked, "projectile.blocked should be emitted")
end)

test("projectile hits the nearest target before a later wall", function()
    local files = runtimeDefinitions()
    addProjectileDefinitions(files, 6000)
    files["content/stages/test.lua"].spawns[2].position.x = 190
    files["content/stages/test.lua"].spawns[3] = {
        id = "near",
        actor = "actor.enemy",
        position = {x = 150, y = 100},
    }
    files["content/stages/test.lua"].walls = {
        {
            id = "wall.behind_target",
            shape = {
                type = "rectangle",
                x = 175,
                y = 100,
                width = 4,
                height = 80,
            },
        },
    }
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.geometry")
    local host, world = createRuntime(files, manifest)
    local near = world:get("near")
    local far = world:get("enemy")
    local near_health = near.components["action.health"].current
    local far_health = far.components["action.health"].current

    host.input:setAction("special", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()

    equal(near.components["action.health"].current, near_health - 7)
    equal(far.components["action.health"].current, far_health)
end)

test("projectile pierce resolves every crossed target in distance order", function()
    local files = runtimeDefinitions()
    addProjectileDefinitions(files, 6000)
    files["content/projectiles/bolt.lua"].pierce = 1
    files["content/stages/test.lua"].spawns[2] = {
        id = "far",
        actor = "actor.enemy",
        position = {x = 180, y = 100},
    }
    files["content/stages/test.lua"].spawns[3] = {
        id = "near",
        actor = "actor.enemy",
        position = {x = 150, y = 100},
    }
    local host, world = createRuntime(files)
    host.input:setAction("special", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()

    equal(world:get("near").components["action.health"].current, 23)
    equal(world:get("far").components["action.health"].current, 23)
    local hit_order = {}
    for _, event in ipairs(world.events:recent(20)) do
        if event.name == "projectile.hit" then
            hit_order[#hit_order + 1] = event.payload.target_id
        end
    end
    equal(table.concat(hit_order, ","), "near,far")
end)

test("projectile equal-time targets use stable entity id order", function()
    local files = runtimeDefinitions()
    addProjectileDefinitions(files, 6000)
    files["content/stages/test.lua"].spawns[2] = {
        id = "zeta",
        actor = "actor.enemy",
        position = {x = 160, y = 100},
    }
    files["content/stages/test.lua"].spawns[3] = {
        id = "alpha",
        actor = "actor.enemy",
        position = {x = 160, y = 100},
    }
    local host, world = createRuntime(files)
    host.input:setAction("special", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()

    equal(world:get("alpha").components["action.health"].current, 23)
    equal(world:get("zeta").components["action.health"].current, 30)
end)

test("stacked statuses tick, slow, and expire deterministically", function()
    local host, world = createRuntime(runtimeDefinitions())
    local enemy = world:get("enemy")
    local applied = world:execute({
        type = "apply_status",
        status = "status.burning",
        stacks = 2,
    }, {
        source = world:get("player"),
        target = enemy,
    })
    equal(applied.stacks, 2)
    equal(
        world:service("status"):multiplier(enemy, "move_speed"),
        0.25
    )
    truthy(world.host.rules:evaluate({
        type = "has_status",
        status = "status.burning",
        stacks_at_least = 2,
    }, {target = enemy}))

    for _ = 1, 12 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    equal(enemy.components["action.health"].current, 26)

    local stacked = world:execute({
        type = "apply_status",
        status = "status.burning",
        stacks = 2,
    }, {
        source = world:get("player"),
        target = enemy,
    })
    equal(stacked.stacks, 3)

    for _ = 1, 36 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    equal(world:service("status"):has(enemy, "status.burning"), false)
    local expired = false
    for _, event in ipairs(world.events:recent(20)) do
        if event.name == "status.expired" then expired = true end
    end
    truthy(expired, "status.expired should be emitted")
end)

test("status expiration may safely reapply the same status", function()
    local files = runtimeDefinitions()
    files["content/statuses/renewing.lua"] = {
        schema_version = 1,
        kind = "status",
        id = "status.renewing",
        duration = 1 / 60,
        on_expire = {
            {
                type = "apply_status",
                status = "status.renewing",
            },
        },
    }
    local host, world = createRuntime(files)
    local enemy = world:get("enemy")
    truthy(world:execute({
        type = "apply_status",
        status = "status.renewing",
    }, {
        source = world:get("player"),
        target = enemy,
    }))

    world:update(1 / 60)
    host.input:endFrame()
    local entry =
        enemy.components["action.status"].active["status.renewing"]
    truthy(entry, "on_expire reapplication must survive old expiration")
    truthy(entry.remaining > 0)
end)

test("status damage modifiers transform damage without mutating content", function()
    local _, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")
    local action = {type = "damage", amount = 10}
    world:execute({
        type = "apply_status",
        status = "status.vulnerable",
    }, {
        source = player,
        target = enemy,
    })
    local result = world:execute(action, {
        source = player,
        target = enemy,
    })
    equal(result.amount, 15)
    equal(enemy.components["action.health"].current, 15)
    equal(action.amount, 10)
end)

test("status immunity rejects an applied status", function()
    local files = runtimeDefinitions()
    files["content/actors/enemy.lua"].components[
        "action.status"
    ].immune = {"status.burning"}
    local _, world = createRuntime(files)
    local result = world:execute({
        type = "apply_status",
        status = "status.burning",
    }, {
        source = world:get("player"),
        target = world:get("enemy"),
    })
    truthy(result.resisted)
    equal(
        world:service("status"):has(
            world:get("enemy"),
            "status.burning"
        ),
        false
    )
end)

test("dynamic solid actors block each other by collision layer", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")
    host.input:setAction("move_right", 1, 30)
    for _ = 1, 30 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    local distance =
        enemy.components.transform.x -
        player.components.transform.x
    equal(distance, 20)
    equal(
        player.components.body.collision_layer,
        "actor"
    )
    truthy(player.components.body.collision_mask_set.actor)
end)

test("dynamic solid rectangles fail before runtime", function()
    local files = runtimeDefinitions()
    files["content/actors/enemy.lua"].components.body = {
        shape = "rectangle",
        width = 20,
        height = 20,
        solid = true,
    }
    local Host = require "engine.runtime.host"
    local host = Host.new(runtimeManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(
        boot_error:match("dynamic solid bodies must use shape 'circle'"),
        boot_error
    )
end)

test("repeat hitbox applies a bounded number of timed hits", function()
    local files = runtimeDefinitions()
    addMultiHitDefinition(files)
    local host, world = createRuntime(files)
    local player = world:get("player")
    local enemy = world:get("enemy")
    player.commands.ability = "ability.multi"
    for _ = 1, 30 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    equal(enemy.components["action.health"].current, 24)

    local hits = 0
    for _, event in ipairs(world.events:recent(30)) do
        if event.name == "ability.hit" and
           event.payload.ability_id == "ability.multi" then
            hits = hits + 1
        end
    end
    equal(hits, 3)
end)

test("repeat hitbox requires an explicit maximum hit count", function()
    local files = runtimeDefinitions()
    addMultiHitDefinition(files)
    files["content/abilities/multi.lua"].hitbox.max_hits = nil
    local Host = require "engine.runtime.host"
    local host = Host.new(runtimeManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("is required with repeat_interval"))
end)

test("encounter advances waves and enters data-driven boss phase", function()
    local files = runtimeDefinitions()
    addEncounterDefinition(files)
    local host, world = createRuntime(files)
    local encounter = world:service("encounter")

    world:update(1 / 60)
    host.input:endFrame()
    local state = encounter:state(world, "trial")
    equal(state.status, "active")
    equal(state.wave_index, 1)
    local scout_id = state.live_ids[1]
    truthy(world:get(scout_id))

    local scout = world:get(scout_id)
    scout.components["action.health"].current = 0
    scout.dead = true
    world:update(1 / 60)
    host.input:endFrame()
    equal(state.status, "pending")

    world:update(1 / 60)
    host.input:endFrame()
    equal(state.status, "active")
    equal(state.wave_index, 2)
    local boss = world:get(state.live_ids[1])
    truthy(boss.tag_set.boss)

    boss.components["action.health"].current = 15
    world:update(1 / 60)
    host.input:endFrame()
    truthy(
        world:service("status"):has(
            boss,
            "status.vulnerable"
        )
    )
    equal(state.entered_phases.vulnerable, true)

    boss.components["action.health"].current = 0
    boss.dead = true
    world:update(1 / 60)
    host.input:endFrame()
    equal(state.status, "completed")
    truthy(world.host.rules:evaluate({
        type = "encounter_state",
        encounter = "trial",
        state = "completed",
    }, {world = world}))
    equal(world:snapshot().encounters[1].status, "completed")
end)

test("encounter boss phase must reference a spawn in its wave", function()
    local files = runtimeDefinitions()
    addEncounterDefinition(files)
    files["content/encounters/trial.lua"].waves[
        2
    ].boss_phases[1].spawn = "missing"
    local Host = require "engine.runtime.host"
    local host = Host.new(runtimeManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("references no spawn in this wave"))
end)

test("platformer gravity, buffered jump, and landing are independent", function()
    local files = runtimeDefinitions()
    addPlatformerDefinition(files)
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.geometry")
    local host, world = createRuntime(files, manifest)
    local runner = world:get("runner")
    local transform = runner.components.transform
    local kinematics = runner.components["motion.kinematics"]

    world:update(1 / 60)
    host.input:endFrame()
    truthy(kinematics.grounded)
    truthy(math.abs(transform.y - 250) < 0.01)

    local grounded_x = transform.x
    host.input:setAction("move_right", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    truthy(
        transform.x > grounded_x,
        "runner should move while exactly touching the floor"
    )

    host.input:setAction("jump", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    truthy(not kinematics.grounded)
    truthy(kinematics.velocity_y < 0)
    truthy(transform.y < 250)

    local minimum_y = transform.y
    local landed = false
    for _ = 1, 120 do
        world:update(1 / 60)
        host.input:endFrame()
        minimum_y = math.min(minimum_y, transform.y)
        if kinematics.grounded then
            landed = true
            break
        end
    end
    truthy(landed, "runner should land back on the floor")
    truthy(minimum_y < 160, "jump should leave the floor")
    truthy(math.abs(transform.y - 250) < 0.01)

    local start_x = transform.x
    host.input:setAction("move_right", 1, 10)
    for _ = 1, 10 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    truthy(transform.x > start_x)
end)

test("platformer honors shared status movement modifiers", function()
    local function movedDistance(slowed)
        local files = runtimeDefinitions()
        local burning = files["content/statuses/burning.lua"]
        burning.tick_interval = nil
        burning.tick_actions = nil
        addPlatformerDefinition(files)
        local components =
            files["content/actors/runner.lua"].components
        components["action.status"] = {}
        components["control.player"] = nil
        local manifest = runtimeManifest()
        table.insert(manifest.features, "engine.features.geometry")
        local host, world = createRuntime(files, manifest)
        local runner = world:get("runner")
        world:update(1 / 60)
        host.input:endFrame()
        if slowed then
            world:execute({
                type = "apply_status",
                status = "status.burning",
            }, {
                source = runner,
                target = runner,
            })
        end
        local start_x = runner.components.transform.x
        for _ = 1, 30 do
            runner.components[
                "movement.platformer"
            ].intent_x = 1
            world:update(1 / 60)
            host.input:endFrame()
        end
        return runner.components.transform.x - start_x
    end

    local normal = movedDistance(false)
    local slowed = movedDistance(true)
    truthy(
        slowed < normal * 0.7,
        string.format(
            "expected slow distance below 70%%: normal %.3f, slowed %.3f",
            normal,
            slowed
        )
    )
    truthy(slowed > 0)
end)

test("topdown and platformer controllers cannot share one actor", function()
    local files = runtimeDefinitions()
    addPlatformerDefinition(files)
    files["content/actors/runner.lua"].components[
        "movement.topdown"
    ] = {speed = 120}
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.geometry")
    local Host = require "engine.runtime.host"
    local host = Host.new(manifest, fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("cannot be combined"))
end)

test("pure action runtime moves through semantic input", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local start_x = player.components.transform.x
    host.input:setAction("move_right", 1, 10)
    for _ = 1, 10 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    truthy(player.components.transform.x > start_x + 19)
end)

test("ability effects damage hostile components", function()
    local host, world = createRuntime(runtimeDefinitions())
    local enemy = world:get("enemy")
    host.input:setAction("attack", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(enemy.components["action.health"].current, 20)
    truthy(
        enemy.components["action.reaction"].stagger_remaining > 0,
        "enemy should be staggered by the ability effect"
    )
    local events = world.events:recent(3)
    equal(events[1].name, "actor.damaged")
    equal(events[2].name, "actor.staggered")
    equal(events[3].name, "ability.hit")
end)

test("death cancels transient action state and revive is explicit", function()
    local _, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local combat = player.components["action.combat"]
    local status = player.components["action.status"]
    combat.active = {
        ability_id = "ability.hit",
        phase = "active",
        remaining = 1,
        hit_targets = {},
        hit_count = 0,
    }
    truthy(world:execute({
        type = "apply_status",
        status = "status.vulnerable",
    }, {
        source = player,
        target = player,
    }))

    local killed = world:service("lifecycle"):setHealth(
        world,
        player,
        0
    )
    truthy(killed.killed)
    truthy(player.dead)
    equal(player.life_state, "dying")
    equal(combat.active, nil)
    equal(next(status.active), nil)

    local healed, heal_error = world:execute({
        type = "heal",
        amount = 5,
    }, {
        source = player,
        target = player,
    })
    equal(healed, false)
    truthy(heal_error:match("use revive"))

    local revived = world:execute({
        type = "revive",
        amount = 12,
    }, {
        target = player,
    })
    truthy(revived.applied)
    equal(player.dead, false)
    equal(player.life_state, "alive")
    equal(player.components["action.health"].current, 12)
end)

test("debug health mutation is exact while preserving lifecycle events", function()
    local files = runtimeDefinitions()
    files["content/actors/player.lua"].components["rpg.stats"] = {
        defense = 10,
    }
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.rpg.stats")
    local _, world = createRuntime(files, manifest)
    local player = world:get("player")
    truthy(world:execute({
        type = "apply_status",
        status = "status.vulnerable",
    }, {
        source = player,
        target = player,
    }))
    player.components["action.reaction"].invulnerable_remaining = 1
    player.components["action.parry"].active = true
    player.components["action.parry"].remaining = 0.2

    local result = world:service("lifecycle"):setHealth(
        world,
        player,
        7
    )
    truthy(result.applied)
    equal(player.components["action.health"].current, 7)
    truthy(player.components["action.parry"].active)
    equal(
        player.components["action.reaction"].invulnerable_remaining,
        1
    )
    local damage_event
    for _, event in ipairs(world.events:recent(10)) do
        if event.name == "actor.damaged" then damage_event = event end
    end
    truthy(damage_event)
    equal(damage_event.payload.amount, 43)
end)

test("debug health mutation rolls back when an event subscriber fails", function()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.presentation.impact"
    )
    local _, world = createRuntime(runtimeDefinitions(), manifest)
    local player = world:get("player")
    local original_health =
        player.components["action.health"].current
    local original_events = #world.events:recent(100)
    world.events:on("actor.damaged", function()
        error("expected subscriber failure")
    end)

    local result, mutation_error =
        world:service("lifecycle"):setHealth(
            world,
            player,
            7
        )
    equal(result, nil)
    truthy(
        mutation_error:match("expected subscriber failure"),
        mutation_error
    )
    equal(player.components["action.health"].current, original_health)
    equal(#world.events:recent(100), original_events)
    equal(world:view().shake_remaining, 0)
end)

test("debug health mutation rejects non-finite values", function()
    local _, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local original_health =
        player.components["action.health"].current
    for _, value in ipairs({0 / 0, math.huge, -math.huge}) do
        local result, mutation_error =
            world:service("lifecycle"):setHealth(
                world,
                player,
                value
            )
        equal(result, nil)
        truthy(mutation_error:match("finite number"), mutation_error)
        equal(
            player.components["action.health"].current,
            original_health
        )
    end
end)

test("active hitbox catches a target entering late and only hits once", function()
    local host, world = createRuntime(runtimeDefinitions())
    local enemy = world:get("enemy")
    enemy.components.transform.x = 190

    host.input:setAction("attack", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(enemy.components["action.health"].current, 30)

    enemy.components.transform.x = 145
    world:update(1 / 60)
    host.input:endFrame()
    equal(enemy.components["action.health"].current, 20)

    world:update(1 / 60)
    host.input:endFrame()
    equal(enemy.components["action.health"].current, 20)
end)

test("attack commitment locks movement through recovery", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local start_x = player.components.transform.x

    host.input:setAction("attack", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(player.components["action.combat"].active.phase, "active")

    host.input:setAction("move_right", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(player.components.transform.x, start_x)

    for _ = 1, 12 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    equal(player.components["action.combat"].active, nil)

    host.input:setAction("move_right", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    truthy(player.components.transform.x > start_x)
end)

test("perfect parry cancels damage and staggers the attacker", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")

    host.input:setAction("parry", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    truthy(player.components["action.parry"].active)

    local result = world:execute({
        type = "damage",
        amount = 10,
    }, {
        source = enemy,
        target = player,
    })
    truthy(result.parried)
    truthy(result.perfect)
    equal(player.components["action.health"].current, 50)
    truthy(enemy.components["action.reaction"].stagger_remaining >= 1)
    equal(world.events:recent(1)[1].name, "attack.parried")
end)

test("impact feedback turns a perfect parry into camera shake", function()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.presentation.impact"
    )
    local files = runtimeDefinitions()
    files["content/stages/test.lua"].camera = {
        viewport_width = 200,
        viewport_height = 150,
        follow_tag = "player",
    }
    local host, world = createRuntime(files, manifest)
    local player = world:get("player")
    local enemy = world:get("enemy")

    host.input:setAction("parry", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    local result = world:execute({
        type = "damage",
        amount = 10,
    }, {
        source = enemy,
        target = player,
    })
    truthy(result.parried)
    truthy(result.perfect)

    local view = world:view()
    truthy(view.shake_remaining > 0)
    equal(view.shake_magnitude, 10)
    truthy(
        math.abs(view.shake_offset_x) > 0 or
            math.abs(view.shake_offset_y) > 0
    )
end)

test("camera shake action is deterministic and decays to rest", function()
    local function runShake()
        local manifest = runtimeManifest()
        table.insert(manifest.features, "engine.features.camera")
        local files = runtimeDefinitions()
        files["content/stages/test.lua"].camera = {
            viewport_width = 200,
            viewport_height = 150,
            follow_tag = "player",
        }
        local _, world = createRuntime(files, manifest)
        local result = world:execute({
            type = "camera_shake",
            duration = 0.1,
            magnitude = 8,
            frequency = 24,
        })
        truthy(result.applied)
        local initial = world:view()
        for _ = 1, 7 do world:update(1 / 60) end
        local finished = world:view()
        equal(finished.shake_remaining, 0)
        equal(finished.shake_magnitude, 0)
        equal(finished.shake_offset_x, 0)
        equal(finished.shake_offset_y, 0)
        return initial.shake_offset_x, initial.shake_offset_y
    end

    local first_x, first_y = runShake()
    local second_x, second_y = runShake()
    truthy(math.abs(first_x) > 0 or math.abs(first_y) > 0)
    equal(first_x, second_x)
    equal(first_y, second_y)
end)

test("camera shake stays inside stage bounds", function()
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.camera")
    local files = runtimeDefinitions()
    files["content/stages/test.lua"].camera = {
        viewport_width = 400,
        viewport_height = 300,
        follow_tag = "player",
    }
    local _, world = createRuntime(files, manifest)
    local result = world:execute({
        type = "camera_shake",
        duration = 0.2,
        magnitude = 10,
        frequency = 40,
    })
    truthy(result.applied)
    local view = world:view()
    equal(view.x, 0)
    equal(view.y, 0)
    equal(view.shake_offset_x, 0)
    equal(view.shake_offset_y, 0)
    truthy(
        math.abs(view.shake_raw_offset_x) > 0 or
            math.abs(view.shake_raw_offset_y) > 0
    )

    files = runtimeDefinitions()
    files["content/stages/test.lua"].camera = {
        viewport_width = 200,
        viewport_height = 150,
        follow_tag = "player",
    }
    local _, edge_world = createRuntime(files, manifest)
    local player = edge_world:get("player")
    player.components.transform.x = 400
    player.components.transform.y = 300
    edge_world:update(1 / 60)
    edge_world:execute({
        type = "camera_shake",
        duration = 0.2,
        magnitude = 10,
        frequency = 40,
    })
    view = edge_world:view()
    truthy(view.x >= 0 and view.x <= 200)
    truthy(view.y >= 0 and view.y <= 150)
end)

test("camera shake advances on unscaled time during hitstop", function()
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.camera")
    local files = runtimeDefinitions()
    files["content/stages/test.lua"].camera = {
        viewport_width = 200,
        viewport_height = 150,
        follow_tag = "player",
    }
    local _, world = createRuntime(files, manifest)
    truthy(world:execute({
        type = "camera_shake",
        duration = 0.2,
        magnitude = 10,
        frequency = 40,
    }).applied)
    truthy(world:execute({
        type = "hitstop",
        duration = 0.05,
    }).applied)
    local before = world:view()
    local advanced = world:update(1 / 60)
    equal(advanced, false)
    equal(world.time, 0)
    local during = world:view()
    truthy(during.shake_remaining < before.shake_remaining)
    truthy(
        during.shake_raw_offset_x ~= before.shake_raw_offset_x or
            during.shake_raw_offset_y ~= before.shake_raw_offset_y
    )
end)

test("impact feedback manifest rejects unknown fields", function()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.presentation.impact"
    )
    manifest.impact_feedback = {
        perfect_pary = {
            magnitude = 12,
        },
    }
    local Host = require "engine.runtime.host"
    local host = Host.new(
        manifest,
        fakeFilesystem(runtimeDefinitions())
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("perfect_pary"), boot_error)
end)

test("impact feedback manifest reports invalid values without crashing", function()
    local cases = {
        {
            value = 42,
            expected = "impact_feedback must be a table",
        },
        {
            value = {damage = "strong"},
            expected = "impact_feedback.damage must be a table",
        },
        {
            value = {damage = {duration = 0 / 0}},
            expected = "must be a finite positive number",
        },
    }
    for _, case in ipairs(cases) do
        local manifest = runtimeManifest()
        table.insert(
            manifest.features,
            "engine.features.presentation.impact"
        )
        manifest.impact_feedback = case.value
        local Host = require "engine.runtime.host"
        local host = Host.new(
            manifest,
            fakeFilesystem(runtimeDefinitions())
        )
        local booted, boot_error = host:boot()
        equal(booted, nil)
        truthy(boot_error:match(case.expected), boot_error)
        equal(boot_error:match("could not register"), nil)
    end
end)

test("impact feedback manifest diagnostics are deterministic", function()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.presentation.impact"
    )
    manifest.impact_feedback = {
        zeta = true,
        alpha = true,
    }
    local Host = require "engine.runtime.host"
    local host = Host.new(
        manifest,
        fakeFilesystem(runtimeDefinitions())
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    local alpha = boot_error:find("'alpha'", 1, true)
    local zeta = boot_error:find("'zeta'", 1, true)
    truthy(alpha and zeta and alpha < zeta, boot_error)
end)

test("debug kills keep lifecycle events but skip impact shake", function()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.presentation.impact"
    )
    local _, world = createRuntime(runtimeDefinitions(), manifest)
    local player = world:get("player")
    local result, mutation_error =
        world:service("lifecycle"):setHealth(
            world,
            player,
            0
        )
    truthy(result, mutation_error)
    truthy(result.killed)
    equal(world:view().shake_remaining, 0)
    local killed
    for _, event in ipairs(world.events:recent(20)) do
        if event.name == "actor.killed" then killed = event end
    end
    truthy(killed)
    truthy(killed.payload.debug)
end)

test("parry only guards attacks inside its facing arc", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")
    enemy.components.transform.x = 58

    host.input:setAction("parry", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()

    local result = world:execute({
        type = "damage",
        amount = 10,
    }, {
        source = enemy,
        target = player,
    })
    truthy(result.applied)
    equal(result.parried, nil)
    equal(player.components["action.health"].current, 40)
    equal(player.components["action.parry"].active, false)
end)

test("expired parry allows damage and hit reaction", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")

    host.input:setAction("parry", 1, 1)
    for _ = 1, 25 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    equal(player.components["action.parry"].active, false)

    local result = world:execute({
        type = "damage",
        amount = 10,
    }, {
        source = enemy,
        target = player,
    })
    truthy(result.applied)
    equal(player.components["action.health"].current, 40)
    truthy(
        player.components["action.reaction"].invulnerable_remaining > 0
    )
end)

test("stagger gates movement and acting until recovery", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local start_x = player.components.transform.x

    world:execute({
        type = "stagger",
        duration = 0.1,
    }, {
        source = world:get("enemy"),
        target = player,
    })
    host.input:setAction("move_right", 1, 1)
    host.input:setAction("attack", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(player.components.transform.x, start_x)
    equal(player.components["action.combat"].active, nil)

    for _ = 1, 6 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    host.input:setAction("move_right", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    truthy(player.components.transform.x > start_x)
end)

test("knockback moves through the shared motion service", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")
    local start_x = enemy.components.transform.x

    local result = world:execute({
        type = "knockback",
        distance = 30,
        duration = 0.1,
    }, {
        source = player,
        target = enemy,
    })
    truthy(result.applied)

    for _ = 1, 6 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    truthy(enemy.components.transform.x > start_x + 29)
    equal(enemy.components["action.knockback"].remaining, 0)
end)

test("hitstop freezes scaled systems and world time", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local start_x = player.components.transform.x

    world:execute({
        type = "hitstop",
        duration = 0.05,
    }, {
        source = player,
        target = world:get("enemy"),
    })
    host.input:setAction("move_right", 1, 1)
    local advanced = world:update(1 / 60)
    equal(advanced, false)
    equal(world.time, 0)
    equal(player.components.transform.x, start_x)
    truthy(host.input:isDown("move_right"))

    for _ = 1, 2 do
        advanced = world:update(1 / 60)
        if advanced then host.input:endFrame() end
    end
    equal(world:snapshot().hitstop_remaining, 0)
    truthy(host.input:isDown("move_right"))

    advanced = world:update(1 / 60)
    truthy(advanced)
    if advanced then host.input:endFrame() end
    truthy(world.time > 0)
    truthy(player.components.transform.x > start_x)
end)

test("dodge moves independently and blocks damage during invulnerability", function()
    local host, world = createRuntime(runtimeDefinitions())
    local player = world:get("player")
    local enemy = world:get("enemy")
    local start_x = player.components.transform.x

    host.input:setAction("move_right", 1, 1)
    host.input:setAction("dodge", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    truthy(player.components.transform.x > start_x + 4)
    truthy(player.components["action.dodge"].active)
    truthy(
        player.components["action.reaction"].invulnerable_remaining > 0
    )

    local result = world:execute({
        type = "damage",
        amount = 10,
    }, {
        source = enemy,
        target = player,
    })
    truthy(result.blocked)
    equal(result.reason, "invulnerable")
    equal(player.components["action.health"].current, 50)
end)

test("parry schema compares explicit window with default perfect window", function()
    local files = runtimeDefinitions()
    files["content/actors/player.lua"].components["action.parry"].window = 0.05
    files["content/actors/player.lua"].components[
        "action.parry"
    ].perfect_window = nil

    local Host = require "engine.runtime.host"
    local host = Host.new(runtimeManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("must not exceed the full parry window"))
end)

test("dodge schema compares explicit duration with default invulnerability", function()
    local files = runtimeDefinitions()
    local dodge =
        files["content/actors/player.lua"].components["action.dodge"]
    dodge.duration = 0.1
    dodge.invulnerability = nil

    local Host = require "engine.runtime.host"
    local host = Host.new(runtimeManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("must not exceed dodge duration"))
end)

test("missing cross-content references fail before runtime", function()
    local files = runtimeDefinitions()
    files["content/stages/test.lua"].spawns[2].actor = "actor.missing"

    local Host = require "engine.runtime.host"
    local host = Host.new({
        features = {
            "engine.features.movement.topdown",
            "engine.features.action.combat",
        },
        content_roots = {"content"},
        input = {actions = {}},
    }, fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("actor%.missing"))
end)

test("unknown content fields fail instead of being ignored", function()
    local files = runtimeDefinitions()
    files["content/abilities/hit.lua"].damge = 999

    local Host = require "engine.runtime.host"
    local host = Host.new(
        runtimeManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("not a recognized field"))
    truthy(boot_error:match("damge"))
end)

test("player controller validates semantic input references", function()
    local files = runtimeDefinitions()
    local manifest = runtimeManifest()
    manifest.input.actions.attack = nil

    local Host = require "engine.runtime.host"
    local host = Host.new(manifest, fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("missing input action 'attack'"))
end)

test("failed content reload keeps the running world", function()
    local App = require "engine.core.app"
    local files = runtimeDefinitions()
    local app = App.new(
        runtimeManifest(),
        fakeFilesystem(files)
    )
    local loaded, load_error = app:load()
    truthy(loaded, load_error)
    local original_world = app.world

    files["content/stages/test.lua"].spawns[2].actor = "actor.missing"
    local reloaded, reload_error = app:reloadContent()
    equal(reloaded, nil)
    truthy(reload_error:match("actor%.missing"))
    equal(app.world, original_world)
    truthy(app.world:get("player"))
end)

test("content edit candidates validate without mutating files or world", function()
    local App = require "engine.core.app"
    local util = require "engine.core.util"
    local files = runtimeDefinitions()
    local app = App.new(
        runtimeManifest(),
        fakeFilesystem(files)
    )
    local loaded, load_error = app:load()
    truthy(loaded, load_error)
    local original_world = app.world
    local original_cooldown =
        files["content/abilities/hit.lua"].cooldown

    local candidate =
        util.deepCopy(files["content/abilities/hit.lua"])
    candidate.cooldown = 0.75
    local validated, validation_error =
        app:validateContentDefinition("ability.hit", candidate)
    truthy(validated, validation_error)
    truthy(validated.valid)
    equal(validated.definition.cooldown, 0.75)
    equal(
        files["content/abilities/hit.lua"].cooldown,
        original_cooldown
    )
    equal(app.host.catalog:get("ability.hit").cooldown, original_cooldown)
    equal(app.world, original_world)

    candidate.damge = 999
    validated, validation_error =
        app:validateContentDefinition("ability.hit", candidate)
    equal(validated, nil)
    truthy(validation_error:match("damge"), validation_error)
    equal(app.world, original_world)
end)

test("failed stage entry restores session tables by identity", function()
    local App = require "engine.core.app"
    local app = App.new({
        fixed_dt = 1 / 60,
    }, {})
    local flags = {ready = true}
    app.session.values.flags = flags
    app.session.versions.flags = 1
    app.host = {
        services = {},
        createWorld = function()
            flags.ready = nil
            flags.leaked = true
            app.session.values.extra = {bad = true}
            return nil, "stage initializer failed"
        end,
    }
    local loaded, load_error = app:loadStage("stage.bad")
    equal(loaded, nil)
    truthy(load_error:match("initializer failed"))
    equal(app.session.values.flags, flags)
    truthy(flags.ready)
    equal(flags.leaked, nil)
    equal(app.session.values.extra, nil)
end)

local function worldStageDefinitions()
    local files = runtimeDefinitions()
    local stage = files["content/stages/test.lua"]
    stage.walls = {
        {
            id = "wall.blocker",
            shape = {
                type = "rectangle",
                x = 150,
                y = 100,
                width = 20,
                height = 100,
            },
        },
        {
            id = "wall.polygon",
            shape = {
                type = "polygon",
                points = {
                    {x = 260, y = 220},
                    {x = 320, y = 220},
                    {x = 300, y = 270},
                },
            },
        },
    }
    stage.spawn_points = {
        {id = "default", x = 100, y = 100},
    }
    stage.triggers = {
        {
            id = "trigger.heal",
            shape = {
                type = "rectangle",
                x = 100,
                y = 100,
                width = 50,
                height = 50,
            },
            once = true,
            actions = {
                {type = "heal", amount = 15},
            },
        },
    }
    stage.portals = {
        {
            id = "portal.other",
            shape = {
                type = "rectangle",
                x = 250,
                y = 100,
                width = 40,
                height = 80,
            },
            target_stage = "stage.other",
            target_spawn = "entry",
        },
    }
    stage.camera = {
        viewport_width = 200,
        viewport_height = 150,
        follow_tag = "player",
    }
    files["content/stages/other.lua"] = {
        schema_version = 1,
        kind = "stage",
        id = "stage.other",
        name = "Other",
        width = 500,
        height = 300,
        spawns = {
            {
                id = "player",
                actor = "actor.player",
                position = {x = 50, y = 50},
            },
        },
        spawn_points = {
            {id = "entry", x = 300, y = 200},
        },
        camera = {
            viewport_width = 200,
            viewport_height = 150,
            follow_tag = "player",
        },
    }
    return files
end

local function worldStageManifest()
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.geometry")
    table.insert(manifest.features, "engine.features.navigation")
    table.insert(manifest.features, "engine.features.camera")
    return manifest
end

local function createWorldStageRuntime()
    local Host = require "engine.runtime.host"
    local files = worldStageDefinitions()
    local host = Host.new(worldStageManifest(), fakeFilesystem(files))
    local booted, boot_error = host:boot()
    truthy(booted, boot_error)
    local world, world_error = host:createWorld("stage.test")
    truthy(world, world_error)
    return host, world, files
end

test("stage geometry blocks motion without wall actor content", function()
    local host, world = createWorldStageRuntime()
    local player = world:get("player")
    host.input:setAction("move_right", 1, 30)
    for _ = 1, 30 do
        world:update(1 / 60)
        host.input:endFrame()
    end
    truthy(player.components.transform.x <= 130)
    equal(world:snapshot().geometry.wall_count, 2)
end)

test("stage trigger executes validated rule actions once", function()
    local host, world = createWorldStageRuntime()
    local player = world:get("player")
    local health = player.components["action.health"]
    health.current = 20

    world:update(1 / 60)
    host.input:endFrame()
    equal(health.current, 35)
    equal(world:snapshot().navigation.fired_triggers[1], "trigger.heal")

    world:update(1 / 60)
    host.input:endFrame()
    equal(health.current, 35)
end)

test("stage overlap uses hurtbox offsets and non-circle body extents", function()
    local files = worldStageDefinitions()
    local stage = files["content/stages/test.lua"]
    files["content/actors/player.lua"].components[
        "action.hurtbox"
    ] = {
        radius = 5,
        offset_x = 40,
        offset_y = 0,
    }
    stage.triggers = {
        {
            id = "trigger.offset",
            shape = {
                type = "rectangle",
                x = 140,
                y = 100,
                width = 4,
                height = 4,
            },
            once = true,
            actions = {
                {type = "emit", name = "offset.detected"},
            },
        },
    }
    local host, world = createRuntime(files, worldStageManifest())
    world:update(1 / 60)
    host.input:endFrame()
    equal(
        world:snapshot().navigation.fired_triggers[1],
        "trigger.offset"
    )

    files = worldStageDefinitions()
    files["content/actors/sensor.lua"] = {
        schema_version = 1,
        kind = "actor",
        id = "actor.sensor",
        tags = {"player"},
        components = {
            transform = {},
            body = {
                shape = "rectangle",
                width = 80,
                height = 10,
                solid = false,
            },
        },
    }
    stage = files["content/stages/test.lua"]
    stage.spawns = {
        {
            id = "sensor",
            actor = "actor.sensor",
            position = {x = 100, y = 100},
        },
    }
    stage.triggers = {
        {
            id = "trigger.extent",
            shape = {
                type = "rectangle",
                x = 140,
                y = 100,
                width = 4,
                height = 4,
            },
            once = true,
            actions = {
                {type = "emit", name = "extent.detected"},
            },
        },
    }
    host, world = createRuntime(files, worldStageManifest())
    world:update(1 / 60)
    host.input:endFrame()
    equal(
        world:snapshot().navigation.fired_triggers[1],
        "trigger.extent"
    )
end)

test("failed one-shot trigger remains available for retry", function()
    local Host = require "engine.runtime.host"
    local files = worldStageDefinitions()
    files["content/stages/test.lua"].triggers = {
        {
            id = "trigger.retry",
            shape = {
                type = "rectangle",
                x = 100,
                y = 100,
                width = 40,
                height = 40,
            },
            once = true,
            cooldown = 10,
            actions = {
                {
                    type = "heal",
                    amount = 5,
                },
                {
                    type = "start_encounter",
                    encounter = "missing",
                },
            },
        },
    }
    local host = Host.new(
        worldStageManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    truthy(booted, boot_error)
    local world, world_error = host:createWorld("stage.test")
    truthy(world, world_error)
    local player = world:get("player")
    local health = player.components["action.health"]
    health.current = 10

    world:update(1 / 60)
    host.input:endFrame()
    equal(#world:snapshot().navigation.fired_triggers, 0)
    equal(health.current, 10)

    player.components.transform.x = 50
    world:update(1 / 60)
    host.input:endFrame()
    player.components.transform.x = 100
    world:update(1 / 60)
    host.input:endFrame()

    local failures = 0
    for _, event in ipairs(world.events:recent(100)) do
        if event.name == "trigger.action_failed" then
            failures = failures + 1
        end
    end
    equal(failures, 2)
    equal(#world:snapshot().navigation.fired_triggers, 0)
    equal(health.current, 10)
end)

test("overlapping tilemap gid ranges fail validation", function()
    local Host = require "engine.runtime.host"
    local files = runtimeDefinitions()
    files["assets/tiles.png"] = "fake image bytes"
    files["content/assets/tiles.lua"] = {
        schema_version = 1,
        kind = "asset",
        id = "asset.tiles",
        asset_type = "image",
        path = "assets/tiles.png",
        width = 64,
        height = 32,
    }
    files["content/stages/test.lua"].tilemap = {
        tile_width = 16,
        tile_height = 16,
        tilesets = {
            {
                id = "first",
                first_gid = 1,
                tile_count = 4,
                columns = 4,
                tile_width = 16,
                tile_height = 16,
                asset = "asset.tiles",
            },
            {
                id = "second",
                first_gid = 4,
                tile_count = 2,
                columns = 2,
                tile_width = 16,
                tile_height = 16,
                asset = "asset.tiles",
            },
        },
        layers = {
            {
                id = "ground",
                width = 1,
                height = 1,
                data = {1},
            },
        },
    }
    local manifest = runtimeManifest()
    table.insert(manifest.features, "engine.features.tilemap")
    local host = Host.new(manifest, fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("gid range overlaps tileset 'first'"))
end)

test("camera follows and clamps to canonical viewport", function()
    local host, world = createWorldStageRuntime()
    local player = world:get("player")
    player.components.transform.x = 390
    player.components.transform.y = 290
    world:update(1 / 60)
    host.input:endFrame()
    local view = world:view()
    equal(view.x, 200)
    equal(view.y, 150)
    equal(view.width, 200)
    equal(view.height, 150)
    equal(view.target_id, "player")
end)

test("portal request atomically enters target spawn point", function()
    local App = require "engine.core.app"
    local files = worldStageDefinitions()
    local app = App.new(
        worldStageManifest(),
        fakeFilesystem(files)
    )
    local loaded, load_error = app:load()
    truthy(loaded, load_error)
    truthy(app.world:service("camera"):shake(app.world, {
        duration = 0.2,
        magnitude = 8,
        frequency = 30,
    }).applied)
    truthy(app.world:view().shake_remaining > 0)
    local player = app.world:get("player")
    player.components.transform.x = 250
    player.components.transform.y = 100

    app:update(1 / 60)
    equal(app.world.stage.id, "stage.other")
    equal(app.current_spawn_id, "entry")
    equal(app.transitions, 1)
    local entered = app.world:get("player").components.transform
    equal(entered.x, 300)
    equal(entered.y, 200)
    local entered_view = app.world:view()
    equal(entered_view.target_id, "player")
    equal(entered_view.shake_remaining, 0)
    equal(entered_view.shake_sequence, 0)
    truthy(entered_view.x >= 0 and entered_view.x <= 300)
    truthy(entered_view.y >= 0 and entered_view.y <= 150)
end)

test("portal target spawn is checked across stage content", function()
    local Host = require "engine.runtime.host"
    local files = worldStageDefinitions()
    files["content/stages/test.lua"].portals[1].target_spawn =
        "missing"
    local host = Host.new(
        worldStageManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("has no spawn point 'missing'"))
end)

test("game flow connects title, play, pause, save, gameover, and ending", function()
    local App = require "engine.core.app"
    local files = {
        ["content/actors/player.lua"] = {
            schema_version = 1,
            kind = "actor",
            id = "actor.player",
            tags = {"player"},
            components = {
                transform = {},
            },
        },
        ["content/stages/test.lua"] = {
            schema_version = 1,
            kind = "stage",
            id = "stage.test",
            name = "Test",
            width = 320,
            height = 180,
            spawns = {
                {
                    id = "player",
                    actor = "actor.player",
                    position = {x = 80, y = 90},
                },
            },
        },
    }
    local manifest = {
        id = "test.flow",
        profile = "action-rpg",
        title = "Flow Test",
        initial_stage = "stage.test",
        content_roots = {"content"},
        features = {
            "engine.features.game_flow",
        },
        flow = {
            save_slot = "campaign",
            start_stage = "stage.test",
        },
        input = {
            actions = {
                menu_up = {keys = {}},
                menu_down = {keys = {}},
                menu_confirm = {keys = {}},
                menu_cancel = {keys = {}},
                pause = {keys = {}},
                restart = {keys = {}},
                debug_overlay = {keys = {}},
            },
        },
    }
    local filesystem = fakeFilesystem(files)
    local app = App.new(manifest, filesystem)
    local loaded, load_error = app:load()
    truthy(loaded, load_error)
    equal(app.world:snapshot().game_flow.mode, "title")
    app:update(1 / 60)
    equal(app.world.time, 0)

    app.host.input:setAction("menu_confirm", 1, 1)
    app:update(1 / 60)
    equal(app.world:snapshot().game_flow.mode, "playing")
    truthy(app.world:snapshot().game_flow.started)

    app.host.input:setAction("pause", 1, 1)
    app:update(1 / 60)
    equal(app.world:snapshot().game_flow.mode, "paused")
    app.host.input:setAction("menu_confirm", 1, 1)
    app:update(1 / 60)
    equal(app.world:snapshot().game_flow.mode, "playing")

    local saved, save_error = app:save("campaign")
    truthy(saved, save_error)
    local returned, return_error = app:returnToTitle()
    truthy(returned, return_error)
    local title_state = app.world:snapshot().game_flow
    equal(title_state.mode, "title")
    truthy(title_state.has_save)
    equal(title_state.options[2], "continue")

    local continued, continue_error = app:loadSave("campaign")
    truthy(continued, continue_error)
    equal(app.world:snapshot().game_flow.mode, "playing")
    app.world.events:emit("actor.killed", {target_id = "player"})
    equal(app.world:snapshot().game_flow.mode, "gameover")

    local fresh, fresh_error = app:startNewGame("stage.test")
    truthy(fresh, fresh_error)
    local finished, finish_error =
        app.world:execute({type = "finish_game"})
    truthy(finished, finish_error)
    local ending = app.world:snapshot().game_flow
    equal(ending.mode, "ending")
    truthy(ending.completed)
end)

test("session flags survive stages and transactional content reload", function()
    local App = require "engine.core.app"
    local files = worldStageDefinitions()
    local manifest = worldStageManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.flags"
    )
    local app = App.new(manifest, fakeFilesystem(files))
    local loaded, load_error = app:load()
    truthy(loaded, load_error)

    local result = app.world:execute({
        type = "set_flag",
        name = "story.bridge_open",
    })
    truthy(result.applied)
    truthy(app.world:snapshot().flags["story.bridge_open"])

    loaded, load_error = app:loadStage("stage.other", "entry")
    truthy(loaded, load_error)
    truthy(app.host.rules:evaluate({
        type = "flag",
        name = "story.bridge_open",
    }))

    files["content/stages/test.lua"].portals[
        1
    ].target_spawn = "missing"
    local previous_world = app.world
    local reloaded, reload_error = app:reloadContent()
    equal(reloaded, nil)
    truthy(reload_error:match("has no spawn point 'missing'"))
    equal(app.world, previous_world)
    truthy(app.host.services.flags:get("story.bridge_open"))

    files["content/stages/test.lua"].portals[
        1
    ].target_spawn = "entry"
    reloaded, reload_error = app:reloadContent()
    truthy(reloaded, reload_error)
    truthy(app.host.services.flags:get("story.bridge_open"))
end)

test("session sections migrate independently and reject unknown data", function()
    local Session = require "engine.runtime.session"
    local store = {
        values = {
            example = {old_score = 7},
        },
        versions = {
            example = 1,
        },
    }
    local session = Session.new(store)
    local state = session:registerSection("example", {
        version = 2,
        defaults = {score = 0},
        migrations = {
            [1] = function(previous)
                return {score = previous.old_score}
            end,
        },
        validate = function(value)
            if type(value.score) ~= "number" then
                return nil, "score must be a number"
            end
            return true
        end,
    })
    equal(state.score, 7)
    equal(store.versions.example, 2)
    equal(store.values.example.old_score, nil)

    store.values["removed.feature"] = {}
    store.versions["removed.feature"] = 1
    local known, known_error = session:validateKnown()
    equal(known, nil)
    truthy(known_error:match("unknown session section"))
end)

test("save serializer is deterministic and rejects executable data", function()
    local serializer = require "engine.core.serializer"
    local first, first_error = serializer.encode({
        z = {2, 3},
        a = "value",
    })
    truthy(first, first_error)
    local second, second_error = serializer.encode({
        a = "value",
        z = {2, 3},
    })
    truthy(second, second_error)
    equal(first, second)
    truthy(first:find('["a"]="value"', 1, true))

    local chunk, load_error = loadstring(first, "@save-test")
    truthy(chunk, load_error)
    setfenv(chunk, {})
    local loaded = chunk()
    equal(loaded.a, "value")
    equal(loaded.z[2], 3)

    local encoded, encode_error = serializer.encode({
        callback = function() end,
    })
    equal(encoded, nil)
    truthy(encode_error:match("unsupported function"))
end)

test("save load restores feature state and rejects bad data transactionally", function()
    local App = require "engine.core.app"
    local files = worldStageDefinitions()
    local filesystem = fakeFilesystem(files)
    local manifest = worldStageManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.flags"
    )
    local app = App.new(manifest, filesystem)
    local loaded, load_error = app:load()
    truthy(loaded, load_error)
    local changed = app.host.services.flags:set(
        app.world,
        "story.saved",
        true
    )
    truthy(changed.applied)
    loaded, load_error = app:loadStage("stage.other", "entry")
    truthy(loaded, load_error)
    truthy(app.world:service("camera"):shake(app.world, {
        duration = 0.2,
        magnitude = 8,
        frequency = 30,
    }).applied)
    truthy(app.world:view().shake_remaining > 0)

    local saved, save_error = app:save("unit_slot")
    truthy(saved, save_error)
    equal(saved.stage_id, "stage.other")
    app.host.services.flags:set(app.world, "story.saved", false)
    loaded, load_error = app:loadStage("stage.test", "default")
    truthy(loaded, load_error)

    local restored, restore_error = app:loadSave("unit_slot")
    truthy(restored, restore_error)
    equal(app.current_stage_id, "stage.other")
    equal(app.current_spawn_id, "entry")
    truthy(app.host.services.flags:get("story.saved"))
    equal(app.world:view().target_id, "player")
    equal(app.world:view().shake_remaining, 0)
    equal(app.world:view().shake_sequence, 0)

    local invalid, export_error = app:exportSave()
    truthy(invalid, export_error)
    invalid.sections["removed.feature"] = {
        version = 1,
        data = {},
    }
    local previous_world = app.world
    local previous_host = app.host
    local previous_session = app.session
    restored, restore_error = app:importSave(invalid)
    equal(restored, nil)
    truthy(restore_error:match("unknown session section"))
    equal(app.world, previous_world)
    equal(app.host, previous_host)
    equal(app.session, previous_session)
    truthy(app.host.services.flags:get("story.saved"))
end)

test("inventory gives, validates, and consumes data-driven items", function()
    local files = runtimeDefinitions()
    files["content/items/potion.lua"] = {
        schema_version = 1,
        kind = "item",
        id = "item.potion",
        name = "Potion",
        stack_limit = 2,
        consumable = true,
        effects = {
            {type = "heal", amount = 10},
        },
        value = 25,
    }
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.inventory"
    )
    local _, world = createRuntime(files, manifest)
    local inventory = world:service("inventory")
    local player = world:get("player")
    player.components["action.health"].current = 20

    local result = world:execute({
        type = "give_item",
        item = "item.potion",
        amount = 2,
    })
    equal(result.count, 2)
    equal(inventory:count("item.potion"), 2)
    local overflow, overflow_error = inventory:give(
        world,
        "item.potion",
        1
    )
    equal(overflow, nil)
    truthy(overflow_error:match("stack limit"))

    result = world:execute({
        type = "use_item",
        item = "item.potion",
    }, {
        source = player,
        target = player,
    })
    truthy(result.applied)
    equal(player.components["action.health"].current, 30)
    equal(inventory:count("item.potion"), 1)
    truthy(world.host.rules:evaluate({
        type = "has_item",
        item = "item.potion",
        amount = 1,
    }))
end)

test("failed consumable effects roll back healing and item removal", function()
    local files = runtimeDefinitions()
    files["content/items/unstable.lua"] = {
        schema_version = 1,
        kind = "item",
        id = "item.unstable",
        name = "Unstable Potion",
        stack_limit = 1,
        consumable = true,
        effects = {
            {type = "heal", amount = 10},
            {
                type = "start_encounter",
                encounter = "missing.runtime.placement",
            },
        },
    }
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.inventory"
    )
    local _, world = createRuntime(files, manifest)
    local inventory = world:service("inventory")
    local player = world:get("player")
    player.components["action.health"].current = 20
    truthy(inventory:give(world, "item.unstable", 1))

    local result, use_error = world:execute({
        type = "use_item",
        item = "item.unstable",
    }, {
        source = player,
        target = player,
    })
    equal(result, nil)
    truthy(use_error:match("item effects failed"))
    equal(player.components["action.health"].current, 20)
    equal(inventory:count("item.unstable"), 1)
end)

test("consumable item requires validated effects", function()
    local files = runtimeDefinitions()
    files["content/items/bad.lua"] = {
        schema_version = 1,
        kind = "item",
        id = "item.bad",
        name = "Bad Item",
        consumable = true,
    }
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.inventory"
    )
    local Host = require "engine.runtime.host"
    local host = Host.new(manifest, fakeFilesystem(files))
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("require at least one effect"))
end)

local function equipmentDefinitions()
    local files = runtimeDefinitions()
    files["content/items/sword.lua"] = {
        schema_version = 1,
        kind = "item",
        id = "item.iron_sword",
        name = "Iron Sword",
        stack_limit = 1,
        value = 80,
        equipment = {
            slot = "weapon",
            modifiers = {
                attack = 5,
                move_speed = -0.1,
            },
        },
    }
    local player =
        files["content/actors/player.lua"].components
    player["rpg.stats"] = {
        attack = 2,
        defense = 0,
        move_speed = 1,
    }
    player["rpg.equipment"] = {
        loadout = "hero",
        slots = {"weapon", "armor"},
    }
    files["content/actors/enemy.lua"].components[
        "rpg.stats"
    ] = {
        defense = 3,
    }
    return files
end

local function equipmentManifest()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.equipment"
    )
    return manifest
end

test("equipment persists loadout and provides derived combat stats", function()
    local _, world = createRuntime(
        equipmentDefinitions(),
        equipmentManifest()
    )
    local player = world:get("player")
    local enemy = world:get("enemy")
    local inventory = world:service("inventory")
    local stats = world:service("stats")

    inventory:give(world, "item.iron_sword", 1)
    local result = world:execute({
        type = "equip_item",
        item = "item.iron_sword",
    }, {
        target = player,
    })
    truthy(result.applied)
    equal(result.slot, "weapon")
    equal(stats:value(world, player, "attack"), 7)
    equal(stats:value(world, player, "move_speed"), 0.9)

    result = world:execute({
        type = "damage",
        amount = 10,
    }, {
        source = player,
        target = enemy,
    })
    equal(result.amount, 14)
    equal(enemy.components["action.health"].current, 16)
    truthy(world.host.rules:evaluate({
        type = "item_equipped",
        item = "item.iron_sword",
        slot = "weapon",
    }, {
        target = player,
    }))

    local removed, remove_error = inventory:take(
        world,
        "item.iron_sword",
        1
    )
    equal(removed, nil)
    truthy(remove_error:match("equipped item"))
    world:execute({
        type = "unequip_slot",
        slot = "weapon",
    }, {
        target = player,
    })
    truthy(inventory:take(world, "item.iron_sword", 1))
end)

test("equipment rejects unknown stat modifier names", function()
    local files = equipmentDefinitions()
    files["content/items/sword.lua"].equipment.modifiers.atack = 9
    local Host = require "engine.runtime.host"
    local host = Host.new(
        equipmentManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("atack"))
    truthy(boot_error:match("not a recognized field"))
end)

local function localeDefinitions()
    local files = runtimeDefinitions()
    files["content/locales/en.lua"] = {
        schema_version = 1,
        kind = "locale",
        id = "locale.en",
        code = "en",
        strings = {
            ["item.potion.name"] = "Potion",
            ["ui.confirm"] = "Confirm",
        },
    }
    files["content/locales/ko.lua"] = {
        schema_version = 1,
        kind = "locale",
        id = "locale.ko",
        code = "ko",
        strings = {
            ["item.potion.name"] = "회복 물약",
        },
    }
    return files
end

local function localeManifest()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.locale"
    )
    manifest.locale = {
        default = "locale.ko",
        fallback = "locale.en",
    }
    return manifest
end

test("locale overrides fallback text and changes through rules", function()
    local _, world = createRuntime(
        localeDefinitions(),
        localeManifest()
    )
    local locale = world:service("locale")
    equal(locale:code(), "ko")
    equal(locale:text("item.potion.name"), "회복 물약")
    equal(locale:text("ui.confirm"), "Confirm")
    equal(locale:text("missing.key", "Fallback"), "Fallback")

    local result = world:execute({
        type = "set_locale",
        locale = "locale.en",
    })
    truthy(result.applied)
    equal(locale:text("item.potion.name"), "Potion")
    equal(world:snapshot().locale.id, "locale.en")
end)

test("locale content rejects duplicate language codes", function()
    local files = localeDefinitions()
    files["content/locales/duplicate.lua"] = {
        schema_version = 1,
        kind = "locale",
        id = "locale.other_ko",
        code = "ko",
        strings = {hello = "안녕"},
    }
    local Host = require "engine.runtime.host"
    local host = Host.new(
        localeManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("duplicates locale code"))
end)

local function dialogueDefinitions()
    local files = localeDefinitions()
    files["content/dialogues/guide.lua"] = {
        schema_version = 1,
        kind = "dialogue",
        id = "dialogue.guide",
        name_key = "dialogue.guide.name",
        start = "greeting",
        nodes = {
            greeting = {
                speaker_key = "npc.guide.name",
                text_key = "dialogue.guide.greeting",
                choices = {
                    {
                        id = "accept",
                        text_key = "dialogue.guide.accept",
                        condition = {
                            type = "not",
                            condition = {
                                type = "flag",
                                name = "story.guide_helped",
                            },
                        },
                        actions = {
                            {
                                type = "set_flag",
                                name = "story.guide_helped",
                            },
                        },
                        next = "thanks",
                    },
                    {
                        id = "leave",
                        text = "Leave",
                    },
                },
            },
            thanks = {
                speaker_key = "npc.guide.name",
                text_key = "dialogue.guide.thanks",
            },
        },
    }
    files["content/locales/en.lua"].strings[
        "dialogue.guide.name"
    ] = "Guide"
    files["content/locales/en.lua"].strings[
        "npc.guide.name"
    ] = "Guide"
    files["content/locales/en.lua"].strings[
        "dialogue.guide.greeting"
    ] = "Will you help?"
    files["content/locales/en.lua"].strings[
        "dialogue.guide.accept"
    ] = "I will."
    files["content/locales/en.lua"].strings[
        "dialogue.guide.thanks"
    ] = "Thank you."
    files["content/locales/ko.lua"].strings[
        "npc.guide.name"
    ] = "안내인"
    files["content/locales/ko.lua"].strings[
        "dialogue.guide.greeting"
    ] = "도와주시겠습니까?"
    files["content/locales/ko.lua"].strings[
        "dialogue.guide.accept"
    ] = "돕겠습니다."
    files["content/locales/ko.lua"].strings[
        "dialogue.guide.thanks"
    ] = "고맙습니다."
    files["content/actors/guide.lua"] = {
        schema_version = 1,
        kind = "actor",
        id = "actor.guide",
        tags = {"npc"},
        components = {
            transform = {},
            body = {
                shape = "circle",
                radius = 10,
                solid = false,
            },
            ["rpg.interactable"] = {
                input = "interact",
                range = 50,
                prompt = "Talk",
                actions = {
                    {
                        type = "start_dialogue",
                        dialogue = "dialogue.guide",
                    },
                },
            },
        },
    }
    table.insert(
        files["content/stages/test.lua"].spawns,
        {
            id = "guide",
            actor = "actor.guide",
            position = {x = 125, y = 100},
        }
    )
    return files
end

local function dialogueManifest()
    local manifest = localeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.flags"
    )
    table.insert(
        manifest.features,
        "engine.features.rpg.dialogue"
    )
    table.insert(
        manifest.features,
        "engine.features.rpg.interaction"
    )
    for _, action in ipairs({
        "interact",
        "menu_up",
        "menu_down",
        "menu_confirm",
        "menu_cancel",
    }) do
        manifest.input.actions[action] = {keys = {}}
    end
    return manifest
end

test("interaction drives localized conditional dialogue graph", function()
    local host, world = createRuntime(
        dialogueDefinitions(),
        dialogueManifest()
    )
    world:update(1 / 60)
    host.input:endFrame()
    equal(world:snapshot().interaction.target_id, "guide")

    host.input:setAction("interact", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    local snapshot = world:snapshot()
    truthy(snapshot.dialogue.active)
    equal(snapshot.dialogue.node_id, "greeting")
    equal(snapshot.dialogue.speaker, "안내인")
    equal(snapshot.dialogue.text, "도와주시겠습니까?")
    equal(snapshot.dialogue.choices[1].id, "accept")
    equal(snapshot.interaction.active, false)
    equal(snapshot.interaction.target_id, nil)
    local player = world:get("player")
    equal(world:allows(player, "move"), false)

    host.input:setAction("menu_confirm", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    snapshot = world:snapshot()
    equal(snapshot.dialogue.node_id, "thanks")
    truthy(world:service("flags"):get("story.guide_helped"))

    host.input:setAction("menu_confirm", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(world:snapshot().dialogue.active, false)
    truthy(world:allows(player, "move"))
end)

test("dialogue graph rejects missing node references", function()
    local files = dialogueDefinitions()
    files["content/dialogues/guide.lua"].nodes[
        "thanks"
    ] = nil
    local Host = require "engine.runtime.host"
    local host = Host.new(
        dialogueManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("references missing node 'thanks'"))
end)

local function questDefinitions()
    local files = runtimeDefinitions()
    files["content/items/reward.lua"] = {
        schema_version = 1,
        kind = "item",
        id = "item.quest_reward",
        name = "Quest Reward",
        stack_limit = 5,
    }
    files["content/quests/hunt.lua"] = {
        schema_version = 1,
        kind = "quest",
        id = "quest.slime_hunt",
        name = "Slime Hunt",
        objectives = {
            {
                id = "defeat_slimes",
                event = "actor.killed",
                count = 2,
                where = {
                    actor_id = "actor.enemy",
                },
            },
        },
        on_start = {
            {
                type = "set_flag",
                name = "quest.slime_hunt.started",
            },
        },
        on_complete = {
            {
                type = "give_item",
                item = "item.quest_reward",
            },
            {
                type = "set_flag",
                name = "quest.slime_hunt.completed",
            },
        },
    }
    return files
end

local function questManifest()
    local manifest = runtimeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.flags"
    )
    table.insert(
        manifest.features,
        "engine.features.rpg.inventory"
    )
    table.insert(
        manifest.features,
        "engine.features.rpg.quest"
    )
    return manifest
end

test("quest subscribes to events across world transitions", function()
    local Host = require "engine.runtime.host"
    local host = Host.new(
        questManifest(),
        fakeFilesystem(questDefinitions())
    )
    local booted, boot_error = host:boot()
    truthy(booted, boot_error)
    local world, world_error = host:createWorld("stage.test")
    truthy(world, world_error)

    local result = world:execute({
        type = "start_quest",
        quest = "quest.slime_hunt",
    })
    truthy(result.applied)
    truthy(host.services.flags:get("quest.slime_hunt.started"))
    world:execute({
        type = "damage",
        amount = 30,
    }, {
        source = world:get("player"),
        target = world:get("enemy"),
    })
    local state = host.services.quest:state("quest.slime_hunt")
    equal(state.objectives.defeat_slimes, 1)
    equal(state.status, "active")

    world, world_error = host:createWorld("stage.test")
    truthy(world, world_error)
    world:execute({
        type = "damage",
        amount = 30,
    }, {
        source = world:get("player"),
        target = world:get("enemy"),
    })
    equal(state.objectives.defeat_slimes, 2)
    equal(state.status, "completed")
    equal(
        host.services.inventory:count("item.quest_reward"),
        1
    )
    truthy(host.services.flags:get("quest.slime_hunt.completed"))
    equal(world:snapshot().quests[1].status, "completed")
end)

test("failed quest rewards roll back progress and remain retryable", function()
    local files = questDefinitions()
    files["content/items/reward.lua"].stack_limit = 1
    files["content/quests/hunt.lua"].objectives[1].count = 1
    files["content/quests/hunt.lua"].on_complete = {
        {
            type = "set_flag",
            name = "quest.slime_hunt.completed",
        },
        {
            type = "give_item",
            item = "item.quest_reward",
        },
    }
    local host, world = createRuntime(files, questManifest())
    local inventory = host.services.inventory
    truthy(inventory:give(world, "item.quest_reward", 1))
    truthy(world:execute({
        type = "start_quest",
        quest = "quest.slime_hunt",
    }))

    truthy(world:execute({
        type = "damage",
        amount = 30,
    }, {
        source = world:get("player"),
        target = world:get("enemy"),
    }))
    local state = host.services.quest:state("quest.slime_hunt")
    equal(state.status, "active")
    equal(state.objectives.defeat_slimes, 0)
    equal(inventory:count("item.quest_reward"), 1)
    equal(host.services.flags:get("quest.slime_hunt.completed"), false)
    local failure_seen = false
    for _, event in ipairs(world.events:recent(20)) do
        if event.name == "quest.action_failed" then
            failure_seen = true
        end
    end
    truthy(failure_seen)

    truthy(inventory:take(world, "item.quest_reward", 1))
    world.events:emit("actor.killed", {
        source_id = "player",
        target_id = "retry",
        actor_id = "actor.enemy",
    })
    equal(state.status, "completed")
    equal(state.objectives.defeat_slimes, 1)
    equal(inventory:count("item.quest_reward"), 1)
    truthy(host.services.flags:get("quest.slime_hunt.completed"))

    world.events:emit("actor.killed", {
        source_id = "player",
        target_id = "duplicate",
        actor_id = "actor.enemy",
    })
    equal(inventory:count("item.quest_reward"), 1)
end)

test("quest objective ids and references are strict", function()
    local files = questDefinitions()
    files["content/quests/hunt.lua"].objectives[2] = {
        id = "defeat_slimes",
        event = "actor.killed",
    }
    local Host = require "engine.runtime.host"
    local host = Host.new(
        questManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("duplicates another objective id"))
end)

local function shopDefinitions()
    local files = localeDefinitions()
    files["content/items/herb.lua"] = {
        schema_version = 1,
        kind = "item",
        id = "item.herb",
        name_key = "item.herb.name",
        stack_limit = 2,
        value = 10,
    }
    files["content/shops/village.lua"] = {
        schema_version = 1,
        kind = "shop",
        id = "shop.village",
        name_key = "shop.village.name",
        offers = {
            {
                item = "item.herb",
                buy_price = 20,
                sell_price = 10,
            },
        },
    }
    files["content/locales/en.lua"].strings[
        "item.herb.name"
    ] = "Herb"
    files["content/locales/en.lua"].strings[
        "shop.village.name"
    ] = "Village Shop"
    files["content/locales/ko.lua"].strings[
        "item.herb.name"
    ] = "약초"
    files["content/locales/ko.lua"].strings[
        "shop.village.name"
    ] = "마을 상점"
    return files
end

local function shopManifest()
    local manifest = localeManifest()
    table.insert(
        manifest.features,
        "engine.features.rpg.inventory"
    )
    table.insert(
        manifest.features,
        "engine.features.rpg.economy"
    )
    table.insert(
        manifest.features,
        "engine.features.rpg.shop"
    )
    for _, action in ipairs({
        "menu_up",
        "menu_down",
        "menu_left",
        "menu_right",
        "menu_confirm",
        "menu_cancel",
    }) do
        manifest.input.actions[action] = {keys = {}}
    end
    return manifest
end

test("shop buy and sell mutate currency and inventory atomically", function()
    local host, world = createRuntime(
        shopDefinitions(),
        shopManifest()
    )
    local economy = world:service("economy")
    local inventory = world:service("inventory")
    economy:add(world, 50, "test")

    local result = world:execute({
        type = "buy_item",
        shop = "shop.village",
        item = "item.herb",
    })
    truthy(result.applied)
    equal(economy:balance(), 30)
    equal(inventory:count("item.herb"), 1)

    result = world:execute({
        type = "sell_item",
        shop = "shop.village",
        item = "item.herb",
    })
    truthy(result.applied)
    equal(economy:balance(), 40)
    equal(inventory:count("item.herb"), 0)

    inventory:give(world, "item.herb", 2)
    local balance = economy:balance()
    local bought, buy_error = world:service("shop"):buy(
        world,
        "shop.village",
        "item.herb",
        1
    )
    equal(bought, nil)
    truthy(buy_error:match("stack limit"))
    equal(economy:balance(), balance)
    equal(inventory:count("item.herb"), 2)
end)

test("shop menu uses semantic input and exposes localized state", function()
    local host, world = createRuntime(
        shopDefinitions(),
        shopManifest()
    )
    world:service("economy"):add(world, 50, "test")
    local result = world:execute({
        type = "open_shop",
        shop = "shop.village",
    })
    truthy(result.applied)
    equal(world:allows(world:get("player"), "move"), false)

    world:update(1 / 60)
    host.input:endFrame()
    host.input:setAction("menu_confirm", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    local snapshot = world:snapshot()
    truthy(snapshot.shop.active)
    equal(snapshot.shop.offers[1].name, "약초")
    equal(snapshot.shop.offers[1].owned, 1)
    equal(snapshot.shop.balance, 30)

    host.input:setAction("menu_cancel", 1, 1)
    world:update(1 / 60)
    host.input:endFrame()
    equal(world:snapshot().shop.active, false)
end)

test("shop rejects duplicate item offers", function()
    local files = shopDefinitions()
    files["content/shops/village.lua"].offers[2] = {
        item = "item.herb",
        buy_price = 99,
    }
    local Host = require "engine.runtime.host"
    local host = Host.new(
        shopManifest(),
        fakeFilesystem(files)
    )
    local booted, boot_error = host:boot()
    equal(booted, nil)
    truthy(boot_error:match("duplicates another shop offer"))
end)

test("polygon geometry detects interior and edge overlap", function()
    local geometry = require "engine.core.geometry"
    local triangle = {
        {x = 0, y = 0},
        {x = 100, y = 0},
        {x = 50, y = 100},
    }
    truthy(geometry.pointInPolygon(50, 30, triangle))
    equal(geometry.pointInPolygon(120, 30, triangle), false)
    truthy(geometry.circleIntersectsPolygon(50, 105, 6, triangle))
    equal(
        geometry.circleIntersectsPolygon(50, 120, 6, triangle),
        false
    )
end)

print(string.format("%d tests passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
