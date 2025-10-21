-- systems/sound.lua
-- Central sound management system with BGM and SFX control

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

-- BGM tracks
sound.bgm = {}

-- SFX categories
sound.sfx = {
    menu = {},
    ui = {},
    combat = {},
    environment = {}
}

-- Sound pools for frequently used sounds
sound.pools = {}

function sound:init()
    print("Sound system initializing...")

    -- Load BGM
    self:loadBGM("menu", "assets/bgm/menu.ogg")
    self:loadBGM("level1", "assets/bgm/level1.ogg")
    self:loadBGM("level2", "assets/bgm/level2.ogg")
    self:loadBGM("boss", "assets/bgm/boss.ogg")

    -- Load Menu SFX
    self:loadSFX("menu", "navigate", "assets/sound/menu/navigate.wav")
    self:loadSFX("menu", "select", "assets/sound/menu/select.wav")
    self:loadSFX("menu", "back", "assets/sound/menu/back.wav")
    self:loadSFX("menu", "error", "assets/sound/menu/error.wav")

    -- Load UI SFX
    self:loadSFX("ui", "save", "assets/sound/ui/save.wav")
    self:loadSFX("ui", "pause", "assets/sound/ui/pause.wav")
    self:loadSFX("ui", "unpause", "assets/sound/ui/unpause.wav")

    -- Load Combat SFX (shared)
    self:loadSFX("combat", "hit_flesh", "assets/sound/combat/hit_flesh.wav")
    self:loadSFX("combat", "hit_metal", "assets/sound/combat/hit_metal.wav")
    self:loadSFX("combat", "parry", "assets/sound/combat/parry.wav")
    self:loadSFX("combat", "parry_perfect", "assets/sound/combat/parry_perfect.wav")
    self:loadSFX("combat", "death", "assets/sound/combat/death.wav")

    print("Sound system initialized")
    self:printStatus()
end

function sound:loadBGM(name, path)
    local info = love.filesystem.getInfo(path)
    if info then
        self.bgm[name] = love.audio.newSource(path, "stream")
        self.bgm[name]:setLooping(true)
        self.bgm[name]:setVolume(self.settings.bgm_volume * self.settings.master_volume)
        print("  Loaded BGM: " .. name)
    else
        print("  WARNING: BGM not found: " .. path)
    end
end

function sound:loadSFX(category, name, path)
    local info = love.filesystem.getInfo(path)
    if info then
        self.sfx[category][name] = love.audio.newSource(path, "static")
        self.sfx[category][name]:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        print("  Loaded SFX: " .. category .. "/" .. name)
    else
        print("  WARNING: SFX not found: " .. path)
    end
end

function sound:createPool(category, name, path, pool_size)
    pool_size = pool_size or 5

    local info = love.filesystem.getInfo(path)
    if not info then
        print("  WARNING: Cannot create pool for missing file: " .. path)
        return
    end

    local pool_key = category .. "_" .. name
    self.pools[pool_key] = {
        sources = {},
        current_index = 1
    }

    for i = 1, pool_size do
        local source = love.audio.newSource(path, "static")
        source:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        table.insert(self.pools[pool_key].sources, source)
    end

    print("  Created pool: " .. pool_key .. " (size: " .. pool_size .. ")")
end

function sound:playBGM(name, fade_time)
    fade_time = fade_time or 1.0

    if self.current_bgm_name == name and self.current_bgm and self.current_bgm:isPlaying() then
        return
    end

    if not self.bgm[name] then
        print("WARNING: BGM not found: " .. name)
        return
    end

    -- Fade out current BGM
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
    source:setVolume(self.settings.sfx_volume * self.settings.master_volume * volume_multiplier)
    source:play()
end

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

    local source = pool.sources[pool.current_index]
    source:stop()
    source:setPitch(pitch)
    source:setVolume(self.settings.sfx_volume * self.settings.master_volume * volume_multiplier)
    source:play()

    pool.current_index = pool.current_index + 1
    if pool.current_index > #pool.sources then
        pool.current_index = 1
    end
end

function sound:setMasterVolume(volume)
    self.settings.master_volume = math.max(0, math.min(1, volume))
    self:updateAllVolumes()
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
            source:setVolume(self.settings.sfx_volume * self.settings.master_volume)
        end
    end
end

function sound:updateAllVolumes()
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

    for _, bgm in pairs(self.bgm) do
        bgm:stop()
    end

    print("Sound system cleaned up")
end

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

    print("Loaded BGM: " .. bgm_count)
    print("Loaded SFX: " .. sfx_count)
    print("Sound Pools: " .. #self.pools)
    print("===========================")
end

sound:init()

return sound
