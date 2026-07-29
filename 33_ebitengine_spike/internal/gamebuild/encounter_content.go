package gamebuild

import (
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func buildEncounterPlacements(
	catalog *content.Catalog,
	strings map[string]string,
	placements []stageEncounter,
	impact ImpactOptions,
	seenInstances map[string]struct{},
	stageInstances []InstanceMetadata,
	dialogues map[string]sim.DialogueDefinition,
	quests map[string]sim.QuestDefinition,
) (
	[]sim.EncounterConfig,
	[]InstanceMetadata,
	sim.Coord,
	error,
) {
	result := make([]sim.EncounterConfig, 0, len(placements))
	metadata := make([]InstanceMetadata, 0)
	var interactionRange sim.Coord
	seenPlacements := make(map[string]struct{}, len(placements))
	for _, placement := range placements {
		if placement.ID == "" || placement.Encounter == "" ||
			!finite(placement.Position.X) ||
			!finite(placement.Position.Y) {
			return nil, nil, 0, fmt.Errorf(
				"invalid encounter placement %q",
				placement.ID,
			)
		}
		if _, duplicate := seenPlacements[placement.ID]; duplicate {
			return nil, nil, 0, fmt.Errorf(
				"duplicate encounter placement %q",
				placement.ID,
			)
		}
		seenPlacements[placement.ID] = struct{}{}
		var authored encounterDefinition
		if err := catalog.Decode(placement.Encounter, &authored); err != nil {
			return nil, nil, 0, err
		}
		if err := validateHeader(
			authored.SchemaVersion,
			authored.Kind,
			authored.ID,
			"encounter",
			placement.Encounter,
		); err != nil {
			return nil, nil, 0, err
		}
		if len(authored.Waves) == 0 {
			return nil, nil, 0, fmt.Errorf(
				"%s has no waves",
				authored.ID,
			)
		}
		autoStart := true
		if placement.AutoStart != nil {
			autoStart = *placement.AutoStart
		}
		targetTag := authored.TargetTag
		if targetTag == "" {
			targetTag = "player"
		}
		targetEntityID, err := encounterTargetEntity(
			stageInstances,
			targetTag,
		)
		if err != nil {
			return nil, nil, 0, fmt.Errorf(
				"%s target_tag %q: %w",
				authored.ID,
				targetTag,
				err,
			)
		}
		converted := sim.EncounterConfig{
			ID:             placement.ID,
			DefinitionID:   authored.ID,
			TargetEntityID: targetEntityID,
			AutoStart:      autoStart,
		}
		converted.OnComplete, err = buildEncounterActions(
			catalog,
			authored.OnComplete,
		)
		if err != nil {
			return nil, nil, 0, fmt.Errorf(
				"%s on_complete: %w",
				authored.ID,
				err,
			)
		}
		waveIDs := make(map[string]struct{}, len(authored.Waves))
		for waveIndex, wave := range authored.Waves {
			if wave.ID == "" || len(wave.Spawns) == 0 ||
				!finite(wave.Delay) || wave.Delay < 0 ||
				!durationFitsPortableTicks(wave.Delay) {
				return nil, nil, 0, fmt.Errorf(
					"%s has invalid wave %d",
					authored.ID,
					waveIndex+1,
				)
			}
			if _, duplicate := waveIDs[wave.ID]; duplicate {
				return nil, nil, 0, fmt.Errorf(
					"%s duplicates wave %q",
					authored.ID,
					wave.ID,
				)
			}
			waveIDs[wave.ID] = struct{}{}
			runtimeWave := sim.EncounterWaveConfig{
				ID:         wave.ID,
				DelayTicks: secondsToTicks(wave.Delay),
			}
			runtimeWave.OnStart, err = buildEncounterActions(
				catalog,
				wave.OnStart,
			)
			if err != nil {
				return nil, nil, 0, fmt.Errorf(
					"%s wave %q on_start: %w",
					authored.ID,
					wave.ID,
					err,
				)
			}
			runtimeWave.OnComplete, err =
				buildEncounterActions(catalog, wave.OnComplete)
			if err != nil {
				return nil, nil, 0, fmt.Errorf(
					"%s wave %q on_complete: %w",
					authored.ID,
					wave.ID,
					err,
				)
			}
			spawnIDs := make(map[string]struct{}, len(wave.Spawns))
			for _, spawn := range wave.Spawns {
				spawnID := spawn.ID
				if spawn.ID == "" || spawn.Actor == "" {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q has invalid spawn",
						authored.ID,
						wave.ID,
					)
				}
				if _, duplicate := spawnIDs[spawn.ID]; duplicate {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q duplicates spawn %q",
						authored.ID,
						wave.ID,
						spawn.ID,
					)
				}
				spawnIDs[spawn.ID] = struct{}{}
				entityID := fmt.Sprintf(
					"encounter.%s.wave.%d.%s",
					placement.ID,
					waveIndex+1,
					spawn.ID,
				)
				if _, duplicate := seenInstances[entityID]; duplicate {
					return nil, nil, 0, fmt.Errorf(
						"generated entity ID %q is duplicated",
						entityID,
					)
				}
				seenInstances[entityID] = struct{}{}
				spawn.ID = entityID
				spawn.Position.X += placement.Position.X
				spawn.Position.Y += placement.Position.Y
				entity, instance, dialogue, quest, actorRange, err :=
					buildEntity(
						catalog,
						strings,
						spawn,
						impact,
					)
				if err != nil {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q spawn %q: %w",
						authored.ID,
						wave.ID,
						entityID,
						err,
					)
				}
				if entity.Controlled {
					return nil, nil, 0, fmt.Errorf(
						"encounter spawn %q cannot be controlled",
						entityID,
					)
				}
				runtimeWave.Spawns = append(
					runtimeWave.Spawns,
					sim.EncounterSpawnConfig{
						ID:     spawnID,
						Entity: entity,
					},
				)
				metadata = append(metadata, instance)
				interactionRange = max(interactionRange, actorRange)
				if dialogue != nil {
					dialogues[dialogue.ID] = *dialogue
				}
				if quest != nil {
					quests[quest.ID] = *quest
				}
			}
			phaseIDs := make(map[string]struct{}, len(wave.BossPhases))
			for _, phase := range wave.BossPhases {
				if phase.ID == "" || phase.Spawn == "" ||
					!finite(phase.HealthRatioAtMost) ||
					phase.HealthRatioAtMost <= 0 ||
					phase.HealthRatioAtMost > 1 {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q has invalid boss phase %q",
						authored.ID,
						wave.ID,
						phase.ID,
					)
				}
				if _, duplicate := phaseIDs[phase.ID]; duplicate {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q duplicates boss phase %q",
						authored.ID,
						wave.ID,
						phase.ID,
					)
				}
				phaseIDs[phase.ID] = struct{}{}
				if _, exists := spawnIDs[phase.Spawn]; !exists {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q phase %q references unknown spawn %q",
						authored.ID,
						wave.ID,
						phase.ID,
						phase.Spawn,
					)
				}
				actions, err := buildEncounterActions(
					catalog,
					phase.Actions,
				)
				if err != nil {
					return nil, nil, 0, fmt.Errorf(
						"%s wave %q phase %q: %w",
						authored.ID,
						wave.ID,
						phase.ID,
						err,
					)
				}
				runtimeWave.BossPhases = append(
					runtimeWave.BossPhases,
					sim.BossPhaseConfig{
						ID:      phase.ID,
						SpawnID: phase.Spawn,
						HealthRatioAtMost: sim.Coord(math.Round(
							phase.HealthRatioAtMost *
								float64(sim.UnitsPerPixel),
						)),
						Actions: actions,
					},
				)
			}
			converted.Waves = append(converted.Waves, runtimeWave)
		}
		result = append(result, converted)
	}
	sort.Slice(result, func(left, right int) bool {
		return result[left].ID < result[right].ID
	})
	sort.Slice(metadata, func(left, right int) bool {
		return metadata[left].ID < metadata[right].ID
	})
	return result, metadata, interactionRange, nil
}

func encounterTargetEntity(
	instances []InstanceMetadata,
	targetTag string,
) (string, error) {
	matches := make([]string, 0, 1)
	for _, instance := range instances {
		for _, tag := range instance.Tags {
			if tag == targetTag {
				matches = append(matches, instance.ID)
				break
			}
		}
	}
	if len(matches) == 0 {
		return "", fmt.Errorf("matches no stage actor")
	}
	sort.Strings(matches)
	return matches[0], nil
}

func buildEncounterActions(
	catalog *content.Catalog,
	authored []contentAction,
) ([]sim.EncounterActionConfig, error) {
	result := make(
		[]sim.EncounterActionConfig,
		0,
		len(authored),
	)
	for _, action := range authored {
		switch action.Type {
		case "emit":
			if action.Name == "" {
				return nil, fmt.Errorf("emit action requires name")
			}
			if sim.IsReservedEventType(sim.EventType(action.Name)) {
				return nil, fmt.Errorf(
					"emit action name %q is reserved by the engine",
					action.Name,
				)
			}
			result = append(result, sim.EncounterActionConfig{
				Type:  sim.EncounterEmit,
				Event: action.Name,
			})
		case "apply_status":
			if action.Status == "" {
				return nil, fmt.Errorf(
					"apply_status action requires status",
				)
			}
			var header struct {
				Kind string `json:"kind"`
				ID   string `json:"id"`
			}
			if err := catalog.Decode(action.Status, &header); err != nil {
				return nil, err
			}
			if header.Kind != "status" || header.ID != action.Status {
				return nil, fmt.Errorf(
					"apply_status references invalid status %q",
					action.Status,
				)
			}
			result = append(result, sim.EncounterActionConfig{
				Type:     sim.EncounterApplyStatus,
				StatusID: action.Status,
			})
		default:
			return nil, fmt.Errorf(
				"unsupported action %q",
				action.Type,
			)
		}
	}
	return result, nil
}
