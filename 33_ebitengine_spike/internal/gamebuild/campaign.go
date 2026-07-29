package gamebuild

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
)

const implicitEntrySpawnID = "default"

type campaignDefinitionHeader struct {
	SchemaVersion int    `json:"schema_version"`
	Kind          string `json:"kind"`
	ID            string `json:"id"`
}

type campaignActorDefinition struct {
	campaignDefinitionHeader
	Components map[string]json.RawMessage `json:"components"`
}

type campaignStageDefinition struct {
	campaignDefinitionHeader
	Spawns      []campaignStageSpawn      `json:"spawns"`
	SpawnPoints []campaignStageSpawnPoint `json:"spawn_points"`
}

type campaignStageSpawn struct {
	ID       string                 `json:"id"`
	ActorID  string                 `json:"actor"`
	Position *campaignStagePosition `json:"position"`
}

type campaignStagePosition struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type campaignStageSpawnPoint struct {
	ID string `json:"id"`
}

type campaignItemDefinition struct {
	campaignDefinitionHeader
	StackLimit *int64                 `json:"stack_limit"`
	Equipment  *campaignItemEquipment `json:"equipment"`
}

type campaignItemEquipment struct {
	Slot string `json:"slot"`
}

type campaignQuestDefinition struct {
	campaignDefinitionHeader
	InitiallyActive *bool                    `json:"initially_active"`
	Objectives      []campaignQuestObjective `json:"objectives"`
}

type campaignQuestObjective struct {
	ID    string `json:"id"`
	Count *int64 `json:"count"`
}

// BuildCampaignConfig translates the complete runtime-neutral catalog into
// the durable, stage-independent definition owned by package campaign.
//
// ContentID hashes the compiler's canonical catalog envelope, not a subset of
// fields consumed here. Any reviewed content revision therefore invalidates a
// save even when the changed definition is presentation-only.
func BuildCampaignConfig(
	catalog *content.Catalog,
) (campaign.Config, error) {
	if catalog == nil {
		return campaign.Config{}, fmt.Errorf(
			"build campaign config: catalog is nil",
		)
	}

	canonical, err := content.MarshalCanonical(catalog)
	if err != nil {
		return campaign.Config{}, fmt.Errorf(
			"build campaign config: invalid catalog: %w",
			err,
		)
	}
	if err := catalog.ValidateProjectReferences(); err != nil {
		return campaign.Config{}, fmt.Errorf(
			"build campaign config: invalid project manifest: %w",
			err,
		)
	}

	validations := make([]DefinitionValidation, 0, len(catalog.IDs()))
	for _, id := range catalog.IDs() {
		validation, err := ValidateDefinition(catalog, id)
		if err != nil {
			return campaign.Config{}, fmt.Errorf(
				"build campaign config: %w",
				err,
			)
		}
		validations = append(validations, validation)
	}

	controlledActors, err := campaignControlledActors(catalog, validations)
	if err != nil {
		return campaign.Config{}, err
	}

	manifest := catalog.Project()
	fingerprint := sha256.Sum256(canonical)
	result := campaign.Config{
		Version:             campaign.CurrentConfigVersion,
		ProjectID:           manifest.ID,
		ContentID:           "sha256:" + hex.EncodeToString(fingerprint[:]),
		DefaultLocale:       manifest.Locale.Default,
		Locales:             []string{},
		InitialStageID:      manifest.Flow.StartStage,
		InitialEntrySpawnID: manifest.Flow.StartSpawn,
		Stages:              []campaign.StageDefinition{},
		Flags:               []string{},
		Items:               []campaign.ItemDefinition{},
		EquipmentSlots:      []string{},
		Quests:              []campaign.QuestDefinition{},
	}

	equipmentSlots := make(map[string]struct{})
	flags := make(map[string]struct{})
	for _, definition := range catalog.Definitions {
		if err := collectCampaignFlags(definition.Data, flags); err != nil {
			return campaign.Config{}, fmt.Errorf(
				"build campaign config: %s: %w",
				definition.Source,
				err,
			)
		}
	}

	for _, validation := range validations {
		switch validation.Kind {
		case "locale":
			result.Locales = append(result.Locales, validation.ID)

		case "stage":
			stage, err := translateCampaignStage(
				catalog,
				validation.ID,
				controlledActors,
			)
			if err != nil {
				return campaign.Config{}, err
			}
			result.Stages = append(result.Stages, stage)

		case "item":
			item, err := translateCampaignItem(catalog, validation.ID)
			if err != nil {
				return campaign.Config{}, err
			}
			result.Items = append(result.Items, item)
			if item.EquipmentSlot != "" {
				equipmentSlots[item.EquipmentSlot] = struct{}{}
			}

		case "quest":
			quest, err := translateCampaignQuest(catalog, validation.ID)
			if err != nil {
				return campaign.Config{}, err
			}
			result.Quests = append(result.Quests, quest)
		}
	}

	result.Flags = sortedCampaignSet(flags)
	result.EquipmentSlots = sortedCampaignSet(equipmentSlots)
	sort.Strings(result.Locales)
	sort.Slice(result.Stages, func(i, j int) bool {
		return result.Stages[i].ID < result.Stages[j].ID
	})
	sort.Slice(result.Items, func(i, j int) bool {
		return result.Items[i].ID < result.Items[j].ID
	})
	sort.Slice(result.Quests, func(i, j int) bool {
		return result.Quests[i].ID < result.Quests[j].ID
	})

	if err := result.Validate(); err != nil {
		return campaign.Config{}, fmt.Errorf(
			"build campaign config: translated config is invalid: %w",
			err,
		)
	}
	return result, nil
}

func campaignControlledActors(
	catalog *content.Catalog,
	validations []DefinitionValidation,
) (map[string]struct{}, error) {
	result := make(map[string]struct{})
	for _, validation := range validations {
		if validation.Kind != "actor" {
			continue
		}
		var actor campaignActorDefinition
		if err := decodeCampaignDefinition(
			catalog,
			validation.ID,
			&actor,
		); err != nil {
			return nil, err
		}
		if _, controlled := actor.Components["control.player"]; controlled {
			result[actor.ID] = struct{}{}
		}
	}
	return result, nil
}

func translateCampaignStage(
	catalog *content.Catalog,
	id string,
	controlledActors map[string]struct{},
) (campaign.StageDefinition, error) {
	var authored campaignStageDefinition
	if err := decodeCampaignDefinition(catalog, id, &authored); err != nil {
		return campaign.StageDefinition{}, err
	}

	result := campaign.StageDefinition{
		ID:          authored.ID,
		EntrySpawns: make([]string, 0, max(1, len(authored.SpawnPoints))),
	}
	for _, spawn := range authored.SpawnPoints {
		if strings.TrimSpace(spawn.ID) == "" {
			return campaign.StageDefinition{}, fmt.Errorf(
				"build campaign config: stage %q has an invalid spawn point id",
				id,
			)
		}
		result.EntrySpawns = append(result.EntrySpawns, spawn.ID)
	}

	if len(result.EntrySpawns) == 0 {
		// Legacy showcase fixtures predate named entry spawns. Promote their
		// single authored control.player placement to the identity "default";
		// its authored coordinates remain owned by the stage builder. This is
		// only a local-entry fallback: manifest and portal targets are checked
		// against explicit spawn_points before translation.
		controlledSpawns := 0
		for _, spawn := range authored.Spawns {
			if _, controlled := controlledActors[spawn.ActorID]; !controlled {
				continue
			}
			if strings.TrimSpace(spawn.ID) == "" || spawn.Position == nil {
				return campaign.StageDefinition{}, fmt.Errorf(
					"build campaign config: stage %q controlled spawn is invalid",
					id,
				)
			}
			controlledSpawns++
		}
		if controlledSpawns != 1 {
			return campaign.StageDefinition{}, fmt.Errorf(
				"build campaign config: stage %q has no spawn_points and "+
					"requires exactly one authored controlled player spawn; got %d",
				id,
				controlledSpawns,
			)
		}
		result.EntrySpawns = append(
			result.EntrySpawns,
			implicitEntrySpawnID,
		)
	}

	sort.Strings(result.EntrySpawns)
	for index := 1; index < len(result.EntrySpawns); index++ {
		if result.EntrySpawns[index] == result.EntrySpawns[index-1] {
			return campaign.StageDefinition{}, fmt.Errorf(
				"build campaign config: stage %q duplicates entry spawn %q",
				id,
				result.EntrySpawns[index],
			)
		}
	}
	return result, nil
}

func translateCampaignItem(
	catalog *content.Catalog,
	id string,
) (campaign.ItemDefinition, error) {
	var authored campaignItemDefinition
	if err := decodeCampaignDefinition(catalog, id, &authored); err != nil {
		return campaign.ItemDefinition{}, err
	}
	if authored.StackLimit == nil {
		return campaign.ItemDefinition{}, fmt.Errorf(
			"build campaign config: item %q requires stack_limit",
			id,
		)
	}
	result := campaign.ItemDefinition{
		ID:          authored.ID,
		MaxQuantity: *authored.StackLimit,
	}
	if authored.Equipment != nil {
		if strings.TrimSpace(authored.Equipment.Slot) == "" {
			return campaign.ItemDefinition{}, fmt.Errorf(
				"build campaign config: item %q equipment requires slot",
				id,
			)
		}
		result.EquipmentSlot = authored.Equipment.Slot
	}
	return result, nil
}

func translateCampaignQuest(
	catalog *content.Catalog,
	id string,
) (campaign.QuestDefinition, error) {
	var authored campaignQuestDefinition
	if err := decodeCampaignDefinition(catalog, id, &authored); err != nil {
		return campaign.QuestDefinition{}, err
	}
	result := campaign.QuestDefinition{
		ID:         authored.ID,
		Objectives: make([]campaign.ObjectiveDefinition, 0, len(authored.Objectives)),
	}
	if authored.InitiallyActive != nil {
		result.InitiallyActive = *authored.InitiallyActive
	}
	for _, objective := range authored.Objectives {
		if strings.TrimSpace(objective.ID) == "" {
			return campaign.QuestDefinition{}, fmt.Errorf(
				"build campaign config: quest %q has an invalid objective id",
				id,
			)
		}
		if objective.Count == nil {
			return campaign.QuestDefinition{}, fmt.Errorf(
				"build campaign config: quest %q objective %q requires count",
				id,
				objective.ID,
			)
		}
		result.Objectives = append(
			result.Objectives,
			campaign.ObjectiveDefinition{
				ID:       objective.ID,
				Required: *objective.Count,
			},
		)
	}
	sort.Slice(result.Objectives, func(i, j int) bool {
		return result.Objectives[i].ID < result.Objectives[j].ID
	})
	return result, nil
}

func decodeCampaignDefinition(
	catalog *content.Catalog,
	id string,
	target any,
) error {
	raw, exists := catalog.Definition(id)
	if !exists {
		return fmt.Errorf(
			"build campaign config: definition %q is missing",
			id,
		)
	}
	if err := json.Unmarshal(raw, target); err != nil {
		return fmt.Errorf(
			"build campaign config: decode %q: %w",
			id,
			err,
		)
	}
	return nil
}

func collectCampaignFlags(value any, flags map[string]struct{}) error {
	switch typed := value.(type) {
	case map[string]any:
		if actionType, _ := typed["type"].(string); actionType == "set_flag" {
			name, ok := typed["name"].(string)
			if !ok || strings.TrimSpace(name) == "" {
				return fmt.Errorf("set_flag action requires a non-empty name")
			}
			flags[name] = struct{}{}
		}
		for _, child := range typed {
			if err := collectCampaignFlags(child, flags); err != nil {
				return err
			}
		}
	case []any:
		for _, child := range typed {
			if err := collectCampaignFlags(child, flags); err != nil {
				return err
			}
		}
	}
	return nil
}

func sortedCampaignSet(values map[string]struct{}) []string {
	result := make([]string, 0, len(values))
	for value := range values {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}
