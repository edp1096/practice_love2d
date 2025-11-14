-- engine/scenes/gameplay/render.lua
-- Rendering logic for play scene

local display = require "engine.core.display"
local hud = require "engine.systems.hud.status"
local quickslots_hud = require "engine.systems.hud.quickslots"
local dialogue = require "engine.ui.dialogue"
local effects = require "engine.systems.effects"
local debug = require "engine.core.debug"
local camera_sys = require "engine.core.camera"
local input = require "engine.core.input"
local fonts = require "engine.utils.fonts"
local lighting = require "engine.systems.lighting"
local text_ui = require "engine.utils.text"

local render = {}

-- Main draw function
function render.draw(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    -- Draw parallax backgrounds in PHYSICAL coordinates (same space as world rendering)
    -- Camera uses physical screen size and has its own scale, so parallax needs physical coords too
    self.world:drawParallax(self.cam)

    -- Now apply camera transform for world rendering
    self.cam:attach()

    -- Draw background layer (no parallax)
    self.world:drawLayer("Background_Near")

    self.world:drawLayer("Ground")
    self.world:drawLayer("GroundDeco")
    self.world:drawEntitiesYSorted(self.player)  -- Includes world_items for Y-sorting
    self.world:drawSavePoints()
    self.world:drawWorldItemPrompts(self.player.x, self.player.y, self.player.game_mode)  -- Only prompts
    if debug.enabled then
        self.player:drawDebug()
    end

    -- Platformer mode: Draw Trees layer normally (no Y-sorting needed)
    -- Topdown mode: Trees tiles are drawn via Y-sorting in drawEntitiesYSorted()
    if self.player.game_mode == "platformer" then
        self.world:drawLayer("Trees")
    end

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
    display:Attach()

    local vw, vh = display:GetVirtualDimensions()
    local pb = display.physical_bounds

    hud:draw_health_bar(pb.x + 12, pb.y + 12, 210, 20, self.player.health, self.player.max_health)

    if self.player:isInvincible() or self.player:isDodgeInvincible() then
        text_ui:draw("INVINCIBLE", 17, 35, {1, 1, 0, 1}, hud.small_font)
    end

    if self.player.dodge_active then
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, 0, 1, "Dodge", input:getPrompt("dodge"))
        text_ui:draw("DODGING", 17, vh - 29, {0.3, 1, 0.3, 1}, hud.small_font)
    else
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, self.player.dodge_cooldown, self.player.dodge_cooldown_duration, "Dodge", input:getPrompt("dodge"))
    end

    if self.player.parry_cooldown > 0 then
        text_ui:draw(string.format("Parry CD: %.1f", self.player.parry_cooldown), 17, 35, {0.7, 0.7, 0.7, 1}, hud.small_font)
    end

    if self.player.parry_active then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 15)
        text_ui:draw("PARRY READY!", 17, 35, {0.3, 0.6, 1, pulse}, hud.small_font)
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

        text_ui:draw(text, vw / 2 - text_width / 2, 160, {0, 1, 0.5, alpha}, font)

        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Draw inventory
    hud:draw_inventory(self.inventory, vw, vh)

    -- Draw quickslot belt
    quickslots_hud.draw(self.inventory, self.player, display, self.selected_quickslot)

    -- Draw minimap (check game config and map properties)
    if self.minimap and self:shouldShowMinimap() then
        self.minimap:draw(vw, vh, self.player, self.world.enemies, self.world.npcs)
    end

    -- Draw dialogue (inside virtual coordinates for proper scaling)
    dialogue:draw()

    -- Draw debug help (avoid minimap: size=126, padding=10, total=146)
    if debug.enabled then debug:drawHelp(vw - 250 - 146, 10) end

    display:Detach()

    if self.fade_alpha > 0 then
        local real_w, real_h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, real_w, real_h)
    end
end

return render
