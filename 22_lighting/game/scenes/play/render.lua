-- scenes/play/render.lua
-- Rendering logic for play scene

local screen = require "engine.display"
local hud = require "engine.hud.status"
local dialogue = require "engine.ui.dialogue"
local effects = require "engine.effects"
local debug = require "engine.debug"
local camera_sys = require "engine.camera"
local input = require "engine.input"
local fonts = require "engine.utils.fonts"
local lighting = require "engine.lighting"

local render = {}

-- Main draw function
function render.draw(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    -- Draw background layer (no parallax)
    self.world:drawLayer("Background_Near")

    self.world:drawLayer("Ground")
    self.world:drawEntitiesYSorted(self.player)
    self.world:drawSavePoints()
    if debug.enabled then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees", self.cam)

    -- Draw healing points
    self.world:drawHealingPoints()
    if debug.enabled then
        self.world:drawHealingPointsDebug()
    end
    effects:draw()
    if debug.enabled then self.world:drawDebug() end

    self.cam:detach()

    -- Draw lighting (uses its own canvas, multiply blend works outside camera)
    lighting:draw(self.cam)

    -- Draw screen effects
    effects.screen:draw()

    -- UI rendering starts here
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

    -- All debug info is now shown in app_lifecycle (main.lua) via debug:drawInfo()
    -- (includes FPS, player state, screen info, effects, gamepad)

    hud:draw_parry_success(self.player, vw, vh)
    hud:draw_slow_motion_vignette(camera_sys.time_scale, vw, vh)

    if self.save_notification.active then
        local alpha = math.min(1, self.save_notification.timer / 0.5)
        local font = fonts.subtitle
        if not font then return end  -- Safety check

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

    -- Draw dialogue (inside virtual coordinates for proper scaling)
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
