local Schema = require "engine.runtime.session_schema"
local util = require "engine.core.util"

local feature = {
    id = "rpg.turn_battle",
    requires = {
        "engine.features.session",
        "engine.features.rpg.locale",
        "engine.features.rpg.stats",
        "engine.features.control",
    },
}

local function validateActions(actions, validator, host, path)
    actions = validator:array(actions, path, false)
    for index, action in ipairs(actions or {}) do
        host.rules:validateAction(
            action,
            validator,
            string.format("%s[%d]", path, index)
        )
    end
end

local function validateSkill(definition, validator)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "name_key",
            "effect", "target", "power",
        },
        "content"
    )
    local name = validator:string(definition.name, "name", false)
    local name_key = validator:string(
        definition.name_key,
        "name_key",
        false
    )
    if not name and not name_key then
        validator:error("name", "requires name or name_key")
    end
    local effect = validator:enum(
        definition.effect,
        {"damage", "heal"},
        "effect",
        true
    )
    local target = validator:enum(
        definition.target,
        {"enemy", "self"},
        "target",
        true
    )
    if effect == "damage" and target and target ~= "enemy" then
        validator:error("target", "damage skills must target enemy")
    elseif effect == "heal" and target and target ~= "self" then
        validator:error("target", "heal skills must target self")
    end
    local power = validator:positive(definition.power, "power", true)
    if power and power % 1 ~= 0 then
        validator:error("power", "must be an integer")
    end
end

local function validateBattler(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"skills"}, path)
    local skills = validator:array(config.skills, path .. ".skills", true)
    if skills and #skills == 0 then
        validator:error(path .. ".skills", "must contain at least one skill")
    end
    local seen = {}
    for index, skill_id in ipairs(skills or {}) do
        local item_path = string.format("%s.skills[%d]", path, index)
        local skill = validator:reference(
            skill_id,
            "turn_skill",
            item_path
        )
        if skill and seen[skill.id] then
            validator:error(item_path, "duplicates another skill")
        elseif skill then
            seen[skill.id] = true
        end
    end
end

local function validateBattle(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "name_key",
            "enemies", "allow_escape", "repeatable",
            "on_start", "on_victory", "on_escape", "on_defeat",
        },
        "content"
    )
    local name = validator:string(definition.name, "name", false)
    local name_key = validator:string(
        definition.name_key,
        "name_key",
        false
    )
    if not name and not name_key then
        validator:error("name", "requires name or name_key")
    end
    validator:boolean(definition.allow_escape, "allow_escape", false)
    validator:boolean(definition.repeatable, "repeatable", false)
    local enemies = validator:array(definition.enemies, "enemies", true)
    if enemies and #enemies == 0 then
        validator:error("enemies", "must contain at least one enemy")
    end
    local seen = {}
    for index, enemy in ipairs(enemies or {}) do
        local path = string.format("enemies[%d]", index)
        if validator:table(enemy, path, true) then
            validator:keys(enemy, {"id", "actor"}, path)
            local id = validator:string(enemy.id, path .. ".id", true)
            if id and seen[id] then
                validator:error(
                    path .. ".id",
                    "duplicates another enemy id"
                )
            elseif id then
                seen[id] = true
            end
            local actor = validator:reference(
                enemy.actor,
                "actor",
                path .. ".actor"
            )
            if actor then
                local components = actor.components or {}
                for _, component_name in ipairs({
                    "action.health",
                    "rpg.stats",
                    "rpg.turn_battler",
                }) do
                    if not components[component_name] then
                        validator:error(
                            path .. ".actor",
                            string.format(
                                "actor '%s' requires component '%s'",
                                actor.id,
                                component_name
                            )
                        )
                    end
                end
            end
        end
    end
    validateActions(definition.on_start, validator, host, "on_start")
    validateActions(
        definition.on_victory,
        validator,
        host,
        "on_victory"
    )
    validateActions(
        definition.on_escape,
        validator,
        host,
        "on_escape"
    )
    validateActions(
        definition.on_defeat,
        validator,
        host,
        "on_defeat"
    )
end

local function stateFor(world)
    local state = world.feature_state.turn_battle
    if not state then
        state = {
            active = false,
            selected = 1,
            turn = 0,
            enemies = {},
            message = nil,
        }
        world.feature_state.turn_battle = state
    end
    return state
end

local function healthConfig(actor)
    return actor.components and actor.components["action.health"] or {}
end

local function statsConfig(actor)
    return actor.components and actor.components["rpg.stats"] or {}
end

local function battlerConfig(actor)
    return actor.components and actor.components["rpg.turn_battler"] or {}
end

function feature:register(host)
    for _, input_name in ipairs({
        "menu_up",
        "menu_down",
        "menu_confirm",
        "menu_cancel",
        "pause",
    }) do
        assert(
            host.input:hasAction(input_name),
            "rpg.turn_battle requires input action '" .. input_name .. "'"
        )
    end

    local session = host.services.session
    local results = session:registerSection("rpg.turn_battles", {
        version = 1,
        defaults = {results = {}},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.turn_battles",
                {"results"},
                {"results"}
            )
            if not valid then return nil, value_error end
            return Schema.map(
                value.results,
                "rpg.turn_battles.results",
                function(result, path)
                    return Schema.enum(
                        result,
                        path,
                        {"won", "lost", "escaped"}
                    )
                end
            )
        end,
    })
    local stats = host.services.stats
    local battle = {}

    local function definition(battle_id)
        local value = host.catalog:get(battle_id)
        if value and value.kind == "turn_battle" then return value end
        return nil
    end

    local function localized(world, value, field, fallback)
        local locale = world:service("locale")
        local key = value and value[field .. "_key"]
        if key and locale then
            return locale:text(key, value[field] or fallback)
        end
        return value and value[field] or fallback
    end

    local function localizedSkill(world, skill)
        return localized(world, skill, "name", skill.id)
    end

    local function playerFor(world, state)
        return state.player_id and world:get(state.player_id) or
            world:findByTag("player")[1]
    end

    local function optionsFor(world, state)
        local options = {}
        local player = playerFor(world, state)
        local battler = player and player.components["rpg.turn_battler"]
        for _, skill_id in ipairs(battler and battler.skills or {}) do
            local skill = host.catalog:get(skill_id)
            options[#options + 1] = {
                id = skill_id,
                type = "skill",
                label = localizedSkill(world, skill),
            }
        end
        local value = definition(state.battle_id)
        if value and value.allow_escape then
            local locale = world:service("locale")
            options[#options + 1] = {
                id = "escape",
                type = "escape",
                label = locale:text("ui.battle.escape", "Escape"),
            }
        end
        return options
    end

    local function executeHooks(world, state, actions, scope)
        local player = playerFor(world, state)
        local result, action_error, failure =
            world:executeActions(actions, {
                source = player,
                target = player,
                interactor = player,
                battle_id = state.battle_id,
            })
        if not result then
            return nil, action_error, {
                battle_id = state.battle_id,
                scope = scope,
                action_index = failure and failure.index or nil,
                action_type = failure and failure.action.type or nil,
                error = action_error,
            }
        end
        return true
    end

    local function emitHookFailure(world, failure)
        if failure then
            world.events:emit("turn_battle.action_failed", failure)
        end
    end

    local function firstLivingEnemy(state)
        for _, enemy in ipairs(state.enemies) do
            if enemy.health > 0 then return enemy end
        end
        return nil
    end

    local function allEnemiesDefeated(state)
        return firstLivingEnemy(state) == nil
    end

    local function finish(world, state, outcome, actions)
        local battle_id = state.battle_id
        results.results[battle_id] = outcome
        local executed, action_error, failure =
            executeHooks(world, state, actions, outcome)
        if not executed then return nil, action_error, failure end
        state.active = false
        state.result = outcome
        state.selected = 1
        world.events:emit("turn_battle." .. outcome, {
            battle_id = battle_id,
            turn = state.turn,
        })
        return {
            applied = true,
            battle_id = battle_id,
            result = outcome,
        }
    end

    local function playerDamage(world, state, skill, enemy)
        local player = playerFor(world, state)
        local attack = stats:value(world, player, "attack")
        local amount = math.max(
            1,
            skill.power + attack - enemy.defense
        )
        enemy.health = math.max(0, enemy.health - amount)
        state.message = string.format(
            "%s -%d",
            enemy.name,
            amount
        )
        world.events:emit("turn_battle.skill_used", {
            battle_id = state.battle_id,
            source_id = player.id,
            skill_id = skill.id,
            target_id = enemy.id,
            amount = amount,
        })
        if enemy.health == 0 then
            world.events:emit("turn_battle.enemy_defeated", {
                battle_id = state.battle_id,
                enemy_id = enemy.id,
                actor_id = enemy.actor_id,
            })
        end
    end

    local function playerHeal(world, state, skill)
        local player = playerFor(world, state)
        local result, heal_error = world:execute({
            type = "heal",
            amount = skill.power,
        }, {
            source = player,
            target = player,
            damage_kind = "turn_battle",
        })
        if not result then return nil, heal_error end
        state.message = string.format(
            "%s +%d",
            player.name or player.id,
            result.amount
        )
        world.events:emit("turn_battle.skill_used", {
            battle_id = state.battle_id,
            source_id = player.id,
            skill_id = skill.id,
            target_id = player.id,
            amount = result.amount,
        })
        return true
    end

    local function enemySkill(enemy)
        local healing
        for _, skill_id in ipairs(enemy.skills) do
            local skill = host.catalog:get(skill_id)
            if skill.effect == "damage" then return skill end
            if skill.effect == "heal" and enemy.health < enemy.max_health then
                healing = healing or skill
            end
        end
        return healing or host.catalog:get(enemy.skills[1])
    end

    local function enemyTurns(world, state)
        local player = playerFor(world, state)
        for _, enemy in ipairs(state.enemies) do
            if enemy.health > 0 and not player.dead then
                local skill = enemySkill(enemy)
                if skill.effect == "heal" then
                    local amount = math.min(
                        skill.power,
                        enemy.max_health - enemy.health
                    )
                    enemy.health = enemy.health + amount
                    state.message = string.format(
                        "%s +%d",
                        enemy.name,
                        amount
                    )
                else
                    local source = {
                        id = "turn_battle." .. enemy.id,
                        components = {
                            ["rpg.stats"] = {
                                attack = enemy.attack,
                                defense = enemy.defense,
                                move_speed = 1,
                            },
                        },
                    }
                    local result, damage_error = world:execute({
                        type = "damage",
                        amount = skill.power,
                    }, {
                        source = source,
                        target = player,
                        damage_kind = "turn_battle",
                    })
                    if not result then return nil, damage_error end
                    state.message = string.format(
                        "%s -%d",
                        player.name or player.id,
                        result.amount
                    )
                end
                world.events:emit("turn_battle.skill_used", {
                    battle_id = state.battle_id,
                    source_id = enemy.id,
                    skill_id = skill.id,
                    target_id =
                        skill.target == "self" and enemy.id or player.id,
                })
            end
        end
        return true
    end

    function battle:start(world, battle_id, player)
        local state = stateFor(world)
        if state.active then
            return nil, "another turn battle is already active"
        end
        local value = definition(battle_id)
        if not value then
            return nil, "unknown turn battle '" .. tostring(battle_id) .. "'"
        end
        if results.results[battle_id] == "won" and
           value.repeatable ~= true then
            return {
                applied = false,
                battle_id = battle_id,
                result = "won",
            }
        end
        player = player or world:findByTag("player")[1]
        if not player or
           not player.components["rpg.turn_battler"] or
           not player.components["action.health"] then
            return nil, "turn battle requires a live player battler"
        end
        if player.dead then return nil, "player battler is not alive" end
        local flow = world:service("game_flow")
        if flow and flow:mode(world) ~= "playing" then
            return nil, "turn battle can only start during gameplay"
        end
        for _, modal_name in ipairs({"dialogue", "shop"}) do
            local modal = world.feature_state[modal_name]
            if modal and modal.active then
                return nil, "turn battle cannot start during " .. modal_name
            end
        end

        local action_failure
        local result, start_error = world:transaction(function()
            state.active = true
            state.battle_id = battle_id
            state.player_id = player.id
            state.selected = 1
            state.turn = 1
            state.result = nil
            state.message = nil
            state.enemies = {}
            for _, entry in ipairs(value.enemies) do
                local actor = host.catalog:get(entry.actor)
                local health = healthConfig(actor)
                local actor_stats = statsConfig(actor)
                local battler = battlerConfig(actor)
                state.enemies[#state.enemies + 1] = {
                    id = entry.id,
                    actor_id = actor.id,
                    name = actor.name or actor.id,
                    health = health.current or health.max,
                    max_health = health.max,
                    attack = actor_stats.attack or 0,
                    defense = actor_stats.defense or 0,
                    skills = util.deepCopy(battler.skills),
                }
            end
            local executed, hook_error, failure =
                executeHooks(world, state, value.on_start, "start")
            if not executed then
                action_failure = failure
                return nil, hook_error
            end
            world.events:emit("turn_battle.started", {
                battle_id = battle_id,
                player_id = player.id,
            })
            return {
                applied = true,
                battle_id = battle_id,
            }
        end)
        if not result then
            emitHookFailure(world, action_failure)
            return nil, start_error
        end
        return result
    end

    function battle:choose(world, selector)
        local state = stateFor(world)
        if not state.active then return nil, "no active turn battle" end
        local options = optionsFor(world, state)
        local option = type(selector) == "number" and options[selector] or nil
        if type(selector) ~= "number" then
            for _, candidate in ipairs(options) do
                if candidate.id == selector then option = candidate end
            end
        end
        if not option then
            return nil, "unknown turn battle command '" ..
                tostring(selector) .. "'"
        end
        local value = definition(state.battle_id)
        local action_failure
        local result, turn_error = world:transaction(function()
            if option.type == "escape" then
                local finished, finish_error, failure = finish(
                    world,
                    state,
                    "escaped",
                    value.on_escape
                )
                action_failure = failure
                return finished, finish_error
            end

            local skill = host.catalog:get(option.id)
            if skill.effect == "damage" then
                playerDamage(
                    world,
                    state,
                    skill,
                    firstLivingEnemy(state)
                )
            else
                local healed, heal_error =
                    playerHeal(world, state, skill)
                if not healed then return nil, heal_error end
            end
            if allEnemiesDefeated(state) then
                local finished, finish_error, failure = finish(
                    world,
                    state,
                    "won",
                    value.on_victory
                )
                action_failure = failure
                return finished, finish_error
            end

            local advanced, enemy_error = enemyTurns(world, state)
            if not advanced then return nil, enemy_error end
            local player = playerFor(world, state)
            if player.dead then
                local finished, finish_error, failure = finish(
                    world,
                    state,
                    "lost",
                    value.on_defeat
                )
                action_failure = failure
                return finished, finish_error
            end
            state.turn = state.turn + 1
            return {
                applied = true,
                battle_id = state.battle_id,
                turn = state.turn,
            }
        end)
        if not result then
            emitHookFailure(world, action_failure)
            return nil, turn_error
        end
        return result
    end

    function battle:state(world, battle_id)
        local state = stateFor(world)
        if state.active and
           (not battle_id or state.battle_id == battle_id) then
            return "active"
        end
        if battle_id then return results.results[battle_id] or "never" end
        return state.result or "never"
    end

    function battle:options(world)
        return optionsFor(world, stateFor(world))
    end

    host:registerContentKind("turn_skill", {
        validate = validateSkill,
    })
    host:registerContentKind("turn_battle", {
        validate = function(definition_value, validator)
            validateBattle(definition_value, validator, host)
        end,
    })
    host:registerComponent("rpg.turn_battler", {
        validate = validateBattler,
        validateEntity = function(_, components, validator, path)
            for _, required in ipairs({
                "action.health",
                "rpg.stats",
            }) do
                if not components[required] then
                    validator:error(
                        path,
                        "requires component '" .. required .. "'"
                    )
                end
            end
        end,
        create = function(config)
            return {skills = util.deepCopy(config.skills)}
        end,
    })
    host.rules:registerAction("start_turn_battle", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "battle"}, path)
            validator:reference(
                action.battle,
                "turn_battle",
                path .. ".battle"
            )
        end,
        execute = function(action, context)
            local player = context.interactor or context.source or
                context.world:findByTag("player")[1]
            return battle:start(context.world, action.battle, player)
        end,
    })
    host.rules:registerCondition("turn_battle_state", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "battle", "state"}, path)
            validator:reference(
                condition.battle,
                "turn_battle",
                path .. ".battle"
            )
            validator:enum(
                condition.state,
                {"never", "active", "won", "lost", "escaped"},
                path .. ".state",
                true
            )
        end,
        evaluate = function(condition, context)
            return battle:state(
                context.world,
                condition.battle
            ) == condition.state
        end,
    })

    host:registerWorldInitializer(
        "rpg.turn_battle",
        98,
        function(world)
            stateFor(world)
            return true
        end
    )
    for _, channel in ipairs({"move", "act", "interact"}) do
        host:registerGate(
            channel,
            "rpg.turn_battle",
            function(_, world)
                if stateFor(world).active then
                    return false, "turn_battle"
                end
                return true
            end
        )
    end
    host:registerTimeFilter(
        "rpg.turn_battle",
        5,
        function(world, dt)
            if stateFor(world).active then return 0 end
            return dt
        end
    )
    host:registerAppController(
        "rpg.turn_battle.input",
        5,
        function(world)
            local state = stateFor(world)
            if not state.active then return false end
            local input = host.input
            local options = optionsFor(world, state)
            if input:consumePressed("pause") then
                state.message = world:service("locale"):text(
                    "ui.battle.pause_blocked",
                    "Finish the battle before pausing."
                )
            elseif input:consumePressed("menu_cancel") then
                local value = definition(state.battle_id)
                if value.allow_escape then
                    battle:choose(world, "escape")
                else
                    state.message = world:service("locale"):text(
                        "ui.battle.escape_blocked",
                        "You cannot escape this battle."
                    )
                end
            elseif input:consumePressed("menu_up") then
                state.selected = state.selected - 1
                if state.selected < 1 then state.selected = #options end
            elseif input:consumePressed("menu_down") then
                state.selected = state.selected + 1
                if state.selected > #options then state.selected = 1 end
            elseif input:consumePressed("menu_confirm") then
                local _, choose_error =
                    battle:choose(world, state.selected)
                if choose_error then state.message = tostring(choose_error) end
            end
            return true
        end
    )

    host:registerService("turn_battle", battle)
    host:registerWorldInspector("rpg.turn_battle", function(world)
        local state = stateFor(world)
        local player = playerFor(world, state)
        local health = player and player.components["action.health"]
        local options = {}
        for _, option in ipairs(optionsFor(world, state)) do
            options[#options + 1] = {
                id = option.id,
                type = option.type,
                label = option.label,
            }
        end
        return {
            turn_battle = {
                active = state.active,
                battle_id = state.battle_id,
                result = state.result,
                turn = state.turn,
                selected = state.selected,
                message = state.message,
                player_id = state.player_id,
                player_health = health and health.current or nil,
                player_max_health = health and health.max or nil,
                enemies = util.deepCopy(state.enemies),
                options = options,
                results = util.deepCopy(results.results),
            },
        }
    end)

    local draw_system = {
        id = "rpg.turn_battle.draw",
        draw_order = 500,
        draw_space = "screen",
    }
    function draw_system:draw(world)
        local state = stateFor(world)
        if not state.active then return end
        local value = definition(state.battle_id)
        local view = world:view()
        love.graphics.setColor(0.018, 0.022, 0.04, 0.97)
        love.graphics.rectangle("fill", 0, 0, view.width, view.height)

        love.graphics.setColor(1, 0.82, 0.3, 1)
        love.graphics.printf(
            localized(world, value, "name", value.id),
            40,
            34,
            view.width - 80,
            "center"
        )
        for index, enemy in ipairs(state.enemies) do
            local x = 90 + (index - 1) * 220
            local y = 105
            love.graphics.setColor(0.86, 0.9, 1, 1)
            love.graphics.print(enemy.name, x, y)
            love.graphics.setColor(0.17, 0.18, 0.24, 1)
            love.graphics.rectangle("fill", x, y + 30, 160, 14, 5, 5)
            love.graphics.setColor(0.92, 0.27, 0.25, 1)
            love.graphics.rectangle(
                "fill",
                x,
                y + 30,
                160 * enemy.health / enemy.max_health,
                14,
                5,
                5
            )
            love.graphics.setColor(0.85, 0.88, 0.94, 1)
            love.graphics.printf(
                string.format("%d / %d", enemy.health, enemy.max_health),
                x,
                y + 51,
                160,
                "center"
            )
        end

        local player = playerFor(world, state)
        local health = player.components["action.health"]
        love.graphics.setColor(0.04, 0.065, 0.095, 1)
        love.graphics.rectangle(
            "fill",
            38,
            view.height - 205,
            view.width - 76,
            166,
            10,
            10
        )
        love.graphics.setColor(0.3, 0.8, 1, 1)
        love.graphics.rectangle(
            "line",
            38,
            view.height - 205,
            view.width - 76,
            166,
            10,
            10
        )
        love.graphics.setColor(0.82, 0.9, 1, 1)
        love.graphics.print(
            string.format(
                "%s   HP %d / %d   TURN %d",
                player.name or player.id,
                health.current,
                health.max,
                state.turn
            ),
            60,
            view.height - 183
        )
        for index, option in ipairs(optionsFor(world, state)) do
            local selected = index == state.selected
            love.graphics.setColor(
                selected and 1 or 0.72,
                selected and 0.84 or 0.78,
                selected and 0.3 or 0.88,
                1
            )
            love.graphics.print(
                (selected and "> " or "  ") .. option.label,
                72,
                view.height - 145 + (index - 1) * 25
            )
        end
        if state.message then
            love.graphics.setColor(0.75, 0.9, 1, 1)
            love.graphics.printf(
                state.message,
                330,
                view.height - 142,
                view.width - 400,
                "center"
            )
        end
    end
    host:registerSystem(draw_system)
end

return feature
