# Game Content Creation Guide

This guide shows how to create game content in the `game/` folder - **RPG Maker style**.

---

## 🎯 Philosophy: Content Over Code

The `game/` folder is designed for **content creation**, not engine programming:
- **Minimal code** - mostly data definitions
- **Simple APIs** - call engine functions
- **Quick iteration** - change content without touching engine

---

## 🎬 Creating Scenes

### Scene Structure
Scenes go in `game/scenes/`. Simple scenes can be single files, complex scenes should be modular folders.

**Single File Scene Example:**
```lua
-- game/scenes/credits.lua
local credits = {}

local scene_control = require "engine.scene_control"
local screen = require "lib.screen"

function credits:enter(previous, ...)
    self.text = "Thanks for playing!"
end

function credits:update(dt)
    -- Update logic
end

function credits:draw()
    love.graphics.print(self.text, 100, 100)
end

function credits:keypressed(key)
    if key == "escape" then
        local menu = require "game.scenes.menu"
        scene_control.switch(menu)
    end
end

return credits
```

**Modular Scene Example:**
```
game/scenes/shop/
├── init.lua          - Scene coordinator
├── items.lua         - Shop item definitions
├── render.lua        - UI rendering
└── input.lua         - Input handling
```

### Using Engine Systems in Scenes
```lua
-- game/scenes/yourscene.lua
local scene_control = require "engine.scene_control"
local sound = require "engine.sound"
local input = require "engine.input"
local save_sys = require "engine.save"

function yourscene:enter()
    sound:playBGM("menu", 1.0, true)  -- Play menu music
end

function yourscene:keypressed(key)
    if input:wasPressed("confirm") then
        sound:playSFX("ui", "select")
        -- Do something
    end
end
```

---

## 🎮 Creating Entities

### Enemy Type Example
```lua
-- game/entities/enemy/types/goblin.lua
return {
    -- Stats
    name = "Goblin",
    max_health = 50,
    damage = 10,
    speed = 120,

    -- Visuals
    sprite_path = "assets/images/enemies/goblin.png",
    sprite_width = 32,
    sprite_height = 32,
    collider_width = 28,
    collider_height = 28,

    -- AI
    ai_type = "aggressive",
    chase_range = 200,
    attack_range = 40,
    patrol_speed = 60,

    -- Animation
    animations = {
        idle = { frames = "1-4", fps = 8 },
        walk = { frames = "5-8", fps = 12 },
        attack = { frames = "9-12", fps = 16 }
    },

    -- Sounds
    sounds = {
        hurt = "enemy_hurt",
        death = "enemy_death",
        attack = "enemy_attack"
    }
}
```

### NPC Type Example
```lua
-- game/entities/npc/types/shopkeeper.lua
return {
    name = "Shopkeeper",
    sprite_path = "assets/images/npcs/shopkeeper.png",

    -- Dialogue
    dialogue = {
        "Welcome to my shop!",
        "What can I get you today?",
        "Come back soon!"
    },

    -- Interaction
    on_interact = function(player, npc)
        local dialogue = require "engine.dialogue"
        dialogue:show(npc.config.dialogue, npc.avatar)
    end
}
```

### Item Type Example
```lua
-- game/entities/item/types/mega_potion.lua
return {
    id = "mega_potion",
    name = "Mega Potion",
    description = "Restores 100 HP",
    icon = "assets/images/items/mega_potion.png",
    max_stack = 50,

    use = function(player)
        local sound = require "engine.sound"

        if player.health < player.max_health then
            player.health = math.min(player.health + 100, player.max_health)
            sound:playSFX("player", "heal")
            return true  -- Item consumed
        else
            sound:playSFX("ui", "error")
            return false  -- Item not consumed
        end
    end
}
```

---

## 🎵 Adding Sounds

### 1. Add Audio Files
Place files in `assets/bgm/` or `assets/sound/`:
```
assets/
├── bgm/
│   └── dungeon.ogg
└── sound/
    ├── player/
    │   └── magic_cast.wav
    └── ui/
        └── coin.wav
```

### 2. Register in Sound Config
Edit `game/data/sounds.lua`:
```lua
return {
    bgm = {
        dungeon = {
            path = "assets/bgm/dungeon.ogg",
            volume = 0.7,
            loop = true
        }
    },

    sfx = {
        player = {
            magic_cast = {
                path = "assets/sound/player/magic_cast.wav",
                volume = 0.8,
                pitch_variation = "normal"
            }
        },
        ui = {
            coin = {
                path = "assets/sound/ui/coin.wav",
                volume = 0.9
            }
        }
    }
}
```

### 3. Play in Game
```lua
local sound = require "engine.sound"
sound:playBGM("dungeon")              -- Play dungeon BGM
sound:playSFX("player", "magic_cast") -- Play magic cast sound
sound:playSFX("ui", "coin")           -- Play coin sound
```

---

## 🗺️ Creating Maps

### 1. Create Map in Tiled
- Use Tiled Map Editor to create `.tmx` file
- Place in `assets/maps/levelX/`
- Export to Lua format (`.lua` file)

### 2. Set Map Properties
In Tiled, set map custom properties:
```
Map Properties:
  game_mode = "topdown"  (or "platformer")
  bgm = "dungeon"        (optional - BGM name from sounds.lua)
```

### 3. Map Layers
Required layers:
- **Ground** - Terrain layer
- **Trees** - Top decoration (drawn after entities)
- **Walls** - Collision objects (rectangles, polygons)
- **Portals** - Transition zones
- **Enemies** - Enemy spawn points
- **NPCs** - NPC locations
- **SavePoints** - Save point locations
- **HealingPoints** - Healing areas

### 4. Add Portals
Create object in **Portals** layer:
```
Object Properties:
  type = "portal"
  target_map = "assets/maps/level1/area2.lua"
  spawn_x = 100
  spawn_y = 200
```

### 5. Add Enemies
Create object in **Enemies** layer:
```
Object Properties:
  type = "goblin"  (matches filename in game/entities/enemy/types/)
  patrol_points = "100,200;300,200;300,400"  (optional)
```

### 6. Load Map in Game
```lua
-- In your scene
local world = require "engine.world"
self.world = world:new("assets/maps/level1/dungeon.lua")
```

---

## ⌨️ Configuring Input

### Edit Input Config
Edit `game/data/input_config.lua`:
```lua
return {
    actions = {
        -- Movement
        move_left = {
            keys = {"a", "left"},
            gamepad = {"dpleft"}
        },
        move_right = {
            keys = {"d", "right"},
            gamepad = {"dpright"}
        },

        -- Combat
        attack = {
            mouse = {1},  -- Left mouse button
            gamepad = {"a"}
        },
        special_attack = {
            mouse = {2},  -- Right mouse button
            gamepad = {"x"},
            keys = {"e"}
        },

        -- Custom action
        magic = {
            keys = {"q"},
            gamepad = {"y"}
        }
    },

    -- Mode-specific overrides
    mode_overrides = {
        platformer = {
            jump = { keys = {"w", "up", "space"}, gamepad = {"b"} }
        }
    }
}
```

### Use in Game
```lua
local input = require "engine.input"

function play:update(dt)
    if input:wasPressed("magic") then
        -- Cast magic spell
    end

    if input:isDown("attack") then
        -- Charge attack
    end
end
```

---

## 🎞️ Creating Cutscenes

### 1. Define Cutscene
Edit `game/data/intro_configs.lua`:
```lua
return {
    chapter1_intro = {
        background = "assets/images/cutscenes/chapter1_bg.png",
        bgm = "dramatic",
        messages = {
            "Long ago, in a distant land...",
            "A great evil awakened...",
            "Only one hero can stop it..."
        },
        speaker = "Narrator"
    }
}
```

### 2. Trigger Cutscene
```lua
local scene_control = require "engine.scene_control"
local intro = require "game.scenes.intro"

-- Show intro, then go to play scene
scene_control.switch(
    intro,
    "chapter1_intro",                    -- Intro ID
    "assets/maps/level1/area1.lua",      -- Target map after intro
    400, 250,                             -- Spawn position
    1                                     -- Save slot
)
```

---

## 💾 Using Save System

### Save Game
```lua
local save_sys = require "engine.save"

function play:saveGame()
    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y,
        inventory = self.inventory:save()
    }

    save_sys:saveGame(self.current_save_slot, save_data)
end
```

### Load Game
```lua
local save_sys = require "engine.save"

function menu:loadGame(slot)
    local save_data = save_sys:loadGame(slot)

    if save_data then
        local play = require "game.scenes.play"
        scene_control.switch(play, save_data.map, save_data.x, save_data.y, slot)
    end
end
```

---

## 🎨 Customizing HUD

The HUD is rendered by `engine/hud.lua`, but you can customize colors/layout:

```lua
-- In your play scene
local hud = require "engine.hud"

function play:draw()
    -- ... draw game world ...

    -- Draw HUD with custom colors
    love.graphics.setColor(1, 1, 1)
    hud:draw(self.player, self.inventory)
end
```

For major HUD changes, consider creating a custom HUD in `game/` that calls engine functions.

---

## 🚀 Quick Recipes

### Add a New Level
1. Create map in Tiled: `assets/maps/level2/castle.tmx`
2. Export to Lua: `assets/maps/level2/castle.lua`
3. Add BGM: `game/data/sounds.lua` → `bgm.castle = { ... }`
4. Set map property: `bgm = "castle"`
5. Create portal to it from previous level

### Add a New Enemy
1. Create sprite: `assets/images/enemies/dragon.png`
2. Create type: `game/entities/enemy/types/dragon.lua`
3. Place in Tiled map: Object type = "dragon"

### Add a New Item
1. Create icon: `assets/images/items/sword.png`
2. Create type: `game/entities/item/types/sword.lua`
3. Add to inventory: `inventory:addItem("sword", 1)`

### Add a New Menu
1. Create scene: `game/scenes/credits.lua`
2. Add to main menu options: `{ "Credits", ... }`
3. Switch to it: `scene_control.switch(credits)`

---

## 📋 Checklist: New Game from Engine

Starting a new game using this engine:

1. ✅ Copy `engine/` folder
2. ✅ Delete `game/` folder
3. ✅ Create new `game/` with:
   - `game/scenes/` - Your game scenes
   - `game/entities/` - Your characters
   - `game/data/` - Your configs
4. ✅ Create `assets/` with your resources
5. ✅ Update `conf.lua` with your game title
6. ✅ Update `main.lua` to load your first scene
7. ✅ Start creating content!

---

**See also:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - Engine systems reference
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Full structure
