-- systems/sound.lua
-- Optimized for Android with memory tracking and automatic cleanup

local sound = {}

sound.settings = {
    master_volume = 1.0,
    bgm_volume = 0.7,
    sfx_volume = 0.8,
    muted = false
}

sound.current_bgm = nil
sound.current_bgm_name = nil

sound.bgm = {}
sound.sfx = {}
sound.pools = {}
sound.sound_data = nil  -- Store injected sound data

-- Active source tracking for memory management
sound.active_sources = {}
sound.max_active_sources = 32 -- Limit for Android
sound.cleanup_interval = 1.0  -- Cleanup every 1 second
sound.cleanup_timer = 0

-- Memory monitoring (Android optimization)
sound.memory_stats = {
    last_check = 0,
    check_interval = 5.0,
    peak_memory = 0,
    warnings = 0
}

-- Pitch variation presets (loaded from config)
sound.pitch_variations = {}

-- Category constants (loaded from config)
sound.CATEGORY = {}

function sound:init(sound_data)
    if not sound_data then
        print("Warning: No sound data provided to sound:init()")
        return
    end

    -- Store sound data for later use
    self.sound_data = sound_data

    -- Load pitch variations and categories from config
    if sound_data.variations and sound_data.variations.pitch then
        self.pitch_variations = sound_data.variations.pitch
    end
    if sound_data.categories then
        self.CATEGORY = sound_data.categories
    end

    -- Load settings from GameConfig if available
    if GameConfig and GameConfig.sound then
        self.settings.master_volume = GameConfig.sound.master_volume
        self.settings.bgm_volume = GameConfig.sound.bgm_volume
        self.settings.sfx_volume = GameConfig.sound.sfx_volume
        self.settings.muted = GameConfig.sound.muted
    end

    -- Load BGM
    if sound_data.bgm then
        for name, config in pairs(sound_data.bgm) do
            self:_loadBGM(name, config)
        end
    end

    -- Load SFX
    if sound_data.sfx then
        for category, sounds in pairs(sound_data.sfx) do
            self.sfx[category] = {}
            for name, config in pairs(sounds) do
                self:_loadSFX(category, name, config)
            end
        end
    end

    -- Create sound pools
    if sound_data.pools then
        for category, pools in pairs(sound_data.pools) do
            for name, config in pairs(pools) do
                self:_createPool(category, name, config)
            end
        end
    end
end

function sound:_loadBGM(name, config)
    local info = love.filesystem.getInfo(config.path)
    if info then
        self.bgm[name] = love.audio.newSource(config.path, "stream")
        self.bgm[name]:setLooping(config.loop or true)
        self.bgm[name]:setVolume((config.volume or 1.0) * self.settings.bgm_volume * self.settings.master_volume)
    else
        print("WARNING: BGM not found: " .. config.path)
    end
end

function sound:_loadSFX(category, name, config)
    local info = love.filesystem.getInfo(config.path)
    if info then
        self.sfx[category][name] = love.audio.newSource(config.path, "static")
        self.sfx[category][name]:setVolume((config.volume or 1.0) * self.settings.sfx_volume * self.settings.master_volume)
    else
        print("WARNING: SFX not found: " .. config.path)
    end
end

function sound:_createPool(category, name, config)
    local info = love.filesystem.getInfo(config.path)
    if not info then
        print("WARNING: Cannot create pool for missing file: " .. config.path)
        return
    end

    local pool_key = category .. "_" .. name
    self.pools[pool_key] = {
        sources = {},
        current_index = 1,
        base_volume = config.volume or 1.0,
        pitch_variation = config.pitch_variation or "normal"
    }

    for i = 1, (config.size or 5) do
        local source = love.audio.newSource(config.path, "static")
        source:setVolume(self.pools[pool_key].base_volume * self.settings.sfx_volume * self.settings.master_volume)
        table.insert(self.pools[pool_key].sources, source)
    end
end

-- Get pitch value from variation preset name
function sound:_getPitch(variation_name)
    variation_name = variation_name or "normal"
    local preset = self.pitch_variations[variation_name]

    if not preset then
        preset = self.pitch_variations.normal
    end

    return preset.min + math.random() * (preset.max - preset.min)
end

-- Get pitch from sound config
function sound:_getPitchFromConfig(category, name)
    if not self.sound_data or not self.sound_data.sfx then
        return self:_getPitch("normal")
    end

    local config = self.sound_data.sfx[category] and self.sound_data.sfx[category][name]

    if config and config.pitch_variation then
        return self:_getPitch(config.pitch_variation)
    end

    return self:_getPitch("normal")
end

-- Cleanup finished sources to prevent memory leak
function sound:_cleanupFinishedSources()
    local i = 1
    while i <= #self.active_sources do
        local source = self.active_sources[i]
        if not source:isPlaying() then
            source:stop() -- Ensure stopped
            table.remove(self.active_sources, i)
        else
            i = i + 1
        end
    end
end

-- Force cleanup if too many active sources
function sound:_forceCleanup()
    if #self.active_sources >= self.max_active_sources then
        print("WARNING: Max active sources reached (" .. self.max_active_sources .. "), forcing cleanup")

        -- Stop oldest sources first
        local to_remove = math.ceil(#self.active_sources * 0.3) -- Remove 30%
        for i = 1, to_remove do
            if self.active_sources[1] then
                self.active_sources[1]:stop()
                table.remove(self.active_sources, 1)
            end
        end
    end
end

-- Memory monitoring (Android specific)
function sound:_checkMemory()
    local current_time = love.timer.getTime()
    if current_time - self.memory_stats.last_check < self.memory_stats.check_interval then
        return
    end

    self.memory_stats.last_check = current_time

    -- Check Lua memory
    local mem_kb = collectgarbage("count")
    local mem_mb = mem_kb / 1024

    if mem_mb > self.memory_stats.peak_memory then
        self.memory_stats.peak_memory = mem_mb
    end

    -- Warning threshold: 50MB
    if mem_mb > 50 then
        self.memory_stats.warnings = self.memory_stats.warnings + 1
        print(string.format("WARNING: High memory usage: %.2f MB (Peak: %.2f MB)",
            mem_mb, self.memory_stats.peak_memory))

        -- Emergency cleanup
        collectgarbage("collect")
        self:_forceCleanup()
    end
end

-- Update function for periodic cleanup (call from love.update)
function sound:update(dt)
    self.cleanup_timer = self.cleanup_timer + dt

    if self.cleanup_timer >= self.cleanup_interval then
        self.cleanup_timer = 0
        self:_cleanupFinishedSources()
        self:_checkMemory()
    end
end

function sound:createPool(category, name, path, size, pitch_variation)
    size = size or 5
    pitch_variation = pitch_variation or "normal"

    local info = love.filesystem.getInfo(path)
    if not info then
        print("WARNING: Cannot create pool for missing file: " .. path)
        return false
    end

    local pool_key = category .. "_" .. name

    if self.pools[pool_key] then
        return true
    end

    self.pools[pool_key] = {
        sources = {},
        current_index = 1,
        base_volume = 1.0,
        pitch_variation = pitch_variation
    }

    for i = 1, size do
        local source = love.audio.newSource(path, "static")
        source:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        table.insert(self.pools[pool_key].sources, source)
    end

    return true
end

function sound:playBGM(name, fade_time, rewind)
    fade_time = fade_time or 1.0
    rewind = rewind == nil and false or rewind

    if not self.bgm[name] then
        print("WARNING: BGM not found: " .. name)
        return
    end

    -- If same BGM is playing and rewind is not requested, don't restart
    if self.current_bgm_name == name and self.current_bgm and self.current_bgm:isPlaying() and not rewind then
        return
    end

    if self.current_bgm and self.current_bgm:isPlaying() then
        self.current_bgm:stop()
    end

    self.current_bgm = self.bgm[name]
    self.current_bgm_name = name

    -- Rewind to beginning
    self.current_bgm:seek(0)

    if not self.settings.muted then
        self.current_bgm:play()
    end
end

function sound:stopBGM(fade_time)
    fade_time = fade_time or 1.0

    if self.current_bgm then
        self.current_bgm:stop()
        self.current_bgm = nil
        self.current_bgm_name = nil
    end
end

function sound:pauseBGM()
    if self.current_bgm and self.current_bgm:isPlaying() then
        self.current_bgm:pause()
    end
end

function sound:resumeBGM()
    if self.current_bgm and not self.settings.muted then
        self.current_bgm:play()
    end
end

-- Play SFX with automatic pitch variation and memory tracking
function sound:playSFX(category, name, pitch_override, volume_multiplier)
    volume_multiplier = volume_multiplier or 1.0

    if self.settings.muted then return end

    if not self.sfx[category] or not self.sfx[category][name] then
        print("WARNING: SFX not found: " .. category .. "/" .. name)
        return
    end

    -- Check active source limit before creating new one
    self:_forceCleanup()

    local pitch = pitch_override or self:_getPitchFromConfig(category, name)

    local source = self.sfx[category][name]:clone()
    source:setPitch(pitch)
    source:setVolume(source:getVolume() * volume_multiplier)
    source:play()

    -- Track active source for cleanup
    table.insert(self.active_sources, source)
end

-- Play pooled sound with automatic pitch variation
function sound:playPooled(category, name, pitch_override, volume_multiplier)
    volume_multiplier = volume_multiplier or 1.0

    if self.settings.muted then return end

    local pool_key = category .. "_" .. name
    local pool = self.pools[pool_key]

    if not pool then
        print("WARNING: Pool not found: " .. pool_key)
        return
    end

    local pitch = pitch_override or self:_getPitch(pool.pitch_variation)

    local source = pool.sources[pool.current_index]
    source:stop()
    source:setPitch(pitch)
    source:setVolume(pool.base_volume * self.settings.sfx_volume * self.settings.master_volume * volume_multiplier)
    source:play()

    pool.current_index = pool.current_index + 1
    if pool.current_index > #pool.sources then
        pool.current_index = 1
    end
end

function sound:setMasterVolume(volume)
    self.settings.master_volume = math.max(0, math.min(1, volume))
    self:_updateAllVolumes()
end

function sound:setBGMVolume(volume)
    self.settings.bgm_volume = math.max(0, math.min(1, volume))

    for _, bgm in pairs(self.bgm) do
        bgm:setVolume(self.settings.bgm_volume * self.settings.master_volume)
    end
end

function sound:setSFXVolume(volume)
    self.settings.sfx_volume = math.max(0, math.min(1, volume))

    for category, sounds in pairs(self.sfx) do
        for _, sound in pairs(sounds) do
            sound:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        end
    end

    for _, pool in pairs(self.pools) do
        for _, source in ipairs(pool.sources) do
            source:setVolume(pool.base_volume * self.settings.sfx_volume * self.settings.master_volume)
        end
    end
end

function sound:_updateAllVolumes()
    self:setBGMVolume(self.settings.bgm_volume)
    self:setSFXVolume(self.settings.sfx_volume)
end

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

function sound:cleanup()
    self:stopBGM()

    -- Stop all active cloned sources
    for _, source in ipairs(self.active_sources) do
        source:stop()
    end
    self.active_sources = {}

    for _, bgm in pairs(self.bgm) do
        bgm:stop()
    end
end

function sound:printStatus()
    dprint("=== Sound System Status ===")
    dprint("Master Volume: " .. string.format("%.0f%%", self.settings.master_volume * 100))
    dprint("BGM Volume: " .. string.format("%.0f%%", self.settings.bgm_volume * 100))
    dprint("SFX Volume: " .. string.format("%.0f%%", self.settings.sfx_volume * 100))
    dprint("Muted: " .. tostring(self.settings.muted))
    dprint("Current BGM: " .. tostring(self.current_bgm_name or "None"))
    dprint("Active Sources: " .. #self.active_sources .. "/" .. self.max_active_sources)

    local mem_kb = collectgarbage("count")
    local mem_mb = mem_kb / 1024
    dprint(string.format("Memory Usage: %.2f MB (Peak: %.2f MB)", mem_mb, self.memory_stats.peak_memory))

    local bgm_count = 0
    for _ in pairs(self.bgm) do bgm_count = bgm_count + 1 end

    local sfx_count = 0
    for _, category in pairs(self.sfx) do
        for _ in pairs(category) do sfx_count = sfx_count + 1 end
    end

    local pool_count = 0
    for _ in pairs(self.pools) do pool_count = pool_count + 1 end

    dprint("Loaded BGM: " .. bgm_count)
    dprint("Loaded SFX: " .. sfx_count)
    dprint("Sound Pools: " .. pool_count)
    dprint("===========================")
end

-- Get debug info for display
function sound:getDebugInfo()
    local mem_kb = collectgarbage("count")
    return {
        active_sources = #self.active_sources,
        max_sources = self.max_active_sources,
        memory_mb = mem_kb / 1024,
        peak_memory_mb = self.memory_stats.peak_memory,
        warnings = self.memory_stats.warnings
    }
end

return sound
