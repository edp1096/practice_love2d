-- entities/enemy/spawner.lua
-- Enemy spawning logic (programmatic enemy creation)

local enemy_module = require "game.entities.enemy"

local spawner = {}

function spawner:spawnEnemy(world, enemy_type, x, y, patrol_points)
    -- Create enemy instance
    local new_enemy = enemy_module:new(x, y, enemy_type)
    new_enemy.world = world

    -- Set patrol points
    if patrol_points then
        new_enemy:setPatrolPoints(patrol_points)
    else
        -- Default patrol pattern
        new_enemy:setPatrolPoints({
            { x = x - 50, y = y - 50 },
            { x = x + 50, y = y - 50 },
            { x = x + 50, y = y + 50 },
            { x = x - 50, y = y + 50 }
        })
    end

    -- Create collider
    local bounds = new_enemy:getColliderBounds()
    new_enemy.collider = world.physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    new_enemy.collider:setFixedRotation(true)
    new_enemy.collider:setCollisionClass("Enemy")
    new_enemy.collider:setObject(new_enemy)

    -- Platformer mode: remove air resistance for faster falling
    if world.game_mode == "platformer" then
        new_enemy.collider:setLinearDamping(0)
        new_enemy.collider:setGravityScale(1)
        local body = new_enemy.collider.body
        if body then
            body:setLinearDamping(0)
        end
    end

    -- Add to world's enemy list
    table.insert(world.enemies, new_enemy)

    return new_enemy
end

function spawner:spawnHumanoidGroup(world, center_x, center_y)
    -- Spawn a group of humanoid enemies in formation
    local enemies = {}

    -- Bandit at front
    table.insert(enemies, spawner:spawnEnemy(world, "bandit", center_x, center_y - 100, {
        { x = center_x - 80, y = center_y - 100 },
        { x = center_x + 80, y = center_y - 100 }
    }))

    -- Rogue on left flank
    table.insert(enemies, spawner:spawnEnemy(world, "rogue", center_x - 120, center_y, {
        { x = center_x - 120, y = center_y - 60 },
        { x = center_x - 120, y = center_y + 60 }
    }))

    -- Warrior in center
    table.insert(enemies, spawner:spawnEnemy(world, "warrior", center_x, center_y, {
        { x = center_x - 40, y = center_y - 40 },
        { x = center_x + 40, y = center_y - 40 },
        { x = center_x + 40, y = center_y + 40 },
        { x = center_x - 40, y = center_y + 40 }
    }))

    -- Guard on right flank
    table.insert(enemies, spawner:spawnEnemy(world, "guard", center_x + 120, center_y, {
        { x = center_x + 120, y = center_y - 60 },
        { x = center_x + 120, y = center_y + 60 }
    }))

    return enemies
end

return spawner
