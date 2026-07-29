package gamebuild

import (
	"fmt"
	"math"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateAbilitySemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	for _, field := range []string{"windup", "recovery"} {
		if err := optionalNonNegativeNumber(
			data[field],
			id+"."+field,
		); err != nil {
			return err
		}
	}
	if err := requiredPositiveNumber(data["duration"], id+".duration"); err != nil {
		return err
	}
	if err := requiredNonNegativeNumber(data["cooldown"], id+".cooldown"); err != nil {
		return err
	}
	if err := optionalBoolean(data["lock_movement"], id+".lock_movement"); err != nil {
		return err
	}

	hitbox, hasHitbox, err := optionalObject(data["hitbox"], id+".hitbox")
	if err != nil {
		return err
	}
	if hasHitbox {
		if hitbox["shape"] != "arc" {
			return fmt.Errorf("%s.hitbox.shape must be %q", id, "arc")
		}
		if err := requiredPositiveNumber(
			hitbox["reach"],
			id+".hitbox.reach",
		); err != nil {
			return err
		}
		arc, err := requiredNumber(
			hitbox["arc_degrees"],
			id+".hitbox.arc_degrees",
		)
		if err != nil {
			return err
		}
		if arc <= 0 || arc > 360 {
			return fmt.Errorf(
				"%s.hitbox.arc_degrees must be greater than 0 and at most 360",
				id,
			)
		}
		if err := optionalPositiveNumber(
			hitbox["repeat_interval"],
			id+".hitbox.repeat_interval",
		); err != nil {
			return err
		}
		if err := optionalPositiveInteger(
			hitbox["max_hits"],
			id+".hitbox.max_hits",
		); err != nil {
			return err
		}
		if err := validateActions(
			catalog,
			data["effects"],
			id+".effects",
			true,
		); err != nil {
			return err
		}
	} else if data["effects"] != nil {
		return fmt.Errorf("%s.effects requires a hitbox", id)
	}

	_, hasActivation, err := optionalArray(
		data["activation"],
		id+".activation",
	)
	if err != nil {
		return err
	}
	if hasActivation {
		if err := validateActions(
			catalog,
			data["activation"],
			id+".activation",
			true,
		); err != nil {
			return err
		}
	}
	if !hasHitbox && !hasActivation {
		return fmt.Errorf("%s requires hitbox or activation actions", id)
	}

	if visual, exists, err := optionalObject(data["visual"], id+".visual"); err != nil {
		return err
	} else if exists {
		assetID, err := requiredString(visual["asset"], id+".visual.asset")
		if err != nil {
			return err
		}
		if _, err := referencedDefinition(
			catalog,
			assetID,
			"asset",
			id+".visual.asset",
		); err != nil {
			return err
		}
		if err := optionalPositiveNumber(
			visual["scale"],
			id+".visual.scale",
		); err != nil {
			return err
		}
		for _, field := range []string{"distance", "rotation_offset"} {
			if _, exists := visual[field]; exists {
				if _, err := requiredNumber(
					visual[field],
					id+".visual."+field,
				); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

func validateDialogueSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	for _, field := range []string{"name", "name_key"} {
		if err := optionalString(data[field], id+"."+field); err != nil {
			return err
		}
	}
	start, err := requiredString(data["start"], id+".start")
	if err != nil {
		return err
	}
	nodes, err := requiredObject(data["nodes"], id+".nodes")
	if err != nil {
		return err
	}
	if len(nodes) == 0 {
		return fmt.Errorf("%s.nodes must not be empty", id)
	}
	if _, exists := nodes[start]; !exists {
		return fmt.Errorf("%s.start references missing node %q", id, start)
	}
	for nodeID, raw := range nodes {
		if strings.TrimSpace(nodeID) == "" {
			return fmt.Errorf("%s.nodes contains an empty node id", id)
		}
		path := id + ".nodes." + nodeID
		node, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		for _, field := range []string{
			"speaker",
			"speaker_key",
			"text",
			"text_key",
			"next",
		} {
			if err := optionalString(node[field], path+"."+field); err != nil {
				return err
			}
		}
		if !hasNonEmptyString(node["text"]) &&
			!hasNonEmptyString(node["text_key"]) {
			return fmt.Errorf("%s requires text or text_key", path)
		}
		if err := validateActions(
			catalog,
			node["actions"],
			path+".actions",
			false,
		); err != nil {
			return err
		}
		if next, ok := node["next"].(string); ok {
			if _, exists := nodes[next]; !exists {
				return fmt.Errorf("%s.next references missing node %q", path, next)
			}
		}
		choices, hasChoices, err := optionalArray(node["choices"], path+".choices")
		if err != nil {
			return err
		}
		if hasChoices && len(choices) == 0 {
			return fmt.Errorf("%s.choices must not be empty", path)
		}
		if hasChoices && node["next"] != nil {
			return fmt.Errorf("%s cannot define both next and choices", path)
		}
		choiceIDs := make(map[string]struct{}, len(choices))
		for index, rawChoice := range choices {
			choicePath := fmt.Sprintf("%s.choices[%d]", path, index)
			choice, err := requiredObject(rawChoice, choicePath)
			if err != nil {
				return err
			}
			choiceID, err := requiredString(choice["id"], choicePath+".id")
			if err != nil {
				return err
			}
			if _, duplicate := choiceIDs[choiceID]; duplicate {
				return fmt.Errorf("%s.id duplicates choice %q", choicePath, choiceID)
			}
			choiceIDs[choiceID] = struct{}{}
			for _, field := range []string{"text", "text_key", "next"} {
				if err := optionalString(
					choice[field],
					choicePath+"."+field,
				); err != nil {
					return err
				}
			}
			if !hasNonEmptyString(choice["text"]) &&
				!hasNonEmptyString(choice["text_key"]) {
				return fmt.Errorf("%s requires text or text_key", choicePath)
			}
			if next, ok := choice["next"].(string); ok {
				if _, exists := nodes[next]; !exists {
					return fmt.Errorf(
						"%s.next references missing node %q",
						choicePath,
						next,
					)
				}
			}
			if condition := choice["condition"]; condition != nil {
				if err := validateCondition(
					catalog,
					condition,
					choicePath+".condition",
				); err != nil {
					return err
				}
			}
			if err := validateActions(
				catalog,
				choice["actions"],
				choicePath+".actions",
				false,
			); err != nil {
				return err
			}
		}
	}
	return nil
}

func validateQuestSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := validateDisplayName(data, id); err != nil {
		return err
	}
	for _, field := range []string{"description", "description_key"} {
		if err := optionalString(data[field], id+"."+field); err != nil {
			return err
		}
	}
	objectives, err := requiredArray(data["objectives"], id+".objectives")
	if err != nil {
		return err
	}
	if len(objectives) == 0 {
		return fmt.Errorf("%s.objectives must not be empty", id)
	}
	seen := make(map[string]struct{}, len(objectives))
	for index, raw := range objectives {
		path := fmt.Sprintf("%s.objectives[%d]", id, index)
		objective, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		objectiveID, err := requiredString(objective["id"], path+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[objectiveID]; duplicate {
			return fmt.Errorf("%s.id duplicates objective %q", path, objectiveID)
		}
		seen[objectiveID] = struct{}{}
		if _, err := requiredString(objective["event"], path+".event"); err != nil {
			return err
		}
		if err := optionalPositiveInteger(objective["count"], path+".count"); err != nil {
			return err
		}
		if where, exists, err := optionalObject(
			objective["where"],
			path+".where",
		); err != nil {
			return err
		} else if exists {
			for key, value := range where {
				switch value.(type) {
				case string, float64, bool:
				default:
					return fmt.Errorf(
						"%s.where.%s must be a scalar",
						path,
						key,
					)
				}
			}
		}
	}
	for _, field := range []string{"on_start", "on_complete"} {
		if err := validateActions(
			catalog,
			data[field],
			id+"."+field,
			false,
		); err != nil {
			return err
		}
	}
	return nil
}

func validateLocaleSemantics(data map[string]any, id string) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	if _, err := requiredString(data["code"], id+".code"); err != nil {
		return err
	}
	values, err := requiredObject(data["strings"], id+".strings")
	if err != nil {
		return err
	}
	if len(values) == 0 {
		return fmt.Errorf("%s.strings must not be empty", id)
	}
	for key, value := range values {
		if strings.TrimSpace(key) == "" {
			return fmt.Errorf("%s.strings contains an empty key", id)
		}
		if _, err := requiredString(value, id+".strings."+key); err != nil {
			return err
		}
	}
	return nil
}

func validateAssetSemantics(data map[string]any, id string) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	assetType, err := requiredString(data["asset_type"], id+".asset_type")
	if err != nil {
		return err
	}
	if assetType != "image" &&
		assetType != "font" &&
		assetType != "audio" {
		return fmt.Errorf("%s.asset_type has unsupported value %q", id, assetType)
	}
	if _, err := requiredString(data["path"], id+".path"); err != nil {
		return err
	}
	if assetType == "image" {
		if err := requiredPositiveNumber(data["width"], id+".width"); err != nil {
			return err
		}
		if err := requiredPositiveNumber(data["height"], id+".height"); err != nil {
			return err
		}
		if filter := data["filter"]; filter != nil {
			value, err := requiredString(filter, id+".filter")
			if err != nil {
				return err
			}
			if value != "nearest" && value != "linear" {
				return fmt.Errorf("%s.filter has unsupported value %q", id, value)
			}
		}
	} else if data["width"] != nil || data["height"] != nil ||
		data["filter"] != nil {
		return fmt.Errorf("%s non-image asset cannot define image geometry", id)
	}
	return nil
}

func validateSpriteSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	assetID, err := requiredString(data["asset"], id+".asset")
	if err != nil {
		return err
	}
	asset, err := referencedDefinition(catalog, assetID, "asset", id+".asset")
	if err != nil {
		return err
	}
	if asset["asset_type"] != "image" {
		return fmt.Errorf("%s.asset must reference an image asset", id)
	}
	frameWidth, err := requiredPositiveNumberValue(
		data["frame_width"],
		id+".frame_width",
	)
	if err != nil {
		return err
	}
	frameHeight, err := requiredPositiveNumberValue(
		data["frame_height"],
		id+".frame_height",
	)
	if err != nil {
		return err
	}
	if err := optionalPositiveNumber(data["scale"], id+".scale"); err != nil {
		return err
	}
	for _, field := range []string{"origin_x", "origin_y"} {
		if _, exists := data[field]; exists {
			if _, err := requiredNumber(data[field], id+"."+field); err != nil {
				return err
			}
		}
	}
	if err := validateColor(data["tint"], id+".tint", false); err != nil {
		return err
	}
	clips, err := requiredObject(data["clips"], id+".clips")
	if err != nil {
		return err
	}
	if len(clips) == 0 {
		return fmt.Errorf("%s.clips must not be empty", id)
	}
	columns, rows := 0, 0
	if width, ok := number(asset["width"]); ok {
		if math.Mod(width, frameWidth) != 0 {
			return fmt.Errorf("%s.frame_width does not divide its asset", id)
		}
		columns = int(width / frameWidth)
	}
	if height, ok := number(asset["height"]); ok {
		if math.Mod(height, frameHeight) != 0 {
			return fmt.Errorf("%s.frame_height does not divide its asset", id)
		}
		rows = int(height / frameHeight)
	}
	for name, raw := range clips {
		if strings.TrimSpace(name) == "" {
			return fmt.Errorf("%s.clips contains an empty clip name", id)
		}
		path := id + ".clips." + name
		clip, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		if err := requiredPositiveNumber(clip["fps"], path+".fps"); err != nil {
			return err
		}
		if err := optionalBoolean(clip["loop"], path+".loop"); err != nil {
			return err
		}
		frames, err := requiredArray(clip["frames"], path+".frames")
		if err != nil {
			return err
		}
		if len(frames) == 0 {
			return fmt.Errorf("%s.frames must not be empty", path)
		}
		for index, rawFrame := range frames {
			framePath := fmt.Sprintf("%s.frames[%d]", path, index)
			frame, err := requiredArray(rawFrame, framePath)
			if err != nil {
				return err
			}
			if len(frame) != 2 {
				return fmt.Errorf("%s must contain column and row", framePath)
			}
			for coordinate, maximum := range []int{columns, rows} {
				value, err := requiredPositiveIntegerValue(
					frame[coordinate],
					fmt.Sprintf("%s[%d]", framePath, coordinate),
				)
				if err != nil {
					return err
				}
				if maximum > 0 && value > maximum {
					return fmt.Errorf("%s is outside the sprite sheet", framePath)
				}
			}
		}
	}
	defaultClip, err := requiredString(data["default_clip"], id+".default_clip")
	if err != nil {
		return err
	}
	if _, exists := clips[defaultClip]; !exists {
		return fmt.Errorf("%s.default_clip references missing clip %q", id, defaultClip)
	}
	stateMap, err := requiredObject(data["state_map"], id+".state_map")
	if err != nil {
		return err
	}
	for state, raw := range stateMap {
		clip, err := requiredString(raw, id+".state_map."+state)
		if err != nil {
			return err
		}
		if _, exists := clips[clip]; !exists {
			return fmt.Errorf(
				"%s.state_map.%s references missing clip %q",
				id,
				state,
				clip,
			)
		}
	}
	return nil
}

func validateEncounterSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	if err := optionalString(data["target_tag"], id+".target_tag"); err != nil {
		return err
	}
	waves, err := requiredArray(data["waves"], id+".waves")
	if err != nil {
		return err
	}
	if len(waves) == 0 {
		return fmt.Errorf("%s.waves must not be empty", id)
	}
	waveIDs := make(map[string]struct{}, len(waves))
	for waveIndex, rawWave := range waves {
		path := fmt.Sprintf("%s.waves[%d]", id, waveIndex)
		wave, err := requiredObject(rawWave, path)
		if err != nil {
			return err
		}
		waveID, err := requiredString(wave["id"], path+".id")
		if err != nil {
			return err
		}
		if _, duplicate := waveIDs[waveID]; duplicate {
			return fmt.Errorf("%s.id duplicates wave %q", path, waveID)
		}
		waveIDs[waveID] = struct{}{}
		if err := optionalNonNegativeNumber(wave["delay"], path+".delay"); err != nil {
			return err
		}
		spawns, err := requiredArray(wave["spawns"], path+".spawns")
		if err != nil {
			return err
		}
		if len(spawns) == 0 {
			return fmt.Errorf("%s.spawns must not be empty", path)
		}
		spawnIDs := make(map[string]struct{}, len(spawns))
		for spawnIndex, rawSpawn := range spawns {
			spawnPath := fmt.Sprintf("%s.spawns[%d]", path, spawnIndex)
			spawn, err := requiredObject(rawSpawn, spawnPath)
			if err != nil {
				return err
			}
			spawnID, err := requiredString(spawn["id"], spawnPath+".id")
			if err != nil {
				return err
			}
			if _, duplicate := spawnIDs[spawnID]; duplicate {
				return fmt.Errorf("%s.id duplicates spawn %q", spawnPath, spawnID)
			}
			spawnIDs[spawnID] = struct{}{}
			actorID, err := requiredString(spawn["actor"], spawnPath+".actor")
			if err != nil {
				return err
			}
			if _, err := referencedDefinition(
				catalog,
				actorID,
				"actor",
				spawnPath+".actor",
			); err != nil {
				return err
			}
			position, err := requiredObject(spawn["position"], spawnPath+".position")
			if err != nil {
				return err
			}
			for _, axis := range []string{"x", "y"} {
				if _, err := requiredNumber(
					position[axis],
					spawnPath+".position."+axis,
				); err != nil {
					return err
				}
			}
			if err := validateStringArray(
				spawn["tags"],
				spawnPath+".tags",
				false,
			); err != nil {
				return err
			}
			if overrides, exists, err := optionalObject(
				spawn["components"],
				spawnPath+".components",
			); err != nil {
				return err
			} else if exists {
				for name, value := range overrides {
					if _, ok := value.(map[string]any); !ok {
						return fmt.Errorf(
							"%s.components.%s must be an object",
							spawnPath,
							name,
						)
					}
				}
			}
		}
		phases, exists, err := optionalArray(wave["boss_phases"], path+".boss_phases")
		if err != nil {
			return err
		}
		if exists {
			phaseIDs := make(map[string]struct{}, len(phases))
			for phaseIndex, rawPhase := range phases {
				phasePath := fmt.Sprintf(
					"%s.boss_phases[%d]",
					path,
					phaseIndex,
				)
				phase, err := requiredObject(rawPhase, phasePath)
				if err != nil {
					return err
				}
				phaseID, err := requiredString(phase["id"], phasePath+".id")
				if err != nil {
					return err
				}
				if _, duplicate := phaseIDs[phaseID]; duplicate {
					return fmt.Errorf("%s.id duplicates phase %q", phasePath, phaseID)
				}
				phaseIDs[phaseID] = struct{}{}
				spawnID, err := requiredString(phase["spawn"], phasePath+".spawn")
				if err != nil {
					return err
				}
				if _, exists := spawnIDs[spawnID]; !exists {
					return fmt.Errorf(
						"%s.spawn references missing wave spawn %q",
						phasePath,
						spawnID,
					)
				}
				threshold, err := requiredNumber(
					phase["health_ratio_at_most"],
					phasePath+".health_ratio_at_most",
				)
				if err != nil {
					return err
				}
				if threshold <= 0 || threshold > 1 {
					return fmt.Errorf(
						"%s.health_ratio_at_most must be greater than 0 and at most 1",
						phasePath,
					)
				}
				if err := validateActions(
					catalog,
					phase["actions"],
					phasePath+".actions",
					false,
				); err != nil {
					return err
				}
			}
		}
		for _, field := range []string{"on_start", "on_complete"} {
			if err := validateActions(
				catalog,
				wave[field],
				path+"."+field,
				false,
			); err != nil {
				return err
			}
		}
	}
	return validateActions(
		catalog,
		data["on_complete"],
		id+".on_complete",
		false,
	)
}

func validateItemSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := validateDisplayName(data, id); err != nil {
		return err
	}
	for _, field := range []string{"description", "description_key"} {
		if err := optionalString(data[field], id+"."+field); err != nil {
			return err
		}
	}
	if err := optionalPositiveInteger(data["stack_limit"], id+".stack_limit"); err != nil {
		return err
	}
	if err := optionalNonNegativeInteger(data["value"], id+".value"); err != nil {
		return err
	}
	if err := optionalBoolean(data["consumable"], id+".consumable"); err != nil {
		return err
	}
	_, hasEffects, err := optionalArray(data["effects"], id+".effects")
	if err != nil {
		return err
	}
	if hasEffects {
		if err := validateActions(
			catalog,
			data["effects"],
			id+".effects",
			true,
		); err != nil {
			return err
		}
		if consumable, _ := data["consumable"].(bool); !consumable {
			return fmt.Errorf("%s.effects requires consumable=true", id)
		}
	} else if consumable, _ := data["consumable"].(bool); consumable {
		return fmt.Errorf("%s consumable item requires effects", id)
	}
	if equipment, exists, err := optionalObject(
		data["equipment"],
		id+".equipment",
	); err != nil {
		return err
	} else if exists {
		if _, err := requiredString(equipment["slot"], id+".equipment.slot"); err != nil {
			return err
		}
		modifiers, err := requiredObject(
			equipment["modifiers"],
			id+".equipment.modifiers",
		)
		if err != nil {
			return err
		}
		if len(modifiers) == 0 {
			return fmt.Errorf("%s.equipment.modifiers must not be empty", id)
		}
		if err := rejectUnknownKeys(
			modifiers,
			id+".equipment.modifiers",
			"attack",
			"defense",
			"move_speed",
		); err != nil {
			return err
		}
		for name, value := range modifiers {
			if name == "attack" || name == "defense" {
				if _, err := ruleSignedInteger(
					value,
					id+".equipment.modifiers."+name,
				); err != nil {
					return err
				}
				continue
			}
			modifier, err := requiredNumber(
				value,
				id+".equipment.modifiers."+name,
			)
			if err != nil {
				return err
			}
			if math.Abs(modifier) > 16 {
				return fmt.Errorf(
					"%s.equipment.modifiers.%s must be between -16 and 16",
					id,
					name,
				)
			}
		}
	}
	return nil
}

func validateProjectileSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	actorID, err := requiredString(data["actor"], id+".actor")
	if err != nil {
		return err
	}
	actor, err := referencedDefinition(catalog, actorID, "actor", id+".actor")
	if err != nil {
		return err
	}
	components, err := requiredObject(actor["components"], id+".actor.components")
	if err != nil {
		return err
	}
	body, err := requiredObject(components["body"], id+".actor.components.body")
	if err != nil {
		return err
	}
	if body["shape"] != "circle" {
		return fmt.Errorf("%s.actor requires a circle body", id)
	}
	if _, exists := components["motion.facing"]; !exists {
		return fmt.Errorf("%s.actor requires motion.facing", id)
	}
	if _, exists := components["motion.kinematics"]; !exists {
		return fmt.Errorf("%s.actor requires motion.kinematics", id)
	}
	if err := requiredPositiveNumber(data["speed"], id+".speed"); err != nil {
		return err
	}
	if err := requiredPositiveNumber(data["lifetime"], id+".lifetime"); err != nil {
		return err
	}
	if err := optionalNonNegativeNumber(data["spawn_offset"], id+".spawn_offset"); err != nil {
		return err
	}
	if err := optionalNonNegativeInteger(data["pierce"], id+".pierce"); err != nil {
		return err
	}
	if err := optionalBoolean(data["destroy_on_wall"], id+".destroy_on_wall"); err != nil {
		return err
	}
	return validateActions(catalog, data["effects"], id+".effects", true)
}

func validateShopSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := validateDisplayName(data, id); err != nil {
		return err
	}
	offers, err := requiredArray(data["offers"], id+".offers")
	if err != nil {
		return err
	}
	if len(offers) == 0 {
		return fmt.Errorf("%s.offers must not be empty", id)
	}
	seen := make(map[string]struct{}, len(offers))
	for index, raw := range offers {
		path := fmt.Sprintf("%s.offers[%d]", id, index)
		offer, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		itemID, err := requiredString(offer["item"], path+".item")
		if err != nil {
			return err
		}
		if _, duplicate := seen[itemID]; duplicate {
			return fmt.Errorf("%s.item duplicates offer %q", path, itemID)
		}
		seen[itemID] = struct{}{}
		if _, err := referencedDefinition(
			catalog,
			itemID,
			"item",
			path+".item",
		); err != nil {
			return err
		}
		if err := optionalNonNegativeInteger(
			offer["buy_price"],
			path+".buy_price",
		); err != nil {
			return err
		}
		if err := optionalNonNegativeInteger(
			offer["sell_price"],
			path+".sell_price",
		); err != nil {
			return err
		}
		if offer["buy_price"] == nil && offer["sell_price"] == nil {
			return fmt.Errorf("%s requires buy_price or sell_price", path)
		}
	}
	return nil
}

func validateStatusSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	if err := requiredPositiveNumber(data["duration"], id+".duration"); err != nil {
		return err
	}
	stacking := "refresh"
	if data["stacking"] != nil {
		value, err := requiredString(data["stacking"], id+".stacking")
		if err != nil {
			return err
		}
		if value != "refresh" && value != "stack" {
			return fmt.Errorf("%s.stacking has unsupported value %q", id, value)
		}
		stacking = value
	}
	if err := optionalPositiveInteger(data["max_stacks"], id+".max_stacks"); err != nil {
		return err
	}
	if maximum, ok := number(data["max_stacks"]); ok &&
		stacking == "refresh" && maximum != 1 {
		return fmt.Errorf("%s.max_stacks must be 1 for refresh stacking", id)
	}
	_, hasTickActions, err := optionalArray(
		data["tick_actions"],
		id+".tick_actions",
	)
	if err != nil {
		return err
	}
	if hasTickActions {
		if err := validateActions(
			catalog,
			data["tick_actions"],
			id+".tick_actions",
			true,
		); err != nil {
			return err
		}
		if err := requiredPositiveNumber(
			data["tick_interval"],
			id+".tick_interval",
		); err != nil {
			return err
		}
	} else if data["tick_interval"] != nil {
		return fmt.Errorf("%s.tick_interval requires tick_actions", id)
	}
	for _, field := range []string{"on_apply", "on_expire"} {
		if err := validateActions(
			catalog,
			data[field],
			id+"."+field,
			false,
		); err != nil {
			return err
		}
	}
	if modifiers, exists, err := optionalObject(
		data["modifiers"],
		id+".modifiers",
	); err != nil {
		return err
	} else if exists {
		for name, value := range modifiers {
			if name != "move_speed" &&
				name != "damage_dealt" &&
				name != "damage_taken" {
				return fmt.Errorf("%s.modifiers.%s is unsupported", id, name)
			}
			if err := requiredPositiveNumber(
				value,
				id+".modifiers."+name,
			); err != nil {
				return err
			}
		}
	}
	return validateColor(data["color"], id+".color", false)
}

func validateDisplayName(data map[string]any, path string) error {
	if err := optionalString(data["name"], path+".name"); err != nil {
		return err
	}
	if err := optionalString(data["name_key"], path+".name_key"); err != nil {
		return err
	}
	if !hasNonEmptyString(data["name"]) && !hasNonEmptyString(data["name_key"]) {
		return fmt.Errorf("%s requires name or name_key", path)
	}
	return nil
}
