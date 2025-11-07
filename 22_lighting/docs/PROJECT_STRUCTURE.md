# Project Structure

## 📁 Root Directory

```
21_map/
├── main.lua              - Entry point (LÖVE callbacks, error handler, input routing)
├── conf.lua              - LÖVE configuration (window, modules, identity)
├── locker.lua            - Process locking (desktop only, prevents multiple instances)
├── config.ini            - Auto-generated settings (desktop)
│
├── engine/               - Reusable game engine (see ENGINE_GUIDE.md)
├── game/                 - Game-specific content (see GAME_GUIDE.md)
├── lib/                  - Third-party library wrappers
├── vendor/               - External libraries (STI, Windfield, anim8, hump, Talkies)
├── assets/               - Game resources (maps, images, sounds, fonts)
└── docs/                 - Documentation (this folder)
```

---

## 🎮 Engine Folder (`engine/`)

**Purpose:** Reusable systems that can be used in any LÖVE2D game.

```
engine/
├── lifecycle.lua         - Application lifecycle (init, update, draw, resize, quit)
├── scene_control.lua     - Scene stack management (switch, push, pop)
├── camera.lua            - Camera effects (shake, slow-motion)
├── coords.lua            - **Unified coordinate system** (World, Camera, Virtual, Physical)
├── game_mode.lua         - Game mode management (topdown/platformer)
├── sound.lua             - Audio system (BGM, SFX, volume control)
├── save.lua              - Save/Load system (slot-based)
├── inventory.lua         - Inventory system (items, usage)
├── debug.lua             - Debug overlay (F1 toggle)
├── constants.lua         - Engine constants
│
├── display/              - Virtual screen system
│   └── init.lua          - Scaling, letterboxing, coordinate transform
│
├── input/                - Input system
│   ├── init.lua                        - Input facade (API entry point)
│   ├── dispatcher.lua                  - Input event dispatcher
│   ├── virtual_gamepad.lua             - Virtual on-screen gamepad (mobile)
│   └── sources/
│       ├── base_input.lua              - Base class
│       ├── keyboard_input.lua          - Keyboard handling
│       ├── mouse_input.lua             - Mouse/aim handling
│       ├── physical_gamepad_input.lua  - Physical controller
│       └── virtual_gamepad_input.lua   - Virtual gamepad adapter
│
├── world/                - Physics & world system
│   ├── init.lua          - World coordinator (Windfield wrapper)
│   ├── loaders.lua       - Map loading (Tiled TMX)
│   ├── entities.lua      - Entity management (add, remove, update)
│   └── rendering.lua     - Y-sorted rendering
│
├── effects/              - Visual effects system
│   ├── init.lua          - Effects coordinator
│   ├── particles/        - Particle effects (blood, sparks, etc.)
│   └── screen/           - Screen effects (flash, vignette, overlay)
│
├── lighting/             - Lighting system (image-based)
│   ├── init.lua          - Lighting manager (ambient, point lights)
│   └── light.lua         - Individual light object
│
├── hud/                  - In-game HUD system
│   ├── status.lua        - Health bars, cooldowns, status indicators
│   └── minimap.lua       - Minimap rendering
│
├── ui/                   - Menu UI system
│   ├── menu.lua          - Menu UI helpers (layout, navigation, dialogs)
│   └── dialogue.lua      - NPC dialogue system (Talkies wrapper)
│
└── utils/                - Engine utilities
    ├── util.lua          - General utilities
    ├── restart.lua       - Game restart logic
    ├── fonts.lua         - Font management
    └── ini.lua           - INI file parser
```

---

## 🕹️ Game Folder (`game/`)

**Purpose:** Game-specific content (data-driven game development).

```
game/
├── scenes/               - Game screens (menus, gameplay)
│   ├── menu.lua
│   ├── gameover.lua
│   ├── intro.lua
│   ├── pause.lua
│   ├── newgame.lua
│   ├── saveslot.lua
│   ├── play/             - Main gameplay scene (modular)
│   │   ├── init.lua      - Scene coordinator
│   │   ├── update.lua    - Game loop
│   │   ├── render.lua    - Drawing
│   │   └── input.lua     - Input handling
│   ├── settings/         - Settings menu (modular)
│   │   ├── init.lua
│   │   ├── options.lua
│   │   ├── render.lua
│   │   └── input.lua
│   ├── load/             - Load game scene (modular)
│   │   ├── init.lua
│   │   ├── slot_renderer.lua
│   │   └── input.lua
│   └── inventory/        - Inventory overlay (modular)
│       ├── init.lua
│       ├── slot_renderer.lua
│       └── input.lua
│
├── entities/             - Game characters & objects
│   ├── player/
│   │   ├── init.lua      - Main coordinator
│   │   ├── animation.lua - Animation state machine
│   │   ├── combat.lua    - Health, attack, parry, dodge
│   │   ├── render.lua    - Drawing logic
│   │   └── sound.lua     - Player sound effects
│   ├── enemy/
│   │   ├── init.lua
│   │   ├── ai.lua        - AI state machine
│   │   ├── render.lua
│   │   ├── sound.lua
│   │   ├── spawner.lua   - Enemy spawning logic
│   │   └── types/
│   │       ├── slime.lua
│   │       └── humanoid.lua
│   ├── weapon/
│   │   ├── init.lua
│   │   ├── combat.lua
│   │   ├── render.lua
│   │   ├── config/       - Weapon configurations
│   │   └── types/
│   │       └── sword.lua
│   ├── npc/
│   │   ├── init.lua
│   │   └── types/
│   │       └── villager.lua
│   ├── item/
│   │   ├── init.lua
│   │   └── types/
│   │       ├── small_potion.lua
│   │       └── large_potion.lua
│   └── healing_point/
│       └── init.lua
│
└── data/                 - Game configuration data
    ├── input_config.lua  - Key mappings & controller settings
    ├── sounds.lua        - Sound asset definitions (BGM, SFX)
    └── intro_configs.lua - Intro/cutscene configurations
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

| Category | Files | Lines |
|----------|-------|-------|
| **Engine** | ~30 files | ~4,500 lines |
| **Game Content** | ~50 files | ~7,000 lines |
| **Total** | ~80 files | ~11,500 lines |

---

## 🎯 Design Principles

### 1. Engine/Game Separation
- **Engine:** "How does it work?" (systems, mechanisms)
- **Game:** "What does it show?" (content, data)

### 2. Modular Architecture
- Complex systems split into focused files
- Single responsibility per module
- Easy to find and modify

### 3. Content-Driven Philosophy
- Engine is reusable across projects
- Game folder is content-only
- Minimal code in game/ (mostly data)

---

**See also:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - Engine systems reference
- [GAME_GUIDE.md](GAME_GUIDE.md) - Content creation guide
