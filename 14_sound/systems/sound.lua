-- systems/sound.lua
-- Refactored sound management system using centralized sound definitions

local sound_data = require "data.sounds"

local sound = {}

-- Master volume settings
sound.settings = {
    master_volume = 1.0,
    bgm_volume = 0.7,
    sfx_volume = 0.8,
    muted = false
}

-- Currently playing BGM
sound.current_bgm = nil
sound.current_bgm_name = nil

-- Loaded sound sources
sound.bgm = {}
sound.sfx = {}
sound.pools = {}

-- Load all sounds from data definitions
function sound:init()
    print("Sound system initializing...")

    -- Load BGM tracks
    for name, config in pairs(sound_data.bgm) do
        self:_loadBGM(name, config)
    end

    -- Load SFX by category
    for category, sounds in pairs(sound_data.sfx) do
        self.sfx[category] = {}
        for name, config in pairs(sounds) do
            self:_loadSFX(category, name, config)
        end
    end

    -- Create sound pools
    for category, pools in pairs(sound_data.pools) do
        for name, config in pairs(pools) do
            self:_createPool(category, name, config)
        end
    end

    print("Sound system initialized")
    self:printStatus()
end

-- Internal: Load a single BGM track
function sound:_loadBGM(name, config)
    local info = love.filesystem.getInfo(config.path)
    if info then
        self.bgm[name] = love.audio.newSource(config.path, "stream")
        self.bgm[name]:setLooping(config.loop or true)
        self.bgm[name]:setVolume((config.volume or 1.0) * self.settings.bgm_volume * self.settings.master_volume)
        print("  Loaded BGM: " .. name)
    else
        print("  WARNING: BGM not found: " .. config.path)
    end
end

-- Internal: Load a single SFX
function sound:_loadSFX(category, name, config)
    local info = love.filesystem.getInfo(config.path)
    if info then
        self.sfx[category][name] = love.audio.newSource(config.path, "static")
        self.sfx[category][name]:setVolume((config.volume or 1.0) * self.settings.sfx_volume * self.settings.master_volume)
        print("  Loaded SFX: " .. category .. "/" .. name)
    else
        print("  WARNING: SFX not found: " .. config.path)
    end
end

-- Internal: Create a sound pool
function sound:_createPool(category, name, config)
    local info = love.filesystem.getInfo(config.path)
    if not info then
        print("  WARNING: Cannot create pool for missing file: " .. config.path)
        return
    end

    local pool_key = category .. "_" .. name
    self.pools[pool_key] = {
        sources = {},
        current_index = 1,
        base_volume = config.volume or 1.0
    }

    for i = 1, (config.size or 5) do
        local source = love.audio.newSource(config.path, "static")
        source:setVolume(self.pools[pool_key].base_volume * self.settings.sfx_volume * self.settings.master_volume)
        table.insert(self.pools[pool_key].sources, source)
    end

    print("  Created pool: " .. pool_key .. " (size: " .. config.size .. ")")
end

-- Public: Create a sound pool dynamically (for entity-specific pools)
function sound:createPool(category, name, path, size)
    size = size or 5

    local info = love.filesystem.getInfo(path)
    if not info then
        print("WARNING: Cannot create pool for missing file: " .. path)
        return false
    end

    local pool_key = category .. "_" .. name

    -- Don't recreate if already exists
    if self.pools[pool_key] then
        print("Pool already exists: " .. pool_key)
        return true
    end

    self.pools[pool_key] = {
        sources = {},
        current_index = 1,
        base_volume = 1.0
    }

    for i = 1, size do
        local source = love.audio.newSource(path, "static")
        source:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        table.insert(self.pools[pool_key].sources, source)
    end

    print("Created pool: " .. pool_key .. " (size: " .. size .. ")")
    return true
end

-- Play background music with optional fade
function sound:playBGM(name, fade_time)
    fade_time = fade_time or 1.0

    -- Already playing same track
    if self.current_bgm_name == name and self.current_bgm and self.current_bgm:isPlaying() then
        return
    end

    if not self.bgm[name] then
        print("WARNING: BGM not found: " .. name)
        return
    end

    -- Stop current BGM (TODO: implement fade out/in)
    if self.current_bgm and self.current_bgm:isPlaying() then
        self.current_bgm:stop()
    end

    -- Play new BGM
    self.current_bgm = self.bgm[name]
    self.current_bgm_name = name

    if not self.settings.muted then
        self.current_bgm:play()
    end

    print("Playing BGM: " .. name)
end

-- Stop background music
function sound:stopBGM(fade_time)
    fade_time = fade_time or 1.0

    if self.current_bgm then
        self.current_bgm:stop()
        self.current_bgm = nil
        self.current_bgm_name = nil
    end
end

-- Pause background music
function sound:pauseBGM()
    if self.current_bgm and self.current_bgm:isPlaying() then
        self.current_bgm:pause()
    end
end

-- Resume background music
function sound:resumeBGM()
    if self.current_bgm and not self.settings.muted then
        self.current_bgm:play()
    end
end

-- Play sound effect with pitch and volume variation
function sound:playSFX(category, name, pitch, volume_multiplier)
    pitch = pitch or 1.0
    volume_multiplier = volume_multiplier or 1.0

    if self.settings.muted then return end

    if not self.sfx[category] or not self.sfx[category][name] then
        print("WARNING: SFX not found: " .. category .. "/" .. name)
        return
    end

    local source = self.sfx[category][name]:clone()
    source:setPitch(pitch)
    source:setVolume(source:getVolume() * volume_multiplier)
    source:play()
end

-- Play pooled sound (for frequently used sounds)
function sound:playPooled(category, name, pitch, volume_multiplier)
    pitch = pitch or 1.0
    volume_multiplier = volume_multiplier or 1.0

    if self.settings.muted then return end

    local pool_key = category .. "_" .. name
    local pool = self.pools[pool_key]

    if not pool then
        print("WARNING: Pool not found: " .. pool_key)
        return
    end

    -- Get next available source from pool
    local source = pool.sources[pool.current_index]
    source:stop()
    source:setPitch(pitch)
    source:setVolume(pool.base_volume * self.settings.sfx_volume * self.settings.master_volume * volume_multiplier)
    source:play()

    -- Rotate pool index
    pool.current_index = pool.current_index + 1
    if pool.current_index > #pool.sources then
        pool.current_index = 1
    end
end

-- Volume control methods
function sound:setMasterVolume(volume)
    self.settings.master_volume = math.max(0, math.min(1, volume))
    self:_updateAllVolumes()
end

function sound:setBGMVolume(volume)
    self.settings.bgm_volume = math.max(0, math.min(1, volume))

    -- Update all BGM tracks
    for _, bgm in pairs(self.bgm) do
        bgm:setVolume(self.settings.bgm_volume * self.settings.master_volume)
    end
end

function sound:setSFXVolume(volume)
    self.settings.sfx_volume = math.max(0, math.min(1, volume))

    -- Update all SFX
    for category, sounds in pairs(self.sfx) do
        for _, sound in pairs(sounds) do
            sound:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        end
    end

    -- Update all pools
    for _, pool in pairs(self.pools) do
        for _, source in ipairs(pool.sources) do
            source:setVolume(pool.base_volume * self.settings.sfx_volume * self.settings.master_volume)
        end
    end
end

-- Internal: Update all volume settings
function sound:_updateAllVolumes()
    self:setBGMVolume(self.settings.bgm_volume)
    self:setSFXVolume(self.settings.sfx_volume)
end

-- Toggle mute on/off
function sound:toggleMute()
    self.settings.muted = not self.settings.muted

    if self.settings.muted then
        if self.current_bgm and self.current_bgm:isPlaying() then
            self.current_bgm:pause()
        end
    else
        if self.current_bgm then
            self.current_bgm:play()
        end
    end

    return self.settings.muted
end

-- Cleanup all sounds
function sound:cleanup()
    self:stopBGM()

    for _, bgm in pairs(self.bgm) do
        bgm:stop()
    end

    print("Sound system cleaned up")
end

-- Print system status
function sound:printStatus()
    print("=== Sound System Status ===")
    print("Master Volume: " .. string.format("%.0f%%", self.settings.master_volume * 100))
    print("BGM Volume: " .. string.format("%.0f%%", self.settings.bgm_volume * 100))
    print("SFX Volume: " .. string.format("%.0f%%", self.settings.sfx_volume * 100))
    print("Muted: " .. tostring(self.settings.muted))
    print("Current BGM: " .. tostring(self.current_bgm_name or "None"))

    local bgm_count = 0
    for _ in pairs(self.bgm) do bgm_count = bgm_count + 1 end

    local sfx_count = 0
    for _, category in pairs(self.sfx) do
        for _ in pairs(category) do sfx_count = sfx_count + 1 end
    end

    local pool_count = 0
    for _ in pairs(self.pools) do pool_count = pool_count + 1 end

    print("Loaded BGM: " .. bgm_count)
    print("Loaded SFX: " .. sfx_count)
    print("Sound Pools: " .. pool_count)
    print("===========================")
end

-- Initialize on load
sound:init()

return sound
