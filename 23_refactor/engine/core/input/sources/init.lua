-- engine/core/input/sources/init.lua
-- Input source module bundle

return {
    base_input = require "engine.core.input.sources.base_input",
    gamepad = require "engine.core.input.sources.gamepad",
    keyboard_input = require "engine.core.input.sources.keyboard_input",
    mouse_input = require "engine.core.input.sources.mouse_input",
    virtual_pad = require "engine.core.input.sources.virtual_pad",
}
