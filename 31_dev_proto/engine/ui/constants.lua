-- engine/ui/constants.lua
-- Shared UI constants across multiple screens

local constants = {}

-- Container/Panel dimensions (used by inventory, questlog, container)
constants.PANEL_WIDTH = 720
constants.PANEL_HEIGHT = 450
constants.PANEL_Y_IN_CONTAINER = 70  -- Position when inside tabbed container (tab bar at 20, tab height 30, margin 20)

-- Container tab settings
constants.TAB_HEIGHT = 30
constants.TAB_BAR_Y = 20  -- Y position of tab bar in container

-- Common font sizes
constants.FONT_SIZE_TITLE = 16  -- Screen titles (inventory, questlog)
constants.FONT_SIZE_INFO = 14   -- Item info, descriptions
constants.FONT_SIZE_SMALL = 12  -- Small text, hints

-- Close button settings
constants.CLOSE_BUTTON_SIZE = 30
constants.CLOSE_BUTTON_PADDING = 10  -- Distance from panel edge

-- Common spacing values
constants.PADDING_SMALL = 5
constants.PADDING_MEDIUM = 10
constants.PADDING_LARGE = 20
constants.MARGIN_TOP = 20  -- Gap between title and content

return constants
