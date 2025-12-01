# How to Create a New Game

A step-by-step guide to making your own game using this engine.

---

## Prerequisites

- LÖVE 11.5 installed
- Tiled Map Editor for creating maps
- Basic Lua knowledge

---

## Step 1: Copy the Engine

```bash
# Copy the entire project folder
cp -r 28_quest my_new_game
cd my_new_game
```

The `engine/` folder is 100% reusable - don't modify it.

---

## Step 2: Customize Game Data

Edit files in `game/data/`:

### `game/data/player.lua` (Player Stats)
```lua
return {
    max_health = 100,
    base_damage = 10,
    move_speed = 200,
    -- ... customize stats
}
```

### `game/data/entities/types.lua` (Enemies/NPCs)
```lua
enemies.goblin = {
    name = "Goblin",
    hp = 50,
    dmg = 15,
    spd = 80,
    spr = "assets/images/goblin-sheet.png",
    -- ... add more enemies
}
```

### `game/data/quests.lua` (Quests)
```lua
quests.my_first_quest = {
    id = "my_first_quest",
    title = "Kill 5 Goblins",
    objectives = {
        { type = "kill", target = "goblin", count = 5 }
    },
    giver_npc = "village_elder",
    rewards = { gold = 100, exp = 50 }
}
```

### `game/data/dialogues.lua` (Dialogue Trees)
```lua
dialogues.village_elder = {
    start_node = "greeting",
    nodes = {
        greeting = {
            text = "Welcome, traveler!",
            choices = {
                { text = "Do you have quests?", next = "quest_offer" },
                { text = "Goodbye", next = "end" }
            }
        }
    }
}
```

### `game/data/scenes.lua` (Menu Configuration)
```lua
scenes.menu = {
    title = "My New Game",
    options = {
        { text = "New Game", action = "new_game" },
        { text = "Continue", action = "load_recent_save" },
        { text = "Quit", action = "quit" }
    }
}
```

---

## Step 3: Update Game Scenes

Scenes are just 6 lines each - copy and rename:

```lua
-- game/scenes/menu.lua
local builder = require "engine.scenes.builder"
local scene_configs = require "game.data.scenes"
return builder:build("menu", scene_configs)
```

---

## Step 4: Prepare Assets

### `assets/` folder structure:
```
assets/
├── images/
│   ├── goblin-sheet.png  (enemy sprite)
│   ├── player-sheet.png  (player sprite)
│   └── items/            (item icons)
├── maps/
│   └── level1/
│       └── area1.tmx     (Tiled map)
└── sounds/
    ├── bgm/              (background music)
    └── sfx/              (sound effects)
```

### Create Maps in Tiled:
1. Open Tiled and create a new map
2. Add layers: `Ground`, `Decos`, `Walls`, `Portals`, `Enemies`, `NPCs`
3. Set map properties:
   - `game_mode` = `"topdown"` or `"platformer"`
   - `bgm` = `"level1"` (optional)
   - `move_mode` = `"walk"` (optional, for indoor maps - slower walk speed)
4. Export as Lua (not TMX)

---

## Step 5: Configure Setup

Edit `game/setup.lua` to inject your data:

```lua
-- Loads automatically - just check that all data files are imported:
local entity_types = require "game.data.entities.types"
local quests = require "game.data.quests"
local dialogues = require "game.data.dialogues"
-- ...
```

---

## Step 6: Run Your Game

```bash
love .
```

Controls:
- WASD - Move
- Mouse - Aim
- Left Click - Attack
- F - Interact

---

## Quick Checklist

```
[ ] Copy engine folder
[ ] Edit game/data/player.lua
[ ] Edit game/data/entities/types.lua (enemies/NPCs)
[ ] Edit game/data/quests.lua
[ ] Edit game/data/dialogues.lua
[ ] Edit game/data/scenes.lua
[ ] Create maps in Tiled (export as .lua)
[ ] Add assets (sprites, sounds)
[ ] Run: love .
```

---

## Tips

**Add a new enemy (No code required):**
1. Create sprite: `assets/images/enemies/yourenemy.png`
2. Add to Tiled map (Object with `type = "yourenemy"`)
3. Set custom properties: `hp`, `dmg`, `spd`, `spr`

**Add a new quest:**
1. Add to `game/data/quests.lua`
2. Add dialogue choice in `game/data/dialogues.lua`

**Add a new item:**
1. Create icon: `assets/images/items/youritem.png`
2. Add to `game/data/items/consumables/youritem.lua`
3. Define `name`, `description`, `use()` function

**Add a weapon variant (e.g., stronger version):**
1. Add to `game/data/items/weapons/yourweapon.lua`
2. Set `weapon_type` (sword/axe/club/staff)
3. Set `stats` multipliers (damage: additive, range/speed: multiplicative)
4. Register in `game/data/items/init.lua`

---

## More Info

- Full Structure: See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)
- Complete Guide: See [GUIDE.md](GUIDE.md)
- Quick Start: See [README.md](README.md)

---

That's it. You now have a working game engine.

---

**Last Updated:** 2025-11-26
**Architecture:** Engine/Game Separation + Dependency Injection
**Version:** LÖVE 11.5, Lua 5.1
