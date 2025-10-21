-- systems/dialogue.lua
-- Simple dialogue system using Talkies

local Talkies = require "vendor.talkies"

local dialogue = {}

function dialogue:initialize()
    -- Configure Talkies
    Talkies.backgroundColor = { 0, 0, 0, 0.8 }
    Talkies.textSpeed = "fast"
    Talkies.indicatorCharacter = ">"
end

function dialogue:showSimple(npc_name, message) Talkies.say(npc_name, { message }) end

function dialogue:showMultiple(npc_name, messages) Talkies.say(npc_name, messages) end

function dialogue:isOpen() return Talkies.isOpen() end

function dialogue:update(dt) Talkies.update(dt) end

function dialogue:draw() Talkies.draw() end

function dialogue:onAction() Talkies.onAction() end

function dialogue:clear() Talkies.clearMessages() end

return dialogue
