# Project Structure

Complete reference for folder organization.

---

## Root Directory

```
29_indoor/
├── main.lua              - Entry point (dependency injection)
├── conf.lua              - LÖVE configuration
├── startup.lua           - Initialization utilities
├── system.lua            - System handlers
├── config.ini            - User settings
│
├── engine/               - 100% reusable game engine
├── game/                 - Game-specific content
├── vendor/               - External libraries
├── assets/               - Game resources
└── docs/                 - Documentation
```

---

## Engine Folder

### Core Systems (`engine/core/`)

```
core/
├── lifecycle.lua         - Application lifecycle
├── scene_control.lua     - Scene stack management
├── camera.lua            - Camera effects (shake, slow-motion)
├── coords.lua            - Unified coordinate transformations
├── sound.lua             - Audio system
├── save.lua              - Save/load (slot-based)
├── quest.lua             - Quest system (5 types)
├── level.lua             - Level/EXP system
├── debug.lua             - Debug overlay
├── display/              - Virtual screen (scaling, letterboxing)
└── input/                - Input dispatcher + sources
```

### Subsystems (`engine/systems/`)

```
systems/
├── collision.lua         - Collision (dual collider for topdown)
├── inventory.lua         - Inventory system
├── entity_factory.lua    - Creates entities from Tiled
├── prompt.lua            - Interaction prompts (dynamic icons)
├── loot.lua              - Random loot drops
│
├── world/                - Physics & map
│   ├── init.lua          - World coordinator
│   ├── loaders.lua       - Map loading + entity factory
│   ├── entities.lua      - Entity management + persistence
│   └── rendering.lua     - Y-sorted rendering
│
├── effects/              - Visual effects (particles, screen)
├── lighting/             - Dynamic lighting
├── parallax/             - Parallax backgrounds
├── weather/              - Weather system (rain, snow, fog, storm)
│
└── hud/                  - In-game HUD
    ├── status.lua        - Health bars, cooldowns
    ├── minimap.lua       - Minimap (with parallax!)
    ├── quickslots.lua    - Quickslot belt
    └── quest_tracker.lua - Quest HUD (3 active quests)
```

### Entities (`engine/entities/`)

**ALL entities 100% reusable!**

```
entities/
├── player/               - Player system (config injected)
│   ├── init.lua          - Coordinator
│   ├── animation.lua     - Animation state machine
│   ├── combat.lua        - Health, attack, parry, dodge
│   ├── render.lua        - Drawing
│   └── sound.lua         - Sound effects
│
├── enemy/                - Enemy system (type_registry injected)
│   ├── init.lua          - Base class
│   ├── ai.lua            - AI state machine
│   └── render.lua        - Drawing
│
├── weapon/               - Weapon system (config injected)
│   ├── init.lua          - Coordinator
│   ├── combat.lua        - Hit detection, damage
│   └── render.lua        - Drawing
│
├── npc/                  - NPC system
├── item/                 - Item system
├── world_item/           - Dropped items (respawn control)
└── healing_point/        - Health restoration
```

### Scenes (`engine/scenes/`)

```
scenes/
├── builder.lua           - Data-driven scene factory
├── cutscene.lua          - Cutscene/intro
└── gameplay/             - Main gameplay (modular)
    ├── init.lua          - Coordinator
    ├── scene_setup.lua   - Initialization
    ├── save_manager.lua  - Save/load
    ├── update.lua        - Game loop
    ├── render.lua        - Drawing
    └── input.lua         - Input handling
```

### UI Systems (`engine/ui/`)

```
ui/
├── menu/                 - Menu base + helpers
├── screens/              - Reusable screens
│   ├── container.lua     - Tabbed container (inventory + quest log)
│   ├── newgame.lua       - New game slots
│   ├── saveslot.lua      - Save screen
│   ├── load/             - Load screen (modular)
│   ├── inventory/        - Inventory UI (modular)
│   ├── questlog/         - Quest log UI (modular)
│   └── settings/         - Settings (modular)
│
├── dialogue/             - Dialogue system (modular)
│   ├── init.lua          - Main API
│   ├── core.lua          - Core logic (tree, state, input)
│   ├── render.lua        - Rendering
│   └── helpers.lua       - Helpers
│
└── widgets/              - Reusable widgets
    └── button/           - Skip/Next buttons
```

### Utilities (`engine/utils/`)

```
utils/
├── util.lua              - General utilities
├── text.lua              - Text rendering
├── fonts.lua             - Font management
├── shapes.lua            - Shape rendering
├── colors.lua            - Centralized color system
├── helpers.lua           - Helper functions
└── button_icons.lua      - PlayStation/Xbox button icons
```

---

## Game Folder

**`game/entities/` folder DELETED!** All entities in `engine/`.

```
game/
├── scenes/               - Game screens
│   ├── menu.lua          - Main menu (6 lines!)
│   ├── pause.lua         - Pause menu (6 lines!)
│   ├── gameover.lua      - Game over (6 lines!)
│   ├── ending.lua        - Ending (6 lines!)
│   │
│   ├── play/             - Gameplay scene (modular)
│   ├── settings/         - Settings menu (modular)
│   ├── load/             - Load game scene (modular)
│   └── inventory/        - Inventory overlay (modular)
│
└── data/                 - Configuration files
    ├── player.lua        - Player stats (injected)
    ├── entities/
    │   └── types.lua     - Enemy types (injected)
    ├── scenes.lua        - Menu configs
    ├── sounds.lua        - Sound definitions
    ├── input_config.lua  - Input mappings
    ├── quests.lua        - Quest definitions
    └── dialogues.lua     - NPC dialogue trees
```

**Dependency Injection (main.lua):**
```lua
local player_module = require "engine.entities.player"
local player_config = require "game.data.player"
player_module.config = player_config  -- Inject game config
```

---

## Assets Folder

```
assets/
├── maps/                 - Tiled maps (TMX + Lua export)
│   ├── level1/
│   │   ├── area1.tmx     - Tiled source
│   │   └── area1.lua     - Lua export
│   └── level2/
│
├── images/               - Sprites, tilesets
│   ├── player/
│   ├── enemies/
│   ├── items/
│   ├── parallax/         - Parallax backgrounds
│   └── tilesets/
│
├── sounds/               - Sound effects
├── bgm/                  - Background music
└── fonts/                - Font files
```

**Map Properties:**
```
name = "level1_area1"    ← REQUIRED for persistence!
game_mode = "topdown"    (or "platformer")
bgm = "level1"           (optional)
ambient = "day"          (optional)
```

**Object Properties:**
```
WorldItems:
  item_type = "sword"
  respawn = false        ← One-time pickup!

Enemies:
  type = "boss_slime"
  respawn = false        ← One-time kill!

Parallax (in "Parallax" objectgroup):
  Type = "parallax"
  image = "assets/images/parallax/layer1_sky.png"
  parallax_factor = 0.1  (0.0=fixed, 1.0=normal)
  z_index = 1
  repeat_x = true
  offset_y = 0
```

---

## Vendor Folder

External libraries (unmodified):
```
vendor/
├── anim8/                - Sprite animation
├── hump/                 - Utilities (camera, timer, vector)
├── sti/                  - Tiled map loader
├── windfield/            - Box2D wrapper
└── talkies/              - Dialogue system
```

---

## Persistence System

**Save Data Structure:**
```lua
save_data = {
  hp = 100,
  map = "assets/maps/level1/area1.lua",
  x = 500, y = 300,
  inventory = {...},

  -- Persistence tracking
  picked_items = {
    ["level1_area1_obj_46"] = true,  -- Staff picked
  },
  killed_enemies = {
    ["level1_area1_obj_40"] = true,  -- Boss killed
  }
}
```

**Map ID Format:** `"{map_name}_obj_{object_id}"`

**Workflow:**
1. Map load: Check tables, skip if `respawn=false` and already picked/killed
2. Pickup/kill: Add `map_id` to table (only if `respawn=false`)
3. Save: Include tables in save file
4. Load: Restore tables, pass to `world:new()`

---

## Code Statistics

**Before:** 7,649 lines (game folder)
**After:** 4,174 lines **-45% reduction**
- All entities in engine (100% reusable)
- Menu scenes: 358 → 24 lines **-93%**

**New Game Creation:**
- Copy `engine/` (100% reusable)
- Create `game/data/` (~600 lines config)
- Create `game/scenes/` (~2,400 lines logic)
- **Total: ~3,000 lines vs 7,649 (61% less code)**

---

**Last Updated:** 2025-11-25
**Framework:** LÖVE 11.5 + Lua 5.1
