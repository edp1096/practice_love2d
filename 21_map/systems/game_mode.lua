-- systems/game_mode.lua
-- Manages game mode switching between topdown and platformer

local game_mode = {}

game_mode.current = "topdown" -- default mode
game_mode.TOPDOWN = "topdown"
game_mode.PLATFORMER = "platformer"

-- Get current game mode
function game_mode:getCurrent()
    return self.current
end

-- Set game mode
function game_mode:set(mode)
    if mode ~= self.TOPDOWN and mode ~= self.PLATFORMER then
        error("Invalid game mode: " .. tostring(mode))
    end

    local previous = self.current
    self.current = mode

    print("Game mode changed: " .. previous .. " -> " .. mode)
    return previous
end

-- Check if current mode is topdown
function game_mode:isTopdown()
    return self.current == self.TOPDOWN
end

-- Check if current mode is platformer
function game_mode:isPlatformer()
    return self.current == self.PLATFORMER
end

-- Get gravity based on current mode
function game_mode:getGravity()
    if self.current == self.PLATFORMER then
        return 0, 2000 -- gravity for platformer
    else
        return 0, 0    -- no gravity for topdown
    end
end

return game_mode
