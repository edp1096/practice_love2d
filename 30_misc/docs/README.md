# LÖVE2D Game Engine - Quick Start

A LÖVE2D game engine with clean **Engine/Game separation** architecture.

---

## Philosophy

### Engine
- `engine/` - Reusable systems and entities
- Core: lifecycle, input, display, sound, save, camera, quest, inventory
- Systems: world (physics), effects, lighting, parallax, HUD, collision
- Entities: player, enemy, weapon, NPC, item, healing_point
- UI: menu, dialogue, screens, widgets

### Game
- `game/data/` - Configuration files (player, quests, scenes, entities, sounds)
- `game/scenes/` - Menu scenes, UI screens

---

## Quick Start

### Installation
1. Install LÖVE 11.5: https://love2d.org/
2. Run: `love .`

### Controls
**Desktop:**
- **WASD / Arrows** - Move / Jump
- **Mouse** - Aim
- **Left Click / Z** - Attack
- **Right Click / X** - Parry (perfect timing = slow-motion)
- **Shift / C** - Dodge
- **F** - Interact (NPCs, Save Points, Items)
- **I / J** - Inventory / Quest Log
- **Q / E** - Switch tabs
- **Q** - Use item (gameplay)
- **Tab** - Cycle items
- **1-5** - Quick select
- **ESC** - Pause / Close
- **F11** - Fullscreen

**Gamepad (Xbox / PlayStation):**
- **Left Stick / D-Pad** - Move
- **Right Stick** - Aim / Scroll
- **A / Cross (✕)** - Attack / Interact
- **B / Circle (○)** - Jump / Skip / Close
- **X / Square (□)** - Parry
- **Y / Triangle (△)** - Interact
- **LB / L1** - Previous tab
- **LT / L2** - Previous item
- **RB / R1** - Next tab / Dodge
- **RT / R2** - Inventory / Quest Log
- **Start** - Pause

**Debug (if `APP_CONFIG.is_debug = true`):**
- **F1** - Toggle debug mode
- **F2** - Colliders/Grid | **F3** - FPS/Effects | **F4** - Player Info | **F5** - Screen Info
- **F6** - Quest Debug | **F7** - Hot Reload | **F8** - Test Effects
- **F9** - Virtual Mouse | **F10** - Virtual Gamepad | **F11** - Fullscreen

---

## First Steps

1. **Start game**: `love .`
2. **New Game** → Create save slot
3. **Move** with WASD, **Attack** with Left Click
4. **Talk to NPCs** (F key), **Save** at glowing circles
5. **Inventory** (I), **Quest Log** (J)

### Game Modes
- **Topdown** (level1): Free 2D movement, no gravity
- **Platformer** (level2): Horizontal + jump, gravity

### Map Properties
- **`move_mode`**: `"walk"` for indoor maps (slower speed, walk animation)

### Stairs (Topdown Only)
**Visual elevation effect** - player visually moves up/down on stairs (no physics change).

**Tiled Setup:**
1. Create "Stairs" layer (Object Layer)
2. Draw **polygon** shape for diagonal stair area (recommended)
3. Direction auto-detected from polygon shape

**hill_direction values:**
- **`left`**: Moving left = uphill (45° diagonal), right = downhill
- **`right`**: Moving right = uphill (45° diagonal), left = downhill
- **`up`**: Moving up = 30% slower (horizontal unchanged)
- **`down`**: Moving down = 30% slower (horizontal unchanged)

**Guardrails:** Player can only exit from stair ends (top/bottom), not sides.

**Debug:** F2 shows stair polygons (orange) with direction arrows, F4 shows "Stair: X.X" offset.

---

## Creating Content

### Add Enemy
1. Open map: `assets/maps/level1/area1.tmx`
2. Add object to "Enemies" layer, set type: `slime`
3. Add custom properties: `hp`, `dmg`, `spd`, `det_rng`
4. Export to Lua

Or add to `game/data/entities/types.lua` for reusable enemy types.

### Add Menu
1. Add to `game/data/scenes.lua`:
```lua
scenes.mymenu = {
  type = "menu",
  title = "My Menu",
  options = {"Play", "Quit"},
  actions = {
    ["Play"] = {action = "switch_scene", scene = "play"},
    ["Quit"] = {action = "quit"}
  },
  back_action = {action = "quit"}
}
```

2. Create `game/scenes/mymenu.lua`:
```lua
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("mymenu", configs)
```

### Add Item
1. Icon: `assets/images/items/myitem.png`
2. Type: `engine/entities/item/types/myitem.lua`:
```lua
return {
  name = "My Item",
  description = "Useful item",
  icon = "assets/images/items/myitem.png",
  consumable = true,
  effect = function(player)
    player.health = math.min(player.health + 50, player.max_health)
  end
}
```

### Add Map
1. Create in Tiled: `assets/maps/level1/newarea.tmx`
2. Set properties: `name`, `game_mode`, `bgm`, `ambient`
3. Add layers: Ground, Decos, Walls, Portals, Enemies, NPCs, Props
4. Export to Lua
5. Create portal from previous map

### Add Props (Movable/Breakable Objects)
**Tiled Setup:**
1. Create "Props" layer (Object Layer)
2. Add tile objects for visuals (share same `group` property)
3. Add invisible rectangle with `type = "collider"` and same `group`

**Collider Properties:**
- `group` - Links tiles and collider (e.g., "crate1")
- `type = "collider"` - Marks as physics collider
- `movable = true` - Can be pushed by player
- `breakable = true` - Can be destroyed by attacks
- `hp = 10` - Health points (breakable only)
- `respawn = true` - Respawns on map transition (default: false)

**Example (2-tile tall teddy bear):**
```
Tile Object 1: gid=136, group="teddybear1"
Tile Object 2: gid=152, group="teddybear1"
Collider: type="collider", group="teddybear1", movable=true, breakable=true, hp=30
```

### Add Dialogue
**Simple:** Set NPC property `dlg = "Hello!"`

**Tree (choices):** Create in `game/data/dialogues.lua`:
```lua
dialogues.shopkeeper = {
  start_node = "greeting",
  nodes = {
    greeting = {
      text = "Welcome!",
      choices = {
        { text = "Shop", next = "shop" },
        { text = "Bye", next = "end" }
      }
    }
  }
}
```

### Add Shop
1. Add to `game/data/shops.lua`:
```lua
shops.general_store = {
  name = "General Store",
  name_key = "shops.general_store.name",  -- i18n key
  items = {
    { type = "small_potion", price = 30, stock = 10 },
    { type = "large_potion", price = 80, stock = 5 }
  },
  sell_rate = 0.5  -- 50% of buy price
}
```

2. Open shop from dialogue using `open_shop` action:
```lua
nodes = {
  shop = {
    text = "Take a look!",
    actions = { { type = "open_shop", shop_id = "general_store" } }
  }
}
```

**Shop UI Controls:**
- **Tab / LB/RB** - Switch Buy/Sell tabs
- **Up/Down** - Select item
- **Enter/A** - Open quantity dialog
- **Left/Right** - Adjust quantity (±1)
- **Up/Down** - Adjust quantity (±10)
- **ESC/B** - Close

---

## Localization (i18n)

### Adding Translations
1. Create locale file: `game/data/locales/xx.lua` (e.g., `ko.lua`, `ja.lua`)
2. Add to `game/setup.lua`:
```lua
available_locales = { "en", "ko", "ja" },
default_locale = "en",
font_scales = {
    en = 1.0,
    ko = 0.55,  -- Korean font needs smaller scale
    ja = 0.8
}
```

### Translation Keys
- **Items:** `items.small_potion.name`, `items.small_potion.description`
- **Quests:** `quests.quest_id.name`, `quests.quest_id.description`
- **Shops:** `shops.general_store.name`
- **UI:** `inventory.title`, `quest.title`, `shop.buy`, `shop.sell`

### Item Translation Example
1. Define item with `name_key`:
```lua
-- engine/entities/item/types/small_potion.lua
return {
    name = "Small Potion",
    name_key = "items.small_potion.name",
    description_key = "items.small_potion.description",
    ...
}
```

2. Add translations:
```lua
-- game/data/locales/ko.lua
return {
    items = {
        small_potion = {
            name = "소형 포션",
            description = "체력을 30 회복합니다"
        }
    }
}
```

---

## Documentation

- **[CLAUDE.md](../CLAUDE.md)** - Complete API reference and instructions
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - Detailed folder structure
- **[DEVELOPMENT_JOURNAL.md](../DEVELOPMENT_JOURNAL.md)** - Current state summary

---

## Troubleshooting

### Game won't start
- Check LÖVE version: `love --version` (need 11.5)
- Check console for errors

### Files not found
- Use dots in require: `require "engine.core.sound"`
- Use slashes in paths: `"assets/maps/level1/area1.lua"`

### Map won't load
- Export to Lua format (`.lua`)
- Check required layers exist (Ground, Walls)
- Check map properties: `game_mode`, `name`

### Items/enemies respawn
- Set `respawn = false` in Tiled object properties

---

## Web Build

```bash
npm install -g love.js
npm run build
cd web_build && lua server.lua 8080
```

Open: `http://localhost:8080`

---

**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Engine/Game Separation + Data-Driven
**Last Updated:** 2025-12-03
