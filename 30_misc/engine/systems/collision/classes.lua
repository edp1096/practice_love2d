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
    physicsWorld:addCollisionClass("NPCFoot")    -- Topdown NPC foot collider
    physicsWorld:addCollisionClass("Item")
    physicsWorld:addCollisionClass("DeathZone")
    physicsWorld:addCollisionClass("DamageZone")
    physicsWorld:addCollisionClass("Prop")
    physicsWorld:addCollisionClass("PropFoot")  -- Topdown prop foot collider
    physicsWorld:addCollisionClass("Vehicle")
    physicsWorld:addCollisionClass("VehicleFoot")  -- Topdown vehicle foot collider

    physicsWorld.collision_classes.PlayerDodging.ignores = { "Enemy", "EnemyFoot" }

    -- PlayerFootDodging: like PlayerFoot but ignores EnemyFoot (passes through enemies during dodge)
    -- Still collides with Wall, WallBase, NPC/NPCFoot (can't dodge through walls/NPCs)
    physicsWorld.collision_classes.PlayerFootDodging.ignores = { "Player", "PlayerDodging", "Enemy", "EnemyFoot", "NPC", "Portals", "Item", "DeathZone", "DamageZone" }

    -- Topdown mode: Player and Enemy main colliders ignore each other (only foot colliders collide)
    if game_mode == "topdown" then
        physicsWorld.collision_classes.Player.ignores = { "Enemy", "NPC", "Prop", "Vehicle" }
        physicsWorld.collision_classes.Enemy.ignores = { "Player", "PlayerFootDodging", "NPC", "Prop", "Vehicle" }

        -- PlayerFoot: collides with Wall, WallBase, EnemyFoot, NPCFoot, PropFoot, VehicleFoot
        physicsWorld.collision_classes.PlayerFoot.ignores = { "Player", "PlayerDodging", "Enemy", "NPC", "Prop", "Vehicle", "Portals", "Item", "DeathZone", "DamageZone" }

        -- EnemyFoot: collides with Wall, WallBase, PlayerFoot, NPCFoot, PropFoot, VehicleFoot (but NOT PlayerFootDodging)
        physicsWorld.collision_classes.EnemyFoot.ignores = { "Player", "PlayerDodging", "PlayerFootDodging", "Enemy", "NPC", "Prop", "Vehicle", "Portals", "Item", "DeathZone", "DamageZone" }

        -- NPCFoot: collides with Wall, WallBase, PlayerFoot, EnemyFoot, PropFoot, VehicleFoot
        physicsWorld.collision_classes.NPCFoot.ignores = { "Player", "PlayerDodging", "Enemy", "NPC", "Prop", "Vehicle", "Portals", "Item", "DeathZone", "DamageZone" }

        -- Prop: main collider ignores most things (visual only in topdown)
        physicsWorld.collision_classes.Prop.ignores = { "Player", "PlayerDodging", "PlayerFoot", "PlayerFootDodging", "Enemy", "EnemyFoot", "NPC", "NPCFoot", "Vehicle", "VehicleFoot", "Portals", "Item", "DeathZone", "DamageZone" }

        -- PropFoot: collides with Wall, WallBase, PlayerFoot, EnemyFoot, NPCFoot, VehicleFoot (the actual collision surface)
        physicsWorld.collision_classes.PropFoot.ignores = { "Player", "PlayerDodging", "PlayerFootDodging", "Enemy", "NPC", "Prop", "Vehicle", "Portals", "Item", "DeathZone", "DamageZone" }

        -- Vehicle: main collider ignores most things (like Prop)
        physicsWorld.collision_classes.Vehicle.ignores = { "Player", "PlayerDodging", "PlayerFoot", "PlayerFootDodging", "Enemy", "EnemyFoot", "NPC", "NPCFoot", "Prop", "PropFoot", "Portals", "Item", "DeathZone", "DamageZone" }

        -- VehicleFoot: collides with Wall, WallBase, PlayerFoot, EnemyFoot, NPCFoot, PropFoot
        physicsWorld.collision_classes.VehicleFoot.ignores = { "Player", "PlayerDodging", "PlayerFootDodging", "Enemy", "NPC", "Prop", "Vehicle", "Portals", "Item", "DeathZone", "DamageZone" }
    else
        -- Platformer mode: Foot colliders don't exist, main colliders handle everything
        -- But we still set up the rules in case they're created
        physicsWorld.collision_classes.PlayerFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "NPCFoot", "Item", "DeathZone", "DamageZone" }
        physicsWorld.collision_classes.EnemyFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "NPCFoot", "Item", "DeathZone", "DamageZone" }
        physicsWorld.collision_classes.NPCFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }
    end

    -- WallBase only collides with foot colliders (PlayerFoot, EnemyFoot, NPCFoot)
    physicsWorld.collision_classes.WallBase.ignores = { "Player", "PlayerDodging", "Enemy", "Wall", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }

    physicsWorld:collisionClassesSet()
end

return classes
