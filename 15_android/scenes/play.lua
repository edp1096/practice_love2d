-- scenes/play.lua
-- Main gameplay scene with save, gamepad, sound

local play = {}

local player = require "entities.player"
local world = require "systems.world"
local camera = require "vendor.hump.camera"
local scene_control = require "systems.scene_control"
local debug = require "systems.debug"
local screen = require "lib.screen"
local camera_sys = require "systems.camera"
local hud = require "systems.hud"
local effects = require "systems.effects"
local dialogue = require "systems.dialogue"
local save_sys = require "systems.save"
local input = require "systems.input"
local sound = require "systems.sound"
local player_sound = require "entities.player.sound"

local pb = { x = 0, y = 0, w = 960, h = 540 }

-- Check if on mobile platform
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- function play:enter(previous, mapPath, spawn_x, spawn_y, save_slot)
function play:enter(_, mapPath, spawn_x, spawn_y, save_slot)
    mapPath = mapPath or "assets/maps/level1/area1.lua"
    spawn_x = spawn_x or 400
    spawn_y = spawn_y or 250
    save_slot = save_slot or 1

    self.current_map_path = mapPath
    self.cam = camera(0, 0, love.graphics.getWidth() / 960, 0, 0)
    self.world = world:new(mapPath)
    self.player = player:new("assets/images/player-sheet.png", spawn_x, spawn_y)

    self.current_save_slot = save_slot

    local save_data = save_sys:loadGame(save_slot)
    if save_data and save_data.hp then
        self.player.health = save_data.hp
        self.player.max_health = save_data.max_hp
        print("Loaded from save slot " .. save_slot)
    else
        print("Starting new game in slot " .. save_slot)
    end

    self.world:addEntity(self.player)

    self.transition_cooldown = 0

    self.fade_alpha = 1.0
    self.fade_speed = 2.0
    self.is_fading = true

    self.save_notification = {
        active = false,
        timer = 0,
        duration = 2.0,
        text = "Game Saved!"
    }

    dialogue:initialize()

    local level = mapPath:match("level(%d+)")
    if not level then level = "1" end
    level = "level" .. level
    sound:playBGM(level)

    -- Android debug system
    self.debug_enabled = false
    self.debug_button = { x = 10, y = 10, size = 50, touch_id = nil, tap_count = 0, last_tap_time = 0, double_tap_threshold = 0.7 }
end

function play:exit()
    if self.world then self.world:destroy() end
    sound:stopBGM()
end

function play:saveGame(slot)
    slot = slot or self.current_save_slot or 1

    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y
    }

    local success = save_sys:saveGame(slot, save_data)
    if success then
        self.current_save_slot = slot
        self:showSaveNotification()

        sound:playSFX("ui", "save")
    end
end

function play:showSaveNotification()
    self.save_notification.active = true
    self.save_notification.timer = self.save_notification.duration
end

function play:update(dt)
    camera_sys:update(dt)
    local scaled_dt = camera_sys:get_scaled_dt(dt)

    effects:update(dt)
    dialogue:update(dt)

    if self.save_notification.active then
        self.save_notification.timer = self.save_notification.timer - dt
        if self.save_notification.timer <= 0 then
            self.save_notification.active = false
        end
    end

    if self.is_fading and self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
        if self.fade_alpha == 0 then
            self.is_fading = false
        end
    end

    -- CRITICAL: Check player death at the start
    if self.player.health <= 0 then
        print("Player died! Switching to game over...")
        local gameover = require "scenes.gameover"
        scene_control.switch(gameover, self, false)
        return
    end

    local is_dialogue_open = dialogue:isOpen()

    local vx, vy = self.player:update(scaled_dt, self.cam, is_dialogue_open)

    for _, enemy in ipairs(self.world.enemies) do
        if enemy.anim then enemy.anim:update(scaled_dt) end
    end

    for _, npc in ipairs(self.world.npcs) do
        if npc.anim then npc.anim:update(scaled_dt) end
    end

    if is_dialogue_open then
        local shake_x, shake_y = camera_sys:get_shake_offset()
        self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

        local mapWidth = self.world.map.width * self.world.map.tilewidth
        local mapHeight = self.world.map.height * self.world.map.tileheight
        self.cam:lockBounds(mapWidth, mapHeight)

        return
    end

    self.world:moveEntity(self.player, vx, vy, scaled_dt)
    self.world:updateEnemies(scaled_dt, self.player.x, self.player.y)
    self.world:updateNPCs(scaled_dt, self.player.x, self.player.y)

    local shake_callback = function(intensity, duration)
        camera_sys:shake(intensity, duration)
    end

    for _, enemy in ipairs(self.world.enemies) do
        if enemy.state == "attack" and not enemy.stunned then
            local dx = enemy.x - self.player.x
            local dy = enemy.y - self.player.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance < (enemy.attack_range or 60) then
                local damaged, parried, is_perfect = self.player:takeDamage(enemy.damage or 10, shake_callback)

                enemy.has_attacked = true

                if parried then
                    print(is_perfect and "PERFECT PARRY!" or "PARRY!")
                    enemy:stun(nil, is_perfect)

                    if is_perfect then
                        camera_sys:activate_slow_motion(0.3, 0.2)
                    else
                        camera_sys:activate_slow_motion(0.2, 0.4)
                    end

                    camera_sys:shake(8, 0.2)
                end
            end
        end
    end

    -- CRITICAL: Check player death again after enemy attacks
    if self.player.health <= 0 then
        print("Player died after enemy attack! Switching to game over...")
        local gameover = require "scenes.gameover"
        -- scene_control.switch(gameover, self, false)
        scene_control.switch(gameover, false)
        return
    end

    self.world:update(scaled_dt)

    self.player.x = self.player.collider:getX()
    self.player.y = self.player.collider:getY()

    if self.player.weapon.is_attacking then
        local hits = self.world:checkWeaponCollisions(self.player.weapon)
        for _, hit in ipairs(hits) do
            self.world:applyWeaponHit(hit)
            input:vibrateWeaponHit()
            player_sound.playWeaponHit()
        end
    end

    local shake_x, shake_y = camera_sys:get_shake_offset()
    self.cam:lookAt(self.player.x + shake_x, self.player.y + shake_y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    if self.transition_cooldown > 0 then
        self.transition_cooldown = self.transition_cooldown - scaled_dt
    end

    -- Transition check
    if self.transition_cooldown <= 0 then
        local player_w, player_h = 32, 32
        local transition = self.world:checkTransition(
            self.player.x - player_w / 2,
            self.player.y - player_h / 2,
            player_w, player_h
        )

        if transition then
            if transition.transition_type == "gameclear" then
                local gameover = require "scenes.gameover"
                -- scene_control.switch(gameover, self, true)
                scene_control.switch(gameover, true)
                return
            else
                self:switchMap(transition.target_map, transition.spawn_x, transition.spawn_y)
            end
        end
    end
end

function play:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    self.world:drawLayer("Ground")
    self.world:drawEntitiesYSorted(self.player)
    self.world:drawSavePoints()
    if debug.enabled then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees")
    effects:draw()
    if debug.enabled then self.world:drawDebug() end

    self.cam:detach()

    screen:Attach()

    local vw, vh = screen:GetVirtualDimensions()
    pb = screen.physical_bounds

    hud:draw_health_bar(pb.x + 12, pb.y + 12, 210, 20, self.player.health, self.player.max_health)

    love.graphics.setFont(hud.small_font)
    if self.player:isInvincible() or self.player:isDodgeInvincible() then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print("INVINCIBLE", 17, 35)
    end

    if self.player.dodge_active then
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, 0, 1, "Dodge", input:getPrompt("dodge"))
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("DODGING", 17, vh - 29)
    else
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, self.player.dodge_cooldown, self.player.dodge_cooldown_duration, "Dodge", input:getPrompt("dodge"))
    end

    if self.player.parry_cooldown > 0 then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(string.format("Parry CD: %.1f", self.player.parry_cooldown), 17, 35)
    end

    if self.player.parry_active then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 15)
        love.graphics.setColor(0.3, 0.6, 1, pulse)
        love.graphics.print("PARRY READY!", 17, 35)
    end

    love.graphics.setColor(1, 1, 1, 1)

    if debug.show_fps then
        hud:draw_debug_panel(self.player, self.current_save_slot)
        if debug.enabled then
            love.graphics.setFont(hud.tiny_font)
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("Active Effects: " .. effects:getCount(), 8, 140)
            love.graphics.print("F5: Test Effects at Mouse", 8, 154)

            if input:hasGamepad() then
                love.graphics.print(input:getDebugInfo(), 8, 168)
            end

            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    hud:draw_parry_success(self.player, vw, vh)
    hud:draw_slow_motion_vignette(camera_sys.time_scale, vw, vh)

    if self.save_notification.active then
        local alpha = math.min(1, self.save_notification.timer / 0.5)
        local font = love.graphics.newFont(28)
        love.graphics.setFont(font)

        local text = self.save_notification.text
        local text_width = font:getWidth(text)

        love.graphics.setColor(0, 0, 0, 0.7 * alpha)
        love.graphics.rectangle("fill", vw / 2 - text_width / 2 - 20, 150, text_width + 40, 50)

        love.graphics.setColor(0, 1, 0.5, alpha)
        love.graphics.print(text, vw / 2 - text_width / 2, 160)

        love.graphics.setColor(1, 1, 1, 1)
    end

    dialogue:draw()

    if debug.enabled then debug:drawHelp(vw - 250, 10) end

    screen:Detach()

    -- Android debug visualization
    if self.debug_enabled then
        self:drawDebugAimArea()
        self:drawDebugInfo()
    end
    if love.system.getOS() == "Android" then
        self:drawDebugButton()
    end

    if self.fade_alpha > 0 then
        local real_w, real_h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, real_w, real_h)
    end
end

function play:resize(w, h) self.cam:zoomTo(w / 960) end

function play:keypressed(key)
    -- Toggle debug with F12
    if key == "f12" then
        self.debug_enabled = not self.debug_enabled
        print("Debug mode: " .. tostring(self.debug_enabled))
        return
    end

    if dialogue:isOpen() then
        if input:wasPressed("interact", "keyboard", key) or
            input:wasPressed("menu_select", "keyboard", key) then
            dialogue:onAction()
        end

        return
    end

    if input:wasPressed("pause", "keyboard", key) then
        local pause = require "scenes.pause"
        scene_control.push(pause)

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("dodge", "keyboard", key) then
        if self.player:startDodge() then print("Dodge!") end
    elseif input:wasPressed("interact", "keyboard", key) then
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)

            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            local saveslot = require "scenes.saveslot"
            scene_control.push(saveslot, function(slot)
                self:saveGame(slot)
                print("Game saved to slot " .. slot .. " at savepoint: " .. savepoint.id)
            end)
        end
    elseif input:wasPressed("quicksave_1", "keyboard", key) then
        self:saveGame(1)
        print("Quick saved to slot 1")
    elseif input:wasPressed("quicksave_2", "keyboard", key) then
        self:saveGame(2)
        print("Quick saved to slot 2")
    elseif input:wasPressed("quicksave_3", "keyboard", key) then
        self:saveGame(3)
        print("Quick saved to slot 3")
    elseif key == "f9" then
        self:saveGame()
        print("Manual save triggered (F9)")
    else
        debug:handleInput(key, {
            player = self.player,
            world = self.world,
            camera = self.cam
        })
    end
end

function play:mousepressed(x, y, button)
    -- Ignore mouse events on mobile (virtual gamepad handles all input)
    if is_mobile then
        return
    end

    if dialogue:isOpen() then
        if input:wasPressed("menu_select", "mouse", button) then
            dialogue:onAction()
        end
        return
    end

    if input:wasPressed("attack", "mouse", button) then
        self.player:attack()
    elseif input:wasPressed("parry", "mouse", button) then
        if self.player:startParry() then print("Parry stance activated!") end
    end
end

function play:mousereleased(x, y, button)
    -- Ignore mouse events on mobile
    if is_mobile then
        return
    end
end

function play:gamepadpressed(joystick, button)
    if dialogue:isOpen() then
        if input:wasPressed("interact", "gamepad", button) or
            input:wasPressed("menu_select", "gamepad", button) then
            dialogue:onAction()
        end

        return
    end

    if input:wasPressed("pause", "gamepad", button) then
        local pause = require "scenes.pause"
        scene_control.push(pause)

        sound:playSFX("ui", "pause")
        sound:pauseBGM()
    elseif input:wasPressed("attack", "gamepad", button) then
        self.player:attack()
    elseif input:wasPressed("parry", "gamepad", button) then
        if self.player:startParry() then print("Parry activated!") end
    elseif input:wasPressed("dodge", "gamepad", button) then
        if self.player:startDodge() then print("Dodge!") end
    elseif input:wasPressed("interact", "gamepad", button) then
        local npc = self.world:getInteractableNPC(self.player.x, self.player.y)
        if npc then
            local messages = npc:interact()
            dialogue:showMultiple(npc.name, messages)

            return
        end

        local savepoint = self.world:getInteractableSavePoint()
        if savepoint then
            local saveslot = require "scenes.saveslot"
            scene_control.push(saveslot, function(slot)
                self:saveGame(slot)
                print("Game saved to slot " .. slot .. " at savepoint: " .. savepoint.id)
            end)
        end
    elseif input:wasPressed("quicksave_1", "gamepad", button) then
        self:saveGame(1)
        print("Quick saved to slot 1 [L1]")
    elseif input:wasPressed("quicksave_2", "gamepad", button) then
        self:saveGame(2)
        print("Quick saved to slot 2 [R1]")
    end
end

function play:gamepadreleased(joystick, button) end

function play:touchpressed(id, x, y, dx, dy, pressure)
    -- Handle debug button touch
    if self:handleDebugButtonTouch(x, y, id, true) then
        return
    end
end

function play:touchreleased(id, x, y, dx, dy, pressure)
    -- Handle debug button release
    if self:handleDebugButtonTouch(x, y, id, false) then
        return
    end
end

function play:switchMap(new_map_path, spawn_x, spawn_y)
    if self.world then self.world:destroy() end

    self.current_map_path = new_map_path
    self.world = world:new(new_map_path)

    self.player.x = spawn_x
    self.player.y = spawn_y

    self.player.collider = nil

    self.world:addEntity(self.player)

    self.transition_cooldown = 0.5

    self.cam:lookAt(self.player.x, self.player.y)

    local mapWidth = self.world.map.width * self.world.map.tilewidth
    local mapHeight = self.world.map.height * self.world.map.tileheight
    self.cam:lockBounds(mapWidth, mapHeight)

    self.fade_alpha = 1.0
    self.is_fading = true

    local level = new_map_path:match("level(%d+)")
    if level then sound:playBGM("level" .. level) end
end

-- === ANDROID DEBUG SYSTEM ===

function play:drawDebugButton()
    local btn = self.debug_button
    if not btn then return end

    if self.debug_enabled then
        love.graphics.setColor(0, 1, 0, 0.7)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    end
    love.graphics.rectangle("fill", btn.x, btn.y, btn.size, btn.size)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", btn.x, btn.y, btn.size, btn.size)
    love.graphics.print("D", btn.x + 15, btn.y + 15, 0, 2, 2)
end

function play:drawDebugAimArea()
    if not self.player then return end

    local screen = require "lib.screen"
    local sx, sy = self.cam:cameraCoords(self.player.x, self.player.y)
    local aim_area_size = screen.screen_wh.h
    local half_area = aim_area_size / 2

    love.graphics.push()
    love.graphics.origin()

    love.graphics.setColor(1, 0, 0, 0.3)
    love.graphics.rectangle("line", sx - half_area, sy - half_area, aim_area_size, aim_area_size)

    love.graphics.setColor(1, 1, 0, 0.5)
    love.graphics.line(sx - 20, sy, sx + 20, sy)
    love.graphics.line(sx, sy - 20, sx, sy + 20)

    love.graphics.pop()
end

function play:drawDebugInfo()
    local screen = require "lib.screen"
    local info = { "=== DEBUG ===", string.format("FPS: %d", love.timer.getFPS()),
        string.format("Mem: %.1fMB", collectgarbage("count") / 1024), "" }

    if self.player then
        table.insert(info, string.format("Pos: (%.0f,%.0f)", self.player.x, self.player.y))
        table.insert(info, string.format("Aim: %.2f", self.player.aim_angle or 0))
        table.insert(info, string.format("Src: %s", input.last_aim_source or "-"))
    end

    local sound = require "systems.sound"
    if sound then
        table.insert(info, "")
        table.insert(info, string.format("Sounds: %d/%d", #sound.active_sources, sound.max_active_sources))
    end

    love.graphics.push()
    love.graphics.origin()
    local x, y = screen.render_wh.w - 250, 80
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x - 5, y - 5, 240, #info * 18 + 10)
    love.graphics.setColor(1, 1, 1, 1)
    for i, line in ipairs(info) do
        love.graphics.print(line, x, y + (i - 1) * 18, 0, 0.9, 0.9)
    end
    love.graphics.pop()
end

function play:handleDebugButtonTouch(touch_x, touch_y, touch_id, is_pressed)
    local btn = self.debug_button
    if not btn then return false end

    local in_button = touch_x >= btn.x and touch_x <= btn.x + btn.size and
        touch_y >= btn.y and touch_y <= btn.y + btn.size

    if is_pressed and in_button then
        btn.touch_id = touch_id
        print("Debug button touched: tap_count=" .. btn.tap_count)
        local current_time = love.timer.getTime()
        if current_time - btn.last_tap_time < btn.double_tap_threshold then
            btn.tap_count = btn.tap_count + 1
            if btn.tap_count >= 2 then
                self.debug_enabled = not self.debug_enabled
                print("Debug mode: " .. tostring(self.debug_enabled))
                btn.tap_count = 0
            end
        else
            btn.tap_count = 1
        end
        btn.last_tap_time = current_time
        return true
    elseif not is_pressed and btn.touch_id == touch_id then
        btn.touch_id = nil
        return true
    end

    return false
end

return play
