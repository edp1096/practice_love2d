-- entities/enemy/render.lua
-- Rendering: sprite, effects, health bar, debug visualization

local debug = require "engine.core.debug"
local text_ui = require "engine.utils.text"
local constants = require "engine.core.constants"

local render = {}

-- Local references to constants for performance
local SHADOW = constants.SHADOW
local HIT_FLASH = constants.HIT_FLASH
local COLLIDER_OFFSETS = constants.COLLIDER_OFFSETS

-- Color swap shader (shared across all enemies)
local color_swap_shader = nil

-- Shared font for attack indicator (create once, reuse for all enemies)
local attack_indicator_font = nil

function render.initialize_shader()
    if not color_swap_shader then
        local shader_code = [[
            uniform vec3 target_color;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 pixel = Texel(texture, texture_coords);

                if (pixel.a > 0.0 && pixel.r > 0.1) {
                    if (pixel.r > pixel.g * 1.5 && pixel.r > pixel.b * 1.5) {
                        float original_brightness = max(max(pixel.r, pixel.g), pixel.b);
                        pixel.rgb = target_color * (original_brightness * 0.8);
                    }
                }

                return pixel * color;
            }
        ]]
        color_swap_shader = love.graphics.newShader(shader_code)
    end
end

function render.draw(enemy)
    -- Ensure shader is loaded
    render.initialize_shader()

    local collider_center_x, collider_center_y = enemy:getColliderCenter()

    -- Debug: detection and attack ranges
    if debug.enabled then
        love.graphics.setColor(1, 1, 0, 0.1)
        love.graphics.circle("fill", collider_center_x, collider_center_y, enemy.detection_range)
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.circle("line", collider_center_x, collider_center_y, enemy.detection_range)

        love.graphics.setColor(1, 0, 0, 0.1)
        love.graphics.circle("fill", collider_center_x, collider_center_y, enemy.attack_range)
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("line", collider_center_x, collider_center_y, enemy.attack_range)
    end

    -- Sprite position: humanoids use collider center (like player/NPC), slimes use offset
    local sprite_draw_x, sprite_draw_y
    if enemy.is_humanoid then
        -- Humanoid: use collider center (origin-based positioning)
        sprite_draw_x = collider_center_x + enemy.hit_shake_x
        sprite_draw_y = collider_center_y + enemy.hit_shake_y
    else
        -- Slime: use sprite_draw_offset (offset-based positioning)
        sprite_draw_x, sprite_draw_y = enemy:getSpritePosition()
        sprite_draw_x = sprite_draw_x + enemy.hit_shake_x
        sprite_draw_y = sprite_draw_y + enemy.hit_shake_y
    end

    -- Shadow (positioned at bottom of foot_collider in topdown, or collider in platformer)
    -- Don't draw shadow if enemy is dead
    if enemy.state ~= constants.ENEMY_STATES.DEAD then
        local shadow_x, shadow_y
        if enemy.game_mode == "topdown" and enemy.foot_collider and enemy.foot_collider.body then
            -- Use foot_collider bottom edge for shadow
            local foot_height
            if enemy.is_humanoid then
                foot_height = enemy.collider_height * COLLIDER_OFFSETS.HUMANOID_FOOT_HEIGHT
            else
                foot_height = enemy.collider_height * COLLIDER_OFFSETS.SLIME_FOOT_HEIGHT
            end
            shadow_x = enemy.foot_collider:getX()
            shadow_y = enemy.foot_collider:getY() + foot_height / 2 - 2
        else
            -- Platformer mode or fallback: use main collider
            shadow_x = collider_center_x
            shadow_y = collider_center_y + (enemy.collider_height / 2) - 2
        end

        local shadow_width = enemy.collider_width * SHADOW.WIDTH_RATIO
        local shadow_height = enemy.collider_width * SHADOW.HEIGHT_RATIO
        love.graphics.setColor(0, 0, 0, SHADOW.ALPHA)
        love.graphics.ellipse("fill", shadow_x, shadow_y, shadow_width, shadow_height)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Determine sprite color
    local draw_color = { 1, 1, 1, 1 }

    if enemy.state == constants.ENEMY_STATES.HIT then
        draw_color = { 1, 1, 1, 1 }
    elseif enemy.state == constants.ENEMY_STATES.DEAD then
        draw_color = { 0.5, 0.5, 0.5, 0.5 }
    elseif enemy.is_stunned then
        -- Stunned: pulsing yellow
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 8)
        draw_color = { 1, 1, pulse, 1 }
    end

    -- Draw weapon behind sprite for left/up directions (humanoid only)
    if enemy.is_humanoid and enemy.weapon and enemy.weapon_drawn then
        if enemy.direction == "left" or enemy.direction == "up" then
            render.drawWeapon(enemy, draw_color)
        end
    end

    -- Apply color swap shader
    if enemy.target_color then
        love.graphics.setShader(color_swap_shader)
        if color_swap_shader then
            color_swap_shader:send("target_color", enemy.target_color)
        end
    end

    love.graphics.setColor(draw_color)

    -- Draw sprite
    enemy.anim:draw(
        enemy.spriteSheet,
        sprite_draw_x,
        sprite_draw_y,
        nil,
        enemy.sprite_scale,
        enemy.sprite_scale,
        enemy.sprite_origin_x,
        enemy.sprite_origin_y
    )

    -- Hit flash
    if enemy.state == constants.ENEMY_STATES.HIT and enemy.hit_flash_timer > 0 then
        local flash_intensity = enemy.hit_flash_timer / HIT_FLASH.DURATION
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, flash_intensity * HIT_FLASH.INTENSITY)
        enemy.anim:draw(
            enemy.spriteSheet,
            sprite_draw_x,
            sprite_draw_y,
            nil,
            enemy.sprite_scale,
            enemy.sprite_scale,
            enemy.sprite_origin_x,
            enemy.sprite_origin_y
        )
        love.graphics.setBlendMode("alpha")
    end

    -- Stun stars effect
    if enemy.is_stunned then
        local star_offset = enemy.collider_width * 1.0
        local star_size = enemy.collider_width * 0.2
        local time = love.timer.getTime()

        for i = 1, 3 do
            local angle = (time * 3 + i * (math.pi * 2 / 3))
            local star_x = collider_center_x + math.cos(angle) * star_offset
            local star_y = collider_center_y - enemy.collider_height * 0.625 + math.sin(angle) * 15

            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.circle("fill", star_x, star_y, star_size)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("line", star_x, star_y, star_size)
        end
    end

    -- Attack windup indicator (!)
    if enemy.state == constants.ENEMY_STATES.ATTACK_WINDUP then
        if not attack_indicator_font then
            attack_indicator_font = love.graphics.newFont(24)
        end

        local indicator_y = collider_center_y - enemy.collider_height * 0.75
        local pulse = 0.5 + math.sin(love.timer.getTime() * 15) * 0.5

        -- Exclamation mark background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.circle("fill", collider_center_x, indicator_y, 12)

        -- Exclamation mark with pulse effect
        love.graphics.setColor(1, 0.2, 0.2, pulse)
        love.graphics.setFont(attack_indicator_font)
        love.graphics.printf("!", collider_center_x - 15, indicator_y - 12, 30, "center")
    end

    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)

    -- Draw weapon in front of sprite for right/down directions (humanoid only)
    if enemy.is_humanoid and enemy.weapon and enemy.weapon_drawn then
        if enemy.direction == "right" or enemy.direction == "down" then
            render.drawWeapon(enemy, draw_color)
        end
    end

    -- Debug: collider
    if debug.show_colliders and enemy.collider then
        love.graphics.setColor(1, 0, 0, 0.3)
        local bounds = enemy:getColliderBounds()
        love.graphics.rectangle("fill", bounds.x - bounds.width / 2, bounds.y - bounds.height / 2, bounds.width, bounds.height)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Health bar
    if enemy.health < enemy.max_health and enemy.state ~= "dead" then
        local bar_width = 40
        local bar_height = 4
        local health_percent = enemy.health / enemy.max_health

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", collider_center_x - bar_width / 2, collider_center_y - 30, bar_width, bar_height)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", collider_center_x - bar_width / 2, collider_center_y - 30, bar_width * health_percent, bar_height)

        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Debug: state info
    if debug.enabled then
        love.graphics.setColor(1, 1, 1, 1)
        local status = enemy.type .. " " .. enemy.state .. " (" .. enemy.direction .. ")"
        if enemy.is_stunned then
            status = status .. " STUNNED"
        end
        text_ui:draw(status, collider_center_x - 40, collider_center_y + 30, {1, 1, 1, 1})

        if enemy.target_x and enemy.target_y then
            love.graphics.setColor(0, 1, 0, 0.5)
            love.graphics.circle("fill", enemy.target_x, enemy.target_y, 5)
            love.graphics.line(collider_center_x, collider_center_y, enemy.target_x, enemy.target_y)
        end

        love.graphics.setColor(1, 1, 1, 1)

        if enemy.state == constants.ENEMY_STATES.CHASE then
            if enemy.world and enemy.world:checkLineOfSight(collider_center_x, collider_center_y, enemy.target_x, enemy.target_y) then
                love.graphics.setColor(0, 1, 0, 0.5)
            else
                love.graphics.setColor(1, 0, 0, 0.5)
            end
            love.graphics.setLineWidth(2)
            love.graphics.line(collider_center_x, collider_center_y, enemy.target_x, enemy.target_y)
            love.graphics.setLineWidth(1)
        end
    end
end

function render.drawWeapon(enemy, draw_color)
    if enemy.weapon then
        -- Apply enemy's color to weapon (for dead/stunned effects)
        if draw_color then
            love.graphics.setColor(draw_color)
        end
        enemy.weapon:draw(debug.enabled)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return render
