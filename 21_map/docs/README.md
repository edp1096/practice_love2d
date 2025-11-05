# Project Documentation

This is a LÖVE2D game project with a clean **Engine/Game separation architecture**.

---

## 📚 Documentation Index

### Core Documentation
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - Complete project structure and folder organization
- **[ENGINE_GUIDE.md](ENGINE_GUIDE.md)** - Engine systems reference for developers
- **[GAME_GUIDE.md](GAME_GUIDE.md)** - Game content creation guide (RPG Maker style)

### Guides
- **[QUICKSTART.md](QUICKSTART.md)** - Get started quickly
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development workflows and patterns

---

## 🎯 Project Philosophy

This project follows a **"RPG Maker" style architecture**:

### **Engine (Reusable)**
The `engine/` folder contains generic, reusable game systems that can be used in any LÖVE2D project:
- Physics & collision system
- Input handling (keyboard, gamepad, touch)
- Audio management (BGM, SFX)
- Save/Load system
- Scene management
- UI rendering (HUD, minimap, dialogue)

### **Game (Content)**
The `game/` folder contains game-specific content:
- Scenes (menus, gameplay, settings)
- Entities (player, enemies, NPCs, items)
- Data (sound definitions, input configs, intro cutscenes)

### **Benefits**
- **Easy to create new games**: Copy `engine/` folder, create new `game/` content
- **Clean separation**: Engine code vs Game content
- **Easy maintenance**: Find files quickly with clear structure
- **RPG Maker workflow**: Focus on content, not engine code

---

## 🚀 Quick Links

### Want to create content?
→ Read **[GAME_GUIDE.md](GAME_GUIDE.md)**

### Want to understand the engine?
→ Read **[ENGINE_GUIDE.md](ENGINE_GUIDE.md)**

### Want to see the full structure?
→ Read **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)**

---

**Last Updated:** 2025-11-06
**Framework:** LÖVE 11.5 + Lua 5.1
