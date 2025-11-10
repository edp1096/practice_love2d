# Project Structure

## 📁 Root Directory

```
23_refactor/
├── main.lua              - Entry point (LÖVE callbacks, delegates to startup/system)
├── conf.lua              - LÖVE configuration (window, modules, version)
├── startup.lua           - Initialization utilities (error handler, platform detection, config loading)
├── system.lua            - System-level runtime handlers (hotkeys, instance lock, cleanup)
├── locker.lua            - Process locking (desktop only, prevents multiple instances)
├── config.ini            - User settings (window, sound, input, IsDebug)
│
├── engine/               - Reusable game engine (systems + entities)
├── game/                 - Game-specific content (scenes + data configs)
├── vendor/               - External libraries (STI, Windfield, anim8, hump, Talkies)
├── assets/               - Game resources (maps, images, sounds, fonts)
└── docs/                 - Documentation (this folder)
```

---

## 🎮 Engine Folder (`engine/`)

**Purpose:** 100% reusable game engine with proper layered architecture.

**Architecture:** The engine is organized into clear layers:
- **core/** - Foundation systems (lifecycle, input, display, sound, save, etc.)
- **systems/** - Subsystems (world, effects, lighting, hud)
- **scenes/** - Scene builders and templates
- **entities/** - Reusable entities (player, enemy, weapon, npc, item) ⭐
- **ui/** - UI systems (menu, screens, dialogue, widgets)
- **utils/** - Utilities (text, fonts, util, ini)

```
engine/
├── core/                 - **Core engine systems (Layer 1)**
│   ├── lifecycle.lua     - Application lifecycle (init, update, draw, resize, quit)
│   ├── scene_control.lua - Scene stack management (switch, push, pop)
│   ├── camera.lua        - Camera effects (shake, slow-motion)
│   ├── coords.lua        - **Unified coordinate system** (World, Camera, Virtual, Physical)
│   ├── sound.lua         - Audio system (BGM, SFX, volume control)
│   ├── save.lua          - Save/Load system (slot-based)
│   ├── inventory.lua     - Inventory system (items, usage)
│   ├── debug.lua         - Debug overlay (F1 toggle)
│   ├── constants.lua     - Engine constants
│   │
│   ├── display/          - Virtual screen system
│   │   └── init.lua      - Scaling, letterboxing, coordinate transform
│   │
│   └── input/            - Input system
│       ├── dispatcher.lua              - Input event dispatcher
│       ├── sources/                    - Query-based input sources
│       │   ├── base_input.lua          - Base class
│       │   ├── keyboard_input.lua      - Keyboard handling
│       │   ├── mouse_input.lua         - Mouse/aim handling
│       │   ├── gamepad.lua             - Physical controller
│       │   └── virtual_pad.lua         - Virtual gamepad adapter
│       └── virtual_gamepad/            - Event-based input (mobile touch)
│           ├── init.lua                - Main coordinator
│           ├── renderer.lua            - Drawing functions
│           └── touch.lua               - Touch event handling
│
├── systems/              - **Engine subsystems (Layer 2)**
│   ├── world/            - Physics & world system
│   │   ├── init.lua      - World coordinator (Windfield wrapper)
│   │   ├── loaders.lua   - Map loading (Tiled TMX + entity factory)
│   │   ├── entities.lua  - Entity management (add, remove, update)
│   │   └── rendering.lua - Y-sorted rendering
│   │
│   ├── effects/          - Visual effects system
│   │   ├── init.lua      - Effects coordinator
│   │   ├── particles/    - Particle effects (blood, sparks, etc.)
│   │   │   ├── init.lua
│   │   │   ├── presets.lua
│   │   │   └── systems.lua
│   │   └── screen/       - Screen effects (flash, vignette, overlay)
│   │       ├── init.lua
│   │       ├── presets.lua
│   │       └── shaders.lua
│   │
│   ├── lighting/         - Lighting system (image-based)
│   │   ├── init.lua      - Lighting manager (ambient, point lights)
│   │   └── source.lua    - Individual light source object (LightSource class)
│   │
│   └── hud/              - In-game HUD system
│       ├── init.lua      - HUD module bundle
│       ├── status.lua    - Health bars, cooldowns, status indicators
│       └── minimap.lua   - Minimap rendering
│
├── scenes/               - **Scene management (Layer 3)**
│   ├── builder.lua       - **Data-driven scene factory** (builds menus from configs)
│   ├── cutscene.lua      - Cutscene/intro scene (dialogue sequences)
│   └── gameplay.lua      - Main gameplay scene (world, entities, combat)
│
├── entities/             - **Reusable entities (Layer 3)** ⭐ ALL IN ENGINE!
│   ├── factory.lua       - **Entity factory** (creates entities from Tiled properties)
│   │
│   ├── player/           - Player entity (100% reusable, config injected)
│   │   ├── init.lua      - Main coordinator (dependency injection!)
│   │   ├── animation.lua - Animation state machine
│   │   ├── combat.lua    - Health, attack, parry, dodge
│   │   ├── render.lua    - Drawing logic
│   │   └── sound.lua     - Player sound effects
│   │
│   ├── enemy/            - Enemy entity (100% reusable, types injected)
│   │   ├── init.lua      - Enemy base class
│   │   ├── ai.lua        - AI state machine
│   │   ├── render.lua    - Drawing logic
│   │   ├── sound.lua     - Enemy sound effects
│   │   ├── spawner.lua   - Enemy spawning logic
│   │   └── factory.lua   - Creates enemies from Tiled (uses type_registry)
│   │
│   ├── weapon/           - Weapon entity (100% reusable, config injected)
│   │   ├── init.lua      - Main coordinator (dependency injection!)
│   │   ├── combat.lua    - Combat logic (hit detection, damage)
│   │   ├── render.lua    - Drawing logic
│   │   ├── config/       - Weapon configurations
│   │   │   ├── hand_anchors.lua    - Hand positions per animation frame
│   │   │   ├── swing_configs.lua   - Swing arcs per direction
│   │   │   └── handle_anchors.lua  - Handle pivot points
│   │   └── types/        - Weapon type definitions
│   │       └── sword.lua
│   │
│   ├── npc/              - NPC entity (100% reusable)
│   │   ├── init.lua      - Main coordinator
│   │   └── types/        - NPC type definitions
│   │       └── villager.lua
│   │
│   ├── item/             - Item entity (100% reusable)
│   │   ├── init.lua      - Main coordinator
│   │   └── types/        - Item type definitions
│   │       ├── small_potion.lua
│   │       └── large_potion.lua
│   │
│   └── healing_point/    - Healing point entity
│       └── init.lua      - Health restoration logic
│
├── ui/                   - **UI systems (Layer 4)**
│   ├── menu/             - Menu UI system
│   │   ├── base.lua      - **MenuSceneBase** (base class for all menus)
│   │   └── helpers.lua   - Menu UI helpers (layout, navigation, dialogs, touch)
│   │
│   ├── screens/          - Reusable UI screens
│   │   ├── newgame.lua   - New game slot selection
│   │   ├── saveslot.lua  - Save game screen
│   │   ├── load.lua      - Load game screen
│   │   ├── inventory.lua - Inventory UI
│   │   └── settings.lua  - Settings screen
│   │
│   ├── dialogue.lua      - NPC dialogue system (Talkies wrapper with skip/next buttons)
│   ├── shapes.lua        - Shape rendering utilities (buttons, overlays)
│   └── widgets/          - Reusable UI widgets
│       ├── skip_button.lua  - Skip button with charge system (0.5s hold)
│       └── next_button.lua  - Next button for advancing dialogue
│
└── utils/                - **Engine utilities (Layer 0)**
    ├── util.lua          - General utilities
    ├── text.lua          - **Text rendering utilities** (centralized print wrapper)
    ├── fonts.lua         - Font management
    ├── restart.lua       - Game restart logic
    ├── convert.lua       - Data conversion utilities
    └── ini.lua           - INI file parser
```

**Dependency Injection Pattern:**
```lua
-- main.lua injects game configs into engine classes
local player_module = require "engine.entities.player"
local weapon_module = require "engine.entities.weapon"
local enemy_module = require "engine.entities.enemy"

local player_config = require "game.data.player"
local entity_types = require "game.data.entity_types"

-- Inject configs
player_module.config = player_config
weapon_module.type_registry = entity_types.weapons
weapon_module.effects_config = {slash_sprite = "assets/images/effect-slash.png"}
enemy_module.type_registry = entity_types.enemies
```

---

## 🕹️ Game Folder (`game/`)

**Purpose:** Game-specific content (data-driven, minimal code).

**Key Achievement:** `game/entities/` folder **COMPLETELY DELETED!** All entities moved to `engine/entities/`!

```
game/
├── scenes/               - Game screens (data-driven + complex scenes)
│   ├── menu.lua          - Main menu (6 lines - data-driven!) ⭐
│   ├── pause.lua         - Pause menu (6 lines - data-driven!) ⭐
│   ├── gameover.lua      - Game over (6 lines - data-driven!) ⭐
│   ├── ending.lua        - Ending screen (6 lines - data-driven!) ⭐
│   │
│   ├── play/             - Main gameplay scene (modular)
│   │   ├── init.lua      - Scene coordinator
│   │   ├── update.lua    - Game loop
│   │   ├── render.lua    - Drawing
│   │   └── input.lua     - Input handling
│   │
│   ├── settings/         - Settings menu (modular)
│   │   ├── init.lua      - Settings coordinator
│   │   ├── options.lua   - Option data & logic
│   │   ├── render.lua    - Drawing
│   │   └── input.lua     - Input handling
│   │
│   ├── load/             - Load game scene (modular)
│   │   ├── init.lua      - Load coordinator
│   │   ├── slot_renderer.lua - Save slot rendering
│   │   └── input.lua     - Input handling
│   │
│   └── inventory/        - Inventory overlay (modular)
│       ├── init.lua      - Inventory coordinator
│       ├── slot_renderer.lua - Inventory slot rendering
│       └── input.lua     - Input handling
│
└── data/                 - **Game configuration (data-only, injected into engine)** ⭐
    ├── player.lua        - Player stats & combat config (61 lines)
    │                       ↳ Injected into engine.entities.player.config
    ├── entity_types.lua  - Enemy & weapon types (70 lines) **NEW!**
    │                       ↳ Injected into engine.entities.enemy.type_registry
    ├── scenes.lua        - Menu configs (140 lines, includes flash effects!)
    │                       ↳ Used by engine.scenes.builder
    ├── sounds.lua        - Sound asset definitions (BGM, SFX)
    ├── input_config.lua  - Key mappings & controller settings
    └── intro_configs.lua - Intro/cutscene configurations
```

**Data-Driven Menu Example:**
```lua
-- game/scenes/menu.lua (6 lines total!)
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("menu", configs)
```

**Menu Config Example (game/data/scenes.lua):**
```lua
scenes.gameover = {
  type = "menu",
  title = "GAME OVER",
  bgm = "gameover",
  overlay = true,        -- Semi-transparent background
  overlay_alpha = 0.8,

  flash = {              -- Screen flash effect
    enabled = true,
    color = {0.8, 0, 0}, -- Red flash
    initial_alpha = 1.0,
    fade_speed = 2.0
  },

  options = {"Restart from Here", "Load Last Save", "Quit to Menu"},
  actions = {
    ["Restart from Here"] = {action = "restart_current"},
    ["Load Last Save"] = {action = "restart_from_save"},
    ["Quit to Menu"] = {action = "switch_scene", scene = "menu"}
  },
  back_action = {action = "switch_scene", scene = "menu"}
}
```

---

## 🔧 Vendor Folder (`vendor/`)

**Purpose:** External libraries (unchanged).

```
vendor/
├── anim8/                - Sprite animation library
├── hump/                 - Utility collection (camera, timer, vector)
├── sti/                  - Simple Tiled Implementation (TMX loader)
├── windfield/            - Box2D physics wrapper
└── talkies/              - Dialogue/text box system
```

---

## 🎨 Assets Folder (`assets/`)

**Purpose:** Game resources.

```
assets/
├── maps/                 - Tiled maps (.tmx + .lua)
│   ├── level1/
│   │   ├── area1.lua/tmx
│   │   ├── area2.lua/tmx
│   │   └── area3.lua/tmx
│   └── level2/
│       └── area1.lua/tmx
├── images/               - Sprites, tilesets, UI graphics
├── bgm/                  - Background music (.ogg, .mp3)
├── sound/                - Sound effects (.wav)
└── fonts/                - Custom fonts
```

---

## 📊 File Count Summary

| Category | Files | Lines | Notes |
|----------|-------|-------|-------|
| **Engine Core** | ~25 files | ~3,500 lines | Core systems (lifecycle, input, sound, save) |
| **Engine Systems** | ~20 files | ~2,500 lines | Subsystems (world, effects, lighting, hud) |
| **Engine Entities** | ~25 files | ~2,500 lines | **100% reusable entities** ⭐ |
| **Engine UI** | ~15 files | ~2,000 lines | Menu system, screens, dialogue |
| **Engine Utils** | ~8 files | ~500 lines | Utilities (text, fonts, util, ini) |
| **Game Scenes** | ~20 files | ~3,800 lines | Game-specific scenes |
| **Game Data** | ~6 files | ~600 lines | **Configuration only** ⭐ |
| **Total** | ~119 files | ~15,400 lines | **Engine: ~11,000 lines (100% reusable!)** |

**Key Achievements:**
- ✅ **ALL entities moved to engine/** (player, enemy, weapon, npc, item, healing_point)
- ✅ **game/entities/ completely deleted!** (0 lines)
- ✅ **Data-driven menus** (4 scenes reduced from 358 → 24 lines = 93% reduction)
- ✅ **Dependency injection** (game configs injected via main.lua)
- ✅ **Layered architecture** (core, systems, scenes, entities, ui, utils)
- ✅ **Flash effects** for dramatic scenes (gameover, ending)
- ✅ **Entity factory** for data-driven enemy creation from Tiled
- ✅ **Scene builder** for declarative menu configs

**Code Reduction:**
- Game folder: 7,649 → 4,400 lines (-42% reduction)
- Engine folder: ~11,000 lines (100% reusable!)
- Menu scenes: 358 → 24 lines (-93% reduction)
- Entity code: 2,502 lines moved to engine

---

## 🎯 Design Principles

### 1. Engine/Game Separation
- **Engine:** "How does it work?" (systems, mechanisms, **ALL entities**)
- **Game:** "What does it show?" (content, data, configurations)
- **Key:** Engine is 100% reusable, game injects configs via dependency injection

### 2. Layered Architecture
Engine is organized in clear dependency layers:
```
Layer 0: utils/ (no dependencies)
Layer 1: core/ (depends on utils)
Layer 2: systems/ (depends on core + utils)
Layer 3: scenes/, entities/ (depends on core + systems)
Layer 4: ui/ (depends on core + systems + scenes)
```
- No circular dependencies
- Clear unidirectional flow
- Easy to understand and maintain

### 3. Dependency Injection
- Game configs injected into engine classes via `main.lua`
- Player stats → `engine.entities.player.config`
- Enemy types → `engine.entities.enemy.type_registry`
- Weapon types → `engine.entities.weapon.type_registry`
- **Result:** Engine remains 100% reusable, game provides customization

### 4. Data-Driven Philosophy
- **Entities:** Created from Tiled properties (no code!)
- **Menus:** Built from declarative configs (6 lines per menu!)
- **Flash effects:** Configured in data (color, speed, alpha)
- **Sound:** Asset paths in data files
- **Result:** Maximum reusability, minimum code duplication

### 5. Modular Architecture
- Complex systems split into focused files
- Single responsibility per module
- Easy to find and modify
- Example: `world/` = init.lua + loaders.lua + entities.lua + rendering.lua

---

**See also:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - Engine systems reference
- [GAME_GUIDE.md](GAME_GUIDE.md) - Content creation guide
