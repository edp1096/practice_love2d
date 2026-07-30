package gamebuild

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateCutsceneSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"background",
		"skippable",
		"steps",
		"on_complete",
	); err != nil {
		return err
	}
	for _, field := range []string{"name", "name_key"} {
		if err := optionalString(data[field], id+"."+field); err != nil {
			return err
		}
	}
	if err := optionalBoolean(data["skippable"], id+".skippable"); err != nil {
		return err
	}
	if err := validateCutsceneBackground(
		catalog,
		data["background"],
		id+".background",
	); err != nil {
		return err
	}
	steps, err := requiredArray(data["steps"], id+".steps")
	if err != nil {
		return err
	}
	if len(steps) == 0 {
		return fmt.Errorf("%s.steps must not be empty", id)
	}
	seen := make(map[string]struct{}, len(steps))
	for index, raw := range steps {
		path := fmt.Sprintf("%s.steps[%d]", id, index)
		step, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(
			step,
			path,
			"id",
			"speaker",
			"speaker_key",
			"text",
			"text_key",
			"background",
			"duration",
			"actions",
		); err != nil {
			return err
		}
		stepID, err := requiredString(step["id"], path+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[stepID]; duplicate {
			return fmt.Errorf("%s.id duplicates step %q", path, stepID)
		}
		seen[stepID] = struct{}{}
		for _, field := range []string{
			"speaker",
			"speaker_key",
			"text",
			"text_key",
		} {
			if err := optionalString(
				step[field],
				path+"."+field,
			); err != nil {
				return err
			}
		}
		if step["text"] == nil && step["text_key"] == nil {
			return fmt.Errorf("%s requires text or text_key", path)
		}
		if err := validateCutsceneBackground(
			catalog,
			step["background"],
			path+".background",
		); err != nil {
			return err
		}
		if step["duration"] != nil {
			duration, err := requiredPositiveNumberValue(
				step["duration"],
				path+".duration",
			)
			if err != nil {
				return err
			}
			if !durationFitsPortableTicks(duration) {
				return fmt.Errorf(
					"%s.duration exceeds the supported duration",
					path,
				)
			}
		}
		if err := validateActions(
			catalog,
			step["actions"],
			path+".actions",
			false,
		); err != nil {
			return err
		}
	}
	return validateActions(
		catalog,
		data["on_complete"],
		id+".on_complete",
		false,
	)
}

func validateCutsceneBackground(
	catalog *content.Catalog,
	value any,
	path string,
) error {
	if value == nil {
		return nil
	}
	id, err := requiredString(value, path)
	if err != nil {
		return err
	}
	definition, err := referencedDefinition(catalog, id, "asset", path)
	if err != nil {
		return err
	}
	if definition["asset_type"] != "image" {
		return fmt.Errorf("%s must reference an image asset", path)
	}
	return nil
}
