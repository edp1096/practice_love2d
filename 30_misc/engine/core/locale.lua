-- engine/core/locale.lua
-- Internationalization system wrapper
-- Uses kikito/i18n.lua library

local i18n = require "vendor.i18n"

local locale = {}

-- Font paths per locale (injected from game)
locale.font_paths = {}

-- Font size scale per locale (injected from game, default 1.0)
locale.font_scales = {}

-- Loaded fonts cache (per locale, per size)
locale.fonts = {}

-- Current locale
locale.current = "en"

-- Default font path (fallback)
locale.default_font = nil  -- nil = LÖVE default font

-- Font sizes used in the game (base sizes)
locale.font_sizes = {
    title_large = 44,
    title = 32,
    subtitle = 28,
    option = 22,
    parry_perfect = 32,
    parry = 24,
    info = 14,
    hint = 13,
    small = 12,
    tiny = 11,
    micro = 10
}

--- Initialize locale system
-- @param config Table with locale_data (translations) and font_paths
function locale:init(config)
    config = config or {}

    -- Load translations from locale_data (legacy single-table format)
    if config.locale_data then
        i18n.load(config.locale_data)
    end

    -- Load translations from locale files (new file-based format)
    -- Supports: locale_files = { "path/to/en.lua", "path/to/ko.lua" }
    if config.locale_files then
        for _, file_path in ipairs(config.locale_files) do
            local success, data = pcall(require, file_path:gsub("%.lua$", ""):gsub("/", "."))
            if success and data then
                i18n.load(data)
            else
                print("[locale] Warning: Failed to load locale file:", file_path)
            end
        end
    end

    -- Store font paths
    if config.font_paths then
        self.font_paths = config.font_paths
    end

    -- Store font scales (per locale size multiplier)
    if config.font_scales then
        self.font_scales = config.font_scales
    end

    -- Set default locale
    local default_locale = config.default_locale or "en"
    self:setLocale(default_locale)
end

--- Set current locale
-- @param loc Locale code (e.g., "en", "ko")
function locale:setLocale(loc)
    self.current = loc
    i18n.setLocale(loc)

    -- Reload fonts for new locale
    self:loadFonts()
end

--- Get current locale
function locale:getLocale()
    return self.current
end

--- Load fonts for current locale
function locale:loadFonts()
    local font_path = self.font_paths[self.current]
    -- false means "use default font", nil means "not set, use default_font fallback"
    if font_path == nil then
        font_path = self.default_font
    elseif font_path == false then
        font_path = nil  -- Use LÖVE default font
    end

    -- Get font scale for current locale (default 1.0)
    local scale = self.font_scales[self.current] or 1.0

    -- Clear cached fonts for this locale
    self.fonts[self.current] = {}

    for name, base_size in pairs(self.font_sizes) do
        local scaled_size = math.floor(base_size * scale)
        if font_path then
            self.fonts[self.current][name] = love.graphics.newFont(font_path, scaled_size)
        else
            self.fonts[self.current][name] = love.graphics.newFont(scaled_size)
        end
    end
end

--- Get font by name for current locale
-- @param name Font name (title_large, title, subtitle, option, info, hint, small)
function locale:getFont(name)
    local locale_fonts = self.fonts[self.current]
    if locale_fonts and locale_fonts[name] then
        return locale_fonts[name]
    end
    -- Fallback to default LÖVE font
    return love.graphics.getFont()
end

--- Translate a key
-- @param key Translation key (e.g., "menu.start", "shop.buy")
-- @param data Optional interpolation data
function locale:t(key, data)
    local result = i18n(key, data)
    -- If translation not found, i18n returns the key itself
    return result
end

--- Get available locales
function locale:getAvailableLocales()
    local locales = {}
    for loc, _ in pairs(self.font_paths) do
        table.insert(locales, loc)
    end
    return locales
end

--- Cycle to next locale
function locale:cycleLocale()
    local locales = self:getAvailableLocales()
    if #locales < 2 then return end

    local current_idx = 1
    for i, loc in ipairs(locales) do
        if loc == self.current then
            current_idx = i
            break
        end
    end

    local next_idx = (current_idx % #locales) + 1
    self:setLocale(locales[next_idx])
end

return locale
