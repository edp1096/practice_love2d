# Development Guide

A practical guide to developing with this LÖVE2D game engine. For detailed API reference, see [CLAUDE.md](../CLAUDE.md).

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [Creating Content](#creating-content)
4. [Persistence System](#persistence-system)
5. [Common Tasks](#common-tasks)
6. [Best Practices](#best-practices)

---

## Quick Start

### Running the Game

```bash
# Desktop
love .

# Web (see Web Development section)
npm run build && cd web_build && lua server.lua 8080

# Check syntax
luac -p **/*.lua
```

### Project Structure

```
28_quest/
├── engine/           # Reusable game engine (100% reusable)
├── game/             # Game-specific content
│   ├── data/         # Configuration files (player, quests, dialogues, etc.)
│   └── scenes/       # Game scenes
├── vendor/           # External libraries
├── assets/           # Game resources
├── main.lua          # Entry point (dependency injection)
└── conf.lua          # LÖVE configuration
```

### First Steps

1. **Modify player stats:** Edit `game/data/player.lua`
2. **Change menus:** Edit `game/data/scenes.lua`
3. **Add enemies:** Place in Tiled map with properties
4. **Create maps:** Use Tiled, export to Lua

---

## Core Concepts

### Engine/Game Separation

**Rule:** Engine NEVER imports game files, only game imports engine.

```lua
-- GOOD: game/scenes/menu.lua
local builder = require "engine.scenes.builder"

-- BAD: engine/core/sound.lua
local sounds = require "game.data.sounds"  -- NEVER DO THIS!
```

**Solution:** Use dependency injection in `main.lua`:

```lua
local player_module = require "engine.entities.player"
local player_config = require "game.data.player"
player_module.config = player_config  -- Inject game config
```

### Game Modes

Two modes supported: **topdown** and **platformer**.

Set in Tiled map properties: `game_mode = "topdown"`

**Key Differences:**
- **Topdown:** No gravity, free 2D movement, dual colliders (foot + main)
- **Platformer:** Gravity enabled, jump mechanics, horizontal distance checks

### Coordinate Systems

Always use `engine/core/coords.lua` for transformations:

```lua
local coords = require "engine.core.coords"

-- World ↔ Camera (for rendering)
local cam_x, cam_y = coords:worldToCamera(x, y, camera)

-- Physical ↔ Virtual (for touch input)
local vx, vy = coords:physicalToVirtual(touch_x, touch_y, display)
```

### Scene Management

```lua
local scene_control = require "engine.core.scene_control"

scene_control.switch(scene, ...)  -- Switch to new scene
scene_control.push(scene, ...)    -- Push on stack (pause menu)
scene_control.pop()               -- Return to previous
```

---

## Creating Content

### Adding a New Enemy (Data-Driven!)

**No code required!** Just configure in Tiled:

1. Open map: `assets/maps/level1/area1.tmx`
2. Add object to "Enemies" layer
3. Set object type: `slime`, `goblin`, etc.
4. Add custom properties (optional):
   ```
   hp = 100          (health)
   dmg = 10          (damage)
   spd = 50          (speed)
   det_rng = 200     (detection range)
   respawn = false   (one-time enemy, default: true)
   ```
5. Export to Lua
6. Done! Enemy will spawn with those stats.

**Available enemy types:** See `game/data/entities/types.lua`

**Factory defaults:** See `engine/entities/factory.lua` DEFAULTS section

### Adding a Menu Scene (Data-Driven!)

1. Add to `game/data/scenes.lua`:

```lua
scenes.mymenu = {
  type = "menu",
  title = "My Menu",
  options = {"Start", "Quit"},
  actions = {
    ["Start"] = {action = "switch_scene", scene = "play"},
    ["Quit"] = {action = "quit"}
  },
  back_action = {action = "quit"},

  -- Optional: Flash effect
  flash = {
    enabled = true,
    color = {1, 0, 0},
    initial_alpha = 1.0,
    fade_speed = 2.0
  }
}
```

2. Create file `game/scenes/mymenu.lua`:

```lua
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("mymenu", configs)
```

Done! 6 lines of code.

### Adding an Item

1. Create icon: `assets/images/items/myitem.png`
2. Create type: `engine/entities/item/types/myitem.lua`:

```lua
local myitem = {
  name = "My Item",
  description = "A useful item",
  icon = "assets/images/items/myitem.png",
  max_stack = 99,

  -- Optional: equipment
  equipment_slot = "weapon",  -- or "armor", "accessory"

  -- Optional: consumable
  consumable = true,
  effect = function(player)
    player.health = player.health + 50
  end
}

return myitem
```

3. Add to inventory:

```lua
inventory:addItem("myitem", 1)
```

### Adding NPC Dialogue

The game supports two dialogue modes: **Simple Dialogue** and **Tree Dialogue** (choice-based conversations).

#### Simple Dialogue (Quick Messages)

For basic NPC messages, set directly in Tiled:

```
NPC property: dlg = "Hello, traveler! Welcome to our village."
```

Multiple messages (separated by semicolons):

```
dlg = "Welcome!;How can I help you?;Come back soon!"
```

**Player advances with:**
- **Keyboard:** F key / Z key / Enter
- **Gamepad:** A button (Xbox) / Cross (PS) / Y button
- **Mouse/Touch:** Click anywhere on dialogue box

#### Tree Dialogue (RPG-Style Conversations)

For interactive conversations with player choices, create a dialogue tree.

**Step 1: Create dialogue tree in `game/data/dialogues.lua`**

```lua
local dialogues = {}

dialogues.shopkeeper = {
  start_node = "greeting",
  nodes = {
    -- Initial greeting (auto-advances)
    greeting = {
      text = "Welcome to my shop!",
      speaker = "Shopkeeper",
      next = "main_menu"
    },

    -- Main menu with choices
    main_menu = {
      text = "How can I help you today?",
      speaker = "Shopkeeper",
      choices = {
        { text = "Tell me about your items", next = "items" },
        { text = "Any rumors lately?", next = "rumors" },
        { text = "I'd like to buy something", next = "shop" },
        { text = "Goodbye", next = "end" }
      }
    },

    -- Items info (loops back to menu)
    items = {
      text = "I sell potions, weapons, and armor. All high quality!",
      speaker = "Shopkeeper",
      next = "main_menu"  -- Loop back to menu
    },

    -- Rumors (multi-page dialogue)
    rumors = {
      pages = {
        "Have you heard? There's been strange activity in the northern forest...",
        "Travelers report seeing unusual lights at night.",
        "Some say it's magic, others think it's just fireflies.",
        "I'd stay away if I were you!"
      },
      speaker = "Shopkeeper",
      next = "main_menu"  -- Loop back to menu
    },

    -- Shop (would open shop UI in real game)
    shop = {
      text = "Here's what I have in stock. Take a look!",
      speaker = "Shopkeeper",
      next = "main_menu"
    },

    -- Ending
    ["end"] = {
      text = "Come back anytime! Safe travels!",
      speaker = "Shopkeeper"
      -- No choices, no next = dialogue ends
    }
  }
}

return dialogues
```

**Step 2: Set NPC property in Tiled**

```
dlg = "shopkeeper"
```

**Step 3: Done!** The NPC will show the interactive dialogue tree.

#### Dialogue Navigation

**Keyboard:**
- **Up/Down** or **W/S** - Navigate choices
- **Enter** or **Z** - Select choice
- **F** - Advance dialogue (no choices)

**Mouse/Touch:**
- **Hover** - Highlight choice
- **Click** - Select choice / Advance dialogue

**Gamepad:**
- **D-Pad** or **Left Stick** - Navigate choices
- **A button** (Xbox) / Cross (PS) - Select / Advance
- **Y button** (Xbox) / Triangle (PS) - Same as A
- **B button** (Xbox) / Circle (PS) - Hold 0.5s to skip dialogue (charge indicator)

#### Dialogue Node Properties

**Required:**
- `text` (string) - Single message
- OR `pages` (array) - Multi-page dialogue (Visual Novel style)

**Optional:**
- `speaker` (string) - Character name (displayed above dialogue box)
- `choices` (array) - Player choices: `{ text = "...", next = "node_id" }`
- `next` (string) - Auto-advance to next node (if no choices)

**No `next` and no `choices` = dialogue ends**

#### Advanced: Multi-Page Dialogue

For longer conversations, use `pages` instead of `text`:

```lua
story = {
  pages = {
    "Long ago, in a distant land...",
    "There lived a powerful wizard named Aldric.",
    "He created many magical artifacts.",
    "One of them was the legendary Crystal of Light!",
    "But that's a story for another time..."
  },
  speaker = "Elder",
  next = "main_menu"
}
```

Player advances through pages with same controls (F key, click, A button).

#### RPG Dialogue Pattern (Recommended)

**Best practice:** greeting → main_menu → choices loop back to menu

```lua
dialogues.quest_giver = {
  start_node = "greeting",
  nodes = {
    greeting = {
      text = "Ah, an adventurer! Perfect timing!",
      speaker = "Quest Giver",
      next = "main_menu"  -- Auto-advance to menu
    },
    main_menu = {
      text = "What can I do for you?",
      speaker = "Quest Giver",
      choices = {
        { text = "Do you have any quests?", next = "quest" },
        { text = "Tell me about this town", next = "town" },
        { text = "I'll be going now", next = "end" }
      }
    },
    quest = {
      text = "Yes! I need someone to retrieve a lost item from the caves.",
      speaker = "Quest Giver",
      next = "main_menu"  -- Loop back!
    },
    town = {
      text = "Our town is peaceful, but monsters have been appearing lately.",
      speaker = "Quest Giver",
      next = "main_menu"  -- Loop back!
    },
    ["end"] = {
      text = "Good luck on your journey!",
      speaker = "Quest Giver"
    }
  }
}
```

**Benefits:**
- Players can ask multiple questions without restarting conversation
- Natural RPG dialogue flow
- Easy to add new dialogue branches

### Creating a Map

1. Create in Tiled: `assets/maps/level1/newarea.tmx`

2. Set map properties:
   ```
   name = "level1_newarea"     (for persistence)
   game_mode = "topdown"       (or "platformer")
   bgm = "level1"              (optional)
   ambient = "day"             (optional: day, night, cave, etc.)
   ```

3. Add required layers:
   - **Ground** - Terrain tiles
   - **Trees** - Tiles with depth (Y-sorted in topdown)
   - **Walls** - Collision objects
   - **Portals** - Map transitions
   - **Enemies**, **NPCs** - Spawn points
   - **WorldItems** - Pickable items
   - **SavePoints**, **HealingPoints** - Interaction points

4. Export to Lua

5. Create portal from previous map:
   ```
   type = "portal"
   target_map = "assets/maps/level1/newarea.lua"
   spawn_x = 100
   spawn_y = 200
   ```

### Adding a Sound

1. Add file: `assets/sounds/mysound.ogg`

2. Register in `game/data/sounds.lua`:

```lua
sounds.sfx.mysound = {
  category = "gameplay",
  sources = {
    love.audio.newSource("assets/sounds/mysound.ogg", "static")
  },
  volume = 0.8
}
```

3. Play:

```lua
sound:playSFX("gameplay", "mysound")
```

### Adding Parallax Backgrounds

Create multi-layer scrolling backgrounds with depth effect.

1. **Prepare images:**
   - Place in `assets/backgrounds/`
   - Example: `layer1_sky.png`, `layer2_mountains.png`, etc.

2. **In Tiled map, create "Parallax" objectgroup layer**

3. **Add objects (one per layer) with custom properties:**

```
Object 1 (Sky):
  Name: "sky" (for reference only)
  Type: Leave empty (Tiled may not have type field)

  Custom Properties (Add these!):
    Type (string) = "parallax"                       ← REQUIRED!
    image (string) = "assets/backgrounds/layer1_sky.png"
    parallax_factor (float) = 0.1                    (0.0 = fixed, 1.0 = normal)
    z_index (int) = 1                                (lower = behind)
    repeat_x (bool) = true                           (horizontal tiling)
    offset_y (float) = 0                             (vertical position)
    auto_scroll_x (float) = 0                        (optional: auto-scroll)

Object 2 (Mountains):
  Custom Properties:
    Type = "parallax"
    image = "assets/backgrounds/layer2_mountains.png"
    parallax_factor = 0.3
    z_index = 2
    repeat_x = true
    offset_y = 0

Object 3 (Clouds):
  Custom Properties:
    Type = "parallax"
    image = "assets/backgrounds/layer3_clouds.png"
    parallax_factor = 0.5
    z_index = 3
    repeat_x = true
    offset_y = 0
    auto_scroll_x = 10                               ← Drifting clouds!
```

4. **Export map to Lua**

**Result:** Smooth infinite scrolling backgrounds with depth illusion!

**Tips:**
- Lower parallax_factor = slower scroll = farther away
- Use offset_y to adjust vertical positioning
- auto_scroll_x creates drifting effect (clouds, fog, etc.)
- Works in both topdown and platformer modes

---

## Persistence System

**NEW!** One-time pickups and enemy kills persist across maps and save/load.

### One-Time Items

Items with `respawn = false` only spawn once:

```lua
-- In Tiled (WorldItems layer)
item_type = "sword"
quantity = 1
respawn = false  -- Pick up once, never respawns
```

**How it works:**
1. Item has unique `map_id`: `"level1_area1_obj_46"`
2. When picked up, added to `picked_items` table
3. Saved to save file
4. On map load, filtered out if already picked

**Default:** Items respawn (`respawn = true`)

### One-Time Enemies

Enemies with `respawn = false` stay dead:

```lua
-- In Tiled (Enemies layer)
type = "boss_slime"
hp = 500
respawn = false  -- Kill once, stays dead
```

**How it works:**
1. Enemy has unique `map_id`: `"level1_area1_obj_40"`
2. When killed (after 2s death timer), added to `killed_enemies` table
3. Saved to save file
4. On map load, filtered out if already killed

**Default:** Enemies respawn (`respawn = true`)

### Map ID Generation

Format: `"{map_name}_obj_{object_id}"`

Examples:
- `"level1_area1_obj_46"` - Item with id=46 in level1_area1
- `"level2_area3_obj_120"` - Enemy with id=120 in level2_area3

**Requirements:**
- Map must have `name` property (e.g., `name = "level1_area1"`)
- Object must have unique id (assigned by Tiled)

### Save Data Structure

```lua
save_data = {
  hp = 100,
  max_hp = 100,
  map = "assets/maps/level1/area1.lua",
  x = 500,
  y = 300,
  inventory = {...},
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

---

## Common Tasks

### Debugging

Press **F1** to toggle debug overlay (if `APP_CONFIG.is_debug = true`):

- **F1** - Toggle debug UI
- **F2** - Toggle collision grid
- **F3** - Toggle mouse coordinates
- **F11** - Toggle fullscreen

Debug print:

```lua
dprint("My debug message")  -- Only shows if debug.enabled = true
```

### Testing Map Transitions

1. Add portal to test map
2. Set properties: `target_map`, `spawn_x`, `spawn_y`
3. Walk into portal
4. Check persistence: items/enemies should stay picked/killed

### Checking Colliders

Enable collision debug (F2) to see:
- Player colliders (green for foot, blue for main)
- Enemy colliders (red for foot, orange for main)
- Walls (white)

**Topdown mode:**
- Main colliders ignore each other (pass through)
- Foot colliders collide with walls and each other

**Platformer mode:**
- Uses main collider only
- Ground detection via raycasts

### Adjusting Player Stats

Edit `game/data/player.lua`:

```lua
return {
  health = 100,
  speed = 150,
  jump_force = -600,  -- Platformer only

  abilities = {
    can_attack = true,
    can_dodge = true,
    can_parry = true,
  },

  dodge = {
    cooldown = 1.0,
    speed_multiplier = 2.5,
    duration = 0.3,
  }
}
```

### Changing Input Bindings

Edit `game/data/input_config.lua`:

```lua
keyboard = {
  move_left = "a",
  move_right = "d",
  move_up = "w",
  move_down = "s",
  jump = "space",
  attack = "j",
  dodge = "lshift",
  -- ... etc
}
```

---

## Best Practices

### File Organization

```lua
-- 1. Module declaration
local mymodule = {}

-- 2. Requires
local engine_system = require "engine.core.something"

-- 3. Local functions
local function _helper()
  -- Private helper
end

-- 4. Public functions
function mymodule:publicMethod()
  -- Public API
end

-- 5. Return module
return mymodule
```

### Require Paths

```lua
-- GOOD: Use dots
require "engine.core.sound"
require "game.data.player"

-- BAD: Use slashes
require "engine/core/sound"
```

**Exception:** File paths use forward slashes:

```lua
"assets/maps/level1/area1.lua"  -- File path, not require
```

### Naming Conventions

```lua
local module_name = {}        -- lowercase_with_underscores
function obj:methodName() end  -- camelCase
local CONSTANT_VALUE = 100     -- UPPER_CASE
```

### Entity Lifecycle

**Creating:**
```lua
-- Use factory for Tiled objects
local enemy = factory:createEnemy(obj, enemy_class, map_name)

-- Or direct construction
local player = player_module:new(x, y, config)
```

**Destroying:**
```lua
-- ALWAYS destroy colliders before world
if entity.collider then
  entity.collider:destroy()
  entity.collider = nil
end
if entity.foot_collider then
  entity.foot_collider:destroy()
  entity.foot_collider = nil
end

-- Then destroy world
world:destroy()
```

### Collision Classes

**Available classes:**
- `Player`, `PlayerFoot`, `PlayerDodging`
- `Enemy`, `EnemyFoot`
- `Wall`, `WallBase`
- `NPC`
- `DeathZone`, `DamageZone`

**Topdown ignore rules:**
- Player main ↔ Enemy main (pass through)
- PlayerFoot ↔ EnemyFoot (collide for wall collision)

**Platformer:**
- Uses main collider only
- All entities collide normally

### Time Scaling

Use scaled time for slow-motion effects:

```lua
local scaled_dt = camera_sys:get_scaled_dt(dt)
enemy:update(scaled_dt, player.x, player.y)
```

### Y-Sorting (Topdown)

Entities sorted by **foot_collider bottom edge**:

```lua
-- Player
player.y_sort = foot_collider:getY() + (collider_height * 0.1875) / 2

-- Humanoid enemy
enemy.y_sort = foot_collider:getY() + (collider_height * 0.125) / 2

-- Slime enemy
enemy.y_sort = foot_collider:getY() + (collider_height * 0.6) / 2
```

Trees tiles from Tiled map are also Y-sorted.

**Platformer:** No Y-sorting, Trees layer drawn normally.

---

## Web Development

### Building for Web

The game uses **love.js** to compile to WebAssembly for browser deployment.

**Build Command:**
```bash
npm run build
```

This executes: `love.js -c -t "LÖVE2D RPG Game" -m 67108864 . web_build/game.data`

**Parameters:**
- `-c` - Compatibility mode (no SharedArrayBuffer)
- `-t` - Browser tab title
- `-m 67108864` - 64MB memory allocation

**Output:** `web_build/game.data` (contains all game files)

### Local Testing

**Option 1: Lua Server (Recommended)**
```bash
cd web_build
lua server.lua 8080
```

**Option 2: Node.js**
```bash
cd web_build
npx http-server -p 8080
```

**Access:** `http://localhost:8080` (use `localhost`, not `127.0.0.1`)

### Lua 5.1 Compatibility Rules

**Web builds use Lua 5.1 (not LuaJIT).** Follow these rules:

**Avoid:**
```lua
-- Lua 5.2+ goto (NOT SUPPORTED)
goto continue
::continue::

-- FFI module (LuaJIT only)
local ffi = require("ffi")

-- load() with string (Lua 5.2+)
local func = load("return " .. str)
```

**Use Instead:**
```lua
-- Nested conditionals instead of goto
if condition then
  -- process
end

-- Platform detection for FFI
local os = love.system.getOS()
if os == "Windows" or os == "Linux" or os == "OS X" then
  local ffi = require("ffi")
  -- use FFI
end

-- Compatible load
local func = (loadstring or load)("return " .. str)
```

### Web-Specific Code

**Platform Detection:**
```lua
local os = love.system.getOS()

if os == "Web" then
  -- Web-only code
  -- Example: Hide quit button
elseif os == "Android" or os == "iOS" then
  -- Mobile code
else
  -- Desktop code
end
```

**Example Usage:**
```lua
-- engine/scenes/builder.lua
local function onEnter(self, previous, ...)
  -- Filter out "Quit" on web
  local os = love.system.getOS()
  if os == "Web" and self.options then
    local filtered = {}
    for _, opt in ipairs(self.options) do
      if opt ~= "Quit" then
        table.insert(filtered, opt)
      end
    end
    self.options = filtered
  end
end
```

### Web Platform Limitations

**Browser Behavior:**
- **Tab blur:** Execution pauses when tab loses focus
  - BGM stops (auto-resumes on focus via `love.focus()`)
  - Weather effects pause
  - All timers/animations freeze
- **No quit:** `love.event.quit()` has no effect
- **Fullscreen:** Requires user gesture (button click)

**Storage:**
- Saves stored in browser IndexedDB (not files)
- Browser-specific (not portable)
- Cleared with browser data

**Performance:**
- 60 FPS cap (browser enforced)
- Memory limited (set in build command)
- No JIT compilation (Lua 5.1 interpreter)

### Deployment Checklist

**Pre-Deploy:**
- [ ] Test in multiple browsers (Chrome, Firefox, Safari)
- [ ] Test tab blur/focus behavior
- [ ] Test save/load in browser storage
- [ ] Check memory usage (browser dev tools)
- [ ] Verify all assets load correctly

**Web Server:**
- [ ] Set MIME types:
  - `.wasm` → `application/wasm`
  - `.data` → `application/octet-stream`
  - `.js` → `application/javascript`
- [ ] Enable gzip for `.data`, `.js`, `.wasm`
- [ ] Set appropriate CORS headers
- [ ] Configure cache headers for static assets

**Production:**
- [ ] Upload `web_build/` contents
- [ ] Test on actual hosting environment
- [ ] Monitor browser console for errors
- [ ] Test on mobile browsers (touch controls)

---

## Reference

For detailed API documentation, see:
- **[CLAUDE.md](../CLAUDE.md)** - Complete reference and instructions
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - File structure
- **[README.md](README.md)** - Quick start

For code examples, see:
- **[DEVELOPMENT_JOURNAL.md](../DEVELOPMENT_JOURNAL.md)** - Recent changes and patterns

---

**Last Updated:** 2025-11-17
**Engine Version:** 28_quest
**LÖVE Version:** 11.5
