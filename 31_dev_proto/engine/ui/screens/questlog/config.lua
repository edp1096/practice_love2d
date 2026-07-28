-- engine/ui/screens/questlog/config.lua
-- Quest log UI configuration constants

local ui_constants = require "engine.ui.constants"

local config = {}

-- Panel dimensions (use shared constants)
config.PANEL_WIDTH = ui_constants.PANEL_WIDTH      -- 720
config.PANEL_HEIGHT = ui_constants.PANEL_HEIGHT    -- 450

-- Quest list dimensions
config.LIST_WIDTH = 320
config.LIST_HEIGHT = 310   -- PANEL_HEIGHT (450) - 140

-- Quest item dimensions
config.ITEM_HEIGHT = 50
config.PADDING = ui_constants.PADDING_SMALL  -- 5

-- Category tab dimensions
config.TAB_WIDTH = 130     -- Reduced from 150
config.TAB_HEIGHT = 28     -- Reduced from 35
config.TAB_SPACING = 8     -- Reduced from 10

-- Font sizes (use shared constants)
config.FONT_TITLE = ui_constants.FONT_SIZE_TITLE        -- 16
config.FONT_CATEGORY = ui_constants.FONT_SIZE_INFO      -- 14
config.FONT_QUEST_TITLE = ui_constants.FONT_SIZE_INFO   -- 14
config.FONT_TEXT = ui_constants.FONT_SIZE_SMALL         -- 12
config.FONT_SMALL = 10

-- Scroll settings
config.SCROLL_AMOUNT = 50  -- Pixels per wheel tick (one item height)
config.SCROLL_SPEED = 300  -- Pixels per second for gamepad stick

return config
