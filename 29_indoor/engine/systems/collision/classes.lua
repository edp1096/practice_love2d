-- engine/systems/collision/classes.lua
-- Setup collision classes and ignore rules

local classes = {}

-- Setup collision classes and ignore rules for physics world
function classes.setup(physicsWorld, game_mode)
    physicsWorld:addCollisionClass("Player")
    physicsWorld:addCollisionClass("PlayerDodging")
    physicsWorld:addCollisionClass("PlayerFoot")  -- Topdown foot collider
    physicsWorld:addCollisionClass("PlayerFootDodging")  -- Topdown foot collider during dodge
    physicsWorld:addCollisionClass("Wall")
    physicsWorld:addCollisionClass("WallBase")    -- Topdown base surface
    physicsWorld:addCollisionClass("Portals")
    physicsWorld:addCollisionClass("Enemy")
    physicsWorld:addCollisionClass("EnemyFoot")   -- Topdown enemy foot collider
    physicsWorld:addCollisionClass("NPC")
    physicsWorld:addCollisionClass("Item")
    physicsWorld:addCollisionClass("DeathZone")
    physicsWorld:addCollisionClass("DamageZone")

    physicsWorld.collision_classes.PlayerDodging.ignores = { "Enemy", "EnemyFoot" }

    -- PlayerFootDodging: like PlayerFoot but ignores EnemyFoot (passes through enemies during dodge)
    -- Still collides with Wall, WallBase, NPC (can't dodge through walls/NPCs)
    physicsWorld.collision_classes.PlayerFootDodging.ignores = { "Player", "PlayerDodging", "Enemy", "EnemyFoot", "Portals", "Item", "DeathZone", "DamageZone" }

    -- Topdown mode: Player and Enemy main colliders ignore each other (only foot colliders collide)
    if game_mode == "topdown" then
        physicsWorld.collision_classes.Player.ignores = { "Enemy" }
        physicsWorld.collision_classes.Enemy.ignores = { "Player", "PlayerFootDodging" }

        -- PlayerFoot: collides with Wall, WallBase, EnemyFoot, and NPC (topdown needs NPC collision!)
        physicsWorld.collision_classes.PlayerFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "Item", "DeathZone", "DamageZone" }

        -- EnemyFoot: collides with Wall, WallBase, PlayerFoot, and NPC (but NOT PlayerFootDodging)
        physicsWorld.collision_classes.EnemyFoot.ignores = { "Player", "PlayerDodging", "PlayerFootDodging", "Enemy", "Portals", "Item", "DeathZone", "DamageZone" }
    else
        -- Platformer mode: PlayerFoot and EnemyFoot don't exist, Player main collider handles everything
        -- But we still set up the rules in case they're created
        physicsWorld.collision_classes.PlayerFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }
        physicsWorld.collision_classes.EnemyFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }
    end

    -- WallBase only collides with PlayerFoot and EnemyFoot (not with combat or other systems)
    physicsWorld.collision_classes.WallBase.ignores = { "Player", "PlayerDodging", "Enemy", "Wall", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }

    physicsWorld:collisionClassesSet()
end

return classes
