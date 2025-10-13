-- scenes/play.lua
-- Main gameplay scene: manages world, player, and camera

local play = {}

local player = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local debug = require "systems.debug"
local screen = require "lib.screen"

function play:enter(previous, mapPath, spawn_x, spawn_y)
    mapPath = mapPath or "assets/maps/level1/area1.lua"
    spawn_x = spawn_x or 400
    spawn_y = spawn_y or 250

    self.cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)
    self.world = world:new(mapPath)
    self.player = player:new("assets/images/player-sheet.png", spawn_x, spawn_y)

    self.world:addEntity(self.player)

    self.transition_cooldown = 0

    -- Fade effect
    self.fade_alpha = 1.0
    self.fade_speed = 2.0
    self.is_fading = true
end

function play:exit()
    if self.world then
        self.world:destroy()
    end
end

-- Called when pause scene is pushed
function play:pause() end

-- Called when returning from pause
function play:resume() end

function play:update(dt)
    -- Fade in effect
    if self.is_fading and self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
        if self.fade_alpha == 0 then
            self.is_fading = false
        end
    end

    local vx, vy = self.player:update(dt, self.cam) -- Pass camera for mouse coordinate conversion

    self.world:moveEntity(self.player, vx, vy, dt)
    self.world:updateEnemies(dt, self.player.x, self.player.y)
    self.world:update(dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    -- Check weapon collisions with enemies
    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
        end
    end

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    -- Update transition cooldown
    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - dt
    end

    -- Check for map transitions
    if self.transition_cooldown <= 0 then
        local player_w, player_h = 32, 32 -- Player collision box size
        local transition = self.world:checkTransition(
            self.player.x - player_w / 2,
            self.player.y - player_h / 2,
            player_w,
            player_h
        )

        if transition then
            self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
        end
    end
end

function play:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    self.world:drawLayer("Ground")
    self.world:drawEnemies()
    self.player:drawAll() -- Draw player and weapon with correct layering

    -- Draw debug overlays (hand positions, etc)
    if debug.debug_mode then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees")

    if debug.debug_mode then
        self.world:drawDebug()
    end

    self.cam:detach()

    if debug.show_fps then
        local marking_info = self.player:getHandMarkingInfo()
        local panel_height = marking_info and 220 or 170

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 0, 0, 250, panel_height)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        love.graphics.print(string.format("Player: %.1f, %.1f", self.player.x, self.player.y), 10, 30)
        love.graphics.print("Press ESC to pause", 10, 50)
        love.graphics.print("Left Click to Attack", 10, 70)
        love.graphics.print("H = Hand Marking Mode", 10, 90)

        -- Show attack state
        local state_text = "State: " .. self.player.state
        if self.player.attack_cooldown > 0 then
            state_text = state_text .. string.format(" (CD: %.1f)", self.player.attack_cooldown)
        end
        love.graphics.print(state_text, 10, 110)

        -- Show hand marking mode info
        if marking_info then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("--- HAND MARKING MODE ---", 10, 140)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("Animation: " .. marking_info.animation, 10, 160)
            love.graphics.print(string.format("Frame: %d / %d", marking_info.frame, marking_info.frame_count), 10, 180)
            love.graphics.print("PgUp/PgDown: Change frame", 10, 200)
        end
    end

    -- Draw fade overlay
    if self.fade_alpha > 0 then
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end
end

function play:resize(w, h)
    self.cam:zoomTo(w / 960)
end

function play:keypressed(key)
    if key == "escape" then
        local pause = require "scenes.pause"
        scene_control.push(pause)
    elseif key == "h" and debug.debug_mode then
        -- Toggle hand marking mode (only in debug mode)
        self.player:toggleHandMarking()
    elseif key == "pageup" and debug.debug_mode then
        -- Previous frame in hand marking mode
        self.player:prevFrame()
    elseif key == "pagedown" and debug.debug_mode then
        -- Next frame in hand marking mode
        self.player:nextFrame()
    end
end

function play:mousepressed(x, y, button)
    if button == 1 then -- Left click: Attack
        self.player:attack()
        -- if self.player:attack() then
        --     print("Attack initiated!")
        -- end
    elseif button == 2 then -- Right click: Mark hand or weapon position (debug only)
        if debug.debug_mode then
            local world_x, world_y = self.cam:worldCoords(x, y)

            -- Check if Ctrl is held
            if love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl') then
                -- Ctrl+Right Click: Mark weapon anchor
                self.player:markWeaponAnchor(world_x, world_y)
            else
                -- Right Click: Mark hand position
                self.player:markHandPosition(world_x, world_y)
            end
        end
    end
end

function play:mousereleased(x, y, button)
    -- Currently not used, but needed for scene_control
    -- Future use: charge attacks, aiming, etc.
end

function play:switchMap(new_map_path, spawn_x, spawn_y)
    if self.world then self.world:destroy() end

    self.world = world:new(new_map_path)

    -- Update player position
    self.player.x = spawn_x
    self.player.y = spawn_y

    -- Clear old collider reference (it was destroyed with the old world)
    self.player.collider = nil

    -- Create new collider in the new world
    self.world:addEntity(self.player)

    self.transition_cooldown = 0.5

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    -- Reset fade effect for new area
    self.fade_alpha = 1.0
    self.is_fading = true
end

return play
