-- systems/hud/quickslots.lua
-- Quickslot belt UI rendering and management

local colors = require "engine.ui.colors"

local quickslots = {}

-- Configuration
local SLOT_SIZE = 50
local SLOT_SPACING = 10
local SLOT_COUNT = 5
local FONT_SIZE = 16

-- Font
local key_font = nil
local quantity_font = nil

function quickslots.initialize()
    key_font = love.graphics.newFont(FONT_SIZE)
    quantity_font = love.graphics.newFont(12)
end

-- Draw quickslot belt
function quickslots.draw(inventory, player, display, selected_slot)
    if not key_font then
        quickslots.initialize()
    end

    selected_slot = selected_slot or 1  -- Default to slot 1 if not provided

    -- Calculate position (bottom center of screen)
    local screen_width, screen_height
    if display then
        screen_width, screen_height = display:GetVirtualDimensions()
    else
        screen_width = love.graphics.getWidth()
        screen_height = love.graphics.getHeight()
    end

    local total_width = SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_SPACING
    local start_x = (screen_width - total_width) / 2
    local y = screen_height - SLOT_SIZE - 20  -- 20px from bottom

    -- Draw each slot
    for i = 1, SLOT_COUNT do
        local x = start_x + (i - 1) * (SLOT_SIZE + SLOT_SPACING)

        quickslots.drawSlot(i, x, y, inventory, player, selected_slot)
    end
end

-- Draw single quickslot
function quickslots.drawSlot(slot_index, x, y, inventory, player, selected_slot)
    -- Get item in this slot
    local item, item_id, item_data = inventory:getQuickslotItem(slot_index)

    -- Draw slot background
    colors:apply(colors.for_quickslot_bg)
    love.graphics.rectangle("fill", x, y, SLOT_SIZE, SLOT_SIZE)

    -- Draw slot border (yellow if selected, gray otherwise)
    if slot_index == selected_slot then
        colors:apply(colors.for_quickslot_selected)
        love.graphics.setLineWidth(3)
    else
        colors:apply(colors.for_quickslot_border)
        love.graphics.setLineWidth(2)
    end
    love.graphics.rectangle("line", x, y, SLOT_SIZE, SLOT_SIZE)

    -- Draw key number
    colors:apply(colors.for_text_normal)
    love.graphics.setFont(key_font)
    local key_text = tostring(slot_index)
    local key_width = key_font:getWidth(key_text)
    love.graphics.print(key_text, x + 4, y + 4)

    -- Draw item if assigned
    if item and item_data then
        local can_use = item.canUse and item:canUse(player)

        -- Draw sprite if available
        if item.sprite then
            local sprite_img = love.graphics.newImage(item.sprite.file)
            local sprite_x = item.sprite.x or 0
            local sprite_y = item.sprite.y or 0
            local sprite_w = item.sprite.w or 32
            local sprite_h = item.sprite.h or 32
            local sprite_scale = item.sprite.scale or 1

            -- Create quad for sprite
            local quad = love.graphics.newQuad(
                sprite_x, sprite_y,
                sprite_w, sprite_h,
                sprite_img:getWidth(), sprite_img:getHeight()
            )

            -- Calculate centering
            local draw_x = x + (SLOT_SIZE - sprite_w * sprite_scale) / 2
            local draw_y = y + (SLOT_SIZE - sprite_h * sprite_scale) / 2

            -- Draw sprite
            if can_use then
                colors:apply(colors.WHITE)
            else
                colors:apply(colors.for_quickslot_unusable)
            end

            love.graphics.draw(sprite_img, quad, draw_x, draw_y, 0, sprite_scale, sprite_scale)
        else
            -- Fallback: draw item name
            colors:apply(can_use and colors.for_text_normal or colors.for_quickslot_unusable)
            love.graphics.setFont(quantity_font)
            local name_short = item.name:sub(1, 6)
            love.graphics.printf(name_short, x + 2, y + SLOT_SIZE/2 - 6, SLOT_SIZE - 4, "center")
        end

        -- Draw quantity if stackable
        if item.max_stack and item.max_stack > 1 then
            local quantity = item.quantity or 1  -- Get from item object, not item_data
            colors:apply(colors.for_text_normal)
            love.graphics.setFont(quantity_font)
            local qty_text = tostring(quantity)
            local qty_width = quantity_font:getWidth(qty_text)
            love.graphics.print(qty_text, x + SLOT_SIZE - qty_width - 4, y + SLOT_SIZE - 16)
        end
    end

    colors:reset()
end

return quickslots
