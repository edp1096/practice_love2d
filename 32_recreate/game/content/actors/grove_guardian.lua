return {
    schema_version = 1,
    kind = "actor",
    id = "actor.grove_guardian",
    name = "Grove Guardian",
    tags = {"enemy", "boss"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 20,
            solid = true,
        },
        ["action.hurtbox"] = {
            radius = 20,
        },
        ["render.sprite"] = {
            sprite = "sprite.slime",
            scale = 4,
            tint = {0.76, 0.42, 1.0, 1.0},
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["movement.topdown"] = {
            speed = 64,
        },
        ["action.health"] = {
            max = 240,
            death_delay = 0.55,
        },
        ["action.reaction"] = {
            hit_invulnerability = 0.1,
            flash_duration = 0.18,
        },
        ["action.status"] = {},
        ["action.knockback"] = {
            resistance = 0.65,
        },
        ["action.combat"] = {
            team = "enemy",
            abilities = {"ability.slime_bump"},
            primary = "ability.slime_bump",
        },
        ["action.chase_ai"] = {
            target_tag = "player",
            aggro_range = 520,
            attack_distance = 44,
        },
    },
}
