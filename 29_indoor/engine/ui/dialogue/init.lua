-- engine/ui/dialogue/init.lua
-- Advanced dialogue system with choice support
-- Modular architecture: delegates to core.lua, render.lua, helpers.lua

local core = require "engine.ui.dialogue.core"
local render = require "engine.ui.dialogue.render"
local helpers = require "engine.ui.dialogue.helpers"

local dialogue = {}

-- ============================================================================
-- INITIALIZATION & CORE STATE
-- ============================================================================

function dialogue:initialize(display_module)
    core:initialize(self, display_module)
end

function dialogue:setDisplay(display)
    core:setDisplay(self, display)
end

function dialogue:isOpen()
    return core:isOpen(self)
end

function dialogue:update(dt)
    core:update(self, dt)
end

function dialogue:draw()
    render:draw(self)
end

function dialogue:clear()
    core:clear(self)
end

-- ============================================================================
-- DIALOGUE TREE SYSTEM
-- ============================================================================

function dialogue:showTreeById(dialogue_id, npc_id, npc_obj)
    core.showTreeById(self, dialogue_id, npc_id, npc_obj)
end

function dialogue:showTree(dialogue_tree)
    core.showTree(self, dialogue_tree)
end

function dialogue:advanceTree()
    core:advanceTree(self)
end

function dialogue:selectChoice(choice_index)
    core:selectChoice(self, choice_index)
end

function dialogue:moveChoiceSelection(direction)
    core:moveChoiceSelection(self, direction)
end

-- ============================================================================
-- SIMPLE DIALOGUE METHODS
-- ============================================================================

function dialogue:showSimple(npc_name, message)
    core:showSimple(self, npc_name, message)
end

function dialogue:showMultiple(npc_name, messages)
    core:showMultiple(self, npc_name, messages)
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================

function dialogue:handleInput(source, ...)
    return core:handleInput(self, source, ...)
end

function dialogue:onAction()
    core:onAction(self)
end

-- ============================================================================
-- PERSISTENCE SYSTEM
-- ============================================================================

function dialogue:exportChoiceHistory()
    return helpers:exportChoiceHistory(self)
end

function dialogue:importChoiceHistory(history)
    helpers:importChoiceHistory(self, history)
end

-- ============================================================================
-- DIALOGUE FLAGS SYSTEM
-- ============================================================================

function dialogue:setFlag(dialogue_id, flag_name, value)
    helpers:setFlag(self, dialogue_id, flag_name, value)
end

function dialogue:getFlag(dialogue_id, flag_name, default)
    return helpers:getFlag(self, dialogue_id, flag_name, default)
end

function dialogue:hasFlag(dialogue_id, flag_name)
    return helpers:hasFlag(self, dialogue_id, flag_name)
end

function dialogue:clearFlags(dialogue_id)
    helpers:clearFlags(self, dialogue_id)
end

function dialogue:clearAllFlags()
    helpers:clearAllFlags(self)
end

function dialogue:clearChoiceHistory()
    helpers:clearChoiceHistory(self)
end

return dialogue
