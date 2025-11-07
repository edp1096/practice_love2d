# Complete Development Guide

This comprehensive guide covers engine systems, game content creation, development workflows, and visual effects.

---

## Table of Contents

### [Part 1: Engine Systems](#part-1-engine-systems)
- [Scene Management](#scene-management)
- [Application Lifecycle](#application-lifecycle)
- [Coordinate System](#coordinate-system)
- [Camera System](#camera-system)
- [Sound System](#sound-system)
- [Input System](#input-system)
- [World System](#world-system)
- [Save/Load System](#saveload-system)
- [Inventory System](#inventory-system)
- [Dialogue System](#dialogue-system)
- [Minimap System](#minimap-system)
- [HUD System](#hud-system)
- [Debug System](#debug-system)
- [Game Mode System](#game-mode-system)
- [Utilities](#utilities)

### [Part 2: Visual Effects & Lighting](#part-2-visual-effects--lighting)
- [Effects System](#effects-system)
- [Lighting System](#lighting-system)
- [Rendering Pipeline](#rendering-pipeline)
- [Common Patterns](#common-patterns)

### [Part 3: Game Content Creation](#part-3-game-content-creation)
- [Creating Scenes](#creating-scenes)
- [Creating Entities](#creating-entities)
- [Adding Sounds](#adding-sounds)
- [Creating Maps](#creating-maps)
- [Configuring Input](#configuring-input)
- [Creating Cutscenes](#creating-cutscenes)
- [Using Save System](#using-save-system)
- [Quick Recipes](#quick-recipes)

### [Part 4: Development Workflows](#part-4-development-workflows)
- [Architecture Principles](#architecture-principles)
- [Development Workflows](#development-workflows-1)
- [Code Style](#code-style)
- [Debugging](#debugging)
- [Testing](#testing)
- [Building & Distribution](#building--distribution)
- [Version Control](#version-control)
- [Performance Tips](#performance-tips)

---

# Part 1: Engine Systems

This section documents all engine systems in the `engine/` folder.

## Scene Management

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

## Application Lifecycle

### `engine/lifecycle.lua`
Manages application lifecycle (initialization, update, draw, resize, quit).
Orchestrates all engine systems and delegates to scene_control.

**Key Functions:**
```lua
lifecycle:initialize(initial_scene)  -- Initialize all systems and start first scene
lifecycle:update(dt)                 -- Update input, virtual gamepad, current scene
lifecycle:draw()                     -- Draw scene, virtual gamepad, debug overlays
lifecycle:resize(w, h)               -- Handle window resize
lifecycle:quit()                     -- Clean up and save config
```

**Setup (in main.lua):**
```lua
-- Configure dependencies
lifecycle.display = display
lifecycle.input = input
lifecycle.scene_control = scene_control
-- ... (other dependencies)

-- Initialize application
lifecycle:initialize(menu)
```

**Purpose:**
- Encapsulates complex initialization logic from main.lua
- Coordinates multiple engine systems (input, display, fonts, sound)
- Provides clean separation between LÖVE callbacks and business logic
- Centralizes error handling for system initialization

---

## Coordinate System

### `engine/coords.lua`
Unified coordinate system management for all engine systems. Handles conversions between different coordinate spaces.

**Coordinate Systems:**

1. **WORLD** - Game world coordinates
   - Origin: Map origin (0,0)
   - Unit: Pixels in game world
   - Used by: Entities, colliders, map tiles

2. **CAMERA** - Camera-transformed coordinates
   - Origin: Canvas center
   - Transform: Applied by `camera:attach()`
   - Used by: Rendering within canvas

3. **VIRTUAL** - Virtual screen coordinates
   - Origin: Top-left (0,0)
   - Resolution: Fixed (960x540 default)
   - Used by: UI, HUD, menus

4. **PHYSICAL** - Physical screen coordinates
   - Origin: Top-left (0,0)
   - Resolution: Actual device screen
   - Used by: Window, raw input events

5. **CANVAS** - Canvas pixel coordinates
   - Origin: Top-left (0,0) of canvas
   - Used by: Shaders, low-level rendering

**Key Functions:**
```lua
-- Conversion functions
coords:worldToCamera(wx, wy, camera)
coords:cameraToWorld(cx, cy, camera)
coords:virtualToPhysical(vx, vy, display)
coords:physicalToVirtual(px, py, display)
coords:worldToVirtual(wx, wy, camera, display)
coords:virtualToWorld(vx, vy, camera, display)

-- Utility functions
coords:debugPoint(x, y, camera, display, label)
coords:isVisibleInCamera(wx, wy, camera, margin)
coords:isVisibleInVirtual(vx, vy, display)
coords:distanceWorld(x1, y1, x2, y2)
coords:distanceCamera(x1, y1, x2, y2, camera)
```

**Common Use Cases:**

1. **Mouse Click to World Position:**
```lua
local mx, my = love.mouse.getPosition()  -- Physical
local vx, vy = coords:physicalToVirtual(mx, my, display)
local wx, wy = coords:virtualToWorld(vx, vy, cam, display)
-- Now (wx, wy) is world position
```

2. **UI Overlay on World Object:**
```lua
-- Show health bar above enemy
local cx, cy = coords:worldToCamera(enemy.x, enemy.y, cam)
local vx, vy = coords:physicalToVirtual(cx, cy, display)
-- Draw at (vx, vy) in virtual coords
```

3. **Debugging Coordinates:**
```lua
coords:debugPoint(player.x, player.y, cam, display, "Player")
-- Prints all coordinate representations
```

**Important Notes:**
- Always use the correct coordinate system for each context
- World coords for game logic and physics
- Virtual coords for UI rendering
- Physical coords for raw input
- Camera coords for world rendering
- Canvas coords for shaders

**IMPORTANT - Usage Rules:**
- ✅ **ALWAYS** use `coords:worldToCamera()` and `coords:cameraToWorld()`
- ✅ **ALWAYS** use `coords:physicalToVirtual()` and `coords:virtualToPhysical()`
- ❌ **NEVER** use `camera:cameraCoords()` or `camera:worldCoords()` directly
- ❌ **NEVER** use `display:ToVirtualCoords()` or `display:ToScreenCoords()` directly
- The coords module provides a unified interface and handles nil checks automatically

---

## Camera System

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

## Sound System

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

## Input System

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

**Input Event Dispatcher (`engine/input/dispatcher.lua`):**
Routes LÖVE input events to appropriate handlers with priority system:
```lua
-- Priority order for touch events:
-- 1. Debug button (highest priority)
-- 2. Scene touchpressed (inventory, dialogue overlays)
-- 3. Virtual gamepad (if scene didn't handle it)
-- 4. Fallback to mouse events (desktop testing)

-- Setup (in main.lua)
input_dispatcher.scene_control = scene_control
input_dispatcher.virtual_gamepad = virtual_gamepad
input_dispatcher.input = input

-- Usage in LÖVE callbacks
function love.touchpressed(id, x, y, dx, dy, pressure)
    input_dispatcher:touchpressed(id, x, y, dx, dy, pressure)
end
```

**Purpose:**
- Encapsulates complex input routing logic from main.lua
- Manages touch input priority system
- Coordinates between virtual gamepad, scene input, and mouse fallback
- Handles all LÖVE input callbacks (keyboard, mouse, touch, gamepad)

**Virtual Gamepad (`engine/input/virtual_gamepad.lua`):**
Mobile on-screen gamepad with touch controls:
- **D-pad** (bottom-left): Movement (8-way directional input)
- **Aim stick** (center-right): Aiming direction
- **Action buttons** (bottom-right): A, B, X, Y (diamond layout)
- **Shoulder buttons** (top): L1, L2, R1, R2
- **Menu button** (top-left): Pause/menu access
- Auto-enabled on mobile (Android/iOS)
- Can be tested on PC using F4 debug key

```lua
-- Show/hide virtual gamepad (handled automatically by scenes)
virtual_gamepad:show()   -- Show in gameplay
virtual_gamepad:hide()   -- Hide in menus

-- Get input from virtual gamepad
local stick_x, stick_y = virtual_gamepad:getStickAxis()
local aim_angle, is_aiming = virtual_gamepad:getAimDirection(player.x, player.y, cam)
```

---

## World System

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

## Save/Load System

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

## Inventory System

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

## Dialogue System

### `engine/ui/dialogue.lua`
NPC dialogue system with mobile UI buttons (Talkies library wrapper).

**Key Functions:**
```lua
dialogue:initialize()                        -- Initialize dialogue system
dialogue:setDisplay(display)                 -- Set display reference for buttons
dialogue:showSimple(name, message)           -- Show single message
dialogue:showMultiple(name, messages)        -- Show multiple messages
dialogue:isOpen()                            -- Check if dialogue is active
dialogue:update(dt)                          -- Update dialogue system
dialogue:draw()                              -- Draw dialogue box and buttons
dialogue:onAction()                          -- Advance to next message
dialogue:clear()                             -- Clear all dialogue
dialogue:handleInput(source, ...)           -- Unified input handler
```

**Mobile UI:**
- **NEXT button** (green): Advance to next message
- **SKIP button** (gray): Close all dialogue immediately
- Auto-positioned in bottom-right corner
- Supports both touch and mouse input

**Input Handling:**
```lua
-- Keyboard
if dialogue:handleInput("keyboard") then return end

-- Mouse
if dialogue:handleInput("mouse", x, y) then return end
if dialogue:handleInput("mouse_release", x, y) then return end

-- Touch
if dialogue:handleInput("touch", id, x, y) then return true end
if dialogue:handleInput("touch_release", id, x, y) then return true end
if dialogue:handleInput("touch_move", id, x, y) then return true end
```

**Usage Example:**
```lua
-- Initialize (in scene:enter)
dialogue:initialize()
dialogue:setDisplay(display)

-- Show dialogue
local npc = world:getInteractableNPC(player.x, player.y)
if npc then
    local messages = npc:interact()
    dialogue:showMultiple(npc.name, messages)
end

-- Handle input (in scene input handlers)
function scene:keypressed(key)
    if key == "return" or key == "space" then
        if dialogue:handleInput("keyboard") then return end
    end
end

function scene:mousepressed(x, y, button)
    if button == 1 then
        dialogue:handleInput("mouse", x, y)
    end
end

function scene:touchpressed(id, x, y, dx, dy, pressure)
    return dialogue:handleInput("touch", id, x, y)
end
```

**Widgets:**
- `engine/ui/widgets/skip_button.lua` - SKIP button widget
- `engine/ui/widgets/next_button.lua` - NEXT button widget

---

## Menu UI System

### `engine/ui/menu.lua`
Common UI utilities for menu scenes to eliminate code duplication.

**Layout Functions:**
```lua
ui_scene.createMenuLayout(vh)               -- Create standard menu layout
ui_scene.createMenuFonts()                  -- Create standard fonts
```

**Drawing Functions:**
```lua
ui_scene.drawTitle(text, font, y, width, color)
ui_scene.drawOptions(options, selected, mouse_over, font, layout, width)
ui_scene.drawOverlay(width, height, alpha)
ui_scene.drawControlHints(font, layout, width, custom_text)
ui_scene.drawConfirmDialog(title, subtitle, button_labels, selected, mouse_over, fonts, width, height)
```

**Input Handling Functions:**
```lua
ui_scene.handleKeyboardNav(key, current_selection, option_count)
ui_scene.handleGamepadNav(button, current_selection, option_count)
ui_scene.handleMouseSelection(button, mouse_over)

-- Touch input (NEW)
ui_scene.handleTouchPress(options, layout, width, font, x, y, display)
ui_scene.handleSlotTouchPress(slots, layout, width, x, y, display)
```

**Mouse Detection Functions:**
```lua
ui_scene.updateMouseOver(options, layout, width, font)
ui_scene.updateConfirmMouseOver(width, height, button_count)
```

**Usage Example (Menu Scene):**
```lua
local ui_scene = require "engine.ui.menu"
local display = require "engine.display"
local sound = require "engine.sound"

function menu:enter(previous)
    self.options = {"Continue", "New Game", "Settings", "Quit"}
    self.selected = 1
    self.mouse_over = 0

    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh
    self.fonts = ui_scene.createMenuFonts()
    self.layout = ui_scene.createMenuLayout(vh)
end

function menu:update(dt)
    -- Update mouse-over detection
    self.mouse_over = ui_scene.updateMouseOver(
        self.options, self.layout, self.virtual_width, self.fonts.option)
end

function menu:draw()
    display:Attach()
    ui_scene.drawTitle("Main Menu", self.fonts.title, self.layout.title_y, self.virtual_width)
    ui_scene.drawOptions(self.options, self.selected, self.mouse_over,
        self.fonts.option, self.layout, self.virtual_width)
    ui_scene.drawControlHints(self.fonts.hint, self.layout, self.virtual_width)
    display:Detach()
end

function menu:keypressed(key)
    local nav_result = ui_scene.handleKeyboardNav(key, self.selected, #self.options)
    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    end
end

function menu:mousereleased(x, y, button)
    if button == 1 and self.mouse_over > 0 then
        self.selected = self.mouse_over
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    end
end

-- Touch input (mobile support)
function menu:touchpressed(id, x, y, dx, dy, pressure)
    self.mouse_over = ui_scene.handleTouchPress(
        self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
    return false
end

function menu:touchreleased(id, x, y, dx, dy, pressure)
    local touched = ui_scene.handleTouchPress(
        self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
    if touched > 0 then
        self.selected = touched
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
        return true
    end
    return false
end
```

**Slot-Based Menu Example (Save/Load):**
```lua
function saveslot:touchpressed(id, x, y, dx, dy, pressure)
    self.mouse_over = ui_scene.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    return false
end

function saveslot:touchreleased(id, x, y, dx, dy, pressure)
    local touched = ui_scene.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    if touched > 0 then
        self.selected = touched
        self:selectSlot(self.selected)
        return true
    end
    return false
end
```

**Benefits:**
- Eliminates code duplication across menu scenes
- Consistent UI behavior across all menus
- Built-in mobile touch support
- Easy to maintain and extend

---

## Minimap System

### `engine/minimap.lua`
Minimap rendering system.

**Key Functions:**
```lua
minimap:new()                                 -- Create minimap
minimap:setMap(world)                         -- Set world for minimap
minimap:draw(player_x, player_y)             -- Draw minimap
```

---

## HUD System

### `engine/hud.lua`
Heads-up display rendering.

**Key Functions:**
```lua
hud:draw(player, inventory)                   -- Draw HUD (health, cooldowns)
hud:drawInventoryHUD(inventory)               -- Draw quick-access inventory
hud:drawParryFeedback()                       -- Draw parry success indicator
```

---

## Debug System

### `engine/debug.lua`
Debug overlay and visualization controlled by config.ini.

**Configuration:**
- `config.ini` → `[Game]` → `IsDebug = true/false`
- When `IsDebug = true`: F1-F6 keys are enabled
- When `IsDebug = false`: F1-F6 keys are disabled
- Debug UI starts **OFF** by default (press F1 to enable)

**Key Features:**
- Unified info window (FPS, player state, screen info)
- Hitbox visualization (F1)
- Grid visualization (F2)
- Virtual mouse cursor (F3)
- Virtual gamepad testing (F4, PC only)
- Effects debug (F5)
- Test effects (F6)
- Hand marking mode for animation development

**States:**
```lua
debug.allowed = true/false   -- From GameConfig.is_debug (allows F1-F6)
debug.enabled = true/false   -- Debug UI visibility (toggled with F1)

-- F1: Toggle debug UI (requires allowed = true)
debug:toggle()

-- F2-F6: Layer toggles (require enabled = true)
debug:toggleLayer("visualizations")    -- F2: Grid
debug:toggleLayer("mouse")             -- F3: Virtual mouse
debug:toggleLayer("virtual_gamepad")   -- F4: Virtual gamepad (PC)
debug:toggleLayer("effects")           -- F5: Effects debug
```

**Developer Note:**
- `IsDebug` is a developer-only setting in config.ini
- Not overwritten when saving user settings
- Version is hardcoded in conf.lua, not saved to config.ini

---

## Game Mode System

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

## Utilities

### `engine/utils/util.lua`
General utility functions.

### `engine/utils/restart.lua`
Game restart logic (from save/from current position).

### `engine/utils/fonts.lua`
Font management system.

### `engine/constants.lua`
Engine-wide constants (vibration patterns, input timings, defaults).

---

# Part 2: Visual Effects & Lighting

## Effects System

### `engine/effects/`
Visual effects system with particles and screen effects.

**Subsystems:**
- `effects.particles` - Particle effects (blood, sparks, dust, slash)
- `effects.screen` - Screen effects (damage flash, vignette, overlay)

### Particle Effects

```lua
local effects = require "engine.effects"

-- Spawn particles
effects:spawn("blood", x, y)                  -- Blood splash
effects:spawn("spark", x, y, angle)           -- Sparks
effects:spawn("dust", x, y)                   -- Dust cloud
effects:spawn("slash", x, y, angle)           -- Slash trail

-- Presets
effects:spawnHitEffect(x, y, "player")        -- Player hit combo
effects:spawnParryEffect(x, y, angle, true)   -- Parry (true = perfect)
effects:spawnWeaponTrail(x, y, angle)         -- Weapon swing

-- System
effects:update(dt)                            -- Update particles
effects:draw()                                -- Draw (in camera)
```

### Screen Effects

```lua
-- Damage & Healing
effects.screen:damage()                       -- Red flash (0.3s)
effects.screen:heal()                         -- Green flash (0.4s)

-- Status Effects
effects.screen:poison(5.0)                    -- Green vignette (5s)
effects.screen:invincible(2.0)                -- White pulse (2s)
effects.screen:stun(0.5)                      -- Gray overlay (0.5s)

-- Special
effects.screen:death(2.0)                     -- Red fade in (2s)
effects.screen:low_health()                   -- Red pulse (infinite)
effects.screen:teleport()                     -- White flash (instant)

-- Management
effects.screen:clearEffects("vignette")       -- Remove type
effects.screen:clearEffects()                 -- Remove all

-- System
effects.screen:update(dt)                     -- Update
effects.screen:draw()                         -- Draw (after camera)
```

### Custom Screen Effect

```lua
effects.screen:addEffect({
    type = "flash",              -- "flash", "vignette", "overlay"
    color = {1, 0.5, 0},         -- RGB
    intensity = 0.5,             -- 0.0-1.0
    duration = 1.0,              -- seconds (-1 = infinite)
    fade_out = true,             -- optional
    pulse = false,               -- optional
    pulse_speed = 1.0            -- optional
})
```

---

## Lighting System

### `engine/lighting/`
Dynamic lighting with ambient and light sources using image-based rendering.

**Implementation:** Uses programmatically generated circular gradient images for point lights, providing cross-platform compatibility without shader issues.

### Ambient Light

```lua
local lighting = require "engine.lighting"

-- Presets
lighting:setAmbient("day")        -- Bright (0.95, 0.95, 1.0)
lighting:setAmbient("dusk")       -- Dim (0.7, 0.6, 0.8)
lighting:setAmbient("night")      -- Dark (0.05, 0.05, 0.15)
lighting:setAmbient("cave")       -- Very dark (0.05, 0.05, 0.1)
lighting:setAmbient("indoor")     -- Indoor (0.5, 0.5, 0.55)
lighting:setAmbient("underground")-- Underground (0.1, 0.1, 0.12)

-- Custom
lighting:setAmbient(0.2, 0.3, 0.4)
```

### Point Lights

```lua
-- Torch
local torch = lighting:addLight({
    type = "point",
    x = 100, y = 100,
    radius = 150,
    color = {1, 0.8, 0.5},       -- Warm orange
    intensity = 1.0,
    flicker = true,              -- optional
    flicker_speed = 5.0,         -- optional
    flicker_amount = 0.3         -- optional (0.0-1.0)
})

-- Player light (follow)
function player:new()
    self.light = lighting:addLight({
        type = "point",
        x = self.x, y = self.y,
        radius = 100,
        color = {1, 0.9, 0.7},
        intensity = 0.8
    })
end

function player:update(dt)
    self.light:setPosition(self.x, self.y)
end
```

### Spotlights

```lua
-- Spotlight (not yet implemented)
-- TODO: Implement spotlight using image or shader
```

### Light Control

```lua
light:setPosition(x, y)
light:setColor(r, g, b)
light:setIntensity(1.5)
light:setEnabled(false)            -- Turn off

lighting:removeLight(light)
lighting:clearLights()
```

### System Update & Draw

```lua
lighting:update(dt)                -- Update (flicker, etc)
lighting:draw(camera)              -- Draw (MUST pass camera!)
lighting:setEnabled(false)         -- Disable entire system
```

---

## Rendering Pipeline

Correct rendering order for effects and lighting:

```lua
function scene:draw()
    camera:attach()

    -- 1. Scene
    world:draw()
    entities:draw()

    -- 2. Particle effects (in camera)
    effects:draw()

    camera:detach()

    -- 3. Lighting (after camera)
    lighting:draw(camera)

    -- 4. Screen effects (after camera)
    effects.screen:draw()

    -- 5. UI (unaffected)
    hud:draw()
end
```

---

## Common Patterns

### Combat Hit

```lua
-- Hit effect
effects:spawnHitEffect(enemy.x, enemy.y, "enemy")

-- Screen flash if player hit
if target == player then
    effects.screen:damage()
end
```

### Low Health Warning

```lua
if player.health < player.max_health * 0.2 then
    effects.screen:low_health()  -- Start warning
end

-- Remove when healed
if player.health >= player.max_health * 0.2 then
    effects.screen:clearEffects("vignette")
end
```

### Dynamic Light Following Entity

```lua
-- Create
entity.light = lighting:addLight({
    type = "point",
    x = entity.x, y = entity.y,
    radius = 120,
    color = {1, 0.8, 0.5},
    intensity = 1.0
})

-- Update
entity.light:setPosition(entity.x, entity.y)

-- Remove
lighting:removeLight(entity.light)
```

### Map-Based Lighting

```lua
-- Set ambient via map property (in Tiled)
-- Map Properties:
--   ambient = "night"  (or "day", "dusk", "cave", "indoor", "underground")

-- In scene:enter() or scene:switchMap()
function play:setupLighting()
    lighting:clearLights()
    local ambient = self.world.map.properties.ambient or "day"
    lighting:setAmbient(ambient)

    -- Only add lights in dark environments
    if ambient ~= "day" then
        -- Add player light
        self.player.light = lighting:addLight({
            type = "point",
            x = self.player.x,
            y = self.player.y,
            radius = 350,
            color = {1, 0.9, 0.7},
            intensity = 1.0
        })

        -- Add lights to enemies, NPCs, save points, etc.
        -- (See game/scenes/play/init.lua:setupLighting for full implementation)
    end
end

-- Call in scene:enter() and scene:switchMap()
self:setupLighting()
```

### Important Notes

1. **Screen effects** draw AFTER camera (screen-space)
2. **Lighting** needs camera parameter: `lighting:draw(camera)`
3. **Particles** draw IN camera (world-space)
4. Performance: ~10-20 lights, ~2-3 screen effects at once
5. Infinite screen effects (`duration = -1`) must be cleared manually
6. Light culling recommended for many lights (check distance from camera)
7. **Lighting system** uses image-based rendering (no shaders) for cross-platform compatibility
8. Light images are generated at init time (256x256 with quadratic falloff)

---

# Part 3: Game Content Creation

This section shows how to create game content in the `game/` folder.

## Philosophy: Content Over Code

The `game/` folder is designed for **content creation**, not engine programming:
- **Minimal code** - mostly data definitions
- **Simple APIs** - call engine functions
- **Quick iteration** - change content without touching engine

---

## Creating Scenes

### Scene Structure
Scenes go in `game/scenes/`. Simple scenes can be single files, complex scenes should be modular folders.

**Single File Scene Example:**
```lua
-- game/scenes/credits.lua
local credits = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"

function credits:enter(previous, ...)
    self.text = "Thanks for playing!"
end

function credits:update(dt)
    -- Update logic
end

function credits:draw()
    love.graphics.print(self.text, 100, 100)
end

function credits:keypressed(key)
    if key == "escape" then
        local menu = require "game.scenes.menu"
        scene_control.switch(menu)
    end
end

return credits
```

**Modular Scene Example:**
```
game/scenes/shop/
├── init.lua          - Scene coordinator
├── items.lua         - Shop item definitions
├── render.lua        - UI rendering
└── input.lua         - Input handling
```

### Using Engine Systems in Scenes
```lua
-- game/scenes/yourscene.lua
local scene_control = require "engine.scene_control"
local sound = require "engine.sound"
local input = require "engine.input"
local save_sys = require "engine.save"

function yourscene:enter()
    sound:playBGM("menu", 1.0, true)  -- Play menu music
end

function yourscene:keypressed(key)
    if input:wasPressed("confirm") then
        sound:playSFX("ui", "select")
        -- Do something
    end
end
```

---

## Creating Entities

### Enemy Type Example
```lua
-- game/entities/enemy/types/goblin.lua
return {
    -- Stats
    name = "Goblin",
    max_health = 50,
    damage = 10,
    speed = 120,

    -- Visuals
    sprite_path = "assets/images/enemies/goblin.png",
    sprite_width = 32,
    sprite_height = 32,
    collider_width = 28,
    collider_height = 28,

    -- AI
    ai_type = "aggressive",
    chase_range = 200,
    attack_range = 40,
    patrol_speed = 60,

    -- Animation
    animations = {
        idle = { frames = "1-4", fps = 8 },
        walk = { frames = "5-8", fps = 12 },
        attack = { frames = "9-12", fps = 16 }
    },

    -- Sounds
    sounds = {
        hurt = "enemy_hurt",
        death = "enemy_death",
        attack = "enemy_attack"
    }
}
```

### NPC Type Example
```lua
-- game/entities/npc/types/shopkeeper.lua
return {
    name = "Shopkeeper",
    sprite_path = "assets/images/npcs/shopkeeper.png",

    -- Dialogue
    dialogue = {
        "Welcome to my shop!",
        "What can I get you today?",
        "Come back soon!"
    },

    -- Interaction
    on_interact = function(player, npc)
        local dialogue = require "engine.ui.dialogue"
        dialogue:show(npc.config.dialogue, npc.avatar)
    end
}
```

### Item Type Example
```lua
-- game/entities/item/types/mega_potion.lua
return {
    id = "mega_potion",
    name = "Mega Potion",
    description = "Restores 100 HP",
    icon = "assets/images/items/mega_potion.png",
    max_stack = 50,

    use = function(player)
        local sound = require "engine.sound"

        if player.health < player.max_health then
            player.health = math.min(player.health + 100, player.max_health)
            sound:playSFX("player", "heal")
            return true  -- Item consumed
        else
            sound:playSFX("ui", "error")
            return false  -- Item not consumed
        end
    end
}
```

---

## Adding Sounds

### 1. Add Audio Files
Place files in `assets/bgm/` or `assets/sound/`:
```
assets/
├── bgm/
│   └── dungeon.ogg
└── sound/
    ├── player/
    │   └── magic_cast.wav
    └── ui/
        └── coin.wav
```

### 2. Register in Sound Config
Edit `game/data/sounds.lua`:
```lua
return {
    bgm = {
        dungeon = {
            path = "assets/bgm/dungeon.ogg",
            volume = 0.7,
            loop = true
        }
    },

    sfx = {
        player = {
            magic_cast = {
                path = "assets/sound/player/magic_cast.wav",
                volume = 0.8,
                pitch_variation = "normal"
            }
        },
        ui = {
            coin = {
                path = "assets/sound/ui/coin.wav",
                volume = 0.9
            }
        }
    }
}
```

### 3. Play in Game
```lua
local sound = require "engine.sound"
sound:playBGM("dungeon")              -- Play dungeon BGM
sound:playSFX("player", "magic_cast") -- Play magic cast sound
sound:playSFX("ui", "coin")           -- Play coin sound
```

---

## Creating Maps

### 1. Create Map in Tiled
- Use Tiled Map Editor to create `.tmx` file
- Place in `assets/maps/levelX/`
- Export to Lua format (`.lua` file)

### 2. Set Map Properties
In Tiled, set map custom properties:
```
Map Properties:
  game_mode = "topdown"  (or "platformer")
  bgm = "dungeon"        (optional - BGM name from sounds.lua)
  ambient = "night"      (optional - lighting preset)
```

### 3. Map Layers
Required layers:
- **Ground** - Terrain layer
- **Trees** - Top decoration (drawn after entities)
- **Walls** - Collision objects (rectangles, polygons)
- **Portals** - Transition zones
- **Enemies** - Enemy spawn points
- **NPCs** - NPC locations
- **SavePoints** - Save point locations
- **HealingPoints** - Healing areas
- **Lights** - Light sources (optional)

### 4. Add Portals
Create object in **Portals** layer:
```
Object Properties:
  type = "portal"
  target_map = "assets/maps/level1/area2.lua"
  spawn_x = 100
  spawn_y = 200
```

### 5. Add Enemies
Create object in **Enemies** layer:
```
Object Properties:
  type = "goblin"  (matches filename in game/entities/enemy/types/)
  patrol_points = "100,200;300,200;300,400"  (optional)
```

### 6. Load Map in Game
```lua
-- In your scene
local world = require "engine.world"
self.world = world:new("assets/maps/level1/dungeon.lua")
```

---

## Configuring Input

### Edit Input Config
Edit `game/data/input_config.lua`:
```lua
return {
    actions = {
        -- Movement
        move_left = {
            keys = {"a", "left"},
            gamepad = {"dpleft"}
        },
        move_right = {
            keys = {"d", "right"},
            gamepad = {"dpright"}
        },

        -- Combat
        attack = {
            mouse = {1},  -- Left mouse button
            gamepad = {"a"}
        },
        special_attack = {
            mouse = {2},  -- Right mouse button
            gamepad = {"x"},
            keys = {"e"}
        },

        -- Custom action
        magic = {
            keys = {"q"},
            gamepad = {"y"}
        }
    },

    -- Mode-specific overrides
    mode_overrides = {
        platformer = {
            jump = { keys = {"w", "up", "space"}, gamepad = {"b"} }
        }
    }
}
```

### Use in Game
```lua
local input = require "engine.input"

function play:update(dt)
    if input:wasPressed("magic") then
        -- Cast magic spell
    end

    if input:isDown("attack") then
        -- Charge attack
    end
end
```

---

## Creating Cutscenes

### 1. Define Cutscene
Edit `game/data/intro_configs.lua`:
```lua
return {
    chapter1_intro = {
        background = "assets/images/cutscenes/chapter1_bg.png",
        bgm = "dramatic",
        messages = {
            "Long ago, in a distant land...",
            "A great evil awakened...",
            "Only one hero can stop it..."
        },
        speaker = "Narrator"
    }
}
```

### 2. Trigger Cutscene
```lua
local scene_control = require "engine.scene_control"
local intro = require "game.scenes.intro"

-- Show intro, then go to play scene
scene_control.switch(
    intro,
    "chapter1_intro",                    -- Intro ID
    "assets/maps/level1/area1.lua",      -- Target map after intro
    400, 250,                             -- Spawn position
    1                                     -- Save slot
)
```

---

## Using Save System

### Save Game
```lua
local save_sys = require "engine.save"

function play:saveGame()
    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y,
        inventory = self.inventory:save()
    }

    save_sys:saveGame(self.current_save_slot, save_data)
end
```

### Load Game
```lua
local save_sys = require "engine.save"

function menu:loadGame(slot)
    local save_data = save_sys:loadGame(slot)

    if save_data then
        local play = require "game.scenes.play"
        scene_control.switch(play, save_data.map, save_data.x, save_data.y, slot)
    end
end
```

---

## Quick Recipes

### Add a New Level
1. Create map in Tiled: `assets/maps/level2/castle.tmx`
2. Export to Lua: `assets/maps/level2/castle.lua`
3. Add BGM: `game/data/sounds.lua` → `bgm.castle = { ... }`
4. Set map property: `bgm = "castle"`
5. Create portal to it from previous level

### Add a New Enemy
1. Create sprite: `assets/images/enemies/dragon.png`
2. Create type: `game/entities/enemy/types/dragon.lua`
3. Place in Tiled map: Object type = "dragon"

### Add a New Item
1. Create icon: `assets/images/items/sword.png`
2. Create type: `game/entities/item/types/sword.lua`
3. Add to inventory: `inventory:addItem("sword", 1)`

### Add a New Menu
1. Create scene: `game/scenes/credits.lua`
2. Add to main menu options: `{ "Credits", ... }`
3. Switch to it: `scene_control.switch(credits)`

---

# Part 4: Development Workflows

## Architecture Principles

### 1. Engine/Game Separation
**Goal:** Engine is reusable, game is content.

**Rules:**
- ✅ Engine files should NOT import game files
- ✅ Game files CAN import engine files
- ✅ Engine should be generic and configurable
- ✅ Game should be data-driven

**Example:**
```lua
-- ❌ BAD: Engine depends on game content
-- engine/sound.lua
local game_sounds = require "game.data.sounds"  -- NO!

-- ✅ GOOD: Game passes data to engine
-- game/scenes/menu.lua
local sound = require "engine.sound"
local sounds_config = require "game.data.sounds"
sound:init(sounds_config)  -- Pass config to engine
```

### 2. Modular Architecture
**Goal:** Each file has a single responsibility.

**When to split a file:**
- File exceeds 500 lines
- File has multiple unrelated responsibilities
- File is hard to navigate

**Modular Scene Pattern:**
```
game/scenes/yourscene/
├── init.lua          - Coordinator (enter, exit, update, draw)
├── input.lua         - Input handling only
├── render.lua        - Drawing logic only
└── logic.lua         - Business logic only
```

### 3. Data-Driven Design
**Goal:** Minimize code in game/, maximize data.

**Prefer data over code:**
```lua
-- ❌ BAD: Hardcoded in scene
function menu:enter()
    self.options = {"New Game", "Load", "Quit"}
    self.title = "My Game"
end

-- ✅ GOOD: Data-driven
-- game/data/menu_config.lua
return {
    title = "My Game",
    options = {"New Game", "Load", "Quit"}
}

-- game/scenes/menu.lua
local menu_config = require "game.data.menu_config"
function menu:enter()
    self.options = menu_config.options
    self.title = menu_config.title
end
```

---

## Development Workflows

### Adding a New Engine System

1. **Create system file:**
   ```lua
   -- engine/yoursystem.lua
   local yoursystem = {}

   function yoursystem:init(config)
       -- Initialize with config
   end

   function yoursystem:update(dt)
       -- Update logic
   end

   return yoursystem
   ```

2. **Add to engine utilities:**
   - Keep it generic (no game-specific code)
   - Accept config from game layer
   - Follow existing system patterns

3. **Document in this guide**

### Adding a New Game Scene

1. **Create scene structure:**
   ```bash
   mkdir -p game/scenes/yourscene
   touch game/scenes/yourscene/init.lua
   touch game/scenes/yourscene/input.lua
   touch game/scenes/yourscene/render.lua
   ```

2. **Implement scene lifecycle:**
   ```lua
   -- game/scenes/yourscene/init.lua
   local yourscene = {}

   function yourscene:enter(previous, ...) end
   function yourscene:exit() end
   function yourscene:update(dt) end
   function yourscene:draw() end
   function yourscene:keypressed(key) end

   return yourscene
   ```

3. **Connect to scene control:**
   ```lua
   local scene_control = require "engine.scene_control"
   local yourscene = require "game.scenes.yourscene"
   scene_control.switch(yourscene)
   ```

### Adding a New Entity Type

1. **Create entity definition:**
   ```lua
   -- game/entities/enemy/types/yourenemy.lua
   return {
       name = "Your Enemy",
       max_health = 100,
       damage = 20,
       speed = 150,
       sprite_path = "assets/images/enemies/yourenemy.png",
       -- ... more properties
   }
   ```

2. **Add sprite to assets:**
   ```
   assets/images/enemies/yourenemy.png
   ```

3. **Place in Tiled map:**
   - Create object in Enemies layer
   - Set property: `type = "yourenemy"`

### Adding Sound Effects

1. **Add audio file:**
   ```
   assets/sound/category/soundname.wav
   ```

2. **Register in sounds config:**
   ```lua
   -- game/data/sounds.lua
   sfx = {
       category = {
           soundname = {
               path = "assets/sound/category/soundname.wav",
               volume = 0.8,
               pitch_variation = "normal"
           }
       }
   }
   ```

3. **Play in game:**
   ```lua
   local sound = require "engine.sound"
   sound:playSFX("category", "soundname")
   ```

---

## Code Style

### Naming Conventions
```lua
-- Modules: lowercase with underscores
local scene_control = require "engine.scene_control"

-- Classes/Objects: PascalCase (rare in Lua)
local Player = require "game.entities.player"

-- Functions: camelCase
function player:updateAnimation(dt)

-- Constants: UPPER_CASE
local MAX_HEALTH = 100

-- Private functions: prefix with underscore
local function _internalHelper()
```

### File Organization
```lua
-- 1. Module declaration
local mymodule = {}

-- 2. Requires
local engine_system = require "engine.something"
local game_data = require "game.data.something"

-- 3. Local constants
local MAX_ITEMS = 10

-- 4. Local functions
local function _helper()
end

-- 5. Public functions
function mymodule:publicMethod()
end

-- 6. Return module
return mymodule
```

### Comments
```lua
-- Single-line comments for brief explanations

--[[
Multi-line comments for:
- Complex logic explanations
- API documentation
- TODOs
]]

--- Documentation comments (LDoc style)
--- @param player table The player entity
--- @return boolean Success status
function combat:attack(player)
end
```

---

## Debugging

### Debug Mode (F1)
- Toggle with F1 key (unified info window + hitboxes)
- F2: Toggle grid visualization
- F3: Toggle virtual mouse
- Shows FPS, player state, screen info
- Visualizes hitboxes and collision areas

### Print Debugging

**Conditional Debug Print (dprint):**
```lua
-- Use dprint() for debug messages (only prints when F1 debug mode is enabled)
dprint("Player HP:", player.health)
dprint("Enemy spawned at:", x, y)

-- Use print() for critical errors/warnings (always prints)
print("ERROR: Failed to load map")
print("Warning: Missing texture")
```

**When to use each:**
- `dprint()`: Debug info, state changes, verbose logging
- `print()`: Errors, warnings, critical messages

**Format complex tables:**
```lua
local inspect = require "vendor.inspect"  -- (if available)
dprint(inspect(player))
```

### Error Handling
```lua
-- Use pcall for risky operations
local success, result = pcall(function()
    return require "game.optional.module"
end)

if not success then
    print("Warning: Optional module not found")
    result = nil
end
```

### Common Issues

**Issue: File not found**
```
Solution: Check require path uses dots, not slashes
✅ require "game.scenes.menu"
❌ require "game/scenes/menu"
```

**Issue: Nil value errors**
```
Solution: Check if module exists before using
local module = require "engine.something"
if not module then return end
module:doSomething()
```

**Issue: Physics behaving strangely**
```
Solution: Check game_mode in map properties
Topdown: no gravity
Platformer: gravity enabled
```

---

## Testing

### Manual Testing Checklist
- [ ] Game starts without errors
- [ ] All scenes accessible (menu, play, settings, etc.)
- [ ] Keyboard controls work
- [ ] Gamepad controls work (if available)
- [ ] Touch controls work (mobile/virtual gamepad)
- [ ] Sound plays correctly (BGM, SFX)
- [ ] Save/Load works
- [ ] Inventory system works
- [ ] Combat system works (attack, parry, dodge)
- [ ] Map transitions work
- [ ] NPCs and dialogue work
- [ ] Game modes work (topdown, platformer)
- [ ] Effects and lighting work

### Performance Testing
```lua
-- Check FPS in debug mode (F1)
-- Monitor memory usage
-- Profile with LuaJIT profiler (if needed)
```

---

## Building & Distribution

### Create .love file
```bash
# Exclude unnecessary files
zip -9 -r game.love . -x "*.git*" "*.md" "docs/*" ".vscode/*"
```

### Windows
```bash
# Concatenate LÖVE with game
cat love.exe game.love > mygame.exe
```

### macOS
```bash
# Replace love.app contents
cp -r game.love MyGame.app/Contents/Resources/
```

### Linux
```bash
# AppImage or package .love file
# Users run with: love game.love
```

### Mobile (Android)
```bash
# Use love-android-sdl2
# Package .love into APK
```

---

## Version Control

### Git Workflow
```bash
# Ignore unnecessary files
echo "config.ini" >> .gitignore
echo "*.log" >> .gitignore
echo ".DS_Store" >> .gitignore

# Commit structure changes
git add engine/ game/
git commit -m "Refactor: Separate engine and game folders"

# Commit content changes
git add game/entities/enemy/types/newenemy.lua
git commit -m "Add new enemy: Dragon"
```

### Branching Strategy
```
main          - Stable releases
develop       - Development branch
feature/X     - New features
bugfix/X      - Bug fixes
```

---

## Performance Tips

### Avoid in Hot Paths
```lua
-- ❌ BAD: Creating tables every frame
function update(dt)
    local pos = {x = player.x, y = player.y}  -- Creates garbage
end

-- ✅ GOOD: Reuse tables
local temp_pos = {x = 0, y = 0}
function update(dt)
    temp_pos.x = player.x
    temp_pos.y = player.y
end
```

### Lazy Loading
```lua
-- Load resources on-demand, not all at startup
-- Engine already does this for sounds
```

### Profiling
```lua
-- Measure expensive operations
local start = love.timer.getTime()
expensiveOperation()
print("Took:", love.timer.getTime() - start)
```

---

**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Engine/Game Separation
**Last Updated:** 2025-11-07
