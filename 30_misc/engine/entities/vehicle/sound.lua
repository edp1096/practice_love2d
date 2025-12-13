-- engine/entities/vehicle/sound.lua
-- Vehicle sound management with per-type sound support
-- Each vehicle type can define custom sounds in game/data/entities/vehicles.lua

local sound = require "engine.core.sound"

local vehicle_sound = {}

-- Default sound paths (fallback when vehicle type doesn't define custom sounds)
local DEFAULT_SOUNDS = {
    summon = "assets/sound/vehicle/summon.wav",
    board = "assets/sound/vehicle/board.wav",
    dismount = "assets/sound/vehicle/dismount.wav",
    engine_loop = "assets/sound/vehicle/engine_loop.wav",
}

-- Engine loop sources per vehicle type
local engine_sources = {}
local engine_volume = 0.4

-- State tracking
local is_engine_playing = false
local current_vehicle = nil

-- Get sound path for a vehicle type
-- Returns custom path if defined, otherwise default
local function getSoundPath(vehicle, sound_name)
    if vehicle and vehicle.sounds and vehicle.sounds[sound_name] then
        return vehicle.sounds[sound_name]
    end
    return DEFAULT_SOUNDS[sound_name]
end

-- Get or create engine source for a vehicle type
local function getEngineSource(vehicle)
    if not vehicle then return nil end

    local vehicle_type = vehicle.type or "default"

    -- Already cached
    if engine_sources[vehicle_type] then
        return engine_sources[vehicle_type]
    end

    -- Create new source for this type
    local path = getSoundPath(vehicle, "engine_loop")
    local info = love.filesystem.getInfo(path)

    if info then
        local source = love.audio.newSource(path, "static")
        source:setLooping(true)
        source:setVolume(engine_volume * sound.settings.sfx_volume * sound.settings.master_volume)
        engine_sources[vehicle_type] = source
        return source
    end

    return nil
end

-- Play a one-shot sound for a vehicle
local function playVehicleSound(vehicle, sound_name)
    if sound.settings.muted then return end

    local path = getSoundPath(vehicle, sound_name)
    local info = love.filesystem.getInfo(path)

    if info then
        local source = love.audio.newSource(path, "static")
        source:setVolume(0.6 * sound.settings.sfx_volume * sound.settings.master_volume)
        source:play()
    else
        -- Fallback to sfx system if custom path not found
        if sound.sfx.vehicle and sound.sfx.vehicle[sound_name] then
            sound:playSFX("vehicle", sound_name)
        end
    end
end

-- Update engine sound based on vehicle state
function vehicle_sound.update(vehicle, is_moving)
    if not vehicle then return end

    local engine_source = getEngineSource(vehicle)
    if not engine_source then return end

    -- Check if this is a different vehicle
    if current_vehicle ~= vehicle then
        vehicle_sound.stopEngine()
        current_vehicle = vehicle
    end

    if is_moving then
        if not is_engine_playing then
            vehicle_sound.startEngine(vehicle)
        end
        -- Higher pitch when moving
        engine_source:setPitch(1.1)
    else
        if is_engine_playing then
            -- Lower pitch when idle
            engine_source:setPitch(0.9)
        end
    end
end

-- Start engine sound for a vehicle
function vehicle_sound.startEngine(vehicle)
    if sound.settings.muted then return end

    local engine_source = getEngineSource(vehicle or current_vehicle)
    if not engine_source then return end

    if not is_engine_playing then
        engine_source:setVolume(engine_volume * sound.settings.sfx_volume * sound.settings.master_volume)
        engine_source:play()
        is_engine_playing = true
    end
end

-- Stop engine sound
function vehicle_sound.stopEngine()
    if current_vehicle then
        local engine_source = getEngineSource(current_vehicle)
        if engine_source and is_engine_playing then
            engine_source:stop()
        end
    end
    is_engine_playing = false
    current_vehicle = nil
end

-- Pause engine sound
function vehicle_sound.pauseEngine()
    if current_vehicle then
        local engine_source = getEngineSource(current_vehicle)
        if engine_source and is_engine_playing then
            engine_source:pause()
        end
    end
end

-- Resume engine sound
function vehicle_sound.resumeEngine()
    if current_vehicle and not sound.settings.muted then
        local engine_source = getEngineSource(current_vehicle)
        if engine_source and is_engine_playing then
            engine_source:play()
        end
    end
end

-- Play summon sound for a vehicle
function vehicle_sound.playSummon(vehicle)
    playVehicleSound(vehicle, "summon")
end

-- Play board sound for a vehicle
function vehicle_sound.playBoard(vehicle)
    playVehicleSound(vehicle, "board")
end

-- Play dismount sound for a vehicle
function vehicle_sound.playDismount(vehicle)
    playVehicleSound(vehicle, "dismount")
end

-- Update volume when settings change
function vehicle_sound.updateVolume()
    for _, source in pairs(engine_sources) do
        source:setVolume(engine_volume * sound.settings.sfx_volume * sound.settings.master_volume)
    end
end

-- Check if engine is playing
function vehicle_sound.isEnginePlaying()
    return is_engine_playing
end

-- Cleanup all sounds
function vehicle_sound.cleanup()
    vehicle_sound.stopEngine()
    for type_name, source in pairs(engine_sources) do
        source:stop()
    end
    engine_sources = {}
    current_vehicle = nil
end

-- Preload sounds for a vehicle type (optional, for faster first play)
function vehicle_sound.preload(vehicle)
    getEngineSource(vehicle)
end

return vehicle_sound
