# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 📁 Project Overview

This is a **LÖVE2D game project** (version 11.5) written in Lua. It's a 2D action RPG with **Engine/Game separation architecture** (RPG Maker style).

### Architecture Philosophy
- **`engine/`** - Reusable game systems (can be used in any LÖVE2D project)
- **`game/`** - Game-specific content (scenes, entities, data)
- **`assets/`** - Game resources (maps, images, sounds)

**Goal:** Create new games by copying `engine/` and creating new `game/` content.

---

## 🚀 Running the Game

```bash
# Desktop
love .

# Check syntax
luac -p **/*.lua
```

**Platform Detection:**
- Desktop: Keyboard/mouse + physical gamepad
- Mobile (Android/iOS): Virtual gamepad + touch input

---

## 📂 Project Structure

```
21_map/
├── main.lua, conf.lua, locker.lua    # Entry points
├── engine/                            # Reusable systems ⭐
│   ├── scene_control.lua, camera.lua, sound.lua, ...
│   ├── input/                         # Input system (keyboard, gamepad, touch)
│   ├── world/                         # Physics & map loading (Windfield/STI)
│   └── utils/                         # Engine utilities
├── game/                              # Game content ⭐
│   ├── scenes/                        # Game screens (menu, play, settings, etc.)
│   ├── entities/                      # Player, enemies, NPCs, items
│   └── data/                          # Configs (sounds, inputs, intros)
├── lib/                               # Third-party wrappers
├── vendor/                            # External libraries (STI, Windfield, anim8, hump, Talkies)
└── assets/                            # Resources (maps, images, sounds)
```

**Documentation:**
- **[docs/README.md](docs/README.md)** - Documentation index
- **[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)** - Complete structure
- **[docs/ENGINE_GUIDE.md](docs/ENGINE_GUIDE.md)** - Engine systems reference
- **[docs/GAME_GUIDE.md](docs/GAME_GUIDE.md)** - Content creation guide
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** - Development workflows

---

## 🎯 Key Systems

### Scene Management (`engine/scene_control.lua`)
```lua
scene_control.switch(scene, ...)  -- Switch to new scene
scene_control.push(scene, ...)    -- Push scene (like pause)
scene_control.pop()               -- Return to previous scene
```

### Input System (`engine/input/`)
Unified input across keyboard, mouse, gamepad, and touch:
```lua
input:wasPressed("action_name")   -- Check if action was pressed
input:isDown("action_name")       -- Check if action is held
```

**Config:** `game/data/input_config.lua`

### World System (`engine/world/`)
Physics & map loading (Windfield + STI):
```lua
world:new(mapPath)                -- Load Tiled map
world:addEntity(entity)           -- Add entity to world
world:update(dt)                  -- Update physics
```

**Game Modes:**
- **Topdown:** No gravity, free 2D movement
- **Platformer:** Gravity enabled, horizontal + jump

### Sound System (`engine/sound.lua`)
```lua
sound:playBGM(name, fade, rewind) -- Play background music
sound:playSFX(category, name)     -- Play sound effect
```

**Config:** `game/data/sounds.lua`

### Save/Load System (`engine/save.lua`)
```lua
save_sys:saveGame(slot, data)     -- Save to slot (1-3)
save_sys:loadGame(slot)           -- Load from slot
```

---

## 🎮 Game Content

### Scenes (`game/scenes/`)
Game screens (menus, gameplay). Complex scenes are modular:
```
game/scenes/play/
├── init.lua      - Scene coordinator
├── update.lua    - Game loop
├── render.lua    - Drawing
└── input.lua     - Input handling
```

### Entities (`game/entities/`)
Player, enemies, NPCs, weapons, items. Modular structure:
```
game/entities/player/
├── init.lua      - Main coordinator
├── animation.lua - Animation state machine
├── combat.lua    - Health, attack, parry, dodge
├── render.lua    - Drawing logic
└── sound.lua     - Sound effects
```

### Data (`game/data/`)
Configuration files:
- `input_config.lua` - Key mappings & controller settings
- `sounds.lua` - Sound asset definitions
- `intro_configs.lua` - Cutscene configurations

---

## 🗺️ Maps

**Location:** `assets/maps/levelX/`

**Format:** Tiled TMX files exported to Lua

**Required Map Properties:**
```
game_mode = "topdown"  (or "platformer")
bgm = "level1"         (optional - BGM name from sounds.lua)
```

**Required Layers:**
- Ground, Trees (terrain)
- Walls (collision)
- Portals (transitions)
- Enemies, NPCs
- SavePoints, HealingPoints
- DeathZones, DamageZones

**Portals:**
```
Object Properties:
  type = "portal"
  target_map = "assets/maps/level1/area2.lua"
  spawn_x = 100
  spawn_y = 200
```

---

## 💻 Development Workflows

### Adding Content

**New Enemy:**
1. Create sprite: `assets/images/enemies/yourenemy.png`
2. Create type: `game/entities/enemy/types/yourenemy.lua`
3. Place in Tiled: Object with `type = "yourenemy"`

**New Item:**
1. Create icon: `assets/images/items/youritem.png`
2. Create type: `game/entities/item/types/youritem.lua`
3. Add to inventory: `inventory:addItem("youritem", 1)`

**New Sound:**
1. Add file: `assets/bgm/yourmusic.ogg`
2. Register: `game/data/sounds.lua`
3. Play: `sound:playBGM("yourmusic")`

**New Map:**
1. Create in Tiled: `assets/maps/level1/newarea.tmx`
2. Set properties: `game_mode`, `bgm`
3. Export to Lua
4. Create portal from previous map

### Code Style

**Naming:**
```lua
local module_name = require "engine.module_name"  -- lowercase with underscores
function object:methodName() end                  -- camelCase
local CONSTANT_VALUE = 100                        -- UPPER_CASE
```

**Require Paths:**
```lua
-- Use dots, not slashes
require "engine.sound"        -- ✅ Correct
require "engine/sound"        -- ❌ Wrong

-- Engine systems
require "engine.scene_control"
require "engine.input"
require "engine.world"

-- Game content
require "game.scenes.menu"
require "game.entities.player"
require "game.data.sounds"
```

**File Organization:**
```lua
-- 1. Module declaration
local mymodule = {}

-- 2. Requires
local engine_system = require "engine.something"

-- 3. Local functions
local function _helper() end

-- 4. Public functions
function mymodule:publicMethod() end

-- 5. Return module
return mymodule
```

---

## 🎨 Combat System

**Attack:** Left click / A button
**Parry:** Right click / X button (perfect timing → slow-motion)
**Dodge:** Shift / R1 button (invincibility frames)
**Jump:** W/Up/Space / B button (platformer only)
**Interact:** F key / A button (near NPCs/SavePoints)

**Combat Feedback:**
- Camera shake on hits
- Slow-motion on perfect parry
- Vibration/haptics
- Hit particles

---

## 🔧 Engine Systems Reference

### Core
- `engine/scene_control.lua` - Scene stack management
- `engine/camera.lua` - Camera effects (shake, slow-motion)
- `engine/game_mode.lua` - Topdown vs Platformer

### Media
- `engine/sound.lua` - Audio (BGM, SFX)
- `engine/effects.lua` - Particle effects

### UI
- `engine/hud.lua` - Health bars, cooldowns
- `engine/minimap.lua` - Minimap rendering
- `engine/dialogue.lua` - NPC dialogues

### Data
- `engine/save.lua` - Save/Load system
- `engine/inventory.lua` - Item management

### Debug
- `engine/debug.lua` - Debug overlay (F1: toggle, F2: grid, F3: mouse)
- `engine/constants.lua` - Engine constants

### Subsystems
- `engine/input/` - Input system
- `engine/world/` - Physics & map loading
- `engine/utils/` - Utilities

---

## ⚠️ Important Rules

### Engine/Game Separation
- ✅ Engine files MUST NOT import game files
- ✅ Game files CAN import engine files
- ✅ Engine should be generic
- ✅ Game should be data-driven

### Code Quality
- Remove debug print statements in production
- Delete commented-out code (use git for history)
- Avoid code duplication
- Split files over 500 lines

### Require Paths
- Always use dots: `require "engine.sound"`
- Never use slashes: `require "engine/sound"`
- File paths use forward slashes: `"assets/maps/level1/area1.lua"`

### Coordinate Systems
- Tiled objects: Top-left origin
- Physics colliders: Center origin
- Sprites: Usually center origin

---

## 🐛 Common Pitfalls

**Collision classes:** Player changes to "PlayerDodging" during dodge

**Time scaling:** Use `camera_sys:get_scaled_dt(dt)` for scaled time

**Mobile input:** Check `virtual_gamepad` exists before using

**Game mode:** Always check `game_mode` for mode-specific logic

**Distance in platformer:** Use horizontal-only distance for AI

**Ground detection:** Use raycasts, not collision callbacks

**Shadow positioning:** Use `player.ground_y` in platformer mode

---

## 📚 External Libraries

- **STI** - Tiled map loader (`vendor/sti/`)
- **Windfield** - Box2D wrapper (`vendor/windfield/`)
- **anim8** - Sprite animation (`vendor/anim8/`)
- **hump** - Utilities (`vendor/hump/`)
- **Talkies** - Dialogue system (`vendor/talkies/`)

---

## 🎯 Quick Reference

**Read documentation:**
- Project structure → `docs/PROJECT_STRUCTURE.md`
- Engine systems → `docs/ENGINE_GUIDE.md`
- Content creation → `docs/GAME_GUIDE.md`
- Development → `docs/DEVELOPMENT.md`

**Add content:**
- Enemy → `game/entities/enemy/types/`
- Item → `game/entities/item/types/`
- Sound → `game/data/sounds.lua`
- Map → `assets/maps/`

**Engine systems:**
- Scene → `engine/scene_control.lua`
- Input → `engine/input/`
- Physics → `engine/world/`
- Audio → `engine/sound.lua`

---

**Last Updated:** 2025-11-06
**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Engine/Game Separation (RPG Maker style)
