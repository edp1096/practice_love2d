local root = arg[1] or "."
package.path = table.concat({
    root .. "/?.lua",
    root .. "/?/init.lua",
    package.path,
}, ";")

local passed = 0
local failed = 0

local function test(name, callback)
    io.write("  " .. name .. " ... ")
    local success, err = xpcall(callback, debug.traceback)
    if success then
        passed = passed + 1
        print("ok")
    else
        failed = failed + 1
        print("FAILED")
        print(err)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format(
            "%s: expected %s, got %s",
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

print("31_dev_proto unit tests")

test("JSON is deterministic and escapes control characters", function()
    local json = require "engine.core.debug.json"
    equal(
        json.encode({z = "line\n", a = true, list = {1, 2}}),
        '{"a":true,"list":[1,2],"z":"line\\n"}'
    )
end)

test("JSON flat parameter parser handles primitives", function()
    local json = require "engine.core.debug.json"
    local line =
        '{"id":9,"params":{"name":"a\\\"b","x":-1.25,"enabled":false}}'
    equal(json.getNumber(line, "id"), 9)
    equal(json.getString(line, "name"), 'a"b')
    equal(json.getNumber(line, "x"), -1.25)
    equal(json.getBoolean(line, "enabled"), false)
end)

test("Save codec is safe, deterministic, and preserves sparse slots", function()
    local codec = require "engine.core.save_codec"
    local sparse = {
        [1] = "potion",
        [3] = "bomb",
        name = "quickslots",
        nested = {enabled = true, count = 2},
    }
    local encoded, encode_error = codec.encode(sparse)
    equal(encode_error, nil)
    local decoded, decode_error = codec.decode(encoded)
    equal(decode_error, nil)
    equal(decoded[1], "potion")
    equal(decoded[2], nil)
    equal(decoded[3], "bomb")
    equal(decoded.nested.enabled, true)
    equal(codec.encode(sparse), encoded, "encoding must be deterministic")

    local legacy, legacy_error = codec.decode(
        'return { "first", ["flag"] = true, [3] = "third", }'
    )
    equal(legacy_error, nil)
    equal(legacy[1], "first")
    equal(legacy[2], nil)
    equal(legacy[3], "third")

    _G.SAVE_CODEC_EXECUTED = false
    local malicious, malicious_error = codec.decode(
        '{["value"]=(function() SAVE_CODEC_EXECUTED=true end)()}'
    )
    equal(malicious, nil)
    equal(type(malicious_error), "string")
    equal(_G.SAVE_CODEC_EXECUTED, false)
end)

test("Slot metadata inspection does not change the recent slot", function()
    local codec = require "engine.core.save_codec"
    local contents = assert(codec.encode({
        map = "assets/maps/level1/area2.lua",
        hp = 7,
        max_hp = 10,
        timestamp = 100,
    }))
    local files = {
        ["saves/save_2.lua"] = contents,
    }
    local writes = {}
    _G.love = {
        filesystem = {
            createDirectory = function() return true end,
            getInfo = function(path)
                if files[path] then return {type = "file"} end
            end,
            read = function(path) return files[path] end,
            write = function(path, value)
                writes[#writes + 1] = {path = path, value = value}
                files[path] = value
                return true
            end,
        },
    }
    package.loaded["engine.core.save"] = nil
    local save = require "engine.core.save"
    local info = save:getSlotInfo(2)
    equal(info.exists, true)
    equal(info.level, 1)
    equal(info.area, 2)
    equal(#writes, 0)

    equal(save:loadGame(2).hp, 7)
    equal(#writes, 1)
    equal(writes[1].path, save.RECENT_SLOT_FILE)
end)

test("Inventory and checkpoint snapshots do not share mutable state", function()
    package.loaded["engine.systems.inventory"] = nil
    local inventory = require "engine.systems.inventory"
    local instance = inventory:new({})
    instance.quickslots[1] = "potion"
    instance.quickslots[3] = "bomb"
    local inventory_save = instance:save()
    instance.quickslots[1] = "changed"
    equal(inventory_save.quickslots[1], "potion")
    equal(inventory_save.quickslots[2], nil)
    equal(inventory_save.quickslots[3], "bomb")

    local registry = {
        killed_enemies = {slime = {dead = true}},
        picked_items = {},
        transformed_npcs = {},
        destroyed_props = {},
        syncFromWorld = function() end,
    }
    package.loaded["engine.core.entity_registry"] = registry
    package.loaded["engine.utils.helpers"] = {
        syncPersistenceData = function() end,
    }
    package.loaded["engine.core.persistence"] = nil
    local persistence = require "engine.core.persistence"
    persistence.registered_systems = {}
    persistence:registerSystem("fixture", function()
        return {quickslots = {[1] = "potion", [3] = "bomb"}}
    end)
    persistence:saveCheckpoint({
        current_map_path = "test.lua",
        map_entry_x = 10,
        map_entry_y = 20,
        current_save_slot = 1,
        world = {},
    })

    registry.killed_enemies.slime.dead = false
    local first = persistence:getCheckpoint()
    equal(first.killed_enemies.slime.dead, true)
    first.systems_data.fixture.quickslots[1] = "changed"
    local second = persistence:getCheckpoint()
    equal(second.systems_data.fixture.quickslots[1], "potion")
    equal(second.systems_data.fixture.quickslots[2], nil)
    equal(second.systems_data.fixture.quickslots[3], "bomb")
end)

test("Scene stack restores nested pause screens in order", function()
    package.loaded["engine.core.scene_control"] = nil
    local scene_control = require "engine.core.scene_control"
    local function scene(name)
        return {
            name = name,
            enter = function(self, previous)
                self.entered_from = previous and previous.name
            end,
            pause = function(self) self.paused = true end,
            resume = function(self) self.resumed = true end,
            exit = function(self) self.exited = true end,
        }
    end

    local gameplay = scene("gameplay")
    local pause = scene("pause")
    local settings = scene("settings")
    scene_control.switch(gameplay)
    scene_control.push(pause)
    scene_control.push(settings)
    equal(scene_control.current, settings)
    equal(pause.paused, true)

    scene_control.pop()
    equal(scene_control.current, pause)
    equal(pause.resumed, true)
    scene_control.pop()
    equal(scene_control.current, gameplay)
    equal(gameplay.resumed, true)

    local credits = scene("credits")
    scene_control.switch(credits)
    scene_control.pop()
    equal(scene_control.current, gameplay, "switch/pop fallback")
end)

test("BGM loop and intentional pause state are respected", function()
    local sources = {}
    local function new_source()
        local source = {
            playing = false,
            volume = 1,
            setLooping = function(self, value) self.looping = value end,
            setVolume = function(self, value) self.volume = value end,
            getVolume = function(self) return self.volume end,
            isPlaying = function(self) return self.playing end,
            play = function(self) self.playing = true end,
            pause = function(self) self.playing = false end,
            stop = function(self) self.playing = false end,
            seek = function() end,
        }
        sources[#sources + 1] = source
        return source
    end
    _G.APP_CONFIG = nil
    _G.love = {
        filesystem = {getInfo = function() return {type = "file"} end},
        audio = {newSource = function() return new_source() end},
    }
    package.loaded["engine.core.sound"] = nil
    local sound = require "engine.core.sound"
    sound:_loadBGM("ending", {
        path = "ending.mp3",
        loop = false,
        volume = 0.8,
    })
    equal(sources[1].looping, false)

    sound:playBGM("ending")
    equal(sources[1].playing, true)
    sound:pauseBGM()
    equal(sound.bgm_paused, true)
    equal(sound:shouldAutoResumeBGM(), false)
    sound:toggleMute()
    sound:toggleMute()
    equal(sources[1].playing, false, "unmute must preserve manual pause")
    sound:resumeBGM()
    equal(sound.bgm_paused, false)
    equal(sources[1].playing, true)
end)

test("Inspector gives stable IDs and controls entity state", function()
    package.loaded["engine.core.debug.inspector"] = nil

    local fixture = {
        getBoundingBox = function()
            return 90, 190, 110, 230
        end,
    }
    local collider = {
        id = "physics-player",
        type = "Rectangle",
        collision_class = "Player",
        body = {},
        fixtures = {main = fixture},
        x = 100,
        y = 210,
        isDestroyed = function() return false end,
        getPosition = function(self) return self.x, self.y end,
        setPosition = function(self, x, y) self.x, self.y = x, y end,
        getLinearVelocity = function() return 3, 4 end,
        setLinearVelocity = function(self, x, y)
            self.velocity_x, self.velocity_y = x, y
        end,
        getType = function() return "dynamic" end,
    }
    local player = {
        x = 100,
        y = 200,
        health = 8,
        max_health = 10,
        state = "idle",
        collider = collider,
    }
    local world = {
        game_mode = "topdown",
        map = {
            width = 20,
            height = 10,
            tilewidth = 16,
            tileheight = 16,
            properties = {name = "test_map"},
        },
        enemies = {},
        npcs = {},
        world_items = {},
        props = {},
        vehicles = {},
        healing_points = {},
        savepoints = {},
        walls = {},
        transitions = {},
        death_zones = {},
        damage_zones = {},
    }
    local scene = {
        player = player,
        world = world,
        current_map_path = "test.lua",
        cam = {
            x = 0,
            y = 0,
            scale = 1,
            rot = 0,
            cameraCoords = function(_, x, y) return x + 5, y + 7 end,
        },
    }

    package.loaded["engine.core.scene_control"] = {current = scene}
    _G.love = {
        graphics = {
            getDimensions = function() return 960, 540 end,
        },
    }

    local inspector = require "engine.core.debug.inspector"
    local first = inspector:snapshot()
    local second = inspector:snapshot()
    equal(first.available, true)
    equal(first.entities[1].id, "player")
    equal(second.entities[1].id, "player")
    equal(first.entities[1].screen.x, 105)
    equal(first.entities[1].collider.velocity_y, 4)

    local moved, move_error =
        inspector:setPosition("player", 140, 250, true)
    equal(move_error, nil)
    equal(moved.x, 140)
    equal(moved.y, 250)
    equal(collider.x, 140)
    equal(collider.y, 260)
    equal(collider.velocity_x, 0)

    local damaged, health_error = inspector:setHealth("player", 3)
    equal(health_error, nil)
    equal(damaged.health, 3)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
