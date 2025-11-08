-- engine/ui/menu/base.lua
-- Base class for menu scenes with common navigation/input handling
-- Eliminates code duplication across menu, pause, gameover, newgame, saveslot scenes

local MenuSceneBase = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"
local sound = require "engine.sound"
local input = require "engine.input"
local ui_helpers = require "engine.ui.menu.helpers"
local debug = require "engine.debug"
local text_ui = require "engine.ui.text"

-- Create a new menu scene with common boilerplate
-- config = {
--   title = "Menu Title",
--   options = {"Option1", "Option2"},
--   on_select = function(self, option_index) end,  -- Required: called when option is selected
--   on_back = function(self) end,                 -- Optional: called on ESC/back button
--   on_enter = function(self, previous, ...) end,  -- Optional: custom enter logic
--   on_update = function(self, dt) end,            -- Optional: custom update logic
--   on_draw = function(self) end,                  -- Optional: custom draw logic (before menu)
--   layout = { ... },                              -- Optional: custom layout
--   show_debug = true,                             -- Optional: show debug info
--   background_scene = nil,                        -- Optional: previous scene to draw behind
--   overlay_alpha = nil,                           -- Optional: overlay darkness (0.0-1.0)
-- }
function MenuSceneBase:create(config)
    local scene = {}

    -- Store config
    scene._menu_config = config

    -- === ENTER ===
    function scene:enter(previous, ...)
        self.previous = previous
        self.options = config.options or {}
        self.title = config.title or ""
        self.selected = 1
        self.mouse_over = 0
        self.previous_mouse_over = 0

        -- Setup UI
        local vw, vh = display:GetVirtualDimensions()
        self.virtual_width = vw
        self.virtual_height = vh
        self.fonts = ui_helpers.createMenuFonts()
        self.layout = config.layout or ui_helpers.createMenuLayout(vh)

        -- Hide virtual gamepad in menu
        if input.virtual_gamepad then
            input.virtual_gamepad:hide()
        end

        -- Overlay effect (for pause/dialog scenes)
        if config.overlay_alpha then
            self.overlay_alpha = 0
            self.target_alpha = config.overlay_alpha
        end

        -- Custom enter logic
        if config.on_enter then
            config.on_enter(self, previous, ...)
        end
    end

    -- === UPDATE ===
    function scene:update(dt)
        -- Fade in overlay
        if self.overlay_alpha and self.overlay_alpha < self.target_alpha then
            self.overlay_alpha = math.min(self.overlay_alpha + dt * 2, self.target_alpha)
        end

        -- Mouse hover with sound feedback
        self.previous_mouse_over = self.mouse_over
        self.mouse_over = ui_helpers.updateMouseOver(self.options, self.layout, self.virtual_width, self.fonts.option)

        if self.mouse_over ~= self.previous_mouse_over and self.mouse_over > 0 then
            sound:playSFX("menu", "navigate")
        end

        -- Gamepad navigation
        if input:hasGamepad() then
            if input:wasPressed("menu_up") then
                local new_sel = self.selected - 1
                if new_sel < 1 then new_sel = #self.options end
                sound:playSFX("menu", "navigate")
                self.selected = new_sel
            elseif input:wasPressed("menu_down") then
                local new_sel = self.selected + 1
                if new_sel > #self.options then new_sel = 1 end
                sound:playSFX("menu", "navigate")
                self.selected = new_sel
            end
        end

        -- Custom update logic
        if config.on_update then
            config.on_update(self, dt)
        end
    end

    -- === DRAW ===
    function scene:draw()
        -- Draw background scene if specified
        if config.background_scene and self.previous and self.previous.draw then
            self.previous:draw()
        end

        -- Clear screen if no background
        if not config.background_scene then
            love.graphics.clear(0.1, 0.1, 0.15, 1)
        end

        display:Attach()

        -- Draw overlay if specified
        if self.overlay_alpha then
            ui_helpers.drawOverlay(self.virtual_width, self.virtual_height, self.overlay_alpha)
        end

        -- Custom draw logic (before menu)
        if config.on_draw then
            config.on_draw(self)
        end

        -- Draw menu
        ui_helpers.drawTitle(self.title, self.fonts.title, self.layout.title_y, self.virtual_width)
        ui_helpers.drawOptions(self.options, self.selected, self.mouse_over, self.fonts.option,
            self.layout, self.virtual_width)

        -- Draw control hints
        local custom_hints = config.control_hints
        if custom_hints then
            ui_helpers.drawControlHints(self.fonts.hint, self.layout, self.virtual_width, custom_hints)
        else
            ui_helpers.drawControlHints(self.fonts.hint, self.layout, self.virtual_width)
        end

        -- Debug info
        if config.show_debug then
            if input:hasGamepad() then
                text_ui:draw("Controller: " .. input.joystick_name, 10, 10, {0.3, 0.8, 0.3, 1})
            end

            if debug.enabled then
                debug:drawHelp(self.virtual_width - 250, 10)
            end
        end

        display:Detach()
        display:ShowVirtualMouse()
    end

    -- === INPUT HANDLING ===
    function scene:keypressed(key)
        -- Handle debug keys first
        debug:handleInput(key, {})

        -- If debug mode consumed the key, don't process menu navigation
        if key:match("^f%d+$") and debug.enabled then
            return
        end

        -- Handle keyboard navigation
        local nav_result = ui_helpers.handleKeyboardNav(key, self.selected, #self.options)

        if nav_result.action == "navigate" then
            self.selected = nav_result.new_selection
        elseif nav_result.action == "select" then
            self:executeOption(self.selected)
        elseif nav_result.action == "back" then
            if config.on_back then
                config.on_back(self)
            end
        end
    end

    function scene:gamepadpressed(joystick, button)
        local nav_result = ui_helpers.handleGamepadNav(button, self.selected, #self.options)

        if nav_result.action == "navigate" then
            self.selected = nav_result.new_selection
        elseif nav_result.action == "select" then
            self:executeOption(self.selected)
        elseif nav_result.action == "back" then
            if config.on_back then
                config.on_back(self)
            end
        end
    end

    function scene:mousepressed(x, y, button) end

    function scene:mousereleased(x, y, button)
        if button == 1 and self.mouse_over > 0 then
            self.selected = self.mouse_over
            sound:playSFX("menu", "select")
            self:executeOption(self.selected)
        end
    end

    function scene:touchpressed(id, x, y, dx, dy, pressure)
        self.mouse_over = ui_helpers.handleTouchPress(
            self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
        return false
    end

    function scene:touchreleased(id, x, y, dx, dy, pressure)
        local touched = ui_helpers.handleTouchPress(
            self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
        if touched > 0 then
            self.selected = touched
            sound:playSFX("menu", "select")
            self:executeOption(self.selected)
            return true
        end
        return false
    end

    -- === EXECUTE OPTION ===
    function scene:executeOption(option_index)
        if config.on_select then
            config.on_select(self, option_index)
        end
    end

    -- === RESIZE ===
    function scene:resize(w, h)
        display:Resize(w, h)

        if config.background_scene and self.previous and self.previous.resize then
            self.previous:resize(w, h)
        end
    end

    -- === RESUME (for push/pop scenes) ===
    function scene:resume()
        if self.previous then
            scene_control.previous = self.previous
        end
    end

    return scene
end

return MenuSceneBase
