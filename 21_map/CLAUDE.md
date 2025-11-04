# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a LÖVE2D game project (version 11.5) written in Lua. The game is a 2D action RPG with combat mechanics including attacking, parrying, and dodging. It supports both topdown and platformer game modes, with cross-platform support for desktop (Windows, Linux, macOS) and mobile (Android, iOS).

## Running the Game

### Desktop Development
- Run the game: `love .` (from the project root directory)
- The game will automatically create a `config.ini` file on first run
- Press F11 to toggle fullscreen
- Press F12 to toggle debug mode

### Platform Detection
The game automatically detects the platform via `love.system.getOS()` and adjusts behavior accordingly:
- Desktop: Uses keyboard/mouse and physical gamepad
- Mobile (Android/iOS): Enables virtual gamepad overlay, uses touch input

## Core Architecture

### Entry Points and Configuration
- **main.lua**: Game entry point with LÖVE callbacks and error handler
- **conf.lua**: LÖVE configuration file that reads from config.ini (desktop) or mobile_config.lua (mobile)
- **GameConfig**: Global configuration table defined in conf.lua

### Scene Management System
The game uses a simple scene system via `systems/scene_control.lua`:
- **switch(scene, ...)**: Completely switch to a new scene (calls exit/enter)
- **push(scene, ...)**: Push a scene on top (like pause menu, keeps previous scene)
- **pop()**: Return to previous scene (calls resume)

Main scenes:
- `scenes/menu.lua`: Main menu
- `scenes/play/`: Main gameplay scene (modular: init.lua, input.lua, update.lua, render.lua)
- `scenes/pause.lua`: Pause menu
- `scenes/settings/`: Settings/options menu (modular structure)
- `scenes/load/`: Load game scene (modular: init.lua, slot_renderer.lua, input.lua)
- `scenes/saveslot.lua`: Save slot selection
- `scenes/gameover.lua`: Game over/game clear screen
- `scenes/intro.lua`: Game intro/cutscene

### Entity-Component Architecture

#### Player Entity (entities/player/)
The player is split into specialized modules:
- **init.lua**: Main coordinator that delegates to subsystems
  - Jump logic: Uses last_input_x for horizontal velocity (enables wall jumps)
  - Game mode tracking: player.game_mode set from world
  - Platformer-specific: is_jumping, is_grounded, can_jump, jump_power
- **animation.lua**: Animation state machine and sprite handling
  - Mode-aware: Filters vertical input in platformer mode
  - Stores last_input_x for jump direction
- **combat.lua**: Health, damage, parry, dodge, invincibility mechanics
  - Dodge: Horizontal-only in platformer, 8-directional in topdown
- **render.lua**: Drawing logic
- **sound.lua**: Player sound effects

#### Enemy Entity (entities/enemy/)
Enemies follow a similar modular pattern:
- **init.lua**: Main enemy coordinator
- **ai.lua**: AI state machine (idle, patrol, chase, attack, stunned, dead)
  - Mode-aware: Uses horizontal-only distance in platformer mode
  - Target position handling: Keeps current Y in platformer, tracks player Y in topdown
- **render.lua**: Drawing and health bars
  - Shadow positioned at collider bottom (dynamically calculated)
  - Sprite offset adjustable per enemy type
- **sound.lua**: Enemy sound effects
- **types/**: Enemy type definitions (slime.lua, humanoid.lua, etc.)
  - Slime: 32x32 collider, sprite offset adjusted for proper alignment
  - Humanoid: Variable collider sizes, weapon support

#### Weapon Entity (entities/weapon/)
- **init.lua**: Main weapon coordinator
- **combat.lua**: Hit detection and damage dealing
- **render.lua**: Weapon drawing and swing animations
- **config/**: Configuration files for hand anchors, handle anchors, swing configs
- **types/**: Weapon definitions (sword.lua, etc.)

### Systems

#### World System (systems/world.lua)
Central hub for physics and game world:
- Uses **Windfield** (Box2D wrapper) for physics
- Manages collision classes: Player, PlayerDodging, Wall, Portals, Enemy, Item
- Loads and manages map layers from Tiled maps (.tmx files)
- Manages entity collections: enemies, NPCs, save points, healing points
- Handles Y-sorted rendering for proper depth
- Loads map objects: walls, transitions/portals, enemies, NPCs, save points, healing points
- Supports two game modes: "topdown" (no gravity) and "platformer" (with gravity)

Physics mode handling:
- **Topdown mode**: No gravity (gx=0, gy=0), entities move freely in 2D
- **Platformer mode**: Gravity enabled (gx=0, gy=1000), special movement logic:
  - Ground detection via raycasts (3 rays: left, center, right) for stable edge detection
  - Air control: impulse-based movement for smooth mid-air control
  - Ground control: direct velocity setting for responsive ground movement
  - Dodge: direct velocity override for responsive dodge movement
  - Zero friction on player and walls for smooth platformer feel

#### Input System (systems/input/)
Unified input system that abstracts different input sources with **game mode-specific input handling**:
- **input_coordinator.lua**: Coordinates between multiple input sources
- **sources/**: Individual input source handlers
  - **keyboard_input.lua**: Keyboard handling
  - **mouse_input.lua**: Mouse input for aiming
  - **physical_gamepad_input.lua**: Physical controller support
  - **virtual_gamepad_input.lua**: Touch-based virtual buttons for mobile
- **virtual_gamepad.lua**: On-screen gamepad UI for mobile
- Configuration: `data/input_config.lua` defines all input mappings with mode-specific overrides

Key input features:
- Multi-source input (keyboard, mouse, gamepad, virtual gamepad)
- Action-based mapping system (wasPressed, isDown)
- Analog stick aiming with deadzone support
- Vibration/haptic feedback
- Platform-specific input prompts
- **Mode-specific input handling**: Different key behaviors for topdown vs platformer modes

Input mode separation (data/input_config.lua):
- **mode_overrides** section defines behavior per game mode
- Topdown: W/A/S/D for 4-directional movement, Space for dodge
- Platformer: W/Up/Space for jump, A/D for horizontal movement, S/Down disabled

#### Camera System (systems/camera.lua)
- Camera shake effects
- Slow-motion time scaling for dramatic effects (used during parries)
- Uses **hump.camera** library for camera management

#### Sound System (systems/sound.lua)
- BGM (background music) and SFX (sound effects) management
- Separate volume controls for master, BGM, and SFX
- Lazy loading of sound assets
- Memory monitoring to prevent leaks
- Configuration in `data/sounds.lua`

BGM playback behavior:
- **playBGM(name, fade_time, rewind)**: Plays background music with optional rewind
- **rewind=true**: Always restarts from beginning (used in scene transitions)
- **rewind=false/nil**: Continues from current position if same track is playing
- Scene transitions (play, menu, gameover) always rewind BGM to start
- Portal transitions (map-to-map) keep BGM playing without restart if same track

#### Effects System (systems/effects.lua)
- Particle effects for hits, deaths, etc.
- Manages transient visual effects

#### Dialogue System (systems/dialogue.lua)
- Uses **Talkies** library for NPC conversations
- Multi-message support

#### HUD System (systems/hud.lua)
- Health bars
- Cooldown indicators
- Debug information display
- Inventory UI
- Parry success feedback
- Slow-motion vignette effect

#### Save/Load System
- **systems/save.lua**: Save game state to slots
- **scenes/load/**: Load game scene (modular: init.lua, slot_renderer.lua, input.lua)
- Saves: player HP, position, inventory, map location
- Multiple save slots supported

#### Inventory System (systems/inventory.lua)
- Slot-based inventory with quick-select (1-5 keys)
- Item types defined in `entities/item/types/`
- Items can be used from inventory (Q key / L1 button)
- Cycle through items (Tab / R1 button)

#### Game Mode System (systems/game_mode.lua)
- Supports switching between "topdown" and "platformer" modes
- Reads game_mode from Tiled map properties
- Controls gravity settings for physics world

### Libraries and Dependencies (vendor/)
- **STI** (Simple Tiled Implementation): Tiled map loader (.tmx files)
- **Windfield**: Box2D physics wrapper
- **anim8**: Sprite animation library
- **hump**: Utility collection (camera, gamestate, timer, vector)
- **Talkies**: Dialogue/text box system

### Map Files
Maps are created in **Tiled Map Editor** (.tmx format) and converted to Lua (.lua format):
- Location: `assets/maps/level1/`
- Layers used:
  - **Ground**: Bottom terrain layer
  - **Trees**: Top decoration layer (drawn after entities)
  - **Walls**: Collision objects (rectangles, polygons, polylines, ellipses)
  - **Portals**: Transition zones (type: "portal" or "gameclear")
  - **SavePoints**: Save point locations
  - **Enemies**: Enemy spawn points with properties (type, patrol_points)
  - **NPCs**: NPC locations with properties (type, id)
  - **HealingPoints**: Healing areas with properties (heal_amount, radius, cooldown)
  - **DeathZones**: Instant death areas (pits, lava, void)
  - **DamageZones**: Continuous damage areas with properties (damage, cooldown)

Map properties:
- **game_mode**: "topdown" or "platformer" (required)
- **bgm**: BGM name from data/sounds.lua (optional - if not set, uses level-based BGM)

### Configuration Files
- **config.ini**: Desktop window and sound settings (auto-generated)
- **data/input_config.lua**: All input mappings and controller settings
- **data/sounds.lua**: Sound asset definitions
- **locker.lua**: Process locking for single instance (Lua 5.1 only, desktop)

### Mobile Support
- Virtual gamepad automatically enabled on Android/iOS
- Touch input handling in main.lua (touchpressed, touchreleased, touchmoved)
- Separate mobile_config.lua for mobile-specific settings
- Debug button in top-right corner on mobile for F12 toggle
- Virtual gamepad visible during gameplay, allows touch-through for UI overlays

#### Touch Input Priority System
Touch events are processed in the following order (main.lua):
1. **Debug button** (highest priority)
2. **Scene touchpressed** (inventory UI, dialogue, menus)
   - If scene returns `true`: touch consumed, stop processing
   - If scene returns `false`: continue to next handler
3. **Virtual gamepad** (if scene didn't handle touch)
4. **Fallback** (desktop mouse events)

**Scene Touch Handling:**
- **Inventory UI**: Checks if touch is in virtual gamepad area first
  - In gamepad area → `return false` (let gamepad handle R2/buttons)
  - In UI area → handle click → `return true` (block gamepad)
- **Play scene (dialogue)**: `return true` when dialogue open (block gamepad)
- **Intro/Cutscene**: `return true` for dialogue advancement

#### Virtual Gamepad Layout (DualSense-style)
The virtual gamepad follows a DualSense controller layout:

**Left Side:**
- **D-pad**: Movement (8-directional analog stick)
- **L1**: Use item (selected inventory item)
- **L2**: Next item (cycle through inventory)

**Center:**
- **Aim Stick**: Aiming/attack direction
- **Menu (☰)**: Pause menu

**Right Side:**
- **Face Buttons (Diamond layout):**
  - **A (✕)**: Attack / Interact (context-based - interact takes priority)
  - **B (○)**: Jump (platformer only)
  - **X (□)**: Parry
  - **Y (△)**: Reserved for future use
- **R1**: Dodge
- **R2**: Open/Close inventory (toggle)

**Virtual Gamepad Visibility:**
- Always visible during gameplay (play scene)
- Visible but touch-through during inventory/menu overlays
- `visible` property controls drawing and touch handling
- `isInVirtualPadArea(x, y)`: Checks if touch is in gamepad control area

**Context-based A button:**
- When near NPC/SavePoint: Interact
- Otherwise: Attack

**Inventory Controls:**
- **Open**: Keyboard `I` / Gamepad `R2` (virtual/physical)
- **Close**: Keyboard `I`/`ESC` / Gamepad `B`/`Start`/`R2`
- **Use Item**: `L1` button
- **Cycle Items**: `L2` button
- **Touch**: X button, item slots (uses `screen:ToVirtualCoords()` for accurate conversion)

### Combat Mechanics
- **Attack**: Primary weapon swing (mouse1 / A button on virtual/physical gamepad)
- **Parry**: Block and counter enemy attacks (mouse2 / X button on virtual/physical gamepad)
  - Perfect parry: Press at exact moment of enemy attack (triggers slow-motion)
  - Normal parry: Active parry window
- **Dodge**: Invincibility frames and faster movement (LShift / R1 on virtual gamepad)
  - Changes collision class to PlayerDodging (ignores Enemy collisions)
  - Cooldown system prevents spam
  - Platformer: horizontal dodge only, works in air
  - Topdown: 8-directional dodge
- **Jump**: Platformer mode only (W / Up / Space keys, B button on virtual gamepad)
  - Uses input direction for horizontal velocity (wall-jumping support)
  - Can jump from platform edges (raycast-based ground detection)
- **Interact**: Context-based on A button (virtual gamepad) or F key (keyboard)
  - NPC dialogue, save points
  - Priority over attack when in range

Combat feedback:
- Camera shake on hits
- Slow-motion on parries
- Vibration/haptic feedback
- Hit particles and visual effects
- Enemy stun on successful parry

### Debug System (systems/debug.lua)
Toggle with F12, provides:
- FPS counter
- Debug visualization (colliders, hitboxes, patrol paths)
- Player/enemy state information
- Memory usage
- Helpful command overlay

### Constants (systems/constants.lua)
Centralized game constants for:
- Vibration patterns
- Input timings
- Game balance values

## Development Workflow

### Adding a New Enemy Type
1. Create `entities/enemy/types/your_enemy.lua` with stats and sprite info
2. Add enemy object to Tiled map in "Enemies" layer
3. Set object property "type" to your enemy name
4. Optionally add patrol_points property for patrol behavior

### Creating a New Map
1. Create .tmx file in Tiled with required layers (Ground, Trees, Walls, Portals, Enemies, NPCs)
2. Export to Lua format (.lua file)
3. Set map properties:
   - `game_mode`: "topdown" or "platformer" (required)
   - `bgm`: BGM name from data/sounds.lua (optional - if not set, uses level-based BGM)
4. Add portal objects with properties: target_map, spawn_x, spawn_y

### Adding Background Music (BGM)
1. Place audio file in `assets/bgm/` (supports .ogg, .mp3)
2. Register in `data/sounds.lua` bgm section:
   ```lua
   bgm = {
       level3 = { path = "assets/bgm/level3.ogg", volume = 0.7, loop = true },
   }
   ```
3. **Auto-play by folder name:** Maps in `assets/maps/level3/` automatically play "level3" BGM
4. **Custom BGM per map:** Set Tiled map property `bgm = "boss"` to override
5. **BGM transition behavior:**
   - Same BGM → Continues playing (no restart)
   - Different BGM → Smooth transition to new track
   - Portal/area transitions preserve BGM if same track

### Adding Input Actions
1. Define action in `data/input_config.lua` under appropriate category
2. Access via `input:wasPressed("action_name")` or `input:isDown("action_name")`
3. Add to all relevant sources (keyboard, mouse, gamepad)

### Adding Sound Effects
1. Place audio file in `assets/sounds/`
2. Define in `data/sounds.lua` under appropriate category (ui, player, enemy)
3. Play via `sound:playSFX("category", "name")`

### Adding Hazard Zones

#### Death Zones (Instant Death)
Use for pits, voids, lava, or areas that should kill the player instantly:
1. Create "DeathZones" object layer in Tiled map
2. Add objects (rectangle, polygon, ellipse) where players should die
3. No properties needed - any object in this layer causes instant death
4. Supports all Tiled shape types (rectangle, polygon, ellipse)

**Example use cases:**
- Bottomless pits in platformer levels
- Holes in the floor (topdown mode)
- Lava pools
- Out-of-bounds areas

#### Damage Zones (Continuous Damage)
Use for traps, hazards, or dangerous areas that deal periodic damage:
1. Create "DamageZones" object layer in Tiled map
2. Add objects (rectangle, polygon, ellipse) for hazard areas
3. Set object properties:
   - `damage` (number): Damage per hit (default: 10)
   - `cooldown` (number): Seconds between damage ticks (default: 1.0)

**Example configurations:**
- Spike trap: `damage=20, cooldown=1.0` (high damage, slow)
- Fire area: `damage=5, cooldown=0.5` (low damage, fast)
- Poison gas: `damage=3, cooldown=0.3` (very low damage, very fast)

**Implementation details:**
- Both zones use sensor colliders (no physical collision)
- Player can move through zones freely but takes damage
- DamageZone cooldowns are per-zone (player tracks cooldown for each zone separately)
- Parry/dodge does NOT prevent zone damage
- Works in both topdown and platformer modes

## Code Style Notes
- Lua 5.1 compatible (LÖVE default)
- Use `local` for all variables and functions unless explicitly global
- Module pattern: return a table from each file
- Object-oriented via metatables (`setmetatable({}, class)`)
- Entities use `entity:new()` factory pattern
- All file paths use forward slashes (cross-platform)
- Physics coordinates match sprite coordinates (center-based for most entities)

## Game Mode Differences (Topdown vs Platformer)

### Movement and Physics
**Topdown Mode**:
- No gravity, free 2D movement
- W/A/S/D for 4-directional movement
- Space or LShift for dodge
- Movement uses direct velocity setting

**Platformer Mode**:
- Gravity enabled (gy = 1000)
- A/D for horizontal movement only
- W/Up/Space for jump
- LShift for horizontal dodge
- Air control uses impulse-based physics
- Ground detection via 3 raycasts (left, center, right)
- Friction set to 0 on all entities and walls

### Enemy AI Behavior
**Topdown Mode**:
- Distance calculation uses full 2D distance (Pythagorean theorem)
- Enemies move in 8 directions toward player
- Chase/attack ranges use center-to-center distance

**Platformer Mode**:
- Distance calculation uses **horizontal distance only** (math.abs(dx))
- Enemies move left/right only (Y position maintained)
- Target Y position set to enemy's current Y, not player Y
- Chase/attack ranges subtract collider widths for edge-to-edge distance
- Detection and attack ranges ignore vertical separation

### Input Processing
The game uses a mode-aware input system:
1. **data/input_config.lua**: Defines `mode_overrides` for each game mode
2. **scenes/play.lua**: `isJumpKey()` helper checks if a key is jump in current mode
3. **entities/player/animation.lua**: Filters out vertical input in platformer mode
4. **Key overlap handling**: W/Up keys work as jump in platformer, movement in topdown

Implementation details:
- Vertical input (move_y) is zeroed out in platformer mode before movement calculation
- Jump keys (W/Up/Space) are checked separately from movement in play.lua:keypressed()
- Mode check happens before processing to route input correctly

### Combat Differences
**Topdown**:
- Dodge direction based on movement input or facing direction
- Attack hit detection uses 2D distance

**Platformer**:
- Dodge direction horizontal only (Y component zeroed)
- Attack hit detection uses horizontal distance only
- Jump includes horizontal velocity from input (enables wall jumps)

## Rendering and Visual Effects

### Shadow System
Shadows are rendered differently based on game mode:

**Topdown Mode**:
- Shadow position: `draw_y + 50` (fixed offset below player sprite)
- No dynamic scaling or fading

**Platformer Mode** (entities/player/render.lua):
- Shadow stays on ground level, not attached to jumping player
- Uses `player.ground_y` for shadow Y position (updated via raycasts in scenes/play.lua)
- Dynamic scaling: Gets smaller as player jumps higher (scale 1.0 → 0.3)
- Dynamic fading: Gets more transparent as player jumps higher (alpha 0.4 → 0.1)

**Shadow Position Calculation**:
```lua
-- Ground detection (scenes/play.lua:299-363)
-- Uses Box2D rayCast to find actual ground surface Y coordinate
if ground_detected then
    player.ground_y = py + half_height  -- Player's feet position when grounded
elseif closest_ground_y then
    player.ground_y = closest_ground_y  -- Raycast hit point when in air
end

-- Shadow rendering (entities/player/render.lua:12-38)
shadow_y = player.ground_y  -- Shadow ON the ground surface
height_diff = player.ground_y - (player.y + player.height/2)  -- Distance from feet to ground
shadow_scale = max(0.3, 1.0 - (height_diff / 300))
shadow_alpha = max(0.1, 0.4 - (height_diff / 500))
```

**Coordinate System**:
- `player.x, player.y`: Collider center point (updated from collider:getX(), collider:getY())
- `player.width = 50`, `player.height = 100`
- Player's feet: `player.y + (height/2)` = `player.y + 50`
- Player's head: `player.y - (height/2)` = `player.y - 50`
- Raycasts start from feet position: `py + half_height`

### Enemy Physics in Platformer Mode

**Falling Speed Fix** (systems/world.lua):
Enemies must preserve vertical velocity (gravity) in platformer mode:
```lua
-- In world:updateEnemies()
if self.game_mode == "platformer" then
    _, vy = enemy.collider:getLinearVelocity()  -- Preserve current Y velocity
end
enemy.collider:setLinearVelocity(vx, vy)  -- Only AI controls vx in platformer
```

**Enemy Collider Setup** (systems/world.lua, utils/enemy_spawner.lua):
```lua
if game_mode == "platformer" then
    enemy.collider:setLinearDamping(0)  -- No air resistance
    enemy.collider:setGravityScale(1)   -- Full gravity effect
    enemy.collider.body:setLinearDamping(0)  -- Set on Box2D body too
end
```

Without this, enemies would:
- Fall slowly (AI was overwriting Y velocity every frame)
- Have air resistance (default linear damping > 0)

## Common Pitfalls
- **Collision class changes**: Player changes between "Player" and "PlayerDodging" during dodge - ensure dodge collision ignores are set correctly
- **Y-sorting**: Entities are depth-sorted by Y position in world:drawEntitiesYSorted()
- **Time scaling**: Camera system can slow down time (dt scaling) - use camera_sys:get_scaled_dt(dt)
- **Map coordinates**: Tiled uses top-left origin for objects; sprites often use center origin
- **Mobile input**: Always check if virtual_gamepad is enabled before processing mouse events
- **Save slots**: Current save slot is tracked in play scene, passed to save system
- **Death checks**: Player death must be checked in multiple places in update loop due to combat timing
- **Mode-specific input**: Always check game_mode before processing input that differs between modes
- **Distance calculations**: Use horizontal-only distance in platformer for AI detection/attacks
- **Ground detection**: Platformer uses raycasts, not collision callbacks, for reliable edge detection
- **Friction**: Set to 0 in platformer mode to prevent wall sliding and sticky collisions
- **Enemy Y velocity**: In platformer mode, NEVER overwrite enemy Y velocity from AI - preserve it to allow gravity to work
- **Shadow positioning**: In platformer, shadow uses `player.ground_y` (raycast result), not `player.y + offset`
- **Raycast for ground**: Use Box2D's `rayCast` with callback, not `queryLine`, to get exact hit point coordinates

## NPC System

### NPC Coordinate System
NPCs follow the same coordinate pattern as Enemies for consistency:

**Tiled Object Properties**:
- NPC objects in Tiled: 64x128 (width x height)
- Tiled coordinates (obj.x, obj.y) = **top-left corner**

**NPC Positioning Pattern**:
```lua
-- 1. Initialize NPC with Tiled coordinates
npc:new(obj.x, obj.y, type, id)  -- Tiled top-left corner

-- 2. Calculate collider position using offset
collider_offset_x = 32   -- Horizontal center of Tiled object (64/2)
collider_offset_y = 32   -- Vertical position for legs-only collider
collider_bounds = { x = obj.x + 32, y = obj.y + 32 }

-- 3. Create collider (BSGRectangleCollider uses center coordinates)
collider = newBSGRectangleCollider(bounds.x, bounds.y, 32, 32, 8)

-- 4. Update NPC position to match Enemy pattern (systems/world.lua)
npc.x = collider:getX() - collider_offset_x
npc.y = collider:getY() - collider_offset_y
```

**Rendering (entities/npc/init.lua)**:
```lua
-- All rendering uses collider_center as reference
collider_center_x = self.x + self.collider_offset_x
collider_center_y = self.y + self.collider_offset_y

-- Sprite position
sprite_x = collider_center_x + sprite_draw_offset_x  -- -72 (centers 144px sprite)
sprite_y = collider_center_y + sprite_draw_offset_y  -- -104 (aligns feet with collider)

-- Shadow, F indicator, interaction range all use collider_center
```

**Key Differences from Enemy**:
- NPCs are **static** (no movement updates)
- NPCs use **legs-only collider** (32x32) vs Enemy full-body collider
- NPCs have **interaction range** and dialogue system
- Collider offset calculated for bottom portion of Tiled object

**NPC Configuration (entities/npc/types/villager.lua)**:
```lua
collider_width = 32
collider_height = 32
collider_offset_x = 32   -- Center horizontally in 64px Tiled object
collider_offset_y = 32   -- Position at legs (adjusted from original 112)

sprite_width = 48
sprite_height = 48
sprite_scale = 3  -- 144x144 final size

sprite_draw_offset_x = -72   -- Center 144px sprite (-144/2)
sprite_draw_offset_y = -104  -- Align feet with collider bottom
```

## Code Maintenance

### Code Quality Guidelines
- **Remove debug print statements** before production - they impact performance and pollute logs
- **Delete commented-out code** instead of keeping it around - use version control (git) for history
- **Avoid code duplication** - if you find the same function call repeated multiple times, it's likely a bug
- **File size warnings**:
  - scenes/play.lua is approaching 800 lines - consider refactoring into smaller modules if it grows further
  - Large files (>500 lines) should have clear section comments for navigation

### Recent Maintenance

**2025-11-03 (Session 3 - Scene Refactoring & BGM System)**:
- **Scene Refactoring** - Modularized large scenes into focused files:
  - `scenes/settings.lua` (592 lines) → `scenes/settings/` (4 files: init, options, render, input)
  - `systems/load.lua` (501 lines) → `scenes/load/` (3 files: init, slot_renderer, input) + moved to correct category
  - `scenes/inventory_ui.lua` (351 lines) → `scenes/inventory_ui/` (3 files: init, slot_renderer, input)
  - Benefits: 60% complexity reduction, single responsibility per file, easier maintenance
- **BGM Map Property System** - Added map-based BGM control:
  - Maps can now specify custom BGM via Tiled map property `bgm = "boss"`
  - Auto-play: Maps in `level3/` folder automatically play "level3" BGM
  - Smooth transitions: Same BGM continues without restart, different BGM transitions smoothly
  - Updated `scenes/play/init.lua` switchMap() to check map.properties.bgm
  - Created `docs/BGM_GUIDE.md` with examples and debugging guide
- **Documentation Organization**:
  - Moved `MEMO.md` to `docs/` folder
  - Created `docs/README.md` as documentation index
  - Added Documentation section to CLAUDE.md with quick links
- **Updated menu.lua** - Changed `require "systems.load"` → `require "scenes.load"`

**2025-11-03 (Session 2 - Mobile Input & Virtual Gamepad)**:
- **Virtual gamepad layout redesign** - DualSense-style button mapping:
  - Face buttons: A=attack/interact (context), B=jump, X=parry, Y=reserved
  - Shoulder/Triggers: L1=use item, L2=next item, R1=dodge, R2=inventory toggle
  - Added L2, R1, R2 buttons to virtual gamepad
  - Repositioned buttons for better ergonomics
- **Context-based A button** - Interaction priority over attack:
  - Checks for NPC/SavePoint in range before attacking
  - Single button for context-aware actions
- **Touch input priority system** - Proper event handling order:
  - Scene touchpressed returns true/false to control event propagation
  - Virtual gamepad only handles touch if scene doesn't consume it
  - Inventory UI checks `isInVirtualPadArea()` to allow R2 button through
- **Inventory UI improvements**:
  - R2 toggle: Open and close inventory with same button
  - B button to close inventory
  - Touch input using `screen:ToVirtualCoords()` for accurate coordinate conversion
  - X button touch working correctly on mobile
- **Dialogue touch input** - Added touch advancement for dialogues:
  - Play scene dialogue: touch to advance (blocks virtual gamepad)
  - Intro/cutscene: touch to advance
- **Virtual gamepad visibility management**:
  - `show()`/`hide()` functions control visibility
  - Play scene shows gamepad on enter, hides on exit
  - `visible` property gates touch/draw handlers
- **Input handling refactoring**:
  - Unified gamepad input in play/input.lua (all buttons mapped)
  - Removed old input system dependencies
  - Clear separation between keyboard, physical gamepad, virtual gamepad

**2025-11-02 (Session 2)**:
- **Fixed F11 fullscreen toggle crash** - Changed `camera:setScale()` to `camera:zoomTo()` (hump.camera doesn't have setScale method)
- **Improved restart system** - Added two restart options in pause and gameover menus:
  - "Restart from Here": Restarts current map from last save position
  - "Load Last Save": Loads from most recent save point (may be different map)
- **Code refactoring**:
  - Created `utils/restart.lua` to centralize restart logic (removed ~50 lines of duplication)
  - Removed unnecessary debug print statements from:
    - `scenes/menu.lua`, `scenes/inventory_ui.lua`, `scenes/pause.lua`, `scenes/gameover.lua`
    - `entities/item/types/small_potion.lua`, `entities/item/types/large_potion.lua`
    - `entities/player/combat.lua`
    - `systems/inventory.lua`
  - **Eliminated magic numbers**: Added game start constants to `systems/constants.lua`
    - `GAME_START.DEFAULT_MAP`, `DEFAULT_SPAWN_X`, `DEFAULT_SPAWN_Y`
    - Updated 5 files to use constants instead of hardcoded values (400, 250, "assets/maps/level1/area1.lua")

**2025-11-04 (Session 1 - Xbox Controller Trigger Support)**:
- **Fixed RT trigger not working on Xbox controllers** - Added trigger axis support:
  - Xbox controllers use analog axes (`triggerleft`/`triggerright`) instead of buttons
  - Added trigger state tracking to `systems/input/input_coordinator.lua`
  - Implemented `handleGamepadAxis()` function with threshold detection (0.5)
  - Added `gamepadaxis` event forwarding in:
    - `systems/input/init.lua` - wrapper function
    - `scenes/play/init.lua` and `scenes/play/input.lua` - gameplay scene
    - `scenes/inventory_ui/init.lua` and `scenes/inventory_ui/input.lua` - inventory UI
  - RT trigger now toggles inventory open/close (matching DualSense R2 behavior)
  - LT trigger cycles through inventory items
  - Compatible with both DualSense (button-based) and Xbox (axis-based) controllers
- **Improved inventory UX** - Changed selection controls:
  - Keyboard: Left/Right arrows or A/D (was Up/Down or W/S)
  - Gamepad: D-pad Left/Right (was D-pad Up/Down)
  - More intuitive for horizontal inventory layout

**2025-11-02 (Session 1)**:
- Removed 3 duplicate calls to `world:updateHealingPoints()` in scenes/play.lua (was called 4 times per frame)
- Removed debug print statements from keyboard input handling
- Cleaned up commented-out old function signatures and scene_control.switch calls
- **Fixed NPC coordinate system** to match Enemy pattern (collider_center based rendering)
- **Fixed NPC collider positioning** - was using incorrect offset calculation causing misalignment
- **Updated NPC to use collider_center** for all rendering (shadow, sprite, F indicator, interaction range, debug visualization)

---

## 📚 Documentation

### Main Documentation
- **CLAUDE.md** (this file) - Primary developer guide for Claude Code AI
  - Project overview and architecture
  - Development workflows
  - Code style guidelines
  - Common pitfalls and solutions

### Additional Documentation (docs/ folder)
- **docs/README.md** - Documentation index and finder guide
- **docs/MEMO.md** - Complete project structure reference
  - Folder/file tree with descriptions
  - File count and line statistics
  - Architecture patterns
  - Recent refactoring history
- **docs/BGM_GUIDE.md** - Background music system guide
  - How to add/change BGM
  - Map property-based BGM assignment
  - Intro/Ending special BGM handling
  - Examples and debugging
- **docs/HEALTH_RECOVERY_README.md** - Health recovery system
  - Healing Point implementation
  - Map configuration guide
- **docs/SUMMARY.md** - Feature summary

**Quick Links:**
- Need project structure overview? → `docs/MEMO.md`
- Need to add/change BGM? → `docs/BGM_GUIDE.md`
- Need to understand a system? → This file (CLAUDE.md)
