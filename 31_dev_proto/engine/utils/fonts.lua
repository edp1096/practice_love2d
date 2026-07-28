-- utils/fonts.lua
-- Centralized font manager to avoid duplication across scenes

local fonts = {
    title_large = nil,
    title = nil,
    subtitle = nil,
    option = nil,
    info = nil,
    hint = nil,
    small = nil
}

--- Initialize all fonts (called once in main.lua)
function fonts:init()
    self.title_large = love.graphics.newFont(44)
    self.title = love.graphics.newFont(32)
    self.subtitle = love.graphics.newFont(28)
    self.option = love.graphics.newFont(22)
    self.info = love.graphics.newFont(14)
    self.hint = love.graphics.newFont(13)
    self.small = love.graphics.newFont(12)
end

return fonts
