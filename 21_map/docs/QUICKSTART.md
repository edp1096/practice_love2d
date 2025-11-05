# Quick Start Guide

Get started with this LÖVE2D game project in 5 minutes.

---

## 🚀 Running the Game

### Desktop
```bash
love .
```

### Build for Distribution
```bash
# Windows
zip -9 -r game.love .
cat love.exe game.love > mygame.exe

# macOS / Linux
zip -9 -r game.love .
```

---

## ⌨️ Controls

### Desktop Controls
- **WASD / Arrow Keys** - Move (Topdown) / Move left/right + Jump (Platformer)
- **Mouse** - Aim
- **Left Click / Z** - Attack
- **Right Click / X** - Parry
- **Shift / C** - Dodge
- **F** - Interact (NPCs, Save Points)
- **I** - Open Inventory
- **Q** - Use selected item
- **Tab** - Cycle items
- **1-5** - Quick select inventory slot
- **Escape** - Pause
- **F11** - Toggle Fullscreen
- **F1** - Toggle Debug Mode
- **F2** - Toggle Grid Visualization
- **F3** - Toggle Virtual Mouse

### Gamepad Controls
- **Left Stick / D-Pad** - Move / Aim
- **Right Stick** - Aim
- **A Button** - Attack / Interact
- **B Button** - Jump (Platformer only)
- **X Button** - Parry
- **Y Button** - (Reserved)
- **L1** - Use item
- **L2** - Next item
- **R1** - Dodge
- **R2** - Open/Close Inventory
- **Start** - Pause

### Mobile Controls (Touch)
- **Virtual Gamepad** - On-screen controls (same layout as physical gamepad)
- **Touch anywhere** - Navigate menus / Advance dialogue

---

## 📁 Project Structure

```
21_map/
├── engine/       - Reusable game engine (systems)
├── game/         - Game content (scenes, entities, data)
├── assets/       - Resources (maps, images, sounds)
├── lib/          - Library wrappers
├── vendor/       - External libraries
└── docs/         - Documentation
```

**Key Concept:**
- **engine/** = "How it works" (reusable)
- **game/** = "What it shows" (content)

---

## 🎮 First Steps

### 1. Explore the Game
- Start game with `love .`
- Try New Game → Create save slot
- Walk around with WASD
- Attack enemies with Left Click
- Find NPCs and press F to talk
- Find Save Points (glowing circles) and press F to save

### 2. Try Different Game Modes
- **Topdown mode** (level1/area1-3): Free 2D movement
- **Platformer mode** (level2/area1): Horizontal movement + jump

### 3. Test Combat
- Attack: Left Click / A button
- Parry: Right Click / X button (press RIGHT when enemy attacks for slow-motion)
- Dodge: Shift / R1 button (invincibility frames)

### 4. Inventory System
- Press I to open inventory
- Use items with Q / L1
- Cycle items with Tab / L2
- Quick-select with 1-5 keys

---

## 🛠️ Creating Content

### Add a New Enemy
1. Create sprite: `assets/images/enemies/yourenemy.png`
2. Create type: `game/entities/enemy/types/yourenemy.lua` (copy from `slime.lua`)
3. Open map in Tiled, add enemy object with `type = "yourenemy"`

### Add a New Item
1. Create icon: `assets/images/items/youritem.png`
2. Create type: `game/entities/item/types/youritem.lua` (copy from `small_potion.lua`)
3. Add to inventory in code: `inventory:addItem("youritem", 1)`

### Add a New Map
1. Create `.tmx` in Tiled: `assets/maps/level1/newarea.tmx`
2. Set map property: `game_mode = "topdown"` (or "platformer")
3. Export to Lua: `assets/maps/level1/newarea.lua`
4. Create portal object in previous map: `target_map = "assets/maps/level1/newarea.lua"`

### Add Background Music
1. Place file: `assets/bgm/yourmusic.ogg`
2. Register in `game/data/sounds.lua`:
   ```lua
   bgm = {
       yourmusic = { path = "assets/bgm/yourmusic.ogg", volume = 0.7, loop = true }
   }
   ```
3. Set in Tiled map property: `bgm = "yourmusic"`

---

## 📚 Documentation

- **[README.md](README.md)** - Documentation index
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - Full project structure
- **[ENGINE_GUIDE.md](ENGINE_GUIDE.md)** - Engine systems reference
- **[GAME_GUIDE.md](GAME_GUIDE.md)** - Content creation guide
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development workflows

---

## 🐛 Troubleshooting

### Game won't start
- Check `love --version` (need LÖVE 11.5)
- Check `lua -v` (need Lua 5.1 compatible)
- Look for errors in console

### Files not found errors
- Check all `require` paths use dots: `require "engine.sound"`
- Check file paths use forward slashes: `"assets/maps/level1/area1.lua"`

### No sound
- Check `config.ini` has non-zero volumes
- Check sound files exist in `assets/bgm/` and `assets/sound/`
- Check sound definitions in `game/data/sounds.lua`

### Map won't load
- Check Tiled map is exported to Lua format (`.lua` file)
- Check map has required layers (Ground, Walls, etc.)
- Check map property `game_mode` is set

---

## 🎯 Next Steps

1. Read **[GAME_GUIDE.md](GAME_GUIDE.md)** to learn content creation
2. Read **[ENGINE_GUIDE.md](ENGINE_GUIDE.md)** to understand engine systems
3. Explore `game/` folder to see examples
4. Try modifying existing content
5. Create your own levels and characters!

---

**Need help?** Check the full documentation in `docs/` folder.
