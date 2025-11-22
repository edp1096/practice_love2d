# LÖVE2D Game Engine - Quick Start

A LÖVE2D game project with clean **Engine/Game separation** architecture.

---

## Project Philosophy

### **Engine (100% Reusable)** 
The `engine/` folder contains **ALL** game systems AND entities:
- **Core systems:** lifecycle, input, display, sound, save, camera, debug
- **Subsystems:** world (physics), effects, lighting, parallax, HUD, collision
- **Entities:** player, enemy, weapon, NPC, item, healing_point (**ALL in engine!**)
- **UI:** menu system, screens, dialogue, prompts, widgets
- **Scene builders:** data-driven scene factory, cutscene, gameplay

### **Game (Data + Minimal Code)**
The `game/` folder contains **only** game-specific content:
- **Scenes:** 4 data-driven menus (6 lines each!), complex scenes (play, settings, inventory, load)
- **Data configs:** player stats, enemy types, menu configs, sounds, input mappings
- **No entities folder!** (moved to engine)

### **Benefits**
- **Create new games easily**: Copy `engine/`, create new `game/` content
- **Clean separation**: Engine code vs Game content
- **Easy maintenance**: Clear folder structure
- **Content-focused**: Focus on game design, not engine code
- **61% less code**: ~3,000 lines vs original 7,649 lines

---

## Quick Start

### Installation

1. Install LÖVE 11.5: https://love2d.org/
2. Clone or download this project
3. Run:
   - **Desktop:** `love .`
   - **Web:** See [Web Build](#-web-build) section below

### Controls

**Desktop:**
- **WASD / Arrow Keys** - Move (Topdown) / Move + Jump (Platformer)
- **Mouse** - Aim weapon
- **Left Click / Z** - Attack
- **Right Click / X** - Parry (perfect timing = slow-motion!)
- **Shift / C** - Dodge (invincibility frames)
- **F** - Interact (NPCs, Save Points, Items)
- **I / J** - Toggle Inventory/Quest Log (opens tabbed container)
- **Q / E** - Switch tabs in container (Inventory ↔ Quests)
- **Q** - Use selected item (in gameplay)
- **Tab** - Cycle items (in gameplay)
- **1-5** - Quick select inventory slot (in gameplay)
- **Escape** - Pause / Close menus
- **F11** - Toggle Fullscreen

**Debug Mode (if `APP_CONFIG.is_debug = true`):**
- **F1** - Toggle debug UI
- **F2** - Toggle collision grid
- **F3** - Toggle mouse coordinates
- **F4** - Toggle virtual gamepad (PC test mode)
- **F5** - Toggle effects debug
- **F6** - Test effects at mouse

**Gamepad (Xbox / DualSense):**
- **Left Stick / D-Pad** - Move
- **Right Stick** - Aim weapon / Scroll quest list
- **A / Cross (✕)** - Attack / Interact
- **B / Circle (○)** - Jump / Skip dialogue (hold 0.5s) / Close menus
- **X / Square (□)** - Parry
- **Y / Triangle (△)** - Interact (NPCs/Save Points)
- **LB / L1** - Previous tab (in container)
- **LT / L2** - Next item (in gameplay)
- **RB / R1** - Next tab / Dodge (in gameplay)
- **RT / R2** - Toggle Inventory/Quest Log container
- **Start / Options** - Pause

**Mobile (Touch):**
- **Virtual Gamepad** - On-screen controls (auto-shows on Android/iOS)
- **Touch anywhere** - Navigate menus / Advance dialogue
- **Swipe** - Scroll quest list in Quest Log

---

## Project Structure

```
29_indoor/
├── engine/           # Reusable game engine (100% reusable)
│   ├── core/         # Core systems (lifecycle, input, scene, quest, etc.)
│   ├── systems/      # Subsystems (world, effects, lighting, hud, prompt, entity_factory)
│   ├── entities/     # All entities (player, enemy, weapon, npc, item)
│   ├── scenes/       # Scene builders (builder, cutscene, gameplay - modular 7 files)
│   ├── ui/           # UI systems (menu, dialogue, questlog, widgets)
│   └── utils/        # Utilities (fonts, text, util, colors, etc.)
├── game/             # Game-specific content
│   ├── data/         # Configuration files (player, quests, scenes, sounds, etc.)
│   └── scenes/       # Game scenes (menu, play, settings, inventory, load)
├── assets/           # Game resources (maps, images, sounds)
├── vendor/           # External libraries (STI, Windfield, anim8, etc.)
├── docs/             # Documentation
├── main.lua          # Entry point (dependency injection)
├── conf.lua          # LÖVE configuration
└── startup.lua       # Initialization utilities
```

**Key Concepts:**
- **engine/** = "How it works" (100% reusable)
- **game/** = "What it shows" (data + scenes)
- **Dependency Injection** = Game configs injected via `main.lua`

---

## First Steps

### 1. Explore the Game
- Start: `love .`
- New Game → Create save slot
- Walk around with WASD
- Attack enemies (Left Click)
- Talk to NPCs (F key)
- Save at glowing circles (F key)

### 2. Try Different Game Modes
- **Topdown** (level1/area1-3): Free 2D movement, no gravity
- **Platformer** (level2/area1): Horizontal + jump, gravity enabled

### 3. Test Combat
- **Attack:** Left Click / A button
- **Parry:** Right Click / X button (perfect timing = slow-motion!)
- **Dodge:** Shift / R1 button (invincibility frames)

### 4. Inventory & Quest System
- Press **I** or **R2** to open Inventory tab
- Press **J** to open Quest Log tab
- Both open the same **tabbed container**
- Switch tabs: **Q/E** (keyboard) or **LB/RB** (gamepad)
- Close: **ESC** or **R2** (toggle)
- Use items: **Q** / **L1** (in gameplay)
- Cycle items: **Tab** / **L2** (in gameplay)
- Quick-select: **1-5** keys (in gameplay)
- Scroll quests: **Mouse wheel** / **Right Stick** / **Swipe** (mobile)

### 5. Persistence System
- **One-time items:** Pick up starter weapons (staff, sword) once
- **One-time enemies:** Kill bosses once, they stay dead
- **Respawning:** Regular items/enemies respawn by default
- Set `respawn = false` in Tiled to make items/enemies one-time

---

## Creating Content

### Add a New Enemy  (Data-Driven - No Code!)

**Method 1: Direct in Tiled (Quick)**
1. Open map: `assets/maps/level1/area1.tmx`
2. Add object to "Enemies" layer
3. Set object type: `slime`, `goblin`, etc.
4. Add custom properties:
   ```
   hp = 100           (health)
   dmg = 10           (damage)
   spd = 50           (speed)
   det_rng = 200      (detection range)
   respawn = false    (optional: one-time kill, default: true)
   spr = "assets/images/enemies/yourenemy.png"
   ```
5. Export to Lua - Done!

**Method 2: Enemy Type Registry (Reusable)**
Add to `game/data/entities/types.lua`:
```lua
enemies = {
  yourenemy = {
    hp = 100,
    damage = 15,
    speed = 80,
    sprite = "assets/images/enemies/yourenemy.png",
    detection_range = 250,
    attack_range = 50
  }
}
```

Then in Tiled, just set `type = "yourenemy"`.

### Add a New Menu  (Data-Driven - 6 lines!)

1. Add to `game/data/scenes.lua`:
```lua
scenes.mymenu = {
  type = "menu",
  title = "My Menu",
  options = {"Play", "Settings", "Quit"},
  actions = {
    ["Play"] = {action = "switch_scene", scene = "play"},
    ["Settings"] = {action = "switch_scene", scene = "settings"},
    ["Quit"] = {action = "quit"}
  },
  back_action = {action = "quit"},

  -- Optional: Flash effect
  flash = {
    enabled = true,
    color = {1, 0, 0},     -- Red flash
    initial_alpha = 1.0,
    fade_speed = 2.0
  }
}
```

2. Create `game/scenes/mymenu.lua`:
```lua
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("mymenu", configs)
```

Done! Only 6 lines.

### Add a New Item

1. Create icon: `assets/images/items/youritem.png`
2. Create type: `engine/entities/item/types/youritem.lua`:
```lua
local youritem = {
  name = "Your Item",
  description = "A useful item",
  icon = "assets/images/items/youritem.png",
  max_stack = 99,

  -- Optional: equipment
  equipment_slot = "weapon",  -- or "armor", "accessory"
  weapon_type = "sword",      -- if weapon

  -- Optional: consumable
  consumable = true,
  effect = function(player)
    player.health = math.min(player.health + 50, player.max_health)
  end
}

return youritem
```

3. Add to world or inventory:
```lua
-- Drop in world
world:addWorldItem("youritem", x, y, quantity)

-- Add to inventory
inventory:addItem("youritem", 1)
```

### Add a New Map

1. Create in Tiled: `assets/maps/level1/newarea.tmx`

2. Set map properties:
   ```
   name = "level1_newarea"      (REQUIRED for persistence)
   game_mode = "topdown"        (or "platformer")
   bgm = "level1"               (optional)
   ambient = "day"              (optional: day, night, cave, dusk, indoor, underground)
   ```

3. Add required layers:
   - **Ground** - Terrain tiles
   - **Trees** - Tiles with depth (Y-sorted in topdown)
   - **Walls** - Collision objects (rectangle, polygon, polyline, ellipse)
   - **Portals** - Map transitions
   - **Enemies** - Enemy spawn points
   - **NPCs** - NPC spawn points
   - **WorldItems** - Pickable items
   - **SavePoints** - Save points
   - **HealingPoints** - Health restoration points

4. Export to Lua

5. Create portal in previous map:
   ```
   type = "portal"
   target_map = "assets/maps/level1/newarea.lua"
   spawn_x = 100
   spawn_y = 200
   ```

### Add NPC Dialogue

The game supports two dialogue modes: **Simple Dialogue** and **Tree Dialogue** (choice-based).

#### Method 1: Simple Dialogue (Quick Message)

For single-line messages, set in Tiled:
```
NPC property: dlg = "Hello, traveler!"
```

#### Method 2: Tree Dialogue (Choice-Based RPG Style)

For interactive conversations with choices:

1. Create dialogue tree in `game/data/dialogues.lua`:
```lua
dialogues.shopkeeper = {
  start_node = "greeting",
  nodes = {
    greeting = {
      text = "Welcome to my shop!",
      speaker = "Shopkeeper",
      next = "main_menu"
    },
    main_menu = {
      text = "How can I help you?",
      speaker = "Shopkeeper",
      choices = {
        { text = "Tell me about items", next = "items" },
        { text = "Tell me a story", next = "story" },
        { text = "Goodbye", next = "end" }
      }
    },
    items = {
      text = "I sell potions and weapons!",
      speaker = "Shopkeeper",
      next = "main_menu"  -- Loop back to menu
    },
    story = {
      pages = {  -- Multi-page dialogue (Visual Novel style)
        "Once upon a time...",
        "There was a great kingdom...",
        "And that's how the legend began!"
      },
      speaker = "Shopkeeper",
      next = "main_menu"
    },
    ["end"] = {
      text = "See you later!",
      speaker = "Shopkeeper"
      -- No choices, no next = dialogue ends
    }
  }
}
```

2. Set NPC property in Tiled:
```
dlg = "shopkeeper"
```

3. Done! Players can now:
   - Navigate choices with keyboard (Up/Down, WASD)
   - Select with mouse hover + click
   - Use gamepad (A button to select)
   - Loop back to main menu for continuous interaction

**Dialogue Node Properties:**
- `text` - Single message (string)
- `pages` - Multi-page dialogue (array of strings)
- `speaker` - Character name (displayed above dialogue box)
- `choices` - Player choices: `{ text = "...", next = "node_id" }`
- `next` - Auto-advance to next node (if no choices)

### Add Background Music

1. Place file: `assets/bgm/yourmusic.ogg`
2. Register in `game/data/sounds.lua`:
   ```lua
   bgm = {
     yourmusic = {
       path = "assets/bgm/yourmusic.ogg",
       volume = 0.7,
       loop = true
     }
   }
   ```
3. Set in Tiled map property: `bgm = "yourmusic"`

---

## Documentation

- **[GUIDE.md](GUIDE.md)** - Complete development guide (concepts, workflows, best practices)
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - Detailed project structure reference
- **[../CLAUDE.md](../CLAUDE.md)** - Full API reference and instructions for Claude Code
- **[../DEVELOPMENT_JOURNAL.md](../DEVELOPMENT_JOURNAL.md)** - Recent changes and patterns

---

## Troubleshooting

### Game won't start
- Check LÖVE version: `love --version` (need 11.5)
- Check Lua version: `lua -v` (need 5.1 compatible)
- Look for errors in console

### Files not found errors
- Use dots in require paths: `require "engine.core.sound"`
- Use slashes in file paths: `"assets/maps/level1/area1.lua"`
- Never mix them up!

### No sound
- Check `config.ini` has non-zero volumes
- Check files exist: `assets/bgm/`, `assets/sound/`
- Check `game/data/sounds.lua` definitions

### Map won't load
- Export Tiled map to Lua format (`.lua` file)
- Check required layers exist (Ground, Walls, etc.)
- Check map property `game_mode` is set
- Check map property `name` is set (for persistence)

### Items/enemies respawn when they shouldn't
- Check map has `name` property
- Check objects have `respawn = false` property
- Check save/load is working (save data includes `picked_items`, `killed_enemies`)

---

## Web Build

The game can be deployed to web browsers using **love.js** (LÖVE to WebAssembly compiler).

### Requirements

- **Node.js** and **npm** installed
- **Lua 5.1 compatible code** (see limitations below)

### Build Process

1. **Install love.js globally:**
   ```bash
   npm install -g love.js
   ```

2. **Build for web:**
   ```bash
   npm run build
   ```

   This creates `web_build/game.data` with all game files.

3. **Run local server:**
   ```bash
   cd web_build
   lua server.lua 8080
   ```

   Or using Node.js:
   ```bash
   cd web_build
   npx http-server -p 8080
   ```

4. **Open browser:**
   - Navigate to `http://localhost:8080`
   - Use `localhost` (not `127.0.0.1`) for best compatibility

### Lua 5.1 Compatibility

**Web builds use Lua 5.1 (not LuaJIT).** The codebase is already compatible:

**Avoided Features:**
- `goto` and labels (Lua 5.2+)
- FFI module (LuaJIT only)
- Use `loadstring or load` for compatibility

**Platform Detection:**
```lua
local os = love.system.getOS()
if os == "Web" then
  -- Web-specific behavior
end
```

### Web Platform Limitations

**Browser Restrictions:**
- **Tab blur pauses execution:** BGM and weather stop when tab loses focus
- **Auto-resume on focus:** BGM automatically resumes when tab regains focus
- **No "Quit" button:** Automatically hidden in web builds
- **Fullscreen limitations:** Requires user gesture (button click)

**Storage:**
- Save files stored in browser IndexedDB
- Clear browser data = lost saves
- Not portable between browsers

### Deployment

**Option 1: Lua-based Server (No Node.js required)**
```bash
cd web_build
lua server.lua 8080
```

**Option 2: Any HTTP Server**
```bash
# Python
python -m http.server 8080

# Node.js
npx http-server -p 8080

# PHP
php -S localhost:8080
```

**Production Deployment:**
- Upload `web_build/` contents to web host
- Ensure MIME types: `.wasm` = `application/wasm`, `.data` = `application/octet-stream`
- Enable gzip compression for `.data`, `.js`, `.wasm` files
- Set appropriate CORS headers if needed

---

## Next Steps

1. **Read GUIDE.md** - Learn content creation workflows
2. **Read CLAUDE.md** - Full API reference
3. **Experiment** - Modify existing content
4. **Create** - Build your own game!

---

## Recent Changes

**2025-11-19: Code Quality & Refactoring**
- **Inventory Refactoring**: Removed duplicate grid iteration and sorting logic (5 locations → 2 helper functions, -19 lines)
- **Debug Cleanup**: Removed 29 debug print statements from dialogue, inventory, enemy, and input systems
- **Code Structure**: Removed all `goto` statements (4 instances), replaced with cleaner if-else patterns
- **Constants**: Extracted magic numbers to named constants (DEFAULT_GRID_WIDTH, DEFAULT_GRID_HEIGHT)
- **Controller Input**: PlayStation controllers show colored button shapes (✕○□△), Xbox shows letters (ABXY)
- **Respawn System**: Fixed respawn logic - only entities with explicit `respawn=true` property respawn on map reload

---

**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Layered Pyramid Architecture (99.2% clean) + Engine/Game Separation + Dependency Injection + Data-Driven + Controller Support
**Last Updated:** 2025-11-19
