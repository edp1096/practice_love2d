# LÖVE2D Game Engine

A LÖVE2D game project with a clean **Engine/Game separation architecture**.

---

## 🎯 Project Philosophy

This project follows a **modular architecture**:

### **Engine (Reusable)**
The `engine/` folder contains generic, reusable game systems that can be used in any LÖVE2D project:
- Physics & collision system
- Input handling (keyboard, gamepad, touch)
- Audio management (BGM, SFX)
- Save/Load system
- Scene management
- UI rendering (HUD, minimap, dialogue)
- Visual effects (particles, lighting, screen effects)

### **Game (Content)**
The `game/` folder contains game-specific content:
- Scenes (menus, gameplay, settings)
- Entities (player, enemies, NPCs, items)
- Data (sound definitions, input configs, intro cutscenes)

### **Benefits**
- **Easy to create new games**: Copy `engine/` folder, create new `game/` content
- **Clean separation**: Engine code vs Game content
- **Easy maintenance**: Find files quickly with clear structure
- **Content-focused workflow**: Focus on game content, not engine code

---

## 🚀 Quick Start

### Running the Game

**Desktop:**
```bash
love .
```

**Build for Distribution:**
```bash
# Windows
zip -9 -r game.love .
cat love.exe game.love > mygame.exe

# macOS / Linux
zip -9 -r game.love .
```

### Controls

**Desktop:**
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

**Gamepad:**
- **Left Stick / D-Pad** - Move / Aim
- **Right Stick** - Aim
- **A Button** - Attack / Interact
- **B Button** - Jump (Platformer only)
- **X Button** - Parry
- **L1** - Use item
- **L2** - Next item
- **R1** - Dodge
- **R2** - Open/Close Inventory
- **Start** - Pause

**Mobile (Touch):**
- **Virtual Gamepad** - On-screen controls
- **Touch anywhere** - Navigate menus / Advance dialogue

---

## 📁 Project Structure

```
22_lighting/
├── engine/       - Reusable game engine (systems)
├── game/         - Game content (scenes, entities, data)
├── assets/       - Resources (maps, images, sounds)
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

- **[GUIDE.md](GUIDE.md)** - Complete guide (Engine + Game + Development + Effects)
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - Full project structure

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

**Framework:** LÖVE 11.5 + Lua 5.1
**Architecture:** Engine/Game Separation
**Last Updated:** 2025-11-07
