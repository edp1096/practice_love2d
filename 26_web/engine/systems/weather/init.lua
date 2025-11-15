-- engine/systems/weather/init.lua
-- Dynamic weather system with random pool and script control

local weather = {}

-- Dependencies (lazy loaded)
local rain_effect = nil
local fog_effect = nil
local snow_effect = nil
local storm_effect = nil

-- State
weather.current = nil           -- Current weather type ("rain", "fog", "clear", etc.)
weather.intensity = 1.0         -- Current intensity (0.0 ~ 1.0)
weather.pool = nil              -- Weather pool table {rain=30, fog=20, clear=50}
weather.change_interval = nil   -- {min, max} seconds between changes
weather.next_change_time = 0    -- Timer for next random change
weather.is_forced = false       -- If true, don't auto-change
weather.transition = {          -- Transition state
  active = false,
  from = nil,
  to = nil,
  duration = 0,
  elapsed = 0,
  from_intensity = 0,
  to_intensity = 0
}

-- Available weather effects
local WEATHER_EFFECTS = {
  rain = "engine.systems.weather.rain",
  fog = "engine.systems.weather.fog",
  mist = "engine.systems.weather.fog",  -- Same as fog, different intensity
  snow = "engine.systems.weather.snow",
  storm = "engine.systems.weather.storm",
  -- clear has no effect
}

-- Parse weather pool string: "rain:30,fog:20,clear:50"
local function parseWeatherPool(pool_string)
  if not pool_string or pool_string == "" then
    return {clear = 100}  -- Default: always clear
  end

  local pool = {}
  for entry in string.gmatch(pool_string, "([^,]+)") do
    local weather_type, weight = string.match(entry, "([^:]+):(%d+)")
    if weather_type and weight then
      pool[weather_type] = tonumber(weight)
    end
  end

  return pool
end

-- Roll random weather from pool
local function rollWeather(pool)
  if not pool then return "clear" end

  -- Calculate total weight
  local total = 0
  for _, weight in pairs(pool) do
    total = total + weight
  end

  -- Roll
  local roll = math.random() * total
  local cumulative = 0

  for weather_type, weight in pairs(pool) do
    cumulative = cumulative + weight
    if roll <= cumulative then
      return weather_type
    end
  end

  return "clear"  -- Fallback
end

-- Load weather effect module
local function loadEffect(weather_type)
  local module_path = WEATHER_EFFECTS[weather_type]
  if not module_path then return nil end

  local success, module = pcall(require, module_path)
  if success then
    return module
  else
    print("[Weather] Failed to load effect: " .. weather_type)
    return nil
  end
end

-- Get current effect module
local function getCurrentEffect()
  if weather.current == "rain" then
    if not rain_effect then
      rain_effect = loadEffect("rain")
    end
    return rain_effect
  elseif weather.current == "fog" or weather.current == "mist" then
    if not fog_effect then
      fog_effect = loadEffect("fog")
    end
    return fog_effect
  elseif weather.current == "snow" then
    if not snow_effect then
      snow_effect = loadEffect("snow")
    end
    return snow_effect
  elseif weather.current == "storm" then
    if not storm_effect then
      storm_effect = loadEffect("storm")
    end
    return storm_effect
  end

  return nil  -- "clear" or unknown
end

-- Initialize weather system from map properties
function weather:initialize(map)
  -- Reset state
  self.current = "clear"
  self.intensity = 1.0
  self.is_forced = false
  self.transition.active = false

  -- Parse pool
  local pool_string = map.properties and map.properties.weather_pool
  self.pool = parseWeatherPool(pool_string)

  -- Parse interval
  local interval_string = map.properties and map.properties.weather_change_interval or "300,600"
  local min_interval, max_interval = string.match(interval_string, "(%d+),(%d+)")
  self.change_interval = {
    tonumber(min_interval) or 300,
    tonumber(max_interval) or 600
  }

  -- Roll initial weather
  local initial_weather = rollWeather(self.pool)
  self:set(initial_weather, 1.0, true)  -- instant = true

  -- Schedule next change
  self:scheduleNextChange()
end

-- Set weather (instant or transition)
function weather:set(weather_type, intensity, instant)
  intensity = intensity or 1.0
  instant = instant or false

  if instant then
    -- Instant change
    self.current = weather_type
    self.intensity = intensity
    self.transition.active = false

    -- Initialize effect
    local effect = getCurrentEffect()
    if effect and effect.initialize then
      effect:initialize(intensity)
    end
  else
    -- Transition
    self.transition.active = true
    self.transition.from = self.current
    self.transition.to = weather_type
    self.transition.duration = 2.0  -- 2 seconds fade
    self.transition.elapsed = 0
    self.transition.from_intensity = self.intensity
    self.transition.to_intensity = intensity
  end
end

-- Force set weather (disables auto-change)
function weather:forceSet(weather_type, options)
  options = options or {}
  self.is_forced = true
  self:set(weather_type, options.intensity or 1.0, options.instant)

  -- Optional: auto-resume random after duration
  if options.duration then
    local hump_timer = require "vendor.hump.timer"
    hump_timer.after(options.duration, function()
      if options.then_random then
        self.is_forced = false
        self:rollAndSet()
        self:scheduleNextChange()
      end
    end)
  end
end

-- Roll and set new weather from pool
function weather:rollAndSet()
  local new_weather = rollWeather(self.pool)
  local new_intensity = 1.0

  -- Mist is just light fog
  if new_weather == "mist" then
    new_intensity = 0.5
  end

  self:set(new_weather, new_intensity, false)  -- transition
end

-- Schedule next random weather change
function weather:scheduleNextChange()
  if not self.change_interval then return end

  local min_time, max_time = self.change_interval[1], self.change_interval[2]
  self.next_change_time = math.random(min_time, max_time)
end

-- Update
function weather:update(dt)
  -- Update transition
  if self.transition.active then
    self.transition.elapsed = self.transition.elapsed + dt

    if self.transition.elapsed >= self.transition.duration then
      -- Transition complete
      self.current = self.transition.to
      self.intensity = self.transition.to_intensity
      self.transition.active = false

      -- Initialize new effect
      local effect = getCurrentEffect()
      if effect and effect.initialize then
        effect:initialize(self.intensity)
      end
    else
      -- Transitioning
      local progress = self.transition.elapsed / self.transition.duration
      self.intensity = self.transition.from_intensity +
                       (self.transition.to_intensity - self.transition.from_intensity) * progress
    end
  end

  -- Update current effect
  local effect = getCurrentEffect()
  if effect and effect.update then
    effect:update(dt, self.intensity)
  end

  -- Auto-change timer
  if not self.is_forced and self.next_change_time then
    self.next_change_time = self.next_change_time - dt
    if self.next_change_time <= 0 then
      self:rollAndSet()
      self:scheduleNextChange()
    end
  end
end

-- Draw (called AFTER world/entities, BEFORE HUD)
function weather:draw()
  local effect = getCurrentEffect()
  if effect and effect.draw then
    effect:draw(self.intensity)
  end
end

-- Cleanup
function weather:cleanup()
  if rain_effect and rain_effect.cleanup then
    rain_effect:cleanup()
  end
  if fog_effect and fog_effect.cleanup then
    fog_effect:cleanup()
  end
  if snow_effect and snow_effect.cleanup then
    snow_effect:cleanup()
  end
  if storm_effect and storm_effect.cleanup then
    storm_effect:cleanup()
  end

  self.current = nil
  self.pool = nil
  self.is_forced = false
  self.transition.active = false
end

return weather
