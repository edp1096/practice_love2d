# Development Guide

This guide covers development workflows and best practices for this project.

---

## 🏗️ Architecture Principles

### 1. Engine/Game Separation
**Goal:** Engine is reusable, game is content.

**Rules:**
- ✅ Engine files should NOT import game files
- ✅ Game files CAN import engine files
- ✅ Engine should be generic and configurable
- ✅ Game should be data-driven

**Example:**
```lua
-- ❌ BAD: Engine depends on game content
-- engine/sound.lua
local game_sounds = require "game.data.sounds"  -- NO!

-- ✅ GOOD: Game passes data to engine
-- game/scenes/menu.lua
local sound = require "engine.sound"
local sounds_config = require "game.data.sounds"
sound:init(sounds_config)  -- Pass config to engine
```

### 2. Modular Architecture
**Goal:** Each file has a single responsibility.

**When to split a file:**
- File exceeds 500 lines
- File has multiple unrelated responsibilities
- File is hard to navigate

**Modular Scene Pattern:**
```
game/scenes/yourscene/
├── init.lua          - Coordinator (enter, exit, update, draw)
├── input.lua         - Input handling only
├── render.lua        - Drawing logic only
└── logic.lua         - Business logic only
```

### 3. Data-Driven Design
**Goal:** Minimize code in game/, maximize data.

**Prefer data over code:**
```lua
-- ❌ BAD: Hardcoded in scene
function menu:enter()
    self.options = {"New Game", "Load", "Quit"}
    self.title = "My Game"
end

-- ✅ GOOD: Data-driven
-- game/data/menu_config.lua
return {
    title = "My Game",
    options = {"New Game", "Load", "Quit"}
}

-- game/scenes/menu.lua
local menu_config = require "game.data.menu_config"
function menu:enter()
    self.options = menu_config.options
    self.title = menu_config.title
end
```

---

## 🛠️ Development Workflows

### Adding a New Engine System

1. **Create system file:**
   ```lua
   -- engine/yoursystem.lua
   local yoursystem = {}

   function yoursystem:init(config)
       -- Initialize with config
   end

   function yoursystem:update(dt)
       -- Update logic
   end

   return yoursystem
   ```

2. **Add to engine utilities:**
   - Keep it generic (no game-specific code)
   - Accept config from game layer
   - Follow existing system patterns

3. **Document in ENGINE_GUIDE.md**

### Adding a New Game Scene

1. **Create scene structure:**
   ```bash
   mkdir -p game/scenes/yourscene
   touch game/scenes/yourscene/init.lua
   touch game/scenes/yourscene/input.lua
   touch game/scenes/yourscene/render.lua
   ```

2. **Implement scene lifecycle:**
   ```lua
   -- game/scenes/yourscene/init.lua
   local yourscene = {}

   function yourscene:enter(previous, ...) end
   function yourscene:exit() end
   function yourscene:update(dt) end
   function yourscene:draw() end
   function yourscene:keypressed(key) end

   return yourscene
   ```

3. **Connect to scene control:**
   ```lua
   local scene_control = require "engine.scene_control"
   local yourscene = require "game.scenes.yourscene"
   scene_control.switch(yourscene)
   ```

### Adding a New Entity Type

1. **Create entity definition:**
   ```lua
   -- game/entities/enemy/types/yourenemy.lua
   return {
       name = "Your Enemy",
       max_health = 100,
       damage = 20,
       speed = 150,
       sprite_path = "assets/images/enemies/yourenemy.png",
       -- ... more properties
   }
   ```

2. **Add sprite to assets:**
   ```
   assets/images/enemies/yourenemy.png
   ```

3. **Place in Tiled map:**
   - Create object in Enemies layer
   - Set property: `type = "yourenemy"`

### Adding Sound Effects

1. **Add audio file:**
   ```
   assets/sound/category/soundname.wav
   ```

2. **Register in sounds config:**
   ```lua
   -- game/data/sounds.lua
   sfx = {
       category = {
           soundname = {
               path = "assets/sound/category/soundname.wav",
               volume = 0.8,
               pitch_variation = "normal"
           }
       }
   }
   ```

3. **Play in game:**
   ```lua
   local sound = require "engine.sound"
   sound:playSFX("category", "soundname")
   ```

---

## 🎨 Code Style

### Naming Conventions
```lua
-- Modules: lowercase with underscores
local scene_control = require "engine.scene_control"

-- Classes/Objects: PascalCase (rare in Lua)
local Player = require "game.entities.player"

-- Functions: camelCase
function player:updateAnimation(dt)

-- Constants: UPPER_CASE
local MAX_HEALTH = 100

-- Private functions: prefix with underscore
local function _internalHelper()
```

### File Organization
```lua
-- 1. Module declaration
local mymodule = {}

-- 2. Requires
local engine_system = require "engine.something"
local game_data = require "game.data.something"

-- 3. Local constants
local MAX_ITEMS = 10

-- 4. Local functions
local function _helper()
end

-- 5. Public functions
function mymodule:publicMethod()
end

-- 6. Return module
return mymodule
```

### Comments
```lua
-- Single-line comments for brief explanations

--[[
Multi-line comments for:
- Complex logic explanations
- API documentation
- TODOs
]]

--- Documentation comments (LDoc style)
--- @param player table The player entity
--- @return boolean Success status
function combat:attack(player)
end
```

---

## 🐛 Debugging

### Debug Mode (F1)
- Toggle with F1 key (unified info window + hitboxes)
- F2: Toggle grid visualization
- F3: Toggle virtual mouse
- Shows FPS, player state, screen info
- Visualizes hitboxes and collision areas

### Print Debugging

**Conditional Debug Print (dprint):**
```lua
-- Use dprint() for debug messages (only prints when F1 debug mode is enabled)
dprint("Player HP:", player.health)
dprint("Enemy spawned at:", x, y)

-- Use print() for critical errors/warnings (always prints)
print("ERROR: Failed to load map")
print("Warning: Missing texture")
```

**When to use each:**
- `dprint()`: Debug info, state changes, verbose logging
- `print()`: Errors, warnings, critical messages

**Format complex tables:**
```lua
local inspect = require "vendor.inspect"  -- (if available)
dprint(inspect(player))
```

### Error Handling
```lua
-- Use pcall for risky operations
local success, result = pcall(function()
    return require "game.optional.module"
end)

if not success then
    print("Warning: Optional module not found")
    result = nil
end
```

### Common Issues

**Issue: File not found**
```
Solution: Check require path uses dots, not slashes
✅ require "game.scenes.menu"
❌ require "game/scenes/menu"
```

**Issue: Nil value errors**
```
Solution: Check if module exists before using
local module = require "engine.something"
if not module then return end
module:doSomething()
```

**Issue: Physics behaving strangely**
```
Solution: Check game_mode in map properties
Topdown: no gravity
Platformer: gravity enabled
```

---

## 🧪 Testing

### Manual Testing Checklist
- [ ] Game starts without errors
- [ ] All scenes accessible (menu, play, settings, etc.)
- [ ] Keyboard controls work
- [ ] Gamepad controls work (if available)
- [ ] Touch controls work (mobile/virtual gamepad)
- [ ] Sound plays correctly (BGM, SFX)
- [ ] Save/Load works
- [ ] Inventory system works
- [ ] Combat system works (attack, parry, dodge)
- [ ] Map transitions work
- [ ] NPCs and dialogue work
- [ ] Game modes work (topdown, platformer)

### Performance Testing
```lua
-- Check FPS in debug mode (F1)
-- Monitor memory usage
-- Profile with LuaJIT profiler (if needed)
```

---

## 📦 Building & Distribution

### Create .love file
```bash
# Exclude unnecessary files
zip -9 -r game.love . -x "*.git*" "*.md" "docs/*" ".vscode/*"
```

### Windows
```bash
# Concatenate LÖVE with game
cat love.exe game.love > mygame.exe
```

### macOS
```bash
# Replace love.app contents
cp -r game.love MyGame.app/Contents/Resources/
```

### Linux
```bash
# AppImage or package .love file
# Users run with: love game.love
```

### Mobile (Android)
```bash
# Use love-android-sdl2
# Package .love into APK
```

---

## 🔄 Version Control

### Git Workflow
```bash
# Ignore unnecessary files
echo "config.ini" >> .gitignore
echo "*.log" >> .gitignore
echo ".DS_Store" >> .gitignore

# Commit structure changes
git add engine/ game/
git commit -m "Refactor: Separate engine and game folders"

# Commit content changes
git add game/entities/enemy/types/newenemy.lua
git commit -m "Add new enemy: Dragon"
```

### Branching Strategy
```
main          - Stable releases
develop       - Development branch
feature/X     - New features
bugfix/X      - Bug fixes
```

---

## 📝 Documentation

### Keep Docs Updated
- Update **ENGINE_GUIDE.md** when adding engine systems
- Update **GAME_GUIDE.md** when adding content workflows
- Update **PROJECT_STRUCTURE.md** when restructuring

### Comment Complex Code
```lua
-- Explain WHY, not WHAT
-- ❌ BAD: "Set player speed to 200"
player.speed = 200

-- ✅ GOOD: "Faster speed in platformer mode for responsive controls"
player.speed = (game_mode == "platformer") and 200 or 150
```

---

## 🚀 Performance Tips

### Avoid in Hot Paths
```lua
-- ❌ BAD: Creating tables every frame
function update(dt)
    local pos = {x = player.x, y = player.y}  -- Creates garbage
end

-- ✅ GOOD: Reuse tables
local temp_pos = {x = 0, y = 0}
function update(dt)
    temp_pos.x = player.x
    temp_pos.y = player.y
end
```

### Lazy Loading
```lua
-- Load resources on-demand, not all at startup
-- Engine already does this for sounds
```

### Profiling
```lua
-- Measure expensive operations
local start = love.timer.getTime()
expensiveOperation()
print("Took:", love.timer.getTime() - start)
```

---

## 🎯 Next Steps

1. Read existing code in `engine/` and `game/`
2. Try modifying simple things (enemy stats, sounds)
3. Create a new scene or entity
4. Contribute improvements to engine
5. Build your own game on this engine!

---

**See also:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - Engine API reference
- [GAME_GUIDE.md](GAME_GUIDE.md) - Content creation
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Full structure
