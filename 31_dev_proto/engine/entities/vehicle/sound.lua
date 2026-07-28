-- engine/entities/vehicle/sound.lua
-- Vehicle sound management with idle/drive states
-- Supports per-type custom sounds via game/data/entities/vehicles.lua

local sound = require "engine.core.sound"

local vehicle_sound = {}

-- Default sound paths (fallback when vehicle type doesn't define custom sounds)
local DEFAULT_SOUNDS = {
    summon = "assets/sound/vehicle/summon.wav",
    board = "assets/sound/vehicle/board.wav",
    dismount = "assets/sound/vehicle/dismount.wav",
    engine_idle = "assets/sound/vehicle/engine_idle.wav",
    engine_start = "assets/sound/vehicle/engine_start.wav",
    engine_drive = "assets/sound/vehicle/engine_drive.wav",
}

-- Sound sources per vehicle type
local sound_sources = {}  -- [vehicle_type][sound_name] = source

-- State tracking
local current_vehicle = nil
local current_state = nil  -- "idle" or "drive"
local pending_drive = nil  -- { vehicle, timer } for delayed drive start after engine_start

-- Get sound path for a vehicle type
local function getSoundPath(vehicle, sound_name)
    if vehicle and vehicle.sounds and vehicle.sounds[sound_name] then
        return vehicle.sounds[sound_name]
    end
    return DEFAULT_SOUNDS[sound_name]
end

-- Get volume from sounds.lua config or use default
local function getSoundVolume(sound_name)
    -- Use sounds.lua vehicle section (NOT sfx.vehicle)
    if sound.sound_data and sound.sound_data.vehicle and sound.sound_data.vehicle[sound_name] then
        return sound.sound_data.vehicle[sound_name].volume or 0.5
    end
    return 0.5
end

-- Get or create looping source for a vehicle type
local function getLoopSource(vehicle, sound_name)
    if not vehicle then return nil end

    local vehicle_type = vehicle.type or "default"

    -- Init type cache
    if not sound_sources[vehicle_type] then
        sound_sources[vehicle_type] = {}
    end

    -- Already cached
    if sound_sources[vehicle_type][sound_name] then
        return sound_sources[vehicle_type][sound_name]
    end

    -- Create new source
    local path = getSoundPath(vehicle, sound_name)
    local info = love.filesystem.getInfo(path)

    if info then
        local source = love.audio.newSource(path, "static")
        source:setLooping(true)
        local vol = getSoundVolume(sound_name)
        source:setVolume(vol * sound.settings.sfx_volume * sound.settings.master_volume)
        sound_sources[vehicle_type][sound_name] = source
        return source
    end

    return nil
end

-- Stop all engine sounds for current vehicle
local function stopAllEngineSounds()
    if not current_vehicle then return end

    local vehicle_type = current_vehicle.type or "default"
    local sources = sound_sources[vehicle_type]

    if sources then
        if sources.engine_idle then
            sources.engine_idle:stop()
        end
        if sources.engine_drive then
            sources.engine_drive:stop()
        end
    end

    current_state = nil
end

-- Play a one-shot sound for a vehicle, returns duration if successful
local function playVehicleSound(vehicle, sound_name)
    if sound.settings.muted then return 0 end

    local path = getSoundPath(vehicle, sound_name)
    local info = love.filesystem.getInfo(path)

    if info then
        local source = love.audio.newSource(path, "static")
        local vol = getSoundVolume(sound_name)
        source:setVolume(vol * sound.settings.sfx_volume * sound.settings.master_volume)
        source:play()
        return source:getDuration()
    end
    return 0
end

-- Actually start drive loop (called after engine_start finishes)
local function startDriveLoop(vehicle)
    local idle_source = getLoopSource(vehicle, "engine_idle")
    local drive_source = getLoopSource(vehicle, "engine_drive")

    if idle_source then idle_source:stop() end
    if drive_source and not drive_source:isPlaying() then
        drive_source:play()
    end
    current_state = "drive"
end

-- Set engine state (idle or drive)
local function setEngineState(vehicle, state)
    if not vehicle or sound.settings.muted then return end
    if current_state == state then return end

    local idle_source = getLoopSource(vehicle, "engine_idle")
    local drive_source = getLoopSource(vehicle, "engine_drive")

    if state == "idle" then
        -- Cancel pending drive if switching back to idle
        pending_drive = nil
        if drive_source then drive_source:stop() end
        if idle_source and not idle_source:isPlaying() then
            idle_source:play()
        end
        current_state = "idle"
    elseif state == "drive" then
        -- Play start sound when transitioning from idle to drive
        if current_state == "idle" then
            local duration = playVehicleSound(vehicle, "engine_start")
            if duration > 0 then
                -- Delay drive loop until engine_start finishes (with small overlap)
                pending_drive = { vehicle = vehicle, timer = duration * 0.8 }
                current_state = "starting"  -- Intermediate state
                return
            end
        end
        -- No start sound or already starting, go directly to drive
        startDriveLoop(vehicle)
    end
end

-- Update engine sound based on vehicle movement
function vehicle_sound.update(vehicle, is_moving, dt)
    if not vehicle then return end

    dt = dt or (1/60)  -- Default to ~60fps if not provided

    -- Vehicle changed
    if current_vehicle ~= vehicle then
        vehicle_sound.stopEngine()
        current_vehicle = vehicle
    end

    -- Handle pending drive transition (waiting for engine_start to finish)
    if pending_drive then
        pending_drive.timer = pending_drive.timer - dt
        if pending_drive.timer <= 0 then
            startDriveLoop(pending_drive.vehicle)
            pending_drive = nil
        end
        -- Don't change state while waiting for engine_start
        return
    end

    if is_moving then
        setEngineState(vehicle, "drive")
    else
        setEngineState(vehicle, "idle")
    end
end

-- Start engine (idle state)
function vehicle_sound.startEngine(vehicle)
    if sound.settings.muted then return end

    current_vehicle = vehicle or current_vehicle
    if current_vehicle then
        setEngineState(current_vehicle, "idle")
    end
end

-- Stop engine completely
function vehicle_sound.stopEngine()
    pending_drive = nil
    stopAllEngineSounds()
    current_vehicle = nil
end

-- Pause engine sound
function vehicle_sound.pauseEngine()
    if not current_vehicle then return end

    local vehicle_type = current_vehicle.type or "default"
    local sources = sound_sources[vehicle_type]

    if sources then
        if sources.engine_idle then sources.engine_idle:pause() end
        if sources.engine_drive then sources.engine_drive:pause() end
    end
end

-- Resume engine sound
function vehicle_sound.resumeEngine()
    if not current_vehicle or sound.settings.muted then return end
    if not current_state then return end

    local source_name = "engine_" .. current_state
    local source = getLoopSource(current_vehicle, source_name)
    if source then
        source:play()
    end
end

-- Play summon sound
function vehicle_sound.playSummon(vehicle)
    playVehicleSound(vehicle, "summon")
end

-- Play board sound and start engine
function vehicle_sound.playBoard(vehicle)
    playVehicleSound(vehicle, "board")
    current_vehicle = vehicle
    vehicle_sound.startEngine(vehicle)
end

-- Play dismount sound and stop engine
function vehicle_sound.playDismount(vehicle)
    playVehicleSound(vehicle, "dismount")
    vehicle_sound.stopEngine()
end

-- Update volume when settings change
function vehicle_sound.updateVolume()
    for vehicle_type, sources in pairs(sound_sources) do
        for sound_name, source in pairs(sources) do
            local vol = getSoundVolume(sound_name)
            source:setVolume(vol * sound.settings.sfx_volume * sound.settings.master_volume)
        end
    end
end

-- Check engine state
function vehicle_sound.isEnginePlaying()
    return current_state ~= nil
end

function vehicle_sound.getEngineState()
    return current_state
end

-- Cleanup all sounds
function vehicle_sound.cleanup()
    vehicle_sound.stopEngine()
    for vehicle_type, sources in pairs(sound_sources) do
        for sound_name, source in pairs(sources) do
            source:stop()
        end
    end
    sound_sources = {}
    current_vehicle = nil
    current_state = nil
end

-- Preload sounds for a vehicle type
function vehicle_sound.preload(vehicle)
    getLoopSource(vehicle, "engine_idle")
    getLoopSource(vehicle, "engine_drive")
end

return vehicle_sound
