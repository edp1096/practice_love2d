package main

import (
	"errors"
	"fmt"
)

func runPreview(client *protocolClient, arguments []string) error {
	if len(arguments) == 0 {
		return errors.New(
			"usage: lovectl preview stage|actor|ability|dialogue ...",
		)
	}
	switch arguments[0] {
	case "stage":
		if len(arguments) < 2 || len(arguments) > 3 {
			return errors.New(
				"usage: lovectl preview stage STAGE_ID [SPAWN_ID]",
			)
		}
		params := map[string]any{"stageId": arguments[1]}
		if len(arguments) == 3 {
			params["spawnId"] = arguments[2]
		}
		return callAndPrint(client, "App.loadStage", params)
	case "actor":
		if len(arguments) != 2 &&
			len(arguments) != 4 &&
			len(arguments) != 5 {
			return errors.New(
				"usage: lovectl preview actor ACTOR_ID [X Y [ENTITY_ID]]",
			)
		}
		params := map[string]any{"actorId": arguments[1]}
		if len(arguments) >= 4 {
			x, err := parseFloat(arguments[2], "X")
			if err != nil {
				return err
			}
			y, err := parseFloat(arguments[3], "Y")
			if err != nil {
				return err
			}
			params["x"] = x
			params["y"] = y
		}
		if len(arguments) == 5 {
			params["entityId"] = arguments[4]
		}
		return callAndPrint(client, "Entity.spawn", params)
	case "ability":
		if len(arguments) != 3 {
			return errors.New(
				"usage: lovectl preview ability ENTITY_ID ABILITY_ID",
			)
		}
		return callAndPrint(
			client,
			"Entity.requestAbility",
			map[string]any{
				"entityId":  arguments[1],
				"abilityId": arguments[2],
			},
		)
	case "dialogue":
		if len(arguments) < 2 || len(arguments) > 3 {
			return errors.New(
				"usage: lovectl preview dialogue DIALOGUE_ID [SPEAKER_ENTITY_ID]",
			)
		}
		params := map[string]any{"dialogueId": arguments[1]}
		if len(arguments) == 3 {
			params["speakerId"] = arguments[2]
		}
		return callAndPrint(client, "Dialogue.start", params)
	default:
		return fmt.Errorf("unknown preview type %q", arguments[0])
	}
}
