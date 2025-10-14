-- entities/enemy.lua
local anim8 = require "vendor.anim8"
local debug = require "systems.debug"

local enemy = {}
enemy.__index = enemy

-- Color swap shader (loaded once, shared by all enemies)
local color_swap_shader = nil

-- Enemy type configurations
local ENEMY_TYPES = {
    red_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 100,
        damage = 10,
        speed = 100,
        attack_cooldown = 1.0,
        detection_range = 200,
        attack_range = 50,

        -- Sprite dimensions (original pixel size)
        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        -- Collider settings (physics collision box)
        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0, -- Offset from entity position to collider center
        collider_offset_y = 0,

        -- Sprite drawing offset (from collider center to sprite draw position)
        sprite_draw_offset_x = -32, -- -(sprite_width * sprite_scale / 2)
        sprite_draw_offset_y = -96, -- Visual alignment with collider

        -- Sprite origin for anim8 (usually 0, 0)
        sprite_origin_x = 0,
        sprite_origin_y = 0,

        -- No color swap needed (original sprite)
        source_color = nil,
        target_color = nil
    },
    green_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png", -- Use same sprite
        health = 80,
        damage = 8,
        speed = 120,
        attack_cooldown = 0.8,
        detection_range = 180,
        attack_range = 50,

        -- Sprite dimensions
        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        -- Collider settings
        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        -- Sprite drawing offset
        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        -- Sprite origin
        sprite_origin_x = 0,
        sprite_origin_y = 0,

        -- Swap red to green
        source_color = { 1.0, 0.0, 0.0 }, -- Red (RGB normalized)
        target_color = { 0.0, 1.0, 0.0 }  -- Green
    },
    blue_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png", -- Use same sprite
        health = 120,
        damage = 12,
        speed = 80,
        attack_cooldown = 1.2,
        detection_range = 220,
        attack_range = 50,

        -- Sprite dimensions
        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        -- Collider settings
        collider_width = 32,
        collider_height = 20,
        collider_offset_x = 0,
        collider_offset_y = 10,

        -- Sprite drawing offset
        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        -- Sprite origin
        sprite_origin_x = 0,
        sprite_origin_y = 0,

        -- Swap red to blue
        source_color = { 1.0, 0.0, 0.0 }, -- Red
        target_color = { 0.0, 0.5, 1.0 }  -- Blue
    },
    purple_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png", -- Use same sprite
        health = 150,
        damage = 15,
        speed = 90,
        attack_cooldown = 1.5,
        detection_range = 250,
        attack_range = 60,

        -- Sprite dimensions
        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        -- Collider settings
        collider_width = 32,
        collider_height = 20,
        collider_offset_x = 0,
        collider_offset_y = 10,

        -- Sprite drawing offset
        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        -- Sprite origin
        sprite_origin_x = 0,
        sprite_origin_y = 0,

        -- Swap red to purple
        source_color = { 1.0, 0.0, 0.0 }, -- Red
        target_color = { 0.8, 0.0, 1.0 }  -- Purple
    }
}

function enemy:new(x, y, enemy_type)
    local instance = setmetatable({}, enemy)

    -- Load shader on first use
    if not color_swap_shader then
        local shader_code = [[
            extern vec3 target_color;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 pixel = Texel(texture, texture_coords);

                // Check if pixel is reddish (red channel is dominant)
                if (pixel.a > 0.0 && pixel.r > 0.1) {
                    // Check if this is a red-dominant pixel
                    if (pixel.r > pixel.g * 1.5 && pixel.r > pixel.b * 1.5) {
                        // Calculate relative brightness (0.0 to 1.0)
                        // Use the maximum color channel as reference
                        float original_brightness = max(max(pixel.r, pixel.g), pixel.b);

                        // Apply target color with proportional brightness
                        pixel.rgb = target_color * (original_brightness * 0.8); // 0.8 to reduce overall brightness
                    }
                }

                return pixel * color;
            }
        ]]
        color_swap_shader = love.graphics.newShader(shader_code)
    end

    -- Default to red_slime if type not specified
    enemy_type = enemy_type or "red_slime"

    -- Get configuration for this enemy type
    local config = ENEMY_TYPES[enemy_type]

    if not config then
        error("Unknown enemy type: " .. tostring(enemy_type))
    end

    instance.x = x or 100
    instance.y = y or 100
    instance.type = enemy_type

    -- Debug: Print enemy type
    print("Creating enemy: " .. enemy_type .. " at (" .. x .. ", " .. y .. ")")
    if config.target_color then
        print("  - Color swap enabled: RGB(" .. config.target_color[1] .. ", " .. config.target_color[2] .. ", " .. config.target_color[3] .. ")")
    end

    -- Apply type-specific stats
    instance.speed = config.speed
    instance.health = config.health
    instance.max_health = config.health
    instance.damage = config.damage
    instance.attack_cooldown = config.attack_cooldown
    instance.detection_range = config.detection_range
    instance.attack_range = config.attack_range

    -- Store color swap info
    instance.source_color = config.source_color
    instance.target_color = config.target_color

    -- Store collider settings (physics)
    instance.collider_width = config.collider_width or 40
    instance.collider_height = config.collider_height or 40
    instance.collider_offset_x = config.collider_offset_x or 0
    instance.collider_offset_y = config.collider_offset_y or 0

    -- Store sprite settings (rendering)
    instance.sprite_width = config.sprite_width or 16
    instance.sprite_height = config.sprite_height or 32
    instance.sprite_scale = config.sprite_scale or 4
    instance.sprite_draw_offset_x = config.sprite_draw_offset_x or (-(instance.sprite_width * instance.sprite_scale / 2))
    instance.sprite_draw_offset_y = config.sprite_draw_offset_y or (-(instance.sprite_height * instance.sprite_scale))
    instance.sprite_origin_x = config.sprite_origin_x or 0
    instance.sprite_origin_y = config.sprite_origin_y or 0

    instance.state = "idle"
    instance.state_timer = 0

    instance.patrol_points = {}
    instance.current_patrol_index = 1

    -- Initialize target position
    instance.target_x = instance.x
    instance.target_y = instance.y

    instance.attack_timer = 0

    -- Hit effect state
    instance.hit_flash_timer = 0     -- Timer for white flash effect
    instance.hit_shake_x = 0         -- Shake offset X
    instance.hit_shake_y = 0         -- Shake offset Y
    instance.hit_shake_intensity = 4 -- Shake distance in pixels

    -- Load type-specific sprite sheet
    instance.spriteSheet = love.graphics.newImage(config.sprite_sheet)
    instance.grid = anim8.newGrid(
        instance.sprite_width,
        instance.sprite_height,
        instance.spriteSheet:getWidth(),
        instance.spriteSheet:getHeight()
    )

    -- Animations for right-facing (row 1)
    instance.animations = {}
    instance.animations.idle_right = anim8.newAnimation(instance.grid("1-3", 1), 0.2)
    instance.animations.walk_right = anim8.newAnimation(instance.grid("4-7", 1), 0.12)
    instance.animations.attack_right = anim8.newAnimation(instance.grid("8-11", 1), 0.1)

    -- Animations for left-facing (row 2)
    instance.animations.idle_left = anim8.newAnimation(instance.grid("1-3", 2), 0.2)
    instance.animations.walk_left = anim8.newAnimation(instance.grid("4-7", 2), 0.12)
    instance.animations.attack_left = anim8.newAnimation(instance.grid("8-11", 2), 0.1)

    instance.anim = instance.animations.idle_right
    instance.direction = "right" -- Track current direction (left or right)

    instance.collider = nil

    -- Deprecated: kept for backward compatibility
    instance.width = instance.collider_width
    instance.height = instance.collider_height

    return instance
end

-- Helper method to get collider bounds with offset
function enemy:getColliderBounds()
    return {
        x = self.x + self.collider_offset_x,
        y = self.y + self.collider_offset_y,
        width = self.collider_width,
        height = self.collider_height
    }
end

function enemy:update(dt, player_x, player_y)
    self.anim:update(dt)

    if self.attack_timer > 0 then
        self.attack_timer = self.attack_timer - dt
    end

    if self.state_timer > 0 then
        self.state_timer = self.state_timer - dt
    end

    -- Update hit flash timer
    if self.hit_flash_timer > 0 then
        self.hit_flash_timer = self.hit_flash_timer - dt
    end

    -- Update hit shake effect (random jitter during hit state)
    if self.state == "hit" then
        -- Generate random shake offset
        self.hit_shake_x = (math.random() - 0.5) * 2 * self.hit_shake_intensity
        self.hit_shake_y = (math.random() - 0.5) * 2 * self.hit_shake_intensity
    else
        -- No shake when not in hit state
        self.hit_shake_x = 0
        self.hit_shake_y = 0
    end

    if self.state == "idle" then
        self:updateIdle(dt, player_x, player_y)
    elseif self.state == "patrol" then
        self:updatePatrol(dt, player_x, player_y)
    elseif self.state == "chase" then
        self:updateChase(dt, player_x, player_y)
    elseif self.state == "attack" then
        self:updateAttack(dt, player_x, player_y)
    elseif self.state == "hit" then
        self:updateHit(dt)
    elseif self.state == "dead" then
        return 0, 0
    end

    -- Calculate movement velocity with nil check
    local vx, vy = 0, 0
    if (self.state == "patrol" or self.state == "chase") and self.target_x and self.target_y then
        local dx = self.target_x - self.x
        local dy = self.target_y - self.y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > 5 then
            vx = (dx / distance) * self.speed
            vy = (dy / distance) * self.speed

            -- Update direction based on horizontal movement
            if math.abs(dx) > 5 then -- Only update if significant horizontal movement
                if dx > 0 then
                    self.direction = "right"
                else
                    self.direction = "left"
                end
            end
        end
    end

    return vx, vy
end

function enemy:updateIdle(dt, player_x, player_y)
    -- Use directional idle animation
    self.anim = self.animations["idle_" .. self.direction]

    local distance = self:getDistanceToPoint(player_x, player_y)
    if distance < self.detection_range then
        -- Check line of sight before chasing (from collider center)
        local collider_center_x = self.x + self.collider_offset_x
        local collider_center_y = self.y + self.collider_offset_y
        if self.world and self.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
            self:setState("chase")
        end
    end

    if self.state_timer <= 0 then
        if #self.patrol_points > 0 then
            self:setState("patrol")
        else
            self.state_timer = math.random(2, 5)
        end
    end
end

function enemy:updatePatrol(dt, player_x, player_y)
    -- Use directional walk animation
    self.anim = self.animations["walk_" .. self.direction]

    local distance = self:getDistanceToPoint(player_x, player_y)
    if distance < self.detection_range then
        -- Check line of sight before chasing (from collider center)
        local collider_center_x = self.x + self.collider_offset_x
        local collider_center_y = self.y + self.collider_offset_y
        if self.world and self.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
            self:setState("chase")
            return
        end
    end

    if #self.patrol_points > 0 then
        local patrol_point = self.patrol_points[self.current_patrol_index]
        self.target_x = patrol_point.x
        self.target_y = patrol_point.y

        local dist_to_point = self:getDistanceToPoint(self.target_x, self.target_y)
        if dist_to_point < 10 then
            self.current_patrol_index = self.current_patrol_index + 1
            if self.current_patrol_index > #self.patrol_points then
                self.current_patrol_index = 1
            end
            self:setState("idle")
        end
    end
end

function enemy:updateChase(dt, player_x, player_y)
    -- Use directional walk animation
    self.anim = self.animations["walk_" .. self.direction]

    local distance = self:getDistanceToPoint(player_x, player_y)

    if distance < self.attack_range then
        self:setState("attack")
        return
    end

    if distance > self.detection_range * 1.5 then
        self:setState("idle")
        return
    end

    -- Lose sight if blocked by wall (check from collider center)
    local collider_center_x = self.x + self.collider_offset_x
    local collider_center_y = self.y + self.collider_offset_y
    if self.world and not self.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
        self:setState("idle")
        return
    end

    self.target_x = player_x
    self.target_y = player_y
end

function enemy:updateAttack(dt, player_x, player_y)
    -- Use directional attack animation
    self.anim = self.animations["attack_" .. self.direction]

    if self.attack_timer <= 0 then
        self.attack_timer = self.attack_cooldown
    end

    if self.state_timer <= 0 then
        self:setState("chase")
    end
end

function enemy:updateHit(dt)
    if self.state_timer <= 0 then
        if self.health > 0 then
            self:setState("chase")
        else
            self:setState("dead")
        end
    end
end

function enemy:setState(new_state)
    self.state = new_state

    if new_state == "idle" then
        self.state_timer = math.random(1, 3)
    elseif new_state == "attack" then
        self.state_timer = 0.5
    elseif new_state == "hit" then
        self.state_timer = 0.3
        self.hit_flash_timer = 0.15 -- Flash for 0.15 seconds (half of hit state)
    end
end

function enemy:takeDamage(damage)
    self.health = self.health - damage

    if self.health <= 0 then
        self.health = 0
        self:setState("dead")
    else
        self:setState("hit")
    end
end

function enemy:getDistanceToPoint(x, y)
    -- Calculate distance from collider center
    local collider_center_x = self.x + self.collider_offset_x
    local collider_center_y = self.y + self.collider_offset_y
    local dx = x - collider_center_x
    local dy = y - collider_center_y
    return math.sqrt(dx * dx + dy * dy)
end

function enemy:setPatrolPoints(points)
    self.patrol_points = points
end

function enemy:draw()
    -- Calculate actual collider center position (this is the logical center of the enemy)
    local collider_center_x = self.x + self.collider_offset_x
    local collider_center_y = self.y + self.collider_offset_y

    -- Debug: Draw detection range
    if debug.debug_mode then
        -- Detection range (yellow circle)
        love.graphics.setColor(1, 1, 0, 0.1)
        love.graphics.circle("fill", collider_center_x, collider_center_y, self.detection_range)
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.circle("line", collider_center_x, collider_center_y, self.detection_range)

        -- Attack range (red circle)
        love.graphics.setColor(1, 0, 0, 0.1)
        love.graphics.circle("fill", collider_center_x, collider_center_y, self.attack_range)
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("line", collider_center_x, collider_center_y, self.attack_range)
    end

    -- Calculate sprite drawing position with shake offset
    local sprite_draw_x = collider_center_x + self.sprite_draw_offset_x + self.hit_shake_x
    local sprite_draw_y = collider_center_y + self.sprite_draw_offset_y + self.hit_shake_y

    -- Draw shadow (ellipse under enemy's feet)
    love.graphics.setColor(0, 0, 0, 0.4)                                            -- Semi-transparent black
    love.graphics.ellipse("fill", collider_center_x, collider_center_y + 30, 18, 8) -- Oval shadow
    love.graphics.setColor(1, 1, 1, 1)                                              -- Reset color

    -- Apply shader if color swap is needed
    if self.target_color then
        love.graphics.setShader(color_swap_shader)
        if color_swap_shader then
            color_swap_shader:send("target_color", self.target_color)
        end
    end

    -- Calculate color based on state
    local draw_color = { 1, 1, 1, 1 }

    if self.state == "hit" then
        -- White flash effect that fades out
        local flash_intensity = self.hit_flash_timer / 0.15
        -- Blend towards white based on flash intensity
        draw_color = { 1, 1, 1, 1 } -- Will be modified after drawing sprite
    elseif self.state == "dead" then
        draw_color = { 0.5, 0.5, 0.5, 0.5 }
    end

    love.graphics.setColor(draw_color)

    -- Draw sprite aligned with collider center (with shake offset applied)
    self.anim:draw(
        self.spriteSheet,
        sprite_draw_x,
        sprite_draw_y,
        nil,
        self.sprite_scale,
        self.sprite_scale,
        self.sprite_origin_x,
        self.sprite_origin_y
    )

    -- Apply white flash overlay if in hit state
    if self.state == "hit" and self.hit_flash_timer > 0 then
        local flash_intensity = self.hit_flash_timer / 0.15
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, flash_intensity * 0.7) -- White overlay
        self.anim:draw(
            self.spriteSheet,
            sprite_draw_x,
            sprite_draw_y,
            nil,
            self.sprite_scale,
            self.sprite_scale,
            self.sprite_origin_x,
            self.sprite_origin_y
        )
        love.graphics.setBlendMode("alpha")
    end

    -- Reset shader
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)

    -- Debug: Hitbox
    if debug.show_colliders and self.collider then
        love.graphics.setColor(1, 0, 0, 0.3)
        local bounds = self:getColliderBounds()
        love.graphics.rectangle("fill", bounds.x - bounds.width / 2, bounds.y - bounds.height / 2, bounds.width, bounds.height)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Health bar
    if self.health < self.max_health and self.state ~= "dead" then
        local bar_width = 40
        local bar_height = 4
        local health_percent = self.health / self.max_health

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", collider_center_x - bar_width / 2, collider_center_y - 30, bar_width, bar_height)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", collider_center_x - bar_width / 2, collider_center_y - 30, bar_width * health_percent, bar_height)

        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Debug: State text
    if debug.debug_mode then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(self.type .. " " .. self.state .. " (" .. self.direction .. ")", collider_center_x - 40, collider_center_y + 30)

        -- Target position
        if self.target_x and self.target_y then
            love.graphics.setColor(0, 1, 0, 0.5)
            love.graphics.circle("fill", self.target_x, self.target_y, 5)
            love.graphics.line(collider_center_x, collider_center_y, self.target_x, self.target_y)
        end

        love.graphics.setColor(1, 1, 1, 1)

        -- Debug: Line of sight
        if self.state == "chase" then
            if self.world and self.world:checkLineOfSight(collider_center_x, collider_center_y, self.target_x, self.target_y) then
                love.graphics.setColor(0, 1, 0, 0.5) -- Green = can see
            else
                love.graphics.setColor(1, 0, 0, 0.5) -- Red = blocked
            end
            love.graphics.setLineWidth(2)
            love.graphics.line(collider_center_x, collider_center_y, self.target_x, self.target_y)
            love.graphics.setLineWidth(1)
        end
    end
end

return enemy
