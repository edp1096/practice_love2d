package sim

import (
	"errors"
	"fmt"
)

func validateEncounters(
	config Config,
	entityIDs map[string]struct{},
	dialogues map[string]struct{},
	quests map[string]struct{},
	statuses map[string]struct{},
	projectiles map[string]struct{},
) error {
	encounterIDs := make(map[string]struct{}, len(config.Encounters))
	for _, encounter := range config.Encounters {
		var actionTarget *EntityConfig
		for index := range config.Entities {
			if config.Entities[index].ID == encounter.TargetEntityID {
				actionTarget = &config.Entities[index]
				break
			}
		}
		if encounter.ID == "" || encounter.DefinitionID == "" ||
			actionTarget == nil ||
			len(encounter.Waves) == 0 {
			return fmt.Errorf(
				"encounter %q has invalid configuration",
				encounter.ID,
			)
		}
		if _, duplicate := encounterIDs[encounter.ID]; duplicate {
			return fmt.Errorf("duplicate encounter %q", encounter.ID)
		}
		encounterIDs[encounter.ID] = struct{}{}
		if err := validateEncounterActions(
			encounter.OnComplete,
			statuses,
			actionTarget,
		); err != nil {
			return fmt.Errorf(
				"encounter %q completion: %w",
				encounter.ID,
				err,
			)
		}
		waveIDs := make(map[string]struct{}, len(encounter.Waves))
		for waveIndex, wave := range encounter.Waves {
			if wave.ID == "" || len(wave.Spawns) == 0 ||
				wave.DelayTicks < 0 ||
				!validTickCount(wave.DelayTicks) {
				return fmt.Errorf(
					"encounter %q wave %d is invalid",
					encounter.ID,
					waveIndex+1,
				)
			}
			if _, duplicate := waveIDs[wave.ID]; duplicate {
				return fmt.Errorf(
					"encounter %q duplicates wave %q",
					encounter.ID,
					wave.ID,
				)
			}
			waveIDs[wave.ID] = struct{}{}
			if err := validateEncounterActions(
				wave.OnStart,
				statuses,
				actionTarget,
			); err != nil {
				return fmt.Errorf(
					"encounter %q wave %q start: %w",
					encounter.ID,
					wave.ID,
					err,
				)
			}
			if err := validateEncounterActions(
				wave.OnComplete,
				statuses,
				actionTarget,
			); err != nil {
				return fmt.Errorf(
					"encounter %q wave %q completion: %w",
					encounter.ID,
					wave.ID,
					err,
				)
			}
			spawnIDs := make(
				map[string]EntityConfig,
				len(wave.Spawns),
			)
			for _, spawn := range wave.Spawns {
				expectedID := fmt.Sprintf(
					"encounter.%s.wave.%d.%s",
					encounter.ID,
					waveIndex+1,
					spawn.ID,
				)
				entity := spawn.Entity
				if spawn.ID == "" || entity.ID != expectedID ||
					entity.Controlled {
					return fmt.Errorf(
						"encounter %q wave %q has invalid spawn %q",
						encounter.ID,
						wave.ID,
						spawn.ID,
					)
				}
				if _, duplicate := spawnIDs[spawn.ID]; duplicate {
					return fmt.Errorf(
						"encounter %q wave %q duplicates spawn %q",
						encounter.ID,
						wave.ID,
						spawn.ID,
					)
				}
				if _, duplicate := entityIDs[entity.ID]; duplicate {
					return fmt.Errorf(
						"encounter %q generates duplicate entity %q",
						encounter.ID,
						entity.ID,
					)
				}
				if err := validateEntityDefinition(
					config,
					entity,
					dialogues,
					quests,
				); err != nil {
					return err
				}
				if entity.Status != nil {
					for _, statusID := range entity.Status.Immune {
						if _, exists := statuses[statusID]; !exists {
							return fmt.Errorf(
								"encounter entity %q is immune to unknown status %q",
								entity.ID,
								statusID,
							)
						}
					}
				}
				if entity.Combat != nil {
					for _, ability := range entity.Combat.Abilities {
						if ability.ProjectileID == "" {
							continue
						}
						if _, exists := projectiles[ability.ProjectileID]; !exists {
							return fmt.Errorf(
								"encounter entity %q references unknown projectile %q",
								entity.ID,
								ability.ProjectileID,
							)
						}
					}
				}
				entityIDs[entity.ID] = struct{}{}
				spawnIDs[spawn.ID] = entity
			}
			phaseIDs := make(
				map[string]struct{},
				len(wave.BossPhases),
			)
			for _, phase := range wave.BossPhases {
				target, exists := spawnIDs[phase.SpawnID]
				if phase.ID == "" || !exists ||
					phase.HealthRatioAtMost <= 0 ||
					phase.HealthRatioAtMost > UnitsPerPixel {
					return fmt.Errorf(
						"encounter %q wave %q has invalid boss phase %q",
						encounter.ID,
						wave.ID,
						phase.ID,
					)
				}
				if _, duplicate := phaseIDs[phase.ID]; duplicate {
					return fmt.Errorf(
						"encounter %q wave %q duplicates boss phase %q",
						encounter.ID,
						wave.ID,
						phase.ID,
					)
				}
				phaseIDs[phase.ID] = struct{}{}
				if err := validateEncounterActions(
					phase.Actions,
					statuses,
					&target,
				); err != nil {
					return fmt.Errorf(
						"encounter %q wave %q phase %q: %w",
						encounter.ID,
						wave.ID,
						phase.ID,
						err,
					)
				}
			}
		}
	}
	return nil
}

func validateEncounterActions(
	actions []EncounterActionConfig,
	statuses map[string]struct{},
	target *EntityConfig,
) error {
	for _, action := range actions {
		switch action.Type {
		case EncounterEmit:
			if action.Event == "" || action.StatusID != "" ||
				IsReservedEventType(EventType(action.Event)) {
				return errors.New("emit action is invalid")
			}
		case EncounterApplyStatus:
			if action.Event != "" || action.StatusID == "" {
				return errors.New("apply_status action is invalid")
			}
			if _, exists := statuses[action.StatusID]; !exists {
				return fmt.Errorf(
					"apply_status references unknown status %q",
					action.StatusID,
				)
			}
			if target != nil && target.Status == nil {
				return fmt.Errorf(
					"target %q cannot receive status %q",
					target.ID,
					action.StatusID,
				)
			}
		default:
			return fmt.Errorf(
				"unsupported action %q",
				action.Type,
			)
		}
	}
	return nil
}
