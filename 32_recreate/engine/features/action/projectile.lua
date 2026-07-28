local geometry = require "engine.core.geometry"
local util = require "engine.core.util"

local feature = {
    id = "action.projectile",
    requires = {
        "engine.features.action.combat",
        "engine.features.motion",
    },
}

local function validateActions(actions, validator, host, path)
    actions = validator:array(actions, path, true)
    if actions and #actions == 0 then
        validator:error(path, "must contain at least one action")
    end
    for index, action in ipairs(actions or {}) do
        host.rules:validateAction(
            action,
            validator,
            string.format("%s[%d]", path, index)
        )
    end
end

local function validateProjectile(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "actor",
            "speed", "lifetime", "spawn_offset", "pierce",
            "destroy_on_wall", "effects",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    local actor = validator:reference(definition.actor, "actor", "actor")
    local body = actor and actor.components and actor.components.body
    if actor and (not body or body.shape ~= "circle") then
        validator:error(
            "actor",
            "projectile actor requires a circle body component"
        )
    end
    if actor and not actor.components["motion.facing"] then
        validator:error(
            "actor",
            "projectile actor requires motion.facing"
        )
    end
    if actor and not actor.components["motion.kinematics"] then
        validator:error(
            "actor",
            "projectile actor requires motion.kinematics"
        )
    end
    validator:positive(definition.speed, "speed", true)
    validator:positive(definition.lifetime, "lifetime", true)
    local offset =
        validator:number(definition.spawn_offset, "spawn_offset", false)
    if offset and offset < 0 then
        validator:error("spawn_offset", "must not be negative")
    end
    local pierce = validator:number(definition.pierce, "pierce", false)
    if pierce and (pierce < 0 or pierce % 1 ~= 0) then
        validator:error("pierce", "must be a non-negative integer")
    end
    validator:boolean(
        definition.destroy_on_wall,
        "destroy_on_wall",
        false
    )
    validateActions(definition.effects, validator, host, "effects")
end

local function validateRuntime(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "projectile", "source_id", "team",
            "direction_x", "direction_y", "ability_id",
        },
        path
    )
    validator:reference(
        config.projectile,
        "projectile",
        path .. ".projectile"
    )
    validator:string(config.source_id, path .. ".source_id", false)
    validator:string(config.team, path .. ".team", true)
    if config.ability_id then
        validator:reference(
            config.ability_id,
            "ability",
            path .. ".ability_id"
        )
    end
    local x = validator:number(
        config.direction_x,
        path .. ".direction_x",
        true
    )
    local y = validator:number(
        config.direction_y,
        path .. ".direction_y",
        true
    )
    if x and y and x == 0 and y == 0 then
        validator:error(path, "direction must not be zero")
    end
end

local function projectileOf(entity)
    return entity and entity.components and
        entity.components["action.projectile"] or nil
end

local function targetCenter(entity)
    local transform = entity.components.transform
    local hurtbox = entity.components["action.hurtbox"]
    return transform.x + hurtbox.offset_x,
        transform.y + hurtbox.offset_y,
        hurtbox.radius
end

local function hitTarget(world, entity, state, definition, target)
    state.hit_targets[target.id] = true
    state.hits = state.hits + 1
    local source = state.source_id and world:get(state.source_id) or nil
    for _, action in ipairs(definition.effects) do
        local result = world:execute(action, {
            source = source or entity,
            target = target,
            ability = state.ability_id and
                world.host.catalog:get(state.ability_id) or nil,
            projectile = definition,
            projectile_entity = entity,
        })
        if type(result) == "table" and result.stop_effects then
            break
        end
    end
    world.events:emit("projectile.hit", {
        entity_id = entity.id,
        projectile_id = definition.id,
        source_id = state.source_id,
        target_id = target.id,
        hit_index = state.hits,
    })
    if state.hits > (definition.pierce or 0) then
        world:remove(entity, "projectile_hit")
        return true
    end
    return false
end

local projectile_system = {
    id = "action.projectile.integrate",
    phase = "combat",
    order = 10,
}

function projectile_system:update(world, dt)
    local motion = world:service("motion")
    for _, entity in ipairs(
        world:query("transform", "body", "action.projectile")
    ) do
        if not world.pending_removal[entity.id] then
            local state = projectileOf(entity)
            local definition =
                world.host.catalog:get(state.projectile_id)
            local transform = entity.components.transform
            local body = entity.components.body
            local start_x, start_y = transform.x, transform.y
            local desired_x =
                state.direction_x * definition.speed * dt
            local desired_y =
                state.direction_y * definition.speed * dt
            local moved_x, moved_y = motion:move(
                world,
                entity,
                desired_x,
                desired_y
            )
            motion:setVelocity(
                entity,
                moved_x / dt,
                moved_y / dt
            )

            local hit_wall =
                math.abs(moved_x - desired_x) > 0.0001 or
                math.abs(moved_y - desired_y) > 0.0001
            if hit_wall and definition.destroy_on_wall ~= false then
                world.events:emit("projectile.blocked", {
                    entity_id = entity.id,
                    projectile_id = definition.id,
                    source_id = state.source_id,
                })
                world:remove(entity, "projectile_blocked")
            else
                for _, target in ipairs(
                    world:query(
                        "transform",
                        "action.hurtbox",
                        "action.health",
                        "action.combat"
                    )
                ) do
                    local combat = target.components["action.combat"]
                    if target ~= entity and
                       target.id ~= state.source_id and
                       not target.dead and
                       combat.team ~= state.team and
                       not state.hit_targets[target.id] then
                        local target_x, target_y, target_radius =
                            targetCenter(target)
                        if geometry.sweptCirclesIntersect(
                            start_x,
                            start_y,
                            transform.x,
                            transform.y,
                            body.radius,
                            target_x,
                            target_y,
                            target_radius
                        ) and hitTarget(
                            world,
                            entity,
                            state,
                            definition,
                            target
                        ) then
                            break
                        end
                    end
                end
            end

            state.remaining =
                util.countdown(state.remaining, dt)
            if state.remaining == 0 and
               not world.pending_removal[entity.id] then
                world.events:emit("projectile.expired", {
                    entity_id = entity.id,
                    projectile_id = definition.id,
                    source_id = state.source_id,
                })
                world:remove(entity, "projectile_expired")
            end
        end
    end
end

function feature:register(host)
    host:registerContentKind("projectile", {
        validate = function(definition, validator)
            validateProjectile(definition, validator, host)
        end,
    })
    host:registerComponent("action.projectile", {
        requires = {
            "body",
            "motion.facing",
            "motion.kinematics",
        },
        validate = validateRuntime,
        create = function(config)
            local definition = host.catalog:get(config.projectile)
            local x, y = util.normalize(
                config.direction_x,
                config.direction_y
            )
            return {
                projectile_id = config.projectile,
                source_id = config.source_id,
                team = config.team,
                direction_x = x,
                direction_y = y,
                remaining = definition.lifetime,
                hits = 0,
                hit_targets = {},
                ability_id = config.ability_id,
            }
        end,
    })
    host.rules:registerAction("spawn_projectile", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "projectile"}, path)
            validator:reference(
                action.projectile,
                "projectile",
                path .. ".projectile"
            )
        end,
        execute = function(action, context)
            local source = context.source
            local transform =
                source and source.components and
                source.components.transform
            local combat =
                source and source.components and
                source.components["action.combat"]
            if not transform or not combat then
                return false,
                    "spawn_projectile requires a combat source"
            end
            local definition =
                context.world.host.catalog:get(action.projectile)
            local facing_x, facing_y =
                context.world:service("motion"):facing(source)
            local offset = definition.spawn_offset or 0
            local entity, spawn_error = context.world:spawn(
                definition.actor,
                {
                    position = {
                        x = transform.x + facing_x * offset,
                        y = transform.y + facing_y * offset,
                    },
                    tags = {"projectile"},
                    components = {
                        ["action.projectile"] = {
                            projectile = definition.id,
                            source_id = source.id,
                            team = combat.team,
                            direction_x = facing_x,
                            direction_y = facing_y,
                            ability_id =
                                context.ability and
                                context.ability.id or nil,
                        },
                    },
                }
            )
            if not entity then return false, spawn_error end
            context.world:service("motion"):setFacing(
                entity,
                facing_x,
                facing_y
            )
            context.world.events:emit("projectile.spawned", {
                entity_id = entity.id,
                projectile_id = definition.id,
                source_id = source.id,
                ability_id =
                    context.ability and context.ability.id or nil,
            })
            return {
                applied = true,
                entity_id = entity.id,
                projectile_id = definition.id,
            }
        end,
    })
    host:registerEntityInspector("action.projectile", function(entity)
        local state = projectileOf(entity)
        if not state then return end
        return {
            projectile_id = state.projectile_id,
            projectile_source_id = state.source_id,
            projectile_team = state.team,
            projectile_remaining = state.remaining,
            projectile_hits = state.hits,
            projectile_direction_x = state.direction_x,
            projectile_direction_y = state.direction_y,
        }
    end)
    host:registerDebugDrawer("action.projectile", function(world, options)
        if not options.entities then return end
        for _, entity in ipairs(
            world:query("transform", "action.projectile")
        ) do
            local transform = entity.components.transform
            local state = projectileOf(entity)
            love.graphics.setColor(0.2, 0.95, 1, 0.95)
            love.graphics.line(
                transform.x,
                transform.y,
                transform.x + state.direction_x * 28,
                transform.y + state.direction_y * 28
            )
        end
    end)
    host:registerSystem(projectile_system)
end

return feature
