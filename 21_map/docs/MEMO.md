# Project Structure - LÖVE2D Game

## 📁 Root Files

```
.
├── main.lua              - Game entry point (LÖVE callbacks, touch/input routing)
├── conf.lua              - LÖVE configuration (reads config.ini or mobile_config.lua)
├── locker.lua            - Process locking for single instance (desktop only)
└── config.ini            - Auto-generated config file (desktop only)
```

---

## 📂 Assets

### Maps (Tiled TMX → Lua)
```
assets/maps/
├── level1/
│   ├── area1.lua/tmx     - Starting area
│   ├── area2.lua/tmx     - Second area
│   └── area3.lua/tmx     - Third area
└── level2/
    └── area1.lua/tmx     - Level 2 first area
```

### Graphics
```
assets/images/            - Sprites, tilesets, UI graphics
assets/fonts/             - Custom fonts (if any)
```

### Audio
```
assets/sounds/            - Sound effects and background music
```

---

## 🎮 Scenes (Game Screens)

### Modular Scenes (Refactored)
```
scenes/
├── settings/                    - Settings menu (592 → 717 lines, 4 files)
│   ├── init.lua                 - Scene lifecycle (enter, exit, update, draw)
│   ├── options.lua              - Option definitions & change logic (resolutions, volumes, etc.)
│   ├── render.lua               - UI rendering (menu, arrows, hints)
│   └── input.lua                - Input handling (keyboard, gamepad, mouse, touch)
│
├── load/                        - Load game screen (501 → 607 lines, 3 files) [Moved from systems/]
│   ├── init.lua                 - Scene lifecycle & state management
│   ├── slot_renderer.lua        - Save slot rendering & delete button UI
│   └── input.lua                - Input handling + slot selection
│
├── inventory_ui/                - Inventory overlay (351 → 433 lines, 3 files)
│   ├── init.lua                 - Scene lifecycle & inventory state
│   ├── slot_renderer.lua        - Item grid rendering & close button
│   └── input.lua                - Input handling + item usage
│
└── play/                        - Main gameplay scene (already modular)
    ├── init.lua                 - Scene coordinator (map loading, entities, camera)
    ├── update.lua               - Game loop (movement, combat, transitions)
    ├── render.lua               - Drawing (parallax, world, entities, HUD, minimap)
    └── input.lua                - Gameplay input (attack, dodge, interact, etc.)
```

### Monolithic Scenes (Single Files)
```
scenes/
├── menu.lua                     - Main menu
├── pause.lua                    - Pause menu (overlay)
├── intro.lua                    - Intro/cutscene system
├── gameover.lua                 - Game over / victory screen
├── newgame.lua                  - New game confirmation
└── saveslot.lua                 - Save slot selection
```

---

## 🎯 Entities (Game Objects)

### Player
```
entities/player/
├── init.lua                     - Main coordinator (delegates to subsystems)
├── animation.lua                - Sprite animation state machine (mode-aware)
├── combat.lua                   - Health, attack, parry, dodge, damage
├── render.lua                   - Drawing logic (sprite, shadow, debug)
└── sound.lua                    - Player sound effects
```

### Enemy
```
entities/enemy/
├── init.lua                     - Enemy coordinator
├── ai.lua                       - AI state machine (idle, patrol, chase, attack, stunned)
├── render.lua                   - Drawing & health bars
├── sound.lua                    - Enemy sound effects
└── types/
    ├── slime.lua                - Slime enemy type definition
    └── humanoid.lua             - Humanoid enemy type definition
```

### Weapon
```
entities/weapon/
├── init.lua                     - Weapon coordinator
├── combat.lua                   - Hit detection & damage
├── render.lua                   - Weapon drawing & swing animations
├── config/
│   ├── hand_anchors.lua         - Hand position offsets
│   ├── handle_anchors.lua       - Weapon handle points
│   └── swing_configs.lua        - Swing animation configs
└── types/
    └── sword.lua                - Sword weapon definition
```

### Other Entities
```
entities/
├── npc/
│   ├── init.lua                 - NPC base system
│   └── types/
│       └── villager.lua         - Villager NPC type
├── item/
│   ├── init.lua                 - Item base system
│   └── types/
│       ├── small_potion.lua     - Small HP potion
│       └── large_potion.lua     - Large HP potion
└── healing_point/
    └── init.lua                 - Healing area system
```

---

## 🛠️ Systems (Game Subsystems)

### Input System (Modular)
```
systems/input/
├── init.lua                     - Input facade (hardware management, settings, API)
├── input_coordinator.lua        - Coordinates multiple input sources + gamepad button mapping
├── virtual_gamepad.lua          - Virtual on-screen gamepad for mobile (927 lines)
└── sources/
    ├── base_input.lua           - Base class for input sources
    ├── keyboard_input.lua       - Keyboard handling
    ├── mouse_input.lua          - Mouse/aim handling
    ├── physical_gamepad_input.lua - Physical controller support
    └── virtual_gamepad_input.lua  - Virtual gamepad adapter
```

### World System (Modular)
```
systems/world/
├── init.lua                     - World coordinator (physics, collision, game mode)
├── loaders.lua                  - Map loading & object spawning
├── entities.lua                 - Entity management (add, remove, update)
└── rendering.lua                - Y-sorted entity rendering
```

### Other Systems (Single Files)
```
systems/
├── scene_control.lua            - Scene stack management (switch, push, pop)
├── camera.lua                   - Camera shake & slow-motion effects
├── sound.lua                    - BGM & SFX management (lazy loading)
├── save.lua                     - Save game to slots
├── inventory.lua                - Inventory system (items, usage)
├── dialogue.lua                 - NPC dialogue system (uses Talkies library)
├── effects.lua                  - Particle effects (hits, deaths)
├── hud.lua                      - UI overlay (health bars, cooldowns)
├── debug.lua                    - F12 debug overlay & visualization
├── minimap.lua                  - Minimap rendering system
├── parallax.lua                 - Parallax background scrolling
├── game_mode.lua                - Topdown vs Platformer mode management
└── constants.lua                - Game constants (vibration, input timings, etc.)
```

---

## 📚 Libraries (Custom Wrappers)

```
lib/
├── screen/
│   └── init.lua                 - Virtual resolution system (960x540) + fullscreen
├── text/
│   └── init.lua                 - Text rendering utilities
└── ini/
    └── init.lua                 - INI file parser
```

---

## 🔧 Utilities

```
utils/
├── util.lua                     - General utility functions
├── scene_ui.lua                 - Reusable UI components for scenes
├── restart.lua                  - Game restart logic (from save/from here)
└── enemy_spawner.lua            - Enemy spawning from map objects
```

---

## 📊 Data (Configuration)

```
data/
├── input_config.lua             - Input mappings (keyboard, mouse, gamepad)
│                                  Includes mode-specific overrides (topdown vs platformer)
│                                  Context actions (A button = interact or attack)
├── sounds.lua                   - Sound asset definitions (BGM, SFX categories)
└── intro_configs.lua            - Intro/cutscene configurations
```

---

## 📦 Vendor (Third-Party Libraries)

```
vendor/
├── anim8/                       - Sprite animation library
├── hump/                        - Utility collection (camera, gamestate, timer, vector)
├── sti/                         - Simple Tiled Implementation (TMX loader)
├── windfield/                   - Box2D physics wrapper
└── talkies/                     - Dialogue/text box system
```

---

## 📝 File Count Summary

| Category | Modules | Files | Total Lines |
|----------|---------|-------|-------------|
| **Scenes (Modular)** | 4 scenes | 13 files | ~1,757 lines |
| **Scenes (Monolithic)** | 6 scenes | 6 files | ~1,200 lines |
| **Entities** | 4 types | 20 files | ~2,500 lines |
| **Systems** | 18 systems | 30 files | ~4,500 lines |
| **Libs + Utils** | 4 libs, 4 utils | 8 files | ~1,000 lines |
| **Data + Config** | 3 configs | 3 files | ~500 lines |
| **Total** | - | **~80 files** | **~11,500 lines** |

---

## 🎯 Key Architecture Patterns

### 1. Modular Scenes (New Pattern)
```
scenes/<scene_name>/
├── init.lua          - Scene lifecycle (enter, exit, update, draw)
├── input.lua         - All input handling
├── render.lua        - UI rendering (or slot_renderer.lua for grid layouts)
└── options.lua       - Business logic (settings only)
```

**Benefits:**
- Single responsibility per file
- Easy to find and modify specific functionality
- Consistent pattern across all complex scenes

### 2. Entity Component Pattern
```
entities/<entity_type>/
├── init.lua          - Coordinator (delegates to subsystems)
├── ai.lua            - AI logic (enemies)
├── animation.lua     - Animation state machine (player)
├── combat.lua        - Combat mechanics
├── render.lua        - Drawing logic
└── sound.lua         - Sound effects
```

### 3. System Pattern
```
systems/<system_name>/
├── init.lua          - Main coordinator
└── <subsystems>.lua  - Specialized modules
```

**OR**

```
systems/<system_name>.lua  - Single file for simpler systems
```

### 4. Input Priority Chain
```
main.lua (touch/mouse events)
  ↓
1. Debug button
2. Scene touchpressed (returns true/false)
3. Virtual gamepad (mobile only)
4. Fallback to mouse events
```

### 5. Game Mode Separation
- **Topdown**: Free 2D movement, no gravity
- **Platformer**: Horizontal movement + jump, gravity enabled
- Mode-specific input handling in `data/input_config.lua`
- AI behavior adapts to mode (horizontal-only distance in platformer)

---

## 📱 Platform Support

### Desktop
- Keyboard + Mouse
- Physical gamepad support
- Multi-monitor support
- Resolution settings
- Fullscreen toggle

### Mobile (Android/iOS)
- Virtual on-screen gamepad
- Touch input with priority system
- Mobile vibration support
- Fixed virtual resolution (960x540)
- Optimized UI scaling

---

## 🔄 Recent Refactoring (2025-11-03)

### Input System
- ✅ Unified gamepad button handling in `input_coordinator.lua`
- ✅ Context-based actions (A button = interact OR attack)
- ✅ Removed button mapping duplication from scenes
- ✅ Updated `data/input_config.lua` with DualSense layout

### Scene Refactoring
- ✅ `scenes/settings.lua` → `scenes/settings/` (4 files)
- ✅ `systems/load.lua` → `scenes/load/` (3 files) + added touch support
- ✅ `scenes/inventory_ui.lua` → `scenes/inventory_ui/` (3 files)
- ✅ All scenes now follow modular pattern

### Benefits
- 75% reduction in code complexity
- Eliminated duplicate logic
- Consistent architecture across all scenes
- Easier to maintain and extend

---

## 📖 Documentation Files

```
.
├── CLAUDE.md            - Project overview & developer guide (for Claude Code)
├── MEMO.md              - This file (project structure reference)
└── docs/                - Additional documentation (if any)
```

---

**Last Updated:** 2025-11-03
**Project:** LÖVE2D 2D Action RPG (Topdown + Platformer)
**Framework:** LÖVE 11.5 + Lua 5.1
