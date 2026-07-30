return {
    schema_version = 1,
    kind = "actor",
    id = "actor.turn_slime",
    name = "Training Slime",
    tags = {"turn_enemy"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 18,
            solid = false,
        },
        ["render.shape"] = {
            shape = "circle",
            radius = 18,
            color = {0.8, 0.28, 0.38, 1},
            outline = {1, 0.72, 0.78, 1},
            label = "SLIME",
        },
        ["action.health"] = {
            max = 24,
        },
        ["rpg.stats"] = {
            attack = 2,
            defense = 1,
            move_speed = 1,
        },
        ["rpg.turn_battler"] = {
            skills = {"turn_skill.slime_bump"},
        },
        ["rpg.interactable"] = {
            input = "interact",
            range = 72,
            prompt_key = "interaction.battle",
            condition = {
                type = "quest_state",
                quest = "quest.first_steps",
                state = "active",
            },
            actions = {
                {
                    type = "start_turn_battle",
                    battle = "turn_battle.training_slime",
                },
            },
        },
    },
}
