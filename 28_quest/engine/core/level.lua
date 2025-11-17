-- engine/core/level.lua
-- Player level system (100% reusable)
-- Handles: exp gain, level up, gold management, stat bonuses

local level = {}

-- Level system configuration (can be overridden via init)
level.config = {
    max_level = 50,               -- Maximum player level
    base_exp = 100,               -- Base exp for level 1->2
    exp_curve = 1.5,              -- Exponential curve (higher = steeper)

    -- Stat bonuses per level
    stat_bonuses = {
        max_health = 10,          -- +10 HP per level
        attack_damage = 2,        -- +2 damage per level
        speed = 5                 -- +5 speed per level (optional)
    }
}

-- Level data (runtime state)
level.data = {
    level = 1,
    current_exp = 0,
    gold = 0
}

-- Callbacks
level.callbacks = {
    on_level_up = nil,            -- function(new_level, stat_bonuses)
    on_exp_gained = nil,          -- function(amount, new_current, required)
    on_gold_changed = nil         -- function(amount, new_total)
}

function level:init(config)
    -- Override config if provided
    if config then
        for key, value in pairs(config) do
            self.config[key] = value
        end
    end

    -- Reset to default state
    self.data = {
        level = 1,
        current_exp = 0,
        gold = 0
    }
end

-- Calculate exp required for next level
function level:getRequiredExp(current_level)
    if current_level >= self.config.max_level then
        return 0  -- Max level reached
    end

    return math.floor(self.config.base_exp * (current_level ^ self.config.exp_curve))
end

-- Get current level data
function level:getLevel()
    return self.data.level
end

function level:getCurrentExp()
    return self.data.current_exp
end

function level:getGold()
    return self.data.gold
end

-- Add experience points
function level:addExp(amount)
    if self.data.level >= self.config.max_level then
        return false  -- Already max level
    end

    self.data.current_exp = self.data.current_exp + amount

    -- Check for level up
    local leveled_up = false
    while self.data.current_exp >= self:getRequiredExp(self.data.level) do
        local required = self:getRequiredExp(self.data.level)

        -- Deduct exp and level up
        self.data.current_exp = self.data.current_exp - required
        self.data.level = self.data.level + 1
        leveled_up = true

        -- Trigger level up callback
        if self.callbacks.on_level_up then
            self.callbacks.on_level_up(self.data.level, self.config.stat_bonuses)
        end

        -- Stop if max level reached
        if self.data.level >= self.config.max_level then
            self.data.current_exp = 0
            break
        end
    end

    -- Trigger exp gained callback
    if self.callbacks.on_exp_gained then
        local required = self:getRequiredExp(self.data.level)
        self.callbacks.on_exp_gained(amount, self.data.current_exp, required)
    end

    return leveled_up
end

-- Add gold
function level:addGold(amount)
    self.data.gold = self.data.gold + amount

    if self.callbacks.on_gold_changed then
        self.callbacks.on_gold_changed(amount, self.data.gold)
    end
end

-- Remove gold (returns true if successful, false if not enough gold)
function level:removeGold(amount)
    if self.data.gold < amount then
        return false
    end

    self.data.gold = self.data.gold - amount

    if self.callbacks.on_gold_changed then
        self.callbacks.on_gold_changed(-amount, self.data.gold)
    end

    return true
end

-- Check if player has enough gold
function level:hasGold(amount)
    return self.data.gold >= amount
end

-- Get level progress as percentage (for UI)
function level:getExpProgress()
    if self.data.level >= self.config.max_level then
        return 1.0  -- 100% at max level
    end

    local required = self:getRequiredExp(self.data.level)
    if required <= 0 then return 1.0 end

    return self.data.current_exp / required
end

-- Serialize for save system
function level:serialize()
    return {
        level = self.data.level,
        current_exp = self.data.current_exp,
        gold = self.data.gold
    }
end

-- Deserialize from save system
function level:deserialize(saved_data)
    if not saved_data then return end

    self.data.level = saved_data.level or 1
    self.data.current_exp = saved_data.current_exp or 0
    self.data.gold = saved_data.gold or 0
end

-- Reset to level 1 (for testing)
function level:reset()
    self.data = {
        level = 1,
        current_exp = 0,
        gold = 0
    }
end

-- Debug: Print level info
function level:debugPrint()
    local required = self:getRequiredExp(self.data.level)
    print(string.format("[Level System] Level: %d | Exp: %d/%d (%.1f%%) | Gold: %d",
        self.data.level,
        self.data.current_exp,
        required,
        self:getExpProgress() * 100,
        self.data.gold
    ))
end

level:init()

return level
