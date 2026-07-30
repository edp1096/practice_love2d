package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var contentNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

type contentTemplate struct {
	directory         string
	referenceKind     string
	optionalReference bool
	render            func(name string, reference string) string
}

const scaffoldUsage = "usage: lovectl new TYPE NAME [REFERENCE_ID]\n" +
	"types: actor, ability, projectile, status, encounter, stage, " +
	"item, equipment, dialogue, cutscene, quest, shop, locale, " +
	"turn-skill, turn-battle"

var contentTemplates = map[string]contentTemplate{
	"actor": {
		directory: "actors",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "actor",
    id = "actor.%s",
    name = "%s",
    tags = {},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 12,
            solid = true,
        },
        ["render.shape"] = {
            shape = "circle",
            color = {0.8, 0.8, 0.85, 1.0},
        },
    },
}
`, name, name)
		},
	},
	"ability": {
		directory: "abilities",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "ability",
    id = "ability.%s",
    name = "%s",

    hitbox = {
        shape = "arc",
        reach = 40,
        arc_degrees = 100,
    },
    cooldown = 0.5,
    windup = 0.1,
    duration = 0.12,
    recovery = 0.15,
    lock_movement = true,

    effects = {
        {
            type = "damage",
            amount = 10,
        },
    },
}
`, name, name)
		},
	},
	"projectile": {
		directory:         "projectiles",
		referenceKind:     "actor",
		optionalReference: true,
		render: func(name string, actorID string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "projectile",
    id = "projectile.%s",
    name = "%s",
    actor = "%s",

    speed = 420,
    lifetime = 1.5,
    spawn_offset = 24,
    pierce = 0,
    destroy_on_wall = true,
    effects = {
        {
            type = "damage",
            amount = 10,
        },
    },
}
`, name, name, actorID)
		},
	},
	"status": {
		directory: "statuses",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "status",
    id = "status.%s",
    name = "%s",

    duration = 1.0,
    stacking = "refresh",
    modifiers = {
        move_speed = 0.9,
    },
    color = {0.55, 0.75, 1.0, 1.0},
}
`, name, name)
		},
	},
	"encounter": {
		directory:     "encounters",
		referenceKind: "actor",
		render: func(name string, actorID string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "encounter",
    id = "encounter.%s",
    name = "%s",
    target_tag = "player",

    waves = {
        {
            id = "wave_1",
            spawns = {
                {
                    id = "enemy_1",
                    actor = "%s",
                    position = {x = 0, y = 0},
                },
            },
        },
    },
}
`, name, name, actorID)
		},
	},
	"stage": {
		directory: "stages",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "stage",
    id = "stage.%s",
    name = "%s",

    width = 960,
    height = 540,
    background = {0.07, 0.08, 0.11, 1.0},
    spawns = {},
}
`, name, name)
		},
	},
	"item": {
		directory: "items",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "item",
    id = "item.%s",
    name = "%s",
    description = "Describe this item.",
    stack_limit = 99,
    value = 0,
}
`, name, name)
		},
	},
	"equipment": {
		directory: "items",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "item",
    id = "item.%s",
    name = "%s",
    description = "Describe this equipment.",
    stack_limit = 1,
    value = 0,
    equipment = {
        slot = "weapon",
        modifiers = {
            attack = 1,
        },
    },
}
`, name, name)
		},
	},
	"dialogue": {
		directory: "dialogues",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "dialogue",
    id = "dialogue.%s",
    name = "%s",
    start = "start",

    nodes = {
        start = {
            speaker = "Speaker",
            text = "Write the dialogue here.",
        },
    },
}
`, name, name)
		},
	},
	"cutscene": {
		directory: "cutscenes",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "cutscene",
    id = "cutscene.%s",
    name = "%s",
    skippable = true,

    steps = {
        {
            id = "opening",
            text = "Write the opening scene here.",
        },
    },
    on_complete = {},
}
`, name, name)
		},
	},
	"quest": {
		directory: "quests",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "quest",
    id = "quest.%s",
    name = "%s",
    description = "Describe the objective.",

    objectives = {
        {
            id = "progress",
            event = "quest.%s.progress",
            count = 1,
        },
    },
}
`, name, name, name)
		},
	},
	"shop": {
		directory:     "shops",
		referenceKind: "item",
		render: func(name string, itemID string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "shop",
    id = "shop.%s",
    name = "%s",
    offers = {
        {
            item = "%s",
            buy_price = 10,
            sell_price = 5,
        },
    },
}
`, name, name, itemID)
		},
	},
	"locale": {
		directory: "locales",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "locale",
    id = "locale.%s",
    name = "%s",
    code = "%s",
    strings = {
        ["example.text"] = "Replace this text.",
    },
}
`, name, name, name)
		},
	},
	"turn-skill": {
		directory: "skills",
		render: func(name string, _ string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "turn_skill",
    id = "turn_skill.%s",
    name = "%s",
    effect = "damage",
    target = "enemy",
    power = 10,
}
`, name, name)
		},
	},
	"turn-battle": {
		directory:     "battles",
		referenceKind: "actor",
		render: func(name string, actorID string) string {
			return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "turn_battle",
    id = "turn_battle.%s",
    name = "%s",
    allow_escape = true,
    enemies = {
        {
            id = "enemy_1",
            actor = "%s",
        },
    },
    on_victory = {},
}
`, name, name, actorID)
		},
	},
}

func projectileActorScaffold(name string) string {
	return fmt.Sprintf(`return {
    schema_version = 1,
    kind = "actor",
    id = "actor.projectile_%s",
    name = "%s Projectile",
    tags = {"projectile"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 6,
            solid = true,
            collision_layer = "projectile",
            collision_mask = {"world"},
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["render.shape"] = {
            shape = "circle",
            radius = 7,
            color = {0.25, 0.75, 1.0, 1.0},
            outline = {0.8, 0.95, 1.0, 1.0},
            layer = 10,
        },
    },
}
`, name, name)
}

func writeScaffoldFile(path string, contents string) error {
	file, err := os.OpenFile(
		path,
		os.O_WRONLY|os.O_CREATE|os.O_EXCL,
		0o644,
	)
	if err != nil {
		if os.IsExist(err) {
			return fmt.Errorf("content already exists: %s", path)
		}
		return err
	}
	_, writeErr := file.WriteString(contents)
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}

func createScaffold(
	projectPath string,
	arguments []string,
) ([]string, error) {
	if len(arguments) < 2 {
		return nil, errors.New(scaffoldUsage)
	}
	kind := arguments[0]
	name := arguments[1]
	template, ok := contentTemplates[kind]
	if !ok {
		return nil, fmt.Errorf(
			"unsupported content template %q\n%s",
			kind,
			scaffoldUsage,
		)
	}
	if !contentNamePattern.MatchString(name) {
		return nil, errors.New(
			"NAME must start with a lowercase letter and contain only " +
				"lowercase letters, numbers, and underscores",
		)
	}
	expectedArguments := 2
	if template.referenceKind != "" {
		expectedArguments = 3
	}
	validArgumentCount := len(arguments) == expectedArguments ||
		(template.optionalReference && len(arguments) == 2)
	if !validArgumentCount {
		usage := fmt.Sprintf("usage: lovectl new %s NAME", kind)
		if template.referenceKind != "" {
			referenceName :=
				strings.ToUpper(template.referenceKind) + "_ID"
			if template.optionalReference {
				usage += " [" + referenceName + "]"
			} else {
				usage += " " + referenceName
			}
		}
		return nil, errors.New(usage)
	}
	reference := ""
	if template.referenceKind != "" && len(arguments) == 3 {
		reference = arguments[2]
		if !contentIDPattern.MatchString(reference) ||
			!strings.HasPrefix(reference, template.referenceKind+".") {
			return nil, fmt.Errorf(
				"REFERENCE_ID must be a %s.* content ID",
				template.referenceKind,
			)
		}
	}
	generatedActorPath := ""
	if kind == "projectile" && reference == "" {
		reference = "actor.projectile_" + name
		actorDirectory := filepath.Join(
			projectPath,
			"game",
			"content",
			"actors",
		)
		if err := os.MkdirAll(actorDirectory, 0o755); err != nil {
			return nil, err
		}
		generatedActorPath = filepath.Join(
			actorDirectory,
			"projectile_"+name+".lua",
		)
	}

	directory := filepath.Join(
		projectPath,
		"game",
		"content",
		template.directory,
	)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return nil, err
	}
	path := filepath.Join(directory, name+".lua")
	for _, candidate := range []string{generatedActorPath, path} {
		if candidate == "" {
			continue
		}
		if _, err := os.Lstat(candidate); err == nil {
			return nil, fmt.Errorf("content already exists: %s", candidate)
		} else if !os.IsNotExist(err) {
			return nil, err
		}
	}
	if generatedActorPath != "" {
		if err := writeScaffoldFile(
			generatedActorPath,
			projectileActorScaffold(name),
		); err != nil {
			return nil, err
		}
	}
	if err := writeScaffoldFile(
		path,
		template.render(name, reference),
	); err != nil {
		if generatedActorPath != "" {
			_ = os.Remove(generatedActorPath)
		}
		return nil, err
	}
	paths := []string{}
	if generatedActorPath != "" {
		paths = append(paths, generatedActorPath)
	}
	paths = append(paths, path)
	return paths, nil
}

func runScaffold(projectPath string, arguments []string) error {
	paths, err := createScaffold(projectPath, arguments)
	if err != nil {
		return err
	}
	for _, path := range paths {
		fmt.Println(path)
	}
	return nil
}
