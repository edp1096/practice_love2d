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
	directory     string
	referenceKind string
	render        func(name string, reference string) string
}

const scaffoldUsage = "usage: lovectl new TYPE NAME [REFERENCE_ID]\n" +
	"types: actor, ability, projectile, status, encounter, stage, " +
	"item, equipment, dialogue, quest, shop, locale"

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
		directory:     "projectiles",
		referenceKind: "actor",
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
}

func runScaffold(projectPath string, arguments []string) error {
	if len(arguments) < 2 {
		return errors.New(scaffoldUsage)
	}
	kind := arguments[0]
	name := arguments[1]
	template, ok := contentTemplates[kind]
	if !ok {
		return fmt.Errorf("unsupported content template %q\n%s", kind, scaffoldUsage)
	}
	if !contentNamePattern.MatchString(name) {
		return errors.New(
			"NAME must start with a lowercase letter and contain only " +
				"lowercase letters, numbers, and underscores",
		)
	}
	expectedArguments := 2
	if template.referenceKind != "" {
		expectedArguments = 3
	}
	if len(arguments) != expectedArguments {
		usage := fmt.Sprintf("usage: lovectl new %s NAME", kind)
		if template.referenceKind != "" {
			usage += " " + strings.ToUpper(template.referenceKind) + "_ID"
		}
		return errors.New(usage)
	}
	reference := ""
	if template.referenceKind != "" {
		reference = arguments[2]
		if !contentIDPattern.MatchString(reference) ||
			!strings.HasPrefix(reference, template.referenceKind+".") {
			return fmt.Errorf(
				"REFERENCE_ID must be a %s.* content ID",
				template.referenceKind,
			)
		}
	}

	directory := filepath.Join(
		projectPath,
		"game",
		"content",
		template.directory,
	)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}
	path := filepath.Join(directory, name+".lua")
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		if os.IsExist(err) {
			return fmt.Errorf("content already exists: %s", path)
		}
		return err
	}

	_, writeErr := file.WriteString(template.render(name, reference))
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	fmt.Println(path)
	return nil
}
