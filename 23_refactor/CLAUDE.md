# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 📁 Project Overview

This is a **LÖVE2D game project** (version 11.5) written in Lua. It's a 2D action RPG with **Engine/Game separation architecture**.

### Architecture Philosophy
- **`engine/`** - Reusable game systems (can be used in any LÖVE2D project)
- **`game/`** - Game-specific content (scenes, entities, data)
- **`assets/`** - Game resources (maps, images, sounds)

**Goal:** Create new games by copying `engine/` and creating new `game/` content.

### ⭐ Engine/Game Architecture (REFACTORED!)

**All Entities in Engine** (100% Reusable)
- `engine/entities/player/` - Complete player system with dependency injection
- `engine/entities/enemy/` - Enemy AI with factory-based creation
- `engine/entities/weapon/` - Weapon combat system with config injection
- `engine/entities/npc/` - NPC interaction system
- `engine/entities/item/` - Item management
- `engine/entities/healing_point/` - Health restoration points
- `engine/entities/factory.lua` - Creates entities from Tiled properties

**Data-Driven Configuration**
- `game/data/player.lua` - Player stats/abilities (61 lines)
- `game/data/scenes.lua` - Menu definitions (140 lines, includes flash effects)
- `game/data/entity_types.lua` - Enemy type configs (NEW!)
- `engine/scenes/builder.lua` - Menu scene generator

**Dependency Injection** (NEW!)
- `main.lua` injects game configs into engine classes
- Player: `player_module.config = player_config`
- Weapon: `weapon_module.type_registry`, `weapon_module.effects_config`
- Enemy: `enemy_module.type_registry = enemy_types`

**Result:** `game/entities/` folder completely removed!

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
23_refactor/
├── main.lua, conf.lua, locker.lua    # Entry points (main.lua injects game configs)
├── engine/                            # Reusable systems ⭐
│   ├── core/                          # Core engine systems
│   │   ├── lifecycle.lua              # Application lifecycle (init, update, draw, resize, quit)
│   │   ├── scene_control.lua          # Scene stack management
│   │   ├── camera.lua                 # Camera effects (shake, slow-motion)
│   │   ├── sound.lua                  # Audio system (BGM, SFX)
│   │   ├── save.lua                   # Save/load system
│   │   ├── inventory.lua              # Item management
│   │   ├── debug.lua                  # Debug overlay
│   │   ├── constants.lua              # Engine constants
│   │   ├── coords.lua                 # Unified coordinate transformations
│   │   ├── display/                   # Virtual screen system (scaling, letterboxing)
│   │   └── input/                     # Input system (keyboard, gamepad, touch)
│   │       ├── dispatcher.lua         # Input event dispatcher
│   │       ├── sources/               # Input source modules
│   │       └── virtual_gamepad.lua    # Mobile virtual controls
│   ├── systems/                       # Game subsystems
│   │   ├── world/                     # Physics & map loading (Windfield/STI)
│   │   ├── effects/                   # Visual effects (particles, screen effects)
│   │   ├── lighting/                  # Dynamic lighting system (GLSL shaders)
│   │   └── hud/                       # In-game HUD (status bars, minimap)
│   ├── scenes/                        # Scene builders
│   │   ├── builder.lua                # Data-driven scene factory
│   │   ├── cutscene.lua               # Cutscene/intro scene
│   │   └── gameplay.lua               # Main gameplay scene
│   ├── entities/                      # Reusable entities (100% engine!)
│   │   ├── player/                    # Player system (animation, combat, rendering)
│   │   ├── enemy/                     # Enemy AI (factory-based)
│   │   ├── weapon/                    # Weapon combat system
│   │   ├── npc/                       # NPC interaction
│   │   ├── item/                      # Item system
│   │   ├── healing_point/             # Health restoration points
│   │   └── factory.lua                # Entity factory (Tiled → entities)
│   ├── ui/                            # UI systems
│   │   ├── menu/                      # Menu UI system
│   │   │   ├── base.lua               # Base menu scene class (MenuSceneBase)
│   │   │   └── helpers.lua            # Menu UI helpers (layout, navigation, dialogs)
│   │   ├── screens/                   # Reusable UI screens
│   │   │   ├── newgame.lua            # New game slot selection
│   │   │   ├── saveslot.lua           # Save game screen
│   │   │   ├── load.lua               # Load game screen
│   │   │   ├── inventory.lua          # Inventory UI
│   │   │   └── settings.lua           # Settings screen
│   │   ├── dialogue.lua               # NPC dialogue system (Talkies wrapper)
│   │   ├── shapes.lua                 # Shape rendering utilities
│   │   └── widgets/                   # Reusable UI widgets
│   │       ├── skip_button.lua        # Skip button (0.5s hold charge)
│   │       └── next_button.lua        # Next button for dialogue
│   └── utils/                         # Engine utilities
│       ├── fonts.lua                  # Font management
│       ├── text.lua                   # Text rendering utilities
│       ├── util.lua                   # General utilities
│       ├── convert.lua                # Data conversion helpers
│       ├── ini.lua                    # INI file parser
│       └── restart.lua                # Game restart utilities
├── game/                              # Game content ⭐
│   ├── scenes/                        # Game-specific scenes
│   │   ├── menu.lua                   # Main menu (6 lines, data-driven!)
│   │   ├── pause.lua                  # Pause menu (6 lines, data-driven!)
│   │   ├── gameover.lua               # Game over (6 lines, data-driven!)
│   │   ├── ending.lua                 # Ending screen (6 lines, data-driven!)
│   │   └── (no entities folder!)      # DELETED - all entities in engine!
│   └── data/                          # Configuration files
│       ├── player.lua                 # Player stats/abilities (injected into engine)
│       ├── scenes.lua                 # Menu configurations (with flash effects!)
│       ├── entity_types.lua           # Enemy type configs
│       ├── sounds.lua                 # Sound asset definitions
│       ├── input_config.lua           # Key mappings & controller settings
│       └── intro_configs.lua          # Cutscene configurations
├── vendor/                            # External libraries (STI, Windfield, anim8, hump, Talkies)
└── assets/                            # Resources (maps, images, sounds)
```

**Documentation:**
- **[docs/README.md](docs/README.md)** - Quick start guide
- **[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)** - Complete structure reference
- **[docs/GUIDE.md](docs/GUIDE.md)** - Comprehensive guide (Engine + Game + Development)

---

## 🎯 Key Systems

### Scene Management (`engine/core/scene_control.lua`)
```lua
scene_control.switch(scene, ...)  -- Switch to new scene
scene_control.push(scene, ...)    -- Push scene (like pause)
scene_control.pop()               -- Return to previous scene
```

### Input System (`engine/core/input/`)
Unified input across keyboard, mouse, gamepad, and touch:
```lua
input:wasPressed("action_name")   -- Check if action was pressed
input:isDown("action_name")       -- Check if action is held
```

**Config:** `game/data/input_config.lua`

### World System (`engine/systems/world/`)
Physics & map loading (Windfield + STI):
```lua
world:new(mapPath)                -- Load Tiled map
world:addEntity(entity)           -- Add entity to world
world:update(dt)                  -- Update physics
```

**Game Modes:**
- **Topdown:** No gravity, free 2D movement
- **Platformer:** Gravity enabled, horizontal + jump

### Sound System (`engine/core/sound.lua`)
```lua
sound:playBGM(name, fade, rewind) -- Play background music
sound:playSFX(category, name)     -- Play sound effect
```

**Config:** `game/data/sounds.lua`

### Save/Load System (`engine/core/save.lua`)
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

### Entities (`engine/entities/`) ⭐ MOVED TO ENGINE!
**All entities now 100% reusable!** Configured via dependency injection in `main.lua`:
```
engine/entities/player/
├── init.lua      - Main coordinator
├── animation.lua - Animation state machine
├── combat.lua    - Health, attack, parry, dodge
├── render.lua    - Drawing logic
└── sound.lua     - Sound effects

engine/entities/enemy/
├── init.lua      - Enemy base class
├── ai.lua        - AI behaviors
├── render.lua    - Rendering
├── sound.lua     - Sound effects
└── factory.lua   - Creates enemies from Tiled

engine/entities/weapon/
├── init.lua      - Weapon system
├── combat.lua    - Hit detection, damage
├── render.lua    - Drawing
└── config/       - Hand anchors, swing configs
```

**Dependency Injection Example:**
```lua
-- main.lua
local player_module = require "engine.entities.player"
local player_config = require "game.data.player"
player_module.config = player_config  -- Inject game-specific config!
```

### Data (`game/data/`)
Configuration files (injected into engine):
- `player.lua` - Player stats/abilities (injected into engine.entities.player)
- `entity_types.lua` - Enemy type configs (injected into engine.entities.enemy)
- `scenes.lua` - Menu configurations (includes flash effects)
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
ambient = "day"        (optional - lighting: day, night, dusk, cave, indoor, underground)
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

**New Enemy:** ⭐ Data-driven (No code!)
1. Create sprite: `assets/images/enemies/yourenemy.png`
2. Place in Tiled: Object with `type = "yourenemy"`
3. Add custom properties: `hp`, `dmg`, `spd`, `spr`, etc. (see `engine/entities/factory.lua` DEFAULTS)

**New NPC:** ⭐ Data-driven (No code!)
1. Create sprite: `assets/images/yournpc.png`
2. Place in Tiled: "NPCs" layer, set `type = "yournpc"`
3. Add properties: `name`, `dlg` (semicolon-separated), `spr`, etc.

**New Menu Scene:** ⭐ Data-driven (No code!)
1. Add to `game/data/scenes.lua`:
```lua
scenes.mymenu = {
  type = "menu",
  title = "My Menu",
  options = {"Option1", "Option2"},
  actions = {
    ["Option1"] = {action = "switch_scene", scene = "play"},
    ["Option2"] = {action = "quit"}
  },
  back_action = {action = "quit"},

  -- Optional: Flash effect (like gameover/ending)
  flash = {
    enabled = true,
    color = {1, 0, 0},      -- RGB color
    initial_alpha = 1.0,
    fade_speed = 2.0
  },

  -- Optional: Overlay (like pause/gameover)
  overlay = true,
  overlay_alpha = 0.7
}
```
2. Create file `game/scenes/mymenu.lua`:
```lua
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("mymenu", configs)
```

**New Item:**
1. Create icon: `assets/images/items/youritem.png`
2. Create type: `engine/entities/item/types/youritem.lua` (in engine, not game!)
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
require "engine.core.sound"        -- ✅ Correct
require "engine/core/sound"        -- ❌ Wrong

-- Engine core systems
require "engine.core.scene_control"
require "engine.core.input.dispatcher"
require "engine.core.lifecycle"
require "engine.core.camera"
require "engine.core.sound"

-- Engine subsystems
require "engine.systems.world"
require "engine.systems.effects"
require "engine.systems.lighting"

-- Engine entities
require "engine.entities.player"
require "engine.entities.enemy"

-- Engine scenes & UI
require "engine.scenes.builder"
require "engine.ui.menu.base"

-- Game content
require "game.scenes.menu"
require "game.data.player"
require "game.data.scenes"
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

### Core Systems (`engine/core/`)
- `lifecycle.lua` - Application lifecycle (init, update, draw, resize, quit)
- `scene_control.lua` - Scene stack management (switch, push, pop)
- `camera.lua` - Camera effects (shake, slow-motion)
- `sound.lua` - Audio system (BGM, SFX)
- `save.lua` - Save/load system
- `inventory.lua` - Item management
- `debug.lua` - Debug overlay (F1: toggle, F2: grid, F3: mouse, H: hand marking)
- `constants.lua` - Engine constants
- `coords.lua` - **Unified coordinate transformations** (World, Camera, Virtual, Physical)
- `display/` - Virtual screen system (scaling, letterboxing, coordinate transform)
- `input/` - Input system (keyboard, mouse, gamepad, touch)
  - `dispatcher.lua` - Input event dispatcher
  - `sources/` - Input source modules
  - `virtual_gamepad.lua` - Mobile virtual controls

### Subsystems (`engine/systems/`)
- `world/` - Physics & map loading (Windfield, STI)
  - `init.lua`, `loaders.lua`, `entities.lua`, `rendering.lua`
- `effects/` - Visual effects
  - `particles/` - Particle systems (blood, hit sparks, etc.)
  - `screen/` - Screen effects (flash, vignette, fade)
- `lighting/` - Dynamic lighting system
  - Point lights, spotlights, ambient lighting
  - GLSL shaders for real-time lighting
- `hud/` - In-game HUD
  - `status.lua` - Health bars, cooldowns, status indicators
  - `minimap.lua` - Minimap rendering

### Scene Management (`engine/scenes/`)
- `builder.lua` - **Data-driven scene factory** (builds menus from game/data/scenes.lua)
- `cutscene.lua` - Cutscene/intro scene (dialogue sequences)
- `gameplay.lua` - Main gameplay scene (world, entities, combat)

### Entities (`engine/entities/`) ⭐ 100% Reusable!
- `player/` - Player system (animation, combat, rendering, sound)
- `enemy/` - Enemy AI system
  - `init.lua`, `ai.lua`, `render.lua`, `sound.lua`
  - `factory.lua` - Creates enemies from Tiled properties
- `weapon/` - Weapon combat system
  - `init.lua`, `combat.lua`, `render.lua`
  - `config/` - Hand anchors, swing configs, handle anchors
- `npc/` - NPC interaction system
- `item/` - Item system
- `healing_point/` - Health restoration points
- `factory.lua` - **Entity factory** (creates entities from Tiled map data)

### UI Systems (`engine/ui/`)
- `menu/` - Menu UI system
  - `base.lua` - **MenuSceneBase** (base class for all menus)
  - `helpers.lua` - Menu UI helpers (layout, navigation, dialogs, touch input)
- `screens/` - Reusable UI screens
  - `newgame.lua` - New game slot selection
  - `saveslot.lua` - Save game screen
  - `load.lua` - Load game screen
  - `inventory.lua` - Inventory UI
  - `settings.lua` - Settings screen
- `dialogue.lua` - NPC dialogue system (Talkies wrapper with skip/next buttons)
- `shapes.lua` - Shape rendering utilities (buttons, overlays)
- `widgets/` - Reusable UI widgets
  - `skip_button.lua` - Skip button with charge system (0.5s hold)
  - `next_button.lua` - Next button for advancing dialogue

### Utilities (`engine/utils/`)
- `fonts.lua` - Font management
- `text.lua` - **Text rendering utilities** (centralized print wrapper)
- `util.lua` - General utilities
- `convert.lua` - Data conversion helpers
- `ini.lua` - INI file parser
- `restart.lua` - Game restart utilities

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
**IMPORTANT: Always use `engine/core/coords.lua` for coordinate transformations**

```lua
local coords = require "engine.core.coords"

-- World ↔ Camera (for rendering entities)
local cam_x, cam_y = coords:worldToCamera(world_x, world_y, camera)
local world_x, world_y = coords:cameraToWorld(cam_x, cam_y, camera)

-- Physical ↔ Virtual (for UI, touch input)
local vx, vy = coords:physicalToVirtual(touch_x, touch_y, display)
local px, py = coords:virtualToPhysical(vx, vy, display)
```

**Never use these directly:**
- ❌ `camera:cameraCoords()` / `camera:worldCoords()`
- ❌ `display:ToVirtualCoords()` / `display:ToScreenCoords()`

**Coordinate Origins:**
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
- Quick start → `docs/README.md`
- Project structure → `docs/PROJECT_STRUCTURE.md`
- Complete guide → `docs/GUIDE.md`

**Add content:**
- Enemy → Add to Tiled map with properties (see `engine/entities/factory.lua`)
- Item → `engine/entities/item/types/` (in engine!)
- Sound → `game/data/sounds.lua`
- Map → `assets/maps/` (set `ambient` property for lighting)
- Menu → `game/data/scenes.lua` (data-driven!)

**Engine core systems:**
- Lifecycle → `engine/core/lifecycle.lua`
- Scene → `engine/core/scene_control.lua`, `engine/scenes/builder.lua`
- Display → `engine/core/display/`
- **Coordinates → `engine/core/coords.lua`** (unified coordinate system)
- Input → `engine/core/input/`
- Audio → `engine/core/sound.lua`
- Save → `engine/core/save.lua`

**Engine subsystems:**
- Physics → `engine/systems/world/`
- Lighting → `engine/systems/lighting/`
- Effects → `engine/systems/effects/`
- HUD → `engine/systems/hud/` (status, minimap)

**Engine entities:**
- **Entities → `engine/entities/`** (player, enemy, weapon, npc, item)
- **Factory → `engine/entities/factory.lua`** (creates entities from Tiled)

**Engine UI:**
- Menu → `engine/ui/menu/` (base, helpers)
- Screens → `engine/ui/screens/` (newgame, load, inventory, settings)
- Dialogue → `engine/ui/dialogue.lua`

---

---

## 📊 Progress Summary (23_refactor)

### Completed ✅
- ✅ **All Entities moved to engine/** (Player, Enemy, Weapon, NPC, Item, HealingPoint)
- ✅ Entity factory for Tiled-based creation (`engine/entities/factory.lua`)
- ✅ Menu scenes data-driven (`engine/scenes/builder.lua`)
- ✅ Player config data-driven (`game/data/player.lua`)
- ✅ Dependency injection pattern (main.lua injects game configs into engine)
- ✅ Flash effects for menus (gameover, ending)
- ✅ Folder structure organized with proper layers:
  - `engine/core/` - Core systems
  - `engine/systems/` - Subsystems (world, effects, lighting, hud)
  - `engine/scenes/` - Scene builders
  - `engine/entities/` - Reusable entities
  - `engine/ui/` - UI systems (menu, screens, dialogue)
  - `engine/utils/` - Utilities

### Results 📊

**Entity Code Migration:**
- ✅ `game/entities/` → **DELETED** (0 lines)
- ✅ `engine/entities/player/` (898 lines - reusable)
- ✅ `engine/entities/enemy/` (576 lines - reusable)
- ✅ `engine/entities/weapon/` (566 lines - reusable)
- ✅ `engine/entities/npc/` (190 lines - reusable)
- ✅ `engine/entities/item/` (62 lines - reusable)
- ✅ `engine/entities/healing_point/` (60 lines - reusable)
- ✅ `engine/entities/factory.lua` (150 lines - entity creation from Tiled)
- ✅ Total: **2,502 lines moved to engine** (100% reusable!)

**Scene Code Reduction (Data-Driven):**
- menu.lua: 103 → 6 lines (-94%)
- pause.lua: 119 → 6 lines (-95%)
- gameover.lua: 136 → 6 lines (-96%)
- ending.lua: NEW → 6 lines (data-driven!)
- **Total scenes:** 358 → 24 lines (-93%)
- **Scene configs:** `game/data/scenes.lua` (140 lines, includes flash effects!)

**Game Folder Summary:**
```
Before: 7,649 lines (48 files)
After:  4,174 lines (23 files)
Reduction: -3,475 lines (-45%)
```

**What's left in game/:**
- `scenes/` (~3,200 lines) - Game-specific logic
  - play/, settings/, inventory/, load/ (complex UI scenes)
  - menu.lua, pause.lua, gameover.lua, ending.lua (6 lines each - data-driven!)
- `data/` (~600 lines) - Configuration only
  - player.lua (61 lines) - Player stats (injected into engine)
  - entity_types.lua (70 lines) - Enemy configs (NEW!)
  - scenes.lua (140 lines) - Menu configs (includes flash effects!)
  - sounds.lua (82 lines) - Sound assets
  - input_config.lua (194 lines) - Input mappings
  - intro_configs.lua (75 lines) - Cutscene data

### Architecture Achievement 🏆
**New Game Creation:**
```
1. Copy engine/ (100% reusable - includes ALL entities!)
2. Create main.lua with dependency injection:
   - Inject game/data/player.lua into engine.entities.player
   - Inject game/data/entity_types.lua into engine.entities.enemy
   - Inject weapon configs into engine.entities.weapon
3. Create minimal game/:
   - data/player.lua        (61 lines - player stats)
   - data/entity_types.lua  (70 lines - enemy configs)
   - data/scenes.lua        (140 lines - menu configs + flash effects)
   - data/sounds.lua        (82 lines - sound assets)
   - data/input_config.lua  (194 lines - input mappings)
   - scenes/menu.lua        (6 lines - data-driven!)
   - scenes/pause.lua       (6 lines - data-driven!)
   - scenes/gameover.lua    (6 lines - data-driven!)
   - scenes/ending.lua      (6 lines - data-driven!)
   - scenes/play/           (~1,200 lines - gameplay logic)
   - scenes/settings/       (~700 lines - settings UI)
   - scenes/inventory/      (~400 lines - inventory UI)
   - scenes/load/           (~400 lines - save/load UI)
4. Create Tiled maps (enemies/NPCs via properties - no code!)
5. Add assets (sprites, sounds)

Total new game code: ~3,271 lines (vs 7,649 original = 57% reduction)
With engine: ~15,000 lines total (100% reusable framework!)
```

### Key Achievements 🏆
- **100% entity reusability** - All entities in engine with dependency injection
- **Data-driven menus** - 4 menu scenes reduced to 24 lines total (93% reduction)
- **Data-driven enemies** - Create enemies in Tiled with properties (no code!)
- **Proper layering** - engine/core/, engine/systems/, engine/entities/, engine/ui/
- **Flash effects** - Configurable screen flashes for dramatic scenes
- **Dependency injection** - Game configs injected via main.lua

### 🧪 Testing & New Game Creation

**1. Test Custom Enemy (No Code!):**
- Open Tiled: `assets/maps/level1/area1.tmx`
- Add enemy object, set type: `boss_slime`
- Add properties: `hp=500, dmg=30, spd=80, det_rng=400`
- Export to Lua, run `love .`

**2. Create New Game:**
```bash
# Step 1: Copy engine
cp -r 23_refactor/engine/ my-new-game/engine/

# Step 2: Create minimal game/
mkdir -p my-new-game/game/data
mkdir -p my-new-game/game/scenes

# Step 3: Copy data templates
cp 23_refactor/game/data/player.lua my-new-game/game/data/
cp 23_refactor/game/data/scenes.lua my-new-game/game/data/
cp 23_refactor/game/data/sounds.lua my-new-game/game/data/
cp 23_refactor/game/data/input_config.lua my-new-game/game/data/

# Step 4: Copy scene templates (optional - customize as needed)
cp -r 23_refactor/game/scenes/play/ my-new-game/game/scenes/
cp -r 23_refactor/game/scenes/settings/ my-new-game/game/scenes/
# ... other scenes

# Step 5: Modify configs
# Edit game/data/player.lua (player stats)
# Edit game/data/scenes.lua (menus)
# Edit game/data/sounds.lua (audio assets)

# Step 6: Create Tiled maps + add assets
# Total code: ~3,000 lines (vs 7,649 = 61% less!)
```

**What to customize for new game:**
- `main.lua` - Dependency injection (inject game configs into engine)
- `game/data/player.lua` - Player abilities/stats (injected into engine.entities.player)
- `game/data/entity_types.lua` - Enemy types (injected into engine.entities.enemy)
- `game/data/scenes.lua` - Menu text/options/flash effects
- `game/data/sounds.lua` - Audio file paths
- Tiled maps - Level design, enemy placement (data-driven via properties!)
- Assets - Sprites, sounds, music

**Last Updated:** 2025-11-09
**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Engine/Game Separation + Dependency Injection + Data-Driven Entities
