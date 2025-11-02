-- scenes/play/render.lua
-- Rendering logic for play scene

local screen = require "lib.screen"
local hud = require "systems.hud"
local dialogue = require "systems.dialogue"
local effects = require "systems.effects"
local debug = require "systems.debug"
local camera_sys = require "systems.camera"
local input = require "systems.input"

local render = {}

-- Main draw function
function render.draw(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    -- Draw parallax backgrounds
    if self.parallax then
        local cam_x, cam_y = self.cam:position()
        local vw, vh = screen:GetVirtualDimensions()
        self.parallax:draw(cam_x, cam_y, vw, vh)
    end

    self.world:drawLayer("Ground")
    self.world:drawEntitiesYSorted(self.player)
    self.world:drawSavePoints()
    if debug.enabled then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees")

    -- Draw healing points
    self.world:drawHealingPoints()
    if debug.enabled then
        self.world:drawHealingPointsDebug()
    end
    effects:draw()
    if debug.enabled then self.world:drawDebug() end

    self.cam:detach()

    screen:Attach()

    local vw, vh = screen:GetVirtualDimensions()
    local pb = screen.physical_bounds

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
            love.graphics.print("Active Effects: " .. effects:getCount(), 8, 150)

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

    -- Draw inventory
    hud:draw_inventory(self.inventory, vw, vh)

    -- Draw minimap
    if self.minimap then
        self.minimap:draw(vw, vh, self.player.x, self.player.y, self.world.enemies, self.world.npcs)
    end

    dialogue:draw()

    if debug.enabled then debug:drawHelp(vw - 250, 10) end

    screen:Detach()

    if self.fade_alpha > 0 then
        local real_w, real_h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, real_w, real_h)
    end
end

return render
