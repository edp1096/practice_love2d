--[[
The MIT License (MIT)

Copyright (c) 2018 SSYGEN

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]] --

local path = ... .. '.'
local wf = {}
wf.Math = require(path .. 'mlib.mlib')

-- Polygon triangulation helper functions
local function getPolygonWindingOrder(vertices)
    local area = 0
    local n = #vertices / 2

    for i = 1, #vertices - 2, 2 do
        local j = i + 2
        if j > #vertices then j = 1 end

        area = area + (vertices[i] * vertices[j + 1] - vertices[j] * vertices[i + 1])
    end

    return area > 0 and "ccw" or "cw"
end

local function reversePolygonVertices(vertices)
    local reversed = {}
    for i = #vertices - 1, 1, -2 do
        table.insert(reversed, vertices[i])
        table.insert(reversed, vertices[i + 1])
    end
    return reversed
end

-- Validate triangle for Box2D compatibility
local function isValidTriangle(triangle)
    if #triangle ~= 6 then return false end

    local x1, y1 = triangle[1], triangle[2]
    local x2, y2 = triangle[3], triangle[4]
    local x3, y3 = triangle[5], triangle[6]

    -- Check minimum distance between vertices (Box2D requires > b2_linearSlop = 0.005)
    local MIN_DISTANCE = 0.1  -- Conservative threshold (0.1 units)

    local dist12 = math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
    local dist23 = math.sqrt((x3 - x2)^2 + (y3 - y2)^2)
    local dist31 = math.sqrt((x1 - x3)^2 + (y1 - y3)^2)

    if dist12 < MIN_DISTANCE or dist23 < MIN_DISTANCE or dist31 < MIN_DISTANCE then
        return false, "vertices too close"
    end

    -- Check triangle area using cross product
    local area = math.abs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2

    -- Minimum area threshold
    local MIN_AREA = 0.01  -- Conservative threshold

    if area < MIN_AREA then
        return false, "area too small"
    end

    return true
end

local function triangulatePolygon(vertices)
    if #vertices <= 16 then
        return { vertices }
    end

    if getPolygonWindingOrder(vertices) == "cw" then
        vertices = reversePolygonVertices(vertices)
    end

    local success, result = pcall(love.math.triangulate, vertices)

    if not success then
        print("Warning: Triangulation failed, attempting to use original polygon")
        if #vertices <= 16 then
            return { vertices }
        else
            print("Error: Polygon too complex (" .. (#vertices / 2) .. " vertices), cannot create collider")
            return {}
        end
    end

    local triangles = {}
    local rejected = 0
    for i, triangle in ipairs(result) do
        if #triangle == 6 then
            if getPolygonWindingOrder(triangle) == "cw" then
                triangle = reversePolygonVertices(triangle)
            end

            -- Validate triangle before adding (critical for web/Box2D)
            local valid, reason = isValidTriangle(triangle)
            if valid then
                table.insert(triangles, triangle)
            else
                rejected = rejected + 1
                print("Warning: Rejected invalid triangle #" .. i .. " (" .. (reason or "unknown") .. ")")
            end
        end
    end

    if #triangles == 0 then
        print("Error: No valid triangles created from triangulation (rejected: " .. rejected .. ")")
        return {}
    end

    if rejected > 0 then
        print("Created " .. #triangles .. " triangles from polygon (rejected " .. rejected .. " invalid)")
    else
        print("Created " .. #triangles .. " triangles from polygon")
    end
    return triangles
end

World = {}
World.__index = World

function wf.newWorld(xg, yg, sleep)
    local world = wf.World.new(wf, xg, yg, sleep)

    world.box2d_world:setCallbacks(world.collisionOnEnter, world.collisionOnExit, world.collisionPre, world.collisionPost)
    world:collisionClear()
    world:addCollisionClass('Default')

    for k, v in pairs(world.box2d_world.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'update' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            world[k] = function(self, ...)
                return v(self.box2d_world, ...)
            end
        end
    end

    return world
end

function World.new(wf_self, xg, yg, sleep)
    local self = {}
    self.wf = wf_self

    self.draw_query_for_n_frames = 10
    self.query_debug_drawing_enabled = false
    self.explicit_collision_events = false
    self.collision_classes = {}
    self.masks = {}
    self.is_sensor_memo = {}
    self.query_debug_draw = {}

    love.physics.setMeter(32)
    self.box2d_world = love.physics.newWorld(xg, yg, sleep)

    return setmetatable(self, World)
end

function World:update(dt)
    self:collisionEventsClear()
    self.box2d_world:update(dt)
end

function World:draw(alpha)
    local r, g, b, a = love.graphics.getColor()
    alpha = alpha or 1

    local old_line_width = love.graphics.getLineWidth()
    local ww, wh = love.graphics.getDimensions()
    local base_width = 960
    local scale = math.max(0.1, ww / base_width)
    local line_width = math.max(1.0, 1.5 / scale)
    love.graphics.setLineWidth(line_width)

    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local fixtures = body:getFixtures()
        for _, fixture in ipairs(fixtures) do
            -- Get collision class from fixture's user data
            local collider = fixture:getUserData()
            local draw_color = {1, 0, 0}  -- Default red
            if collider and collider.collision_class then
                local cc = self.collision_classes[collider.collision_class]
                if cc and cc.draw_color then
                    draw_color = cc.draw_color
                end
            end
            love.graphics.setColor(draw_color[1], draw_color[2], draw_color[3], alpha)
            if fixture:getShape():type() == 'PolygonShape' then
                love.graphics.polygon('line', body:getWorldPoints(fixture:getShape():getPoints()))
            elseif fixture:getShape():type() == 'EdgeShape' or fixture:getShape():type() == 'ChainShape' then
                local points = { body:getWorldPoints(fixture:getShape():getPoints()) }
                for i = 1, #points, 2 do
                    if i < #points - 2 then love.graphics.line(points[i], points[i + 1], points[i + 2], points[i + 3]) end
                end
            elseif fixture:getShape():type() == 'CircleShape' then
                local body_x, body_y = body:getPosition()
                local shape_x, shape_y = fixture:getShape():getPoint()
                local r = fixture:getShape():getRadius()
                love.graphics.circle('line', body_x + shape_x, body_y + shape_y, r, 360)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, alpha)

    love.graphics.setColor(0, 1, 0, alpha)
    local joints = self.box2d_world:getJoints()
    for _, joint in ipairs(joints) do
        local x1, y1, x2, y2 = joint:getAnchors()
        if x1 and y1 then love.graphics.circle('line', x1, y1, 4) end
        if x2 and y2 then love.graphics.circle('line', x2, y2, 4) end
    end
    love.graphics.setColor(1, 1, 1, alpha)

    love.graphics.setColor(0, 0, 1, alpha)
    for _, query_draw in ipairs(self.query_debug_draw) do
        query_draw.frames = query_draw.frames - 1
        if query_draw.type == 'circle' then
            love.graphics.circle('line', query_draw.x, query_draw.y, query_draw.r)
        elseif query_draw.type == 'rectangle' then
            love.graphics.rectangle('line', query_draw.x, query_draw.y, query_draw.w, query_draw.h)
        elseif query_draw.type == 'line' then
            love.graphics.line(query_draw.x1, query_draw.y1, query_draw.x2, query_draw.y2)
        elseif query_draw.type == 'polygon' then
            local triangles = love.math.triangulate(query_draw.vertices)
            for _, triangle in ipairs(triangles) do love.graphics.polygon('line', triangle) end
        end
    end
    for i = #self.query_debug_draw, 1, -1 do
        if self.query_debug_draw[i].frames <= 0 then
            table.remove(self.query_debug_draw, i)
        end
    end
    love.graphics.setColor(r, g, b, a)
    love.graphics.setLineWidth(old_line_width)
end

function World:setQueryDebugDrawing(value)
    self.query_debug_drawing_enabled = value
end

function World:setExplicitCollisionEvents(value)
    self.explicit_collision_events = value
end

function World:addCollisionClass(collision_class_name, collision_class)
    if self.collision_classes[collision_class_name] then error('Collision class ' .. collision_class_name .. ' already exists.') end

    if self.explicit_collision_events then
        self.collision_classes[collision_class_name] = collision_class or {}
    else
        self.collision_classes[collision_class_name] = collision_class or {}
        self.collision_classes[collision_class_name].enter = {}
        self.collision_classes[collision_class_name].exit = {}
        self.collision_classes[collision_class_name].pre = {}
        self.collision_classes[collision_class_name].post = {}
        for c_class_name, _ in pairs(self.collision_classes) do
            table.insert(self.collision_classes[collision_class_name].enter, c_class_name)
            table.insert(self.collision_classes[collision_class_name].exit, c_class_name)
            table.insert(self.collision_classes[collision_class_name].pre, c_class_name)
            table.insert(self.collision_classes[collision_class_name].post, c_class_name)
        end
        for c_class_name, _ in pairs(self.collision_classes) do
            table.insert(self.collision_classes[c_class_name].enter, collision_class_name)
            table.insert(self.collision_classes[c_class_name].exit, collision_class_name)
            table.insert(self.collision_classes[c_class_name].pre, collision_class_name)
            table.insert(self.collision_classes[c_class_name].post, collision_class_name)
        end
    end

    self:collisionClassesSet()
end

function World:collisionClassesSet()
    self:generateCategoriesMasks()

    self:collisionClear()
    local collision_table = self:getCollisionCallbacksTable()
    for collision_class_name, collision_list in pairs(collision_table) do
        for _, collision_info in ipairs(collision_list) do
            if collision_info.type == 'enter' then self:addCollisionEnter(collision_class_name, collision_info.other) end
            if collision_info.type == 'exit' then self:addCollisionExit(collision_class_name, collision_info.other) end
            if collision_info.type == 'pre' then self:addCollisionPre(collision_class_name, collision_info.other) end
            if collision_info.type == 'post' then self:addCollisionPost(collision_class_name, collision_info.other) end
        end
    end

    self:collisionEventsClear()
end

function World:collisionClear()
    self.collisions = {}
    self.collisions.on_enter = {}
    self.collisions.on_enter.sensor = {}
    self.collisions.on_enter.non_sensor = {}
    self.collisions.on_exit = {}
    self.collisions.on_exit.sensor = {}
    self.collisions.on_exit.non_sensor = {}
    self.collisions.pre = {}
    self.collisions.pre.sensor = {}
    self.collisions.pre.non_sensor = {}
    self.collisions.post = {}
    self.collisions.post.sensor = {}
    self.collisions.post.non_sensor = {}
end

function World:collisionEventsClear()
    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local fixtures = body:getFixtures()
        if fixtures and fixtures[1] then
            local collider = fixtures[1]:getUserData()
            if collider and collider.collisionEventsClear then
                collider:collisionEventsClear()
            end
        end
    end
end

function World:addCollisionEnter(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.on_enter.non_sensor, { type1 = type1, type2 = type2 })
    else
        table.insert(self.collisions.on_enter.sensor, { type1 = type1, type2 = type2 })
    end
end

function World:addCollisionExit(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.on_exit.non_sensor, { type1 = type1, type2 = type2 })
    else
        table.insert(self.collisions.on_exit.sensor, { type1 = type1, type2 = type2 })
    end
end

function World:addCollisionPre(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.pre.non_sensor, { type1 = type1, type2 = type2 })
    else
        table.insert(self.collisions.pre.sensor, { type1 = type1, type2 = type2 })
    end
end

function World:addCollisionPost(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.post.non_sensor, { type1 = type1, type2 = type2 })
    else
        table.insert(self.collisions.post.sensor, { type1 = type1, type2 = type2 })
    end
end

function World:doesType1IgnoreType2(type1, type2)
    local collision_ignores = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_ignores[collision_class_name] = collision_class.ignores or {}
    end
    local all = {}
    for collision_class_name, _ in pairs(collision_ignores) do
        table.insert(all, collision_class_name)
    end
    local ignored_types = {}
    for _, collision_class_type in ipairs(collision_ignores[type1]) do
        if collision_class_type == 'All' then
            for _, collision_class_name in ipairs(all) do
                table.insert(ignored_types, collision_class_name)
            end
        else
            table.insert(ignored_types, collision_class_type)
        end
    end
    for key, _ in pairs(collision_ignores[type1]) do
        if key == 'except' then
            for _, except_type in ipairs(collision_ignores[type1].except) do
                for i = #ignored_types, 1, -1 do
                    if ignored_types[i] == except_type then table.remove(ignored_types, i) end
                end
            end
        end
    end
    for _, ignored_type in ipairs(ignored_types) do
        if ignored_type == type2 then return true end
    end
end

function World:isCollisionBetweenSensors(type1, type2)
    if not self.is_sensor_memo[type1] then self.is_sensor_memo[type1] = {} end
    if not self.is_sensor_memo[type1][type2] then self.is_sensor_memo[type1][type2] = (self:doesType1IgnoreType2(type1, type2) or self:doesType1IgnoreType2(type2, type1)) end
    if self.is_sensor_memo[type1][type2] then
        return true
    else
        return false
    end
end

function World:generateCategoriesMasks()
    local collision_ignores = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_ignores[collision_class_name] = collision_class.ignores or {}
    end
    local incoming = {}
    local expanded = {}
    local all = {}
    for object_type, _ in pairs(collision_ignores) do
        incoming[object_type] = {}
        expanded[object_type] = {}
        table.insert(all, object_type)
    end
    for object_type, ignore_list in pairs(collision_ignores) do
        for key, ignored_type in pairs(ignore_list) do
            if ignored_type == nil then
                error('Collision class ' .. object_type .. ' has a nil ignored type.')
            end

            if ignored_type == 'All' then
                for _, all_object_type in ipairs(all) do
                    table.insert(incoming[all_object_type], object_type)
                    table.insert(expanded[object_type], all_object_type)
                end
            elseif type(ignored_type) == 'string' then
                if ignored_type ~= 'All' then
                    table.insert(incoming[ignored_type], object_type)
                    table.insert(expanded[object_type], ignored_type)
                end
            end
            if key == 'except' then
                for _, except_ignored_type in ipairs(ignored_type) do
                    for i, v in ipairs(incoming[except_ignored_type]) do
                        if v == object_type then
                            table.remove(incoming[except_ignored_type], i)
                            break
                        end
                    end
                end
                for _, except_ignored_type in ipairs(ignored_type) do
                    for i, v in ipairs(expanded[object_type]) do
                        if v == except_ignored_type then
                            table.remove(expanded[object_type], i)
                            break
                        end
                    end
                end
            end
        end
    end
    local edge_groups = {}
    for k, v in pairs(incoming) do
        table.sort(v, function(a, b) return string.lower(a) < string.lower(b) end)
    end
    local i = 0
    for k, v in pairs(incoming) do
        local str = ""
        for _, c in ipairs(v) do
            str = str .. c
        end
        if not edge_groups[str] then
            i = i + 1; edge_groups[str] = { n = i }
        end
        table.insert(edge_groups[str], k)
    end
    local categories = {}
    for k, _ in pairs(collision_ignores) do
        categories[k] = {}
    end
    for k, v in pairs(edge_groups) do
        for i, c in ipairs(v) do
            categories[c] = v.n
        end
    end
    for k, v in pairs(expanded) do
        local category = { categories[k] }
        local current_masks = {}
        for _, c in ipairs(v) do
            table.insert(current_masks, categories[c])
        end
        self.masks[k] = { categories = category, masks = current_masks }
    end
end

function World:getCollisionCallbacksTable()
    local collision_table = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_table[collision_class_name] = {}
        for _, v in ipairs(collision_class.enter or {}) do table.insert(collision_table[collision_class_name], { type = 'enter', other = v }) end
        for _, v in ipairs(collision_class.exit or {}) do table.insert(collision_table[collision_class_name], { type = 'exit', other = v }) end
        for _, v in ipairs(collision_class.pre or {}) do table.insert(collision_table[collision_class_name], { type = 'pre', other = v }) end
        for _, v in ipairs(collision_class.post or {}) do table.insert(collision_table[collision_class_name], { type = 'post', other = v }) end
    end
    return collision_table
end

local function collEnsure(collision_class_name1, a, collision_class_name2, b)
    if a.collision_class == collision_class_name2 and b.collision_class == collision_class_name1 then
        return b, a
    else
        return a, b
    end
end

local function collIf(collision_class_name1, collision_class_name2, a, b)
    if (a.collision_class == collision_class_name1 and b.collision_class == collision_class_name2) or
        (a.collision_class == collision_class_name2 and b.collision_class == collision_class_name1) then
        return true
    else
        return false
    end
end

function World.collisionOnEnter(fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            for _, collision in ipairs(a.world.collisions.on_enter.sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    table.insert(a.collision_events[collision.type2], { collision_type = 'enter', collider_1 = a, collider_2 = b, contact = contact })
                    if collision.type1 == collision.type2 then
                        table.insert(b.collision_events[collision.type1], { collision_type = 'enter', collider_1 = b, collider_2 = a, contact = contact })
                    end
                end
            end
        end
    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            for _, collision in ipairs(a.world.collisions.on_enter.non_sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    table.insert(a.collision_events[collision.type2], { collision_type = 'enter', collider_1 = a, collider_2 = b, contact = contact })
                    if collision.type1 == collision.type2 then
                        table.insert(b.collision_events[collision.type1], { collision_type = 'enter', collider_1 = b, collider_2 = a, contact = contact })
                    end
                end
            end
        end
    end
end

function World.collisionOnExit(fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            for _, collision in ipairs(a.world.collisions.on_exit.sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    table.insert(a.collision_events[collision.type2], { collision_type = 'exit', collider_1 = a, collider_2 = b, contact = contact })
                    if collision.type1 == collision.type2 then
                        table.insert(b.collision_events[collision.type1], { collision_type = 'exit', collider_1 = b, collider_2 = a, contact = contact })
                    end
                end
            end
        end
    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            for _, collision in ipairs(a.world.collisions.on_exit.non_sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    table.insert(a.collision_events[collision.type2], { collision_type = 'exit', collider_1 = a, collider_2 = b, contact = contact })
                    if collision.type1 == collision.type2 then
                        table.insert(b.collision_events[collision.type1], { collision_type = 'exit', collider_1 = b, collider_2 = a, contact = contact })
                    end
                end
            end
        end
    end
end

function World.collisionPre(fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            for _, collision in ipairs(a.world.collisions.pre.sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:preSolve(b, contact)
                    if collision.type1 == collision.type2 then
                        b:preSolve(a, contact)
                    end
                end
            end
        end
    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            for _, collision in ipairs(a.world.collisions.pre.non_sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:preSolve(b, contact)
                    if collision.type1 == collision.type2 then
                        b:preSolve(a, contact)
                    end
                end
            end
        end
    end
end

function World.collisionPost(fixture_a, fixture_b, contact, ni1, ti1, ni2, ti2)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            for _, collision in ipairs(a.world.collisions.post.sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:postSolve(b, contact, ni1, ti1, ni2, ti2)
                    if collision.type1 == collision.type2 then
                        b:postSolve(a, contact, ni1, ti1, ni2, ti2)
                    end
                end
            end
        end
    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            for _, collision in ipairs(a.world.collisions.post.non_sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:postSolve(b, contact, ni1, ti1, ni2, ti2)
                    if collision.type1 == collision.type2 then
                        b:postSolve(a, contact, ni1, ti1, ni2, ti2)
                    end
                end
            end
        end
    end
end

function World:newCircleCollider(x, y, r, settings)
    return self.wf.Collider.new(self, 'Circle', x, y, r, settings)
end

function World:newRectangleCollider(x, y, w, h, settings)
    return self.wf.Collider.new(self, 'Rectangle', x, y, w, h, settings)
end

function World:newBSGRectangleCollider(x, y, w, h, corner_cut_size, settings)
    return self.wf.Collider.new(self, 'BSGRectangle', x, y, w, h, corner_cut_size, settings)
end

function World:newPolygonCollider(vertices, settings)
    return self.wf.Collider.new(self, 'Polygon', vertices, settings)
end

function World:newLineCollider(x1, y1, x2, y2, settings)
    return self.wf.Collider.new(self, 'Line', x1, y1, x2, y2, settings)
end

function World:newChainCollider(vertices, loop, settings)
    return self.wf.Collider.new(self, 'Chain', vertices, loop, settings)
end

function World:_queryBoundingBox(x1, y1, x2, y2)
    local colliders = {}
    local callback = function(fixture)
        if not fixture:isSensor() then table.insert(colliders, fixture:getUserData()) end
        return true
    end
    self.box2d_world:queryBoundingBox(x1, y1, x2, y2, callback)
    return colliders
end

function World:collisionClassInCollisionClassesList(collision_class, collision_classes)
    if collision_classes[1] == 'All' then
        local all_collision_classes = {}
        for class, _ in pairs(self.collision_classes) do
            table.insert(all_collision_classes, class)
        end
        if collision_classes.except then
            for _, except in ipairs(collision_classes.except) do
                for i, class in ipairs(all_collision_classes) do
                    if class == except then
                        table.remove(all_collision_classes, i)
                        break
                    end
                end
            end
        end
        for _, class in ipairs(all_collision_classes) do
            if class == collision_class then return true end
        end
    else
        for _, class in ipairs(collision_classes) do
            if class == collision_class then return true end
        end
    end
end

function World:queryCircleArea(x, y, radius, collision_class_names)
    if not collision_class_names then collision_class_names = { 'All' } end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, { type = 'circle', x = x, y = y, r = radius, frames = self.draw_query_for_n_frames }) end

    local colliders = self:_queryBoundingBox(x - radius, y - radius, x + radius, y + radius)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if self.wf.Math.polygon.getCircleIntersection(x, y, radius, { collider.body:getWorldPoints(fixture:getShape():getPoints()) }) then
                    table.insert(outs, collider)
                    break
                end
            end
        end
    end
    return outs
end

function World:queryRectangleArea(x, y, w, h, collision_class_names)
    if not collision_class_names then collision_class_names = { 'All' } end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, { type = 'rectangle', x = x, y = y, w = w, h = h, frames = self.draw_query_for_n_frames }) end

    local colliders = self:_queryBoundingBox(x, y, x + w, y + h)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if self.wf.Math.polygon.isPolygonInside({ x, y, x + w, y, x + w, y + h, x, y + h }, { collider.body:getWorldPoints(fixture:getShape():getPoints()) }) then
                    table.insert(outs, collider)
                    break
                end
            end
        end
    end
    return outs
end

function World:queryPolygonArea(vertices, collision_class_names)
    if not collision_class_names then collision_class_names = { 'All' } end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, { type = 'polygon', vertices = vertices, frames = self.draw_query_for_n_frames }) end

    local cx, cy = self.wf.Math.polygon.getCentroid(vertices)
    local d_max = 0
    for i = 1, #vertices, 2 do
        local d = self.wf.Math.line.getLength(cx, cy, vertices[i], vertices[i + 1])
        if d > d_max then d_max = d end
    end
    local colliders = self:_queryBoundingBox(cx - d_max, cy - d_max, cx + d_max, cy + d_max)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if self.wf.Math.polygon.isPolygonInside(vertices, { collider.body:getWorldPoints(fixture:getShape():getPoints()) }) then
                    table.insert(outs, collider)
                    break
                end
            end
        end
    end
    return outs
end

function World:queryLine(x1, y1, x2, y2, collision_class_names)
    if not collision_class_names then collision_class_names = { 'All' } end
    if self.query_debug_drawing_enabled then
        table.insert(self.query_debug_draw, { type = 'line', x1 = x1, y1 = y1, x2 = x2, y2 = y2, frames = self.draw_query_for_n_frames })
    end

    local colliders = {}
    local callback = function(fixture, ...)
        if not fixture:isSensor() then table.insert(colliders, fixture:getUserData()) end
        return 1
    end
    self.box2d_world:rayCast(x1, y1, x2, y2, callback)

    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            table.insert(outs, collider)
        end
    end
    return outs
end

function World:addJoint(joint_type, ...)
    local args = { ... }
    if args[1].body then args[1] = args[1].body end
    if type(args[2]) == "table" and args[2].body then args[2] = args[2].body end
    local joint = love.physics['new' .. joint_type](unpack(args))
    return joint
end

function World:removeJoint(joint)
    joint:destroy()
end

function World:destroy()
    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local fixtures = body:getFixtures()
        if fixtures and fixtures[1] then
            local collider = fixtures[1]:getUserData()
            if collider and collider.destroy then
                collider:destroy()
            end
        end
    end
    local joints = self.box2d_world:getJoints()
    for _, joint in ipairs(joints) do joint:destroy() end
    self.box2d_world:destroy()
    self.box2d_world = nil
end

local Collider = {}
Collider.__index = Collider

local generator = love.math.newRandomGenerator(os.time())
local function UUID()
    local fn = function(x)
        local r = generator:random(16) - 1
        r = (x == "x") and (r + 1) or (r % 4) + 9
        return ("0123456789abcdef"):sub(r, r)
    end
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", fn))
end

function Collider.new(world, collider_type, ...)
    local self = {}
    self.id = UUID()
    self.world = world
    self.type = collider_type
    self.object = nil

    self.shapes = {}
    self.fixtures = {}
    self.sensors = {}

    self.collision_events = {}
    self.collision_stay = {}
    self.enter_collision_data = {}
    self.exit_collision_data = {}
    self.stay_collision_data = {}

    local args = { ... }
    local shape, fixture
    if self.type == 'Circle' then
        self.collision_class = (args[4] and args[4].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, args[1], args[2], (args[4] and args[4].body_type) or 'dynamic')
        shape = love.physics.newCircleShape(args[3])
    elseif self.type == 'Rectangle' then
        self.collision_class = (args[5] and args[5].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, args[1] + args[3] / 2, args[2] + args[4] / 2, (args[5] and args[5].body_type) or 'dynamic')
        shape = love.physics.newRectangleShape(args[3], args[4])
    elseif self.type == 'BSGRectangle' then
        self.collision_class = (args[6] and args[6].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, args[1] + args[3] / 2, args[2] + args[4] / 2, (args[6] and args[6].body_type) or 'dynamic')
        local w, h, s = args[3], args[4], args[5]
        shape = love.physics.newPolygonShape({
            -w / 2, -h / 2 + s, -w / 2 + s, -h / 2,
            w / 2 - s, -h / 2, w / 2, -h / 2 + s,
            w / 2, h / 2 - s, w / 2 - s, h / 2,
            -w / 2 + s, h / 2, -w / 2, h / 2 - s
        })
    elseif self.type == 'Polygon' then
        self.collision_class = (args[2] and args[2].collision_class) or 'Default'
        local body_type = (args[2] and args[2].body_type) or 'dynamic'

        if #args[1] < 6 then
            error("Polygon must have at least 3 vertices (got " .. (#args[1] / 2) .. " vertices)")
        end

        if #args[1] > 32 then
            print("Warning: Polygon has " .. (#args[1] / 2) .. " vertices. Complex polygons may have issues.")
        end

        local cx, cy = 0, 0
        local vertex_count = #args[1] / 2
        for i = 1, #args[1], 2 do
            cx = cx + args[1][i]
            cy = cy + args[1][i + 1]
        end
        cx = cx / vertex_count
        cy = cy / vertex_count

        self.body = love.physics.newBody(self.world.box2d_world, cx, cy, body_type)

        local relative_vertices = {}
        for i = 1, #args[1], 2 do
            table.insert(relative_vertices, args[1][i] - cx)
            table.insert(relative_vertices, args[1][i + 1] - cy)
        end

        if getPolygonWindingOrder(relative_vertices) == "cw" then
            relative_vertices = reversePolygonVertices(relative_vertices)
        end

        local triangles = triangulatePolygon(relative_vertices)

        if #triangles == 0 then
            error("Failed to triangulate polygon: no valid triangles created")
        end

        if #triangles > 1 then
            local created_count = 0
            local rejected_count = 0

            for i, triangle in ipairs(triangles) do
                if getPolygonWindingOrder(triangle) == "cw" then
                    triangle = reversePolygonVertices(triangle)
                end

                local success, tri_shape = pcall(love.physics.newPolygonShape, unpack(triangle))
                if success then
                    created_count = created_count + 1
                    self.shapes['main_' .. created_count] = tri_shape

                    local tri_fixture = love.physics.newFixture(self.body, tri_shape)
                    if self.world.masks[self.collision_class] then
                        tri_fixture:setCategory(unpack(self.world.masks[self.collision_class].categories))
                        tri_fixture:setMask(unpack(self.world.masks[self.collision_class].masks))
                    end
                    tri_fixture:setUserData(self)
                    self.fixtures['main_' .. created_count] = tri_fixture

                    local tri_sensor = love.physics.newFixture(self.body, tri_shape)
                    tri_sensor:setSensor(true)
                    tri_sensor:setUserData(self)
                    self.sensors['main_' .. created_count] = tri_sensor
                else
                    rejected_count = rejected_count + 1
                end
            end

            if created_count == 0 then
                error("Failed to create any valid collision shapes for polygon")
            end

            if rejected_count > 0 then
                print(string.format("Polygon collider: %d triangles created, %d rejected by Box2D", created_count, rejected_count))
            else
                print(string.format("Polygon collider: %d triangles created successfully", created_count))
            end

            shape = self.shapes['main_1']
            fixture = self.fixtures['main_1']
        else
            local success, poly_shape = pcall(love.physics.newPolygonShape, unpack(relative_vertices))
            if not success then
                error("Failed to create polygon shape: " .. tostring(poly_shape))
            end
            shape = poly_shape
        end
    elseif self.type == 'Line' then
        self.collision_class = (args[5] and args[5].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, 0, 0, (args[5] and args[5].body_type) or 'dynamic')
        shape = love.physics.newEdgeShape(args[1], args[2], args[3], args[4])
    elseif self.type == 'Chain' then
        self.collision_class = (args[3] and args[3].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, 0, 0, (args[3] and args[3].body_type) or 'dynamic')
        shape = love.physics.newChainShape(args[1], unpack(args[2]))
    end

    if not fixture then
        fixture = love.physics.newFixture(self.body, shape)
        if self.world.masks[self.collision_class] then
            fixture:setCategory(unpack(self.world.masks[self.collision_class].categories))
            fixture:setMask(unpack(self.world.masks[self.collision_class].masks))
        end
        fixture:setUserData(self)
        local sensor = love.physics.newFixture(self.body, shape)
        sensor:setSensor(true)
        sensor:setUserData(self)

        self.shapes['main'] = shape
        self.fixtures['main'] = fixture
        self.sensors['main'] = sensor
    end

    self.shape = shape
    self.fixture = fixture

    self.preSolve = function() end
    self.postSolve = function() end

    for k, v in pairs(self.body.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            self[k] = function(self, ...)
                return v(self.body, ...)
            end
        end
    end
    for k, v in pairs(self.fixture.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            self[k] = function(self, ...)
                return v(self.fixture, ...)
            end
        end
    end
    for k, v in pairs(self.shape.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            self[k] = function(self, ...)
                return v(self.shape, ...)
            end
        end
    end

    return setmetatable(self, Collider)
end

function Collider:collisionEventsClear()
    self.collision_events = {}
    for other, _ in pairs(self.world.collision_classes) do
        self.collision_events[other] = {}
    end
end

function Collider:setCollisionClass(collision_class_name)
    if not self.world.collision_classes[collision_class_name] then error("Collision class " .. collision_class_name .. " doesn't exist.") end
    self.collision_class = collision_class_name
    for _, fixture in pairs(self.fixtures) do
        if self.world.masks[collision_class_name] then
            fixture:setCategory(unpack(self.world.masks[collision_class_name].categories))
            fixture:setMask(unpack(self.world.masks[collision_class_name].masks))
        end
    end
end

function Collider:enter(other_collision_class_name)
    local events = self.collision_events[other_collision_class_name]
    if events and #events >= 1 then
        for _, e in ipairs(events) do
            if e.collision_type == 'enter' then
                if not self.collision_stay[other_collision_class_name] then self.collision_stay[other_collision_class_name] = {} end
                table.insert(self.collision_stay[other_collision_class_name], { collider = e.collider_2, contact = e.contact })
                self.enter_collision_data[other_collision_class_name] = { collider = e.collider_2, contact = e.contact }
                return true
            end
        end
    end
end

function Collider:getEnterCollisionData(other_collision_class_name)
    return self.enter_collision_data[other_collision_class_name]
end

function Collider:exit(other_collision_class_name)
    local events = self.collision_events[other_collision_class_name]
    if events and #events >= 1 then
        for _, e in ipairs(events) do
            if e.collision_type == 'exit' then
                if self.collision_stay[other_collision_class_name] then
                    for i = #self.collision_stay[other_collision_class_name], 1, -1 do
                        local collision_stay = self.collision_stay[other_collision_class_name][i]
                        if collision_stay.collider.id == e.collider_2.id then table.remove(self.collision_stay[other_collision_class_name], i) end
                    end
                end
                self.exit_collision_data[other_collision_class_name] = { collider = e.collider_2, contact = e.contact }
                return true
            end
        end
    end
end

function Collider:getExitCollisionData(other_collision_class_name)
    return self.exit_collision_data[other_collision_class_name]
end

function Collider:stay(other_collision_class_name)
    if self.collision_stay[other_collision_class_name] then
        if #self.collision_stay[other_collision_class_name] >= 1 then
            return true
        end
    end
end

function Collider:getStayCollisionData(other_collision_class_name)
    return self.collision_stay[other_collision_class_name]
end

function Collider:setPreSolve(callback)
    self.preSolve = callback
end

function Collider:setPostSolve(callback)
    self.postSolve = callback
end

function Collider:setObject(object)
    self.object = object
end

function Collider:getObject()
    return self.object
end

function Collider:addShape(shape_name, shape_type, ...)
    if self.shapes[shape_name] or self.fixtures[shape_name] then error("Shape/fixture " .. shape_name .. " already exists.") end
    local args = { ... }
    local shape = love.physics['new' .. shape_type](unpack(args))
    local fixture = love.physics.newFixture(self.body, shape)
    if self.world.masks[self.collision_class] then
        fixture:setCategory(unpack(self.world.masks[self.collision_class].categories))
        fixture:setMask(unpack(self.world.masks[self.collision_class].masks))
    end
    fixture:setUserData(self)
    local sensor = love.physics.newFixture(self.body, shape)
    sensor:setSensor(true)
    sensor:setUserData(self)

    self.shapes[shape_name] = shape
    self.fixtures[shape_name] = fixture
    self.sensors[shape_name] = sensor
end

function Collider:removeShape(shape_name)
    if not self.shapes[shape_name] then return end
    self.shapes[shape_name] = nil
    self.fixtures[shape_name]:setUserData(nil)
    self.fixtures[shape_name]:destroy()
    self.fixtures[shape_name] = nil
    self.sensors[shape_name]:setUserData(nil)
    self.sensors[shape_name]:destroy()
    self.sensors[shape_name] = nil
end

function Collider:destroy()
    self.collision_stay = nil
    self.enter_collision_data = nil
    self.exit_collision_data = nil
    self:collisionEventsClear()

    self:setObject(nil)
    for name, _ in pairs(self.fixtures) do
        self.shapes[name] = nil
        self.fixtures[name]:setUserData(nil)
        self.fixtures[name] = nil
        self.sensors[name]:setUserData(nil)
        self.sensors[name] = nil
    end
    self.body:destroy()
    self.body = nil
end

wf.World = World
wf.Collider = Collider

return wf
