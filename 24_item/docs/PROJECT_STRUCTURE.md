# Project Structure

Complete reference for the LÖVE2D game engine project structure.

---

## 📁 Root Directory

```
24_item/
├── main.lua              - Entry point (dependency injection)
├── conf.lua              - LÖVE configuration
├── startup.lua           - Initialization utilities
├── system.lua            - System-level handlers
├── locker.lua            - Process locking (desktop)
├── config.ini            - User settings
│
├── engine/               - 100% reusable game engine ⭐
├── game/                 - Game-specific content
├── vendor/               - External libraries
├── assets/               - Game resources
└── docs/                 - Documentation
```

---

## 🎮 Engine Folder

**Purpose:** 100% reusable game engine with layered architecture.

### Core Systems (`engine/core/`)

```
core/
├── lifecycle.lua         - Application lifecycle
├── scene_control.lua     - Scene stack management
├── camera.lua            - Camera effects (shake, slow-motion)
├── coords.lua            - Unified coordinate system
├── sound.lua             - Audio system (BGM, SFX)
├── save.lua              - Save/load system (slot-based)
├── inventory.lua         - Inventory system
├── debug.lua             - Debug overlay (F1-F6)
├── constants.lua         - Engine constants
│
├── display/
│   └── init.lua          - Virtual screen (scaling, letterboxing)
│
└── input/
    ├── dispatcher.lua    - Input event dispatcher
    ├── sources/          - Input sources (keyboard, mouse, gamepad)
    └── virtual_gamepad/  - Mobile touch controls
```

### Subsystems (`engine/systems/`)

```
systems/
├── collision.lua         - Collision system (dual collider for topdown)
│
├── world/                - Physics & map system
│   ├── init.lua          - World coordinator (Windfield + STI)
│   ├── loaders.lua       - Map loading (Tiled + entity factory)
│   ├── entities.lua      - Entity management ⭐ Persistence tracking!
│   └── rendering.lua     - Y-sorted rendering
│
├── effects/              - Visual effects
│   ├── particles/        - Particle effects
│   └── screen/           - Screen effects (flash, vignette)
│
├── lighting/             - Dynamic lighting system
│   ├── init.lua          - Lighting manager
│   └── source.lua        - Light source class
│
└── hud/                  - In-game HUD
    ├── status.lua        - Health bars, cooldowns
    └── minimap.lua       - Minimap rendering
```

### Entities (`engine/entities/`) ⭐

**ALL entities are 100% reusable! No game-specific code.**

```
entities/
├── factory.lua           - Creates entities from Tiled properties
│
├── player/               - Player system (config injected)
│   ├── init.lua          - Main coordinator
│   ├── animation.lua     - Animation state machine
│   ├── combat.lua        - Health, attack, parry, dodge
│   ├── render.lua        - Drawing logic
│   └── sound.lua         - Sound effects
│
├── enemy/                - Enemy system (type_registry injected)
│   ├── init.lua          - Enemy base class
│   ├── ai.lua            - AI state machine
│   ├── render.lua        - Drawing logic
│   ├── sound.lua         - Sound effects
│   ├── spawner.lua       - Spawning logic
│   └── factory.lua       - Creates from Tiled
│
├── weapon/               - Weapon system (config injected)
│   ├── init.lua          - Main coordinator
│   ├── combat.lua        - Hit detection, damage
│   ├── render.lua        - Drawing logic
│   └── config/           - Hand anchors, swing configs
│
├── npc/                  - NPC system
│   ├── init.lua          - NPC base class
│   └── types/            - NPC type definitions
│
├── item/                 - Item system
│   ├── init.lua          - Item base class
│   └── types/            - Item type definitions
│
├── world_item/           - Dropped item system ⭐ Persistence!
│   └── init.lua          - World item with respawn control
│
└── healing_point/        - Health restoration points
    └── init.lua          - Healing logic
```

**Persistence Properties:**
- `world_item` and `enemy` have `map_id` and `respawn` properties
- `map_id` format: `"{map_name}_obj_{object_id}"`
- `respawn = false` makes items/enemies one-time only
- Tracked in `picked_items` and `killed_enemies` tables

### Scenes (`engine/scenes/`)

```
scenes/
├── builder.lua           - Data-driven scene factory ⭐
├── cutscene.lua          - Cutscene/intro scene
└── gameplay/             - Main gameplay scene
    ├── init.lua          - Scene coordinator ⭐ Manages persistence!
    ├── update.lua        - Game loop
    ├── render.lua        - Drawing
    └── input.lua         - Input handling
```

**Persistence in gameplay/init.lua:**
- Loads `picked_items` and `killed_enemies` from save data
- Passes to `world:new()` for filtering
- Saves back to save file on save

### UI Systems (`engine/ui/`)

```
ui/
├── menu/                 - Menu UI system
│   ├── base.lua          - MenuSceneBase (base class)
│   └── helpers.lua       - Menu helpers (layout, navigation)
│
├── screens/              - Reusable UI screens
│   ├── newgame.lua       - New game slot selection
│   ├── saveslot.lua      - Save game screen
│   ├── load.lua          - Load game screen
│   ├── inventory.lua     - Inventory UI
│   └── settings.lua      - Settings screen
│
├── dialogue.lua          - NPC dialogue (Talkies wrapper)
├── prompt.lua            - Interaction prompts (dynamic button icons)
├── shapes.lua            - Shape rendering (buttons, dialogs)
└── widgets/              - Reusable widgets
    ├── skip_button.lua   - Skip button (0.5s hold charge)
    └── next_button.lua   - Next button
```

### Utilities (`engine/utils/`)

```
utils/
├── util.lua              - General utilities
├── text.lua              - Text rendering wrapper
├── fonts.lua             - Font management
├── restart.lua           - Game restart logic
├── convert.lua           - Data conversion
└── ini.lua               - INI file parser
```

---

## 🕹️ Game Folder

**Purpose:** Game-specific content (data-driven, minimal code).

**Key:** `game/entities/` folder **DELETED!** All entities in `engine/entities/`!

```
game/
├── scenes/               - Game screens
│   ├── menu.lua          - Main menu (6 lines!) ⭐
│   ├── pause.lua         - Pause menu (6 lines!) ⭐
│   ├── gameover.lua      - Game over (6 lines!) ⭐
│   ├── ending.lua        - Ending screen (6 lines!) ⭐
│   │
│   ├── play/             - Gameplay scene (modular)
│   ├── settings/         - Settings menu (modular)
│   ├── load/             - Load game scene (modular)
│   └── inventory/        - Inventory overlay (modular)
│
└── data/                 - Configuration files ⭐
    ├── player.lua        - Player stats (injected into engine)
    ├── entities/
    │   └── types.lua     - Enemy types (injected into engine)
    ├── scenes.lua        - Menu configs (used by builder)
    ├── sounds.lua        - Sound definitions
    ├── input_config.lua  - Input mappings
    └── intro_configs.lua - Cutscene configs
```

**Data-Driven Menu Example:**
```lua
-- game/scenes/menu.lua (6 lines!)
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("menu", configs)
```

**Dependency Injection (main.lua):**
```lua
-- Inject game configs into engine
local player_module = require "engine.entities.player"
local enemy_module = require "engine.entities.enemy"
local weapon_module = require "engine.entities.weapon"

local player_config = require "game.data.player"
local entity_types = require "game.data.entities.types"

player_module.config = player_config
enemy_module.type_registry = entity_types.enemies
weapon_module.type_registry = entity_types.weapons
```

---

## 🗺️ Assets Folder

```
assets/
├── maps/                 - Tiled maps (TMX + Lua export)
│   ├── level1/
│   │   ├── area1.tmx     - Tiled source ⭐ Set respawn=false here!
│   │   ├── area1.lua     - Lua export
│   │   ├── area2.tmx
│   │   └── area2.lua
│   └── level2/
│       └── area1.tmx
│
├── images/               - Sprites, tilesets
│   ├── player/
│   ├── enemies/
│   ├── items/
│   └── tilesets/
│
├── sounds/               - Sound effects
│   ├── combat/
│   ├── ui/
│   └── ambient/
│
├── bgm/                  - Background music
│
└── fonts/                - Font files
```

**Map Requirements for Persistence:**
```
Map Properties:
  name = "level1_area1"    ← REQUIRED for persistence!
  game_mode = "topdown"    (or "platformer")
  bgm = "level1"           (optional)
  ambient = "day"          (optional)

WorldItems Object Properties:
  item_type = "sword"
  quantity = 1
  respawn = false          ← One-time pickup!

Enemies Object Properties:
  type = "boss_slime"
  respawn = false          ← One-time kill!
```

---

## 📦 Vendor Folder

External libraries (100% unmodified):

```
vendor/
├── anim8/                - Sprite animation
├── hump/                 - Utilities (camera, timer, vector)
├── sti/                  - Tiled map loader
├── windfield/            - Box2D wrapper (physics)
└── talkies/              - Dialogue system
```

---

## 💾 Persistence System

**NEW!** One-time items and enemies persist across maps and save/load.

### Save Data Structure

```lua
save_data = {
  hp = 100,
  max_hp = 100,
  map = "assets/maps/level1/area1.lua",
  x = 500,
  y = 300,
  inventory = {...},

  -- Persistence tracking ⭐
  picked_items = {
    ["level1_area1_obj_46"] = true,  -- Staff picked up
    ["level1_area2_obj_12"] = true,  -- Potion picked up
  },
  killed_enemies = {
    ["level1_area1_obj_40"] = true,  -- Boss slime killed
    ["level2_area1_obj_8"] = true,   -- Mini-boss killed
  }
}
```

### Map ID Generation

Format: `"{map_name}_obj_{object_id}"`

Examples:
- `"level1_area1_obj_46"` - Item with id=46 in level1_area1
- `"level2_area3_obj_120"` - Enemy with id=120 in level2_area3

### Workflow

1. **Map Load** (`engine/systems/world/loaders.lua`):
   - Check `picked_items` / `killed_enemies` tables
   - Skip spawning if `respawn = false` and already picked/killed

2. **Pickup/Kill** (`engine/scenes/gameplay/input.lua`, `engine/systems/world/entities.lua`):
   - Add `map_id` to `picked_items` / `killed_enemies` table
   - Only for items/enemies with `respawn = false`

3. **Save** (`engine/scenes/gameplay/init.lua:saveGame()`):
   - Save `picked_items` and `killed_enemies` to save file

4. **Load** (`engine/scenes/gameplay/init.lua:enter()`):
   - Load `picked_items` and `killed_enemies` from save file
   - Pass to `world:new()` for filtering

---

## 📊 Code Statistics

**Before Refactoring:**
- Game folder: 7,649 lines (48 files)
- Entities in game/entities/

**After Refactoring:**
- Game folder: 4,174 lines (23 files) ✅ **-45% reduction**
- All entities in engine/entities/ ✅ **100% reusable**
- Menu scenes: 358 → 24 lines ✅ **-93% reduction**

**New Game Creation:**
- Copy `engine/` (100% reusable)
- Create `game/data/` (~600 lines of config)
- Create `game/scenes/` (~2,400 lines of logic)
- Total: ~3,000 lines vs original 7,649 lines ✅ **61% less code**

---

## 🎯 Key Files Reference

**Entry Points:**
- `main.lua` - Dependency injection, LÖVE callbacks
- `conf.lua` - LÖVE configuration
- `startup.lua` - Initialization (error handler, platform detection)

**Engine Core:**
- `engine/core/lifecycle.lua` - Main game loop orchestrator
- `engine/core/scene_control.lua` - Scene management
- `engine/systems/world/init.lua` - Physics & map system
- `engine/scenes/gameplay/init.lua` - Main gameplay scene ⭐ Persistence!

**Entity System:**
- `engine/entities/factory.lua` - Creates entities from Tiled
- `engine/entities/world_item/init.lua` - Dropped items ⭐ Respawn control!
- `engine/entities/enemy/init.lua` - Enemy base class ⭐ Respawn control!

**Game Config:**
- `game/data/player.lua` - Player stats (injected)
- `game/data/entities/types.lua` - Enemy types (injected)
- `game/data/scenes.lua` - Menu configs (data-driven)

**Map Files:**
- `assets/maps/level1/area1.tmx` - Tiled source ⭐ Set respawn here!
- `assets/maps/level1/area1.lua` - Lua export

---

**Last Updated:** 2025-11-13
**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Engine/Game Separation + Dependency Injection + Data-Driven + Persistence
