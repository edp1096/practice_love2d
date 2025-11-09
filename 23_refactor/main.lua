-- main.lua
-- Game entry point

function love.errorhandler(msg)
    msg = tostring(msg)
    local trace = debug.traceback("Error: " .. msg, 2):gsub("\n[^\n]+$", "")

    print("=== FATAL ERROR ===")
    print(trace)

    local log_path = love.filesystem.getSaveDirectory() .. "/crash.log"
    local success, file = pcall(io.open, log_path, "w")
    if success and file then
        file:write("LOVE2D Crash Report\n")
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        file:write(trace .. "\n")
        file:close()
        print("Crash log written to: " .. log_path)
    end

    pcall(function()
        love.filesystem.write("crash.log", trace)
        print("Crash log also saved to: " .. love.filesystem.getSaveDirectory() .. "/crash.log")
    end)

    return function()
        love.event.quit()
    end
end

local love_version = (love._version_major .. "." .. love._version_minor)

local is_android = love.system.getOS() == "Android"
local is_mobile = is_android or love.system.getOS() == "iOS"

local locker
if not is_mobile and _VERSION == "Lua 5.1" then
    local success, result = pcall(require, "locker")
    if success then
        locker = result
    else
        dprint("Warning: Could not load locker module: " .. tostring(result))
    end
end


-- Define global dprint BEFORE loading other modules that might use it
local debug = require "engine.core.debug"

-- Initialize debug mode from config
debug.allowed = GameConfig.is_debug  -- Allow F1-F6 keys if true
debug.enabled = false  -- Debug UI starts OFF, user must press F1 to enable

_G.dprint = function(...) debug:dprint(...) end

-- Print version info
dprint("Running with LOVE " .. love_version .. " and " .. _VERSION)

-- Now load other modules (they can safely use dprint)
local display = require "engine.core.display"
_G.screen = display  -- Global for Talkies compatibility
local utils = require "engine.utils.util"
local scene_control = require "engine.core.scene_control"
local input = require "engine.core.input"
local input_dispatcher = require "engine.core.input.dispatcher"
local lifecycle = require "engine.core.lifecycle"
local sound = require "engine.core.sound"
local fonts = require "engine.utils.fonts"
local coords = require "engine.core.coords"
local effects = require "engine.systems.effects"
local menu = require "game.scenes.menu"

-- Always load virtual_gamepad (needed for PC debug mode testing)
local virtual_gamepad = require "engine.core.input.virtual_gamepad"

-- === Application Lifecycle ===

function love.load()
    -- Load mobile config if on mobile (for LÖVE runtime app)
    if is_mobile then
        local success, mobile_config = pcall(function()
            local content = love.filesystem.read("mobile_config.lua")
            if content then
                local chunk = load(content)
                if chunk then
                    return chunk()
                end
            end
            return nil
        end)

        if success and mobile_config then
            if mobile_config.sound then
                if mobile_config.sound.master_volume ~= nil then
                    GameConfig.sound.master_volume = mobile_config.sound.master_volume
                end
                if mobile_config.sound.bgm_volume ~= nil then
                    GameConfig.sound.bgm_volume = mobile_config.sound.bgm_volume
                end
                if mobile_config.sound.sfx_volume ~= nil then
                    GameConfig.sound.sfx_volume = mobile_config.sound.sfx_volume
                end
                if mobile_config.sound.muted ~= nil then
                    GameConfig.sound.muted = mobile_config.sound.muted
                end
            end
            if mobile_config.input then
                if mobile_config.input.deadzone ~= nil then
                    GameConfig.input.deadzone = mobile_config.input.deadzone
                end
                if mobile_config.input.vibration_enabled ~= nil then
                    GameConfig.input.vibration_enabled = mobile_config.input.vibration_enabled
                end
                if mobile_config.input.vibration_strength ~= nil then
                    GameConfig.input.vibration_strength = mobile_config.input.vibration_strength
                end
                if mobile_config.input.mobile_vibration_enabled ~= nil then
                    GameConfig.input.mobile_vibration_enabled = mobile_config.input.mobile_vibration_enabled
                end
            end
        end
    end

    -- Initialize sound system AFTER loading config
    local sound_data = require "game.data.sounds"
    sound:init(sound_data)

    -- Initialize input system with config
    local input_config = require "game.data.input_config"
    input:init(input_config)

    -- Inject entity type data into engine classes (dependency injection)
    local entity_types = require "game.data.entities.types"
    local enemy_class = require "engine.entities.enemy"
    local npc_class = require "engine.entities.npc"
    local weapon_class = require "engine.entities.weapon"

    enemy_class.type_registry = entity_types.enemies
    npc_class.type_registry = entity_types.npcs
    weapon_class.type_registry = entity_types.weapons
    weapon_class.effects_config = entity_types.weapon_effects

    -- Inject game data into engine systems
    local game_config = require "game.data.game_config"
    local entity_defaults = require "game.data.entities.defaults"
    local player_config = require "game.data.player"
    local cutscene_configs = require "game.data.cutscenes"

    local constants = require "engine.core.constants"
    local factory = require "engine.entities.factory"
    local player_sound = require "engine.entities.player.sound"
    local enemy_sound = require "engine.entities.enemy.sound"
    local gameplay_scene = require "engine.scenes.gameplay"
    local cutscene_scene = require "engine.scenes.cutscene"

    -- Inject game start defaults
    constants.GAME_START.DEFAULT_MAP = game_config.start.map
    constants.GAME_START.DEFAULT_SPAWN_X = game_config.start.spawn_x
    constants.GAME_START.DEFAULT_SPAWN_Y = game_config.start.spawn_y

    -- Inject entity factory defaults
    factory.DEFAULTS = entity_defaults

    -- Inject sound configs
    player_sound.sounds_config = sound_data
    enemy_sound.sounds_config = sound_data

    -- Inject player config
    gameplay_scene.player_config = player_config

    -- Inject cutscene configs
    cutscene_scene.configs = cutscene_configs

    -- Inject game scene path prefix into builder
    local builder = require "engine.scenes.builder"
    local game_scene_prefix = "game.scenes."
    builder.game_scene_prefix = game_scene_prefix

    -- Setup scene loader (inject scene loading into engine)
    scene_control.scene_loader = function(scene_name)
        -- Engine UI screens
        local engine_ui_paths = {
            newgame = "engine.ui.screens.newgame",
            saveslot = "engine.ui.screens.saveslot",
            inventory = "engine.ui.screens.inventory",
            load = "engine.ui.screens.load",
            settings = "engine.ui.screens.settings"
        }

        -- Engine scenes
        local engine_scene_paths = {
            cutscene = "engine.scenes.cutscene",
            intro = "engine.scenes.cutscene",  -- legacy
            gameplay = "engine.scenes.gameplay"
        }

        -- Check engine paths first
        if engine_ui_paths[scene_name] then
            return require(engine_ui_paths[scene_name])
        end
        if engine_scene_paths[scene_name] then
            return require(engine_scene_paths[scene_name])
        end

        -- Fall back to game scenes (menu, pause, gameover) - uses configured prefix
        return require(game_scene_prefix .. scene_name)
    end

    -- Setup input dispatcher
    input_dispatcher.scene_control = scene_control
    input_dispatcher.virtual_gamepad = virtual_gamepad
    input_dispatcher.input = input
    input_dispatcher.is_mobile = is_mobile

    -- Setup app lifecycle
    lifecycle.locker = locker
    lifecycle.display = display
    lifecycle.input = input
    lifecycle.virtual_gamepad = virtual_gamepad
    lifecycle.fonts = fonts
    lifecycle.scene_control = scene_control
    lifecycle.utils = utils
    lifecycle.sound = sound
    lifecycle.effects = effects
    lifecycle.GameConfig = GameConfig
    lifecycle.is_mobile = is_mobile

    -- Initialize coordinate system (must be after display initialization)
    -- Note: camera is scene-specific, so coords will use it dynamically
    coords:init(nil, display)

    -- Initialize application
    lifecycle:initialize(menu)
end

function love.update(dt) lifecycle:update(dt) end

function love.draw() lifecycle:draw() end

function love.resize(w, h) lifecycle:resize(w, h) end

-- === Input Event Handlers ===

function love.keypressed(key)
    -- Handle system-level hotkeys (F11, F1)
    if key == "f11" and not is_mobile then
        display:ToggleFullScreen()
        GameConfig.fullscreen = display.is_fullscreen
        pcall(utils.SaveConfig, utils, GameConfig, sound.settings, input.settings, nil)
        lifecycle:resize(love.graphics.getWidth(), love.graphics.getHeight())
        return
    end

    -- Delegate all other input to dispatcher
    input_dispatcher:keypressed(key)
end

function love.keyreleased(key)
    input_dispatcher:keyreleased(key)
end

function love.mousepressed(x, y, button) input_dispatcher:mousepressed(x, y, button) end

function love.mousereleased(x, y, button) input_dispatcher:mousereleased(x, y, button) end

function love.touchpressed(id, x, y, dx, dy, pressure) input_dispatcher:touchpressed(id, x, y, dx, dy, pressure) end

function love.touchreleased(id, x, y, dx, dy, pressure) input_dispatcher:touchreleased(id, x, y, dx, dy, pressure) end

function love.touchmoved(id, x, y, dx, dy, pressure) input_dispatcher:touchmoved(id, x, y, dx, dy, pressure) end

function love.joystickadded(joystick) input_dispatcher:joystickadded(joystick) end

function love.joystickremoved(joystick) input_dispatcher:joystickremoved(joystick) end

function love.gamepadpressed(joystick, button) input_dispatcher:gamepadpressed(joystick, button) end

function love.gamepadreleased(joystick, button) input_dispatcher:gamepadreleased(joystick, button) end

function love.gamepadaxis(joystick, axis, value) input_dispatcher:gamepadaxis(joystick, axis, value) end

function love.quit() lifecycle:quit() end
