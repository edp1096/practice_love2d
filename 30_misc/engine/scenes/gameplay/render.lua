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
local locale = require "engine.core.locale"
local lighting = require "engine.systems.lighting"
local text_ui = require "engine.utils.text"
local weather = require "engine.systems.weather"
local quest_system = require "engine.core.quest"
local quest_tracker = require "engine.systems.hud.quest_tracker"
local vehicles_hud = require "engine.systems.hud.vehicles"
local level_system = require "engine.core.level"
local shop_ui = require "engine.ui.screens.shop"
local vehicle_select = require "engine.ui.screens.vehicle_select"

local render = {}

-- Main draw function
function render.draw(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    -- Draw parallax backgrounds in virtual coordinates (960x540)
    -- Display transform (scale + letterbox) applied inside parallax:draw()
    self.world:drawParallax(self.cam, display)

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

    -- Platformer mode: Draw Decos layer normally (no Y-sorting needed)
    -- Topdown mode: Decos tiles are drawn via Y-sorting in drawEntitiesYSorted()
    if self.player.game_mode == "platformer" then
        self.world:drawLayer("Decos")
    end

    -- Draw healing points
    self.world:drawHealingPoints()
    if debug.enabled then
        self.world:drawHealingPointsDebug()
    end
    effects:draw()
    if debug.enabled then
        self.world:drawDebug()
        debug:drawRaycast(self.player)
    end

    self.cam:detach()

    -- Draw lighting (uses its own canvas, multiply blend works outside camera)
    lighting:draw(self.cam)

    -- Draw screen effects
    effects.screen:draw()

    -- Draw weather effects (AFTER world/effects, BEFORE HUD)
    weather:draw()

    -- UI rendering starts here
    display:Attach()

    local vw, vh = display:GetVirtualDimensions()
    local pb = display.physical_bounds

    -- Health bar
    hud:draw_health_bar(pb.x + 12, pb.y + 12, 210, 20, self.player.health, self.player.max_health)

    -- Joystick info (right of HP bar, green text)
    if input:hasGamepad() then
        local colors = require "engine.utils.colors"
        local joystick_text = "Joystick: " .. input.joystick_name
        text_ui:draw(joystick_text, pb.x + 12 + 210 + 12, pb.y + 16, colors.for_menu_controller_info, hud.small_font)
    end

    -- Level and gold info (below health bar)
    local level = level_system:getLevel()
    local gold = level_system:getGold()
    hud:draw_level_info(pb.x + 12, pb.y + 36, level, gold)

    -- Experience bar (below level/gold)
    local current_exp = level_system:getCurrentExp()
    local required_exp = level_system:getRequiredExp(level)
    hud:draw_exp_bar(pb.x + 12, pb.y + 52, 210, 16, current_exp, required_exp)

    if self.player:isInvincible() or self.player:isDodgeInvincible() then
        text_ui:draw("INVINCIBLE", 17, 72, {1, 1, 0, 1}, hud.small_font)
    end

    -- Dodge/Evade display (shared cooldown)
    if self.player.dodge_active then
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, 0, 1, "Dodge", input:getPrompt("dodge"))
        text_ui:draw("DODGING", 17, vh - 29, {0.3, 1, 0.3, 1}, hud.small_font)
    elseif self.player.evade_active then
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, 0, 1, "Evade", input:getPrompt("evade"))
        text_ui:draw("EVADING", 17, vh - 29, {0.3, 1, 0.6, 1}, hud.small_font)
    else
        -- Show combined dodge/evade cooldown
        local prompt = input:getPrompt("dodge") .. "/" .. input:getPrompt("evade")
        hud:draw_cooldown(pb.x + 12, pb.h - 52, 210, self.player.dodge_evade_cooldown, self.player.dodge_evade_cooldown_duration, "Dodge/Evade", prompt)
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
        local font = locale:getFont("subtitle") or fonts.subtitle
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

    -- Draw quest tracker (top-right, shows active quests)
    quest_tracker:draw(quest_system, vw, vh, 3)

    -- Draw owned vehicles indicator (bottom-left)
    vehicles_hud:draw()

    -- Draw minimap (check game config and map properties)
    if self.minimap and self:shouldShowMinimap() then
        self.minimap:draw(vw, vh, self.player, self.world.enemies, self.world.npcs)
    end

    -- Draw dialogue (inside virtual coordinates for proper scaling)
    dialogue:draw()

    -- Draw shop UI overlay (after dialogue, before debug)
    if shop_ui:isOpen() then
        display:Detach()  -- Shop manages its own display transform
        shop_ui:draw()
        display:Attach()  -- Re-attach for remaining UI
    end

    -- Draw vehicle select UI overlay
    if vehicle_select:isOpen() then
        display:Detach()  -- Vehicle select manages its own display transform
        vehicle_select:draw()
        display:Attach()  -- Re-attach for remaining UI
    end

    -- Draw debug help (avoid minimap: size=126, padding=10, total=146)
    if debug.enabled then
        debug:drawHelp(vw - 250 - 146, 10)
        debug:drawStairsInfo(self.world, self.player, vh)
    end

    display:Detach()

    if self.fade_alpha > 0 then
        local real_w, real_h = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, real_w, real_h)
    end
end

return render
