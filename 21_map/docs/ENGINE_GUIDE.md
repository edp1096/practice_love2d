# Engine Systems Guide

This guide documents all engine systems in the `engine/` folder.

---

## 🎬 Scene Management

### `engine/scene_control.lua`
Manages scene transitions and scene stack.

**Key Functions:**
```lua
scene_control.switch(scene, ...)    -- Switch to new scene (replace current)
scene_control.push(scene, ...)      -- Push scene on top (like pause menu)
scene_control.pop()                 -- Return to previous scene
```

**Scene Lifecycle:**
```lua
function scene:enter(previous, ...) end  -- Called when entering scene
function scene:exit() end                -- Called when leaving scene
function scene:resume() end              -- Called when returning from pushed scene
function scene:update(dt) end            -- Called every frame
function scene:draw() end                -- Called for rendering
```

---

## 📷 Camera System

### `engine/camera.lua`
Camera effects system (shake, slow-motion).

**Key Functions:**
```lua
camera_sys:shake(intensity, duration)    -- Screen shake effect
camera_sys:setTimeScale(scale)           -- Slow-motion (0.0-1.0)
camera_sys:get_scaled_dt(dt)             -- Get time-scaled delta time
```

**Usage Example:**
```lua
-- Parry hit effect
camera_sys:shake(5, 0.2)
camera_sys:setTimeScale(0.3)  -- 30% speed (slow-motion)
```

---

## 🔊 Sound System

### `engine/sound.lua`
Audio management (BGM, SFX, volume control, lazy loading).

**Key Functions:**
```lua
sound:playBGM(name, fade_time, rewind)   -- Play background music
sound:stopBGM(fade_time)                 -- Stop BGM with fade
sound:playSFX(category, name)            -- Play sound effect
sound:setMasterVolume(volume)            -- Set master volume (0.0-1.0)
sound:setBGMVolume(volume)               -- Set BGM volume
sound:setSFXVolume(volume)               -- Set SFX volume
```

**Usage Example:**
```lua
sound:playBGM("level1", 1.0, true)       -- Play level1 BGM, rewind from start
sound:playSFX("combat", "sword_swing")   -- Play sword swing sound
```

**Sound Configuration:**
Sounds are defined in `game/data/sounds.lua`:
```lua
return {
    bgm = {
        level1 = { path = "assets/bgm/level1.ogg", volume = 0.7, loop = true }
    },
    sfx = {
        combat = {
            sword_swing = { path = "assets/sound/player/sword_swing.wav", volume = 0.7 }
        }
    }
}
```

---

## 🎮 Input System

### `engine/input/`
Unified input system supporting keyboard, mouse, gamepad, and touch.

**Main API (`engine/input/init.lua`):**
```lua
input:wasPressed("action_name")          -- Check if action was just pressed
input:isDown("action_name")              -- Check if action is held down
input:getAimDirection()                  -- Get aim direction (for attacks)
input:vibrate(pattern_name)              -- Trigger vibration/haptics
```

**Input Configuration:**
Actions are defined in `game/data/input_config.lua`:
```lua
actions = {
    move_left = { keys = {"a", "left"}, gamepad = {"dpleft"} },
    attack = { mouse = {1}, gamepad = {"a"} },
    jump = { keys = {"w", "up", "space"}, gamepad = {"b"} }
}
```

**Platform Support:**
- Desktop: Keyboard + Mouse + Physical Gamepad
- Mobile: Virtual on-screen gamepad + Touch input

---

## 🌍 World System

### `engine/world/`
Physics and world management (Windfield/Box2D wrapper).

**Main API (`engine/world/init.lua`):**
```lua
world:new(mapPath)                       -- Create world from Tiled map
world:addEntity(entity)                  -- Add entity to world
world:removeEntity(entity)               -- Remove entity
world:update(dt)                         -- Update physics & entities
world:drawEntitiesYSorted()              -- Draw entities with Y-sorting
```

**Collision Classes:**
- `Player`, `PlayerDodging`
- `Wall`, `Portals`
- `Enemy`, `Item`

**Game Modes:**
- **Topdown:** No gravity, free 2D movement
- **Platformer:** Gravity enabled, horizontal movement + jump

---

## 💾 Save/Load System

### `engine/save.lua`
Slot-based save system.

**Key Functions:**
```lua
save_sys:saveGame(slot, data)            -- Save to slot (1-3)
save_sys:loadGame(slot)                  -- Load from slot
save_sys:getAllSlotsInfo()               -- Get all save slots info
save_sys:hasSaveFiles()                  -- Check if any saves exist
save_sys:deleteSave(slot)                -- Delete save slot
```

**Save Data Structure:**
```lua
{
    hp = 100,
    max_hp = 100,
    map = "assets/maps/level1/area1.lua",
    x = 400,
    y = 250,
    inventory = { ... }
}
```

---

## 🎒 Inventory System

### `engine/inventory.lua`
Item management system.

**Key Functions:**
```lua
inventory:addItem(item_id, quantity)     -- Add item to inventory
inventory:removeItem(item_id, quantity)  -- Remove item
inventory:useItem(slot_index, player)    -- Use item in slot
inventory:selectSlot(index)              -- Select slot (1-10)
inventory:nextItem()                     -- Cycle to next item
inventory:prevItem()                     -- Cycle to previous item
```

**Item Definition:**
Items are defined in `game/entities/item/types/`:
```lua
-- game/entities/item/types/small_potion.lua
return {
    id = "small_potion",
    name = "Small Potion",
    icon = "assets/images/items/small_potion.png",
    max_stack = 99,
    use = function(player)
        player.health = math.min(player.health + 30, player.max_health)
    end
}
```

---

## 💬 Dialogue System

### `engine/dialogue.lua`
NPC dialogue system (Talkies library wrapper).

**Key Functions:**
```lua
dialogue:show(messages, avatar, on_complete)  -- Show dialogue
dialogue:isActive()                           -- Check if dialogue is active
dialogue:update(dt)                           -- Update dialogue system
dialogue:draw()                               -- Draw dialogue box
```

**Usage Example:**
```lua
dialogue:show(
    {"Hello, traveler!", "Welcome to our village."},
    npc.avatar,
    function() print("Dialogue finished") end
)
```

---

## 🗺️ Minimap System

### `engine/minimap.lua`
Minimap rendering system.

**Key Functions:**
```lua
minimap:new()                                 -- Create minimap
minimap:setMap(world)                         -- Set world for minimap
minimap:draw(player_x, player_y)             -- Draw minimap
```

---

## 🎨 Effects System

### `engine/effects.lua`
Particle effects system.

**Key Functions:**
```lua
effects:hitEffect(x, y)                       -- Hit particle effect
effects:deathEffect(x, y)                     -- Death effect
effects:update(dt)                            -- Update particles
effects:draw()                                -- Draw particles
```

---

## 📊 HUD System

### `engine/hud.lua`
Heads-up display rendering.

**Key Functions:**
```lua
hud:draw(player, inventory)                   -- Draw HUD (health, cooldowns)
hud:drawInventoryHUD(inventory)               -- Draw quick-access inventory
hud:drawParryFeedback()                       -- Draw parry success indicator
```

---

## 🐛 Debug System

### `engine/debug.lua`
Debug overlay and visualization (F1 toggle).

**Key Features:**
- Unified info window (FPS, player state, screen info)
- Hitbox visualization (F1)
- Grid visualization (F2)
- Virtual mouse cursor (F3)
- Hand marking mode for animation development

**Toggle:**
```lua
debug.enabled = true/false  -- F1 key toggles this
debug:toggleLayer("visualizations")  -- F2 toggles grid
debug:toggleLayer("mouse")  -- F3 toggles virtual mouse
```

---

## 🎮 Game Mode System

### `engine/game_mode.lua`
Topdown vs Platformer mode management.

**Modes:**
- **topdown:** Free 2D movement, no gravity
- **platformer:** Horizontal movement + jump, gravity enabled

**Set via Tiled map property:**
```
Map Properties:
  game_mode = "topdown"  (or "platformer")
```

---

## 🔧 Utilities

### `engine/utils/util.lua`
General utility functions.

### `engine/utils/restart.lua`
Game restart logic (from save/from current position).

### `engine/utils/scene_ui.lua`
Reusable UI components for menus.

### `engine/utils/fonts.lua`
Font management system.

---

## 📐 Constants

### `engine/constants.lua`
Engine-wide constants.

**Categories:**
- Vibration patterns
- Input timings
- Game start defaults

---

**See also:**
- [GAME_GUIDE.md](GAME_GUIDE.md) - Content creation guide
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Full structure reference
