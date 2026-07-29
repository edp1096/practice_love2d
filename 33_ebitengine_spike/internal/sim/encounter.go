package sim

import (
	"errors"
	"fmt"
	"sort"
)

// StartEncounter transitions one idle authored placement to its first delayed
// wave. Auto-start placements call the same method during Simulation creation.
func (s *Simulation) StartEncounter(id string) error {
	state := s.encounters[id]
	if state == nil {
		return fmt.Errorf("unknown encounter %q", id)
	}
	if state.status != EncounterIdle {
		return nil
	}
	if len(state.definition.Waves) == 0 {
		return fmt.Errorf("encounter %q has no waves", id)
	}
	state.status = EncounterPending
	state.waveIndex = -1
	state.remaining = state.definition.Waves[0].DelayTicks
	state.err = ""
	s.emit(Event{
		Type:         EventEncounterStarted,
		EncounterID:  state.definition.ID,
		DefinitionID: state.definition.DefinitionID,
	})
	return nil
}

func (s *Simulation) advanceEncounters() {
	for _, id := range s.encounterOrder {
		state := s.encounters[id]
		if state.status == EncounterIdle && state.definition.AutoStart {
			if err := s.StartEncounter(id); err != nil {
				s.failEncounter(state, err)
				continue
			}
		}
		switch state.status {
		case EncounterPending:
			state.remaining = countdown(state.remaining)
			if state.remaining == 0 {
				if err := s.beginEncounterWave(state); err != nil {
					s.failEncounter(state, err)
				}
			}
		case EncounterActive:
			if err := s.updateEncounterBossPhases(state); err != nil {
				s.failEncounter(state, err)
				continue
			}
			if s.encounterWaveDefeated(state) {
				if err := s.completeEncounterWave(state); err != nil {
					s.failEncounter(state, err)
				}
			}
		}
	}
}

func (s *Simulation) beginEncounterWave(
	state *encounterRuntime,
) error {
	nextIndex := state.waveIndex + 1
	if nextIndex < 0 || nextIndex >= len(state.definition.Waves) {
		return errors.New("encounter wave index is invalid")
	}
	wave := state.definition.Waves[nextIndex]
	for _, spawn := range wave.Spawns {
		if s.entities[spawn.Entity.ID] != nil {
			return fmt.Errorf(
				"encounter spawn entity %q already exists",
				spawn.Entity.ID,
			)
		}
	}

	if err := s.executeEncounterActions(
		wave.OnStart,
		state,
		wave.ID,
		"",
		state.definition.TargetEntityID,
		"wave_start",
	); err != nil {
		return fmt.Errorf("wave %q start: %w", wave.ID, err)
	}
	state.waveIndex = nextIndex
	state.status = EncounterActive
	state.remaining = 0
	state.liveIDs = nil
	state.spawnEntities = make(map[string]string, len(wave.Spawns))
	state.enteredPhases = make(map[string]struct{})
	state.err = ""
	for _, spawn := range wave.Spawns {
		entity := newEntityRuntime(spawn.Entity)
		s.entities[spawn.Entity.ID] = entity
		s.entityOrder = append(s.entityOrder, spawn.Entity.ID)
		state.liveIDs = append(state.liveIDs, spawn.Entity.ID)
		state.spawnEntities[spawn.ID] = spawn.Entity.ID
		s.emit(Event{
			Type:         EventEntitySpawned,
			EntityID:     spawn.Entity.ID,
			EncounterID:  state.definition.ID,
			DefinitionID: state.definition.DefinitionID,
			WaveID:       wave.ID,
			WaveIndex:    nextIndex + 1,
		})
	}
	sort.Strings(s.entityOrder)
	sort.Strings(state.liveIDs)
	s.emit(Event{
		Type:         EventEncounterWaveStarted,
		EncounterID:  state.definition.ID,
		DefinitionID: state.definition.DefinitionID,
		WaveID:       wave.ID,
		WaveIndex:    nextIndex + 1,
		Amount:       len(state.liveIDs),
	})
	return nil
}

func (s *Simulation) updateEncounterBossPhases(
	state *encounterRuntime,
) error {
	if state.waveIndex < 0 ||
		state.waveIndex >= len(state.definition.Waves) {
		return errors.New("active encounter has no wave")
	}
	wave := state.definition.Waves[state.waveIndex]
	for _, phase := range wave.BossPhases {
		if _, entered := state.enteredPhases[phase.ID]; entered {
			continue
		}
		entityID := state.spawnEntities[phase.SpawnID]
		boss := s.entities[entityID]
		if boss == nil || boss.dead ||
			!healthRatioAtMost(
				boss.health,
				boss.config.MaxHealth,
				phase.HealthRatioAtMost,
			) {
			continue
		}
		state.enteredPhases[phase.ID] = struct{}{}
		if err := s.executeEncounterActions(
			phase.Actions,
			state,
			wave.ID,
			phase.ID,
			entityID,
			"boss_phase",
		); err != nil {
			delete(state.enteredPhases, phase.ID)
			return fmt.Errorf("boss phase %q: %w", phase.ID, err)
		}
		s.emit(Event{
			Type:         EventBossPhaseEntered,
			EntityID:     entityID,
			EncounterID:  state.definition.ID,
			DefinitionID: state.definition.DefinitionID,
			WaveID:       wave.ID,
			WaveIndex:    state.waveIndex + 1,
			PhaseID:      phase.ID,
		})
	}
	return nil
}

func healthRatioAtMost(
	health int,
	maxHealth int,
	threshold Coord,
) bool {
	if health < 0 || maxHealth <= 0 ||
		threshold <= 0 || threshold > UnitsPerPixel {
		return false
	}
	unit := int64(UnitsPerPixel)
	maximum := int64(maxHealth)
	limit := maximum/unit*int64(threshold) +
		maximum%unit*int64(threshold)/unit
	return int64(health) <= limit
}

func (s *Simulation) encounterWaveDefeated(
	state *encounterRuntime,
) bool {
	for _, entityID := range state.liveIDs {
		entity := s.entities[entityID]
		if entity != nil && !entity.dead {
			return false
		}
	}
	return true
}

func (s *Simulation) completeEncounterWave(
	state *encounterRuntime,
) error {
	wave := state.definition.Waves[state.waveIndex]
	next := state.waveIndex + 1
	if err := s.preflightEncounterActions(
		wave.OnComplete,
		state.definition.TargetEntityID,
		wave.ID,
		"",
		"wave_complete",
	); err != nil {
		return fmt.Errorf("wave %q completion: %w", wave.ID, err)
	}
	if next >= len(state.definition.Waves) {
		if err := s.preflightEncounterActions(
			state.definition.OnComplete,
			state.definition.TargetEntityID,
			"",
			"",
			"encounter_complete",
		); err != nil {
			return fmt.Errorf("encounter completion: %w", err)
		}
	}
	if err := s.executeEncounterActions(
		wave.OnComplete,
		state,
		wave.ID,
		"",
		state.definition.TargetEntityID,
		"wave_complete",
	); err != nil {
		return fmt.Errorf("wave %q completion: %w", wave.ID, err)
	}
	s.emit(Event{
		Type:         EventEncounterWaveCompleted,
		EncounterID:  state.definition.ID,
		DefinitionID: state.definition.DefinitionID,
		WaveID:       wave.ID,
		WaveIndex:    state.waveIndex + 1,
	})
	if next < len(state.definition.Waves) {
		state.status = EncounterPending
		state.remaining = state.definition.Waves[next].DelayTicks
		return nil
	}
	if err := s.executeEncounterActions(
		state.definition.OnComplete,
		state,
		"",
		"",
		state.definition.TargetEntityID,
		"encounter_complete",
	); err != nil {
		return fmt.Errorf("encounter completion: %w", err)
	}
	state.status = EncounterCompleted
	state.remaining = 0
	s.emit(Event{
		Type:         EventEncounterCompleted,
		EncounterID:  state.definition.ID,
		DefinitionID: state.definition.DefinitionID,
	})
	return nil
}

func (s *Simulation) executeEncounterActions(
	actions []EncounterActionConfig,
	state *encounterRuntime,
	waveID string,
	phaseID string,
	targetID string,
	scope string,
) error {
	if err := s.preflightEncounterActions(
		actions,
		targetID,
		waveID,
		phaseID,
		scope,
	); err != nil {
		return err
	}
	for _, action := range actions {
		switch action.Type {
		case EncounterEmit:
			s.emit(Event{
				Type:         EventType(action.Event),
				EntityID:     targetID,
				EncounterID:  state.definition.ID,
				DefinitionID: state.definition.DefinitionID,
				WaveID:       waveID,
				WaveIndex:    encounterWaveIndex(state, waveID),
				PhaseID:      phaseID,
			})
		case EncounterApplyStatus:
			target := s.entities[targetID]
			if err := s.applyStatus(
				targetID,
				target,
				action.StatusID,
				1,
			); err != nil {
				return err
			}
		default:
			return fmt.Errorf(
				"unsupported encounter action %q",
				action.Type,
			)
		}
	}
	return nil
}

func (s *Simulation) preflightEncounterActions(
	actions []EncounterActionConfig,
	targetID string,
	waveID string,
	phaseID string,
	scope string,
) error {
	for index, action := range actions {
		var err error
		switch action.Type {
		case EncounterEmit:
			if action.Event == "" ||
				IsReservedEventType(EventType(action.Event)) {
				err = fmt.Errorf(
					"invalid authored event %q",
					action.Event,
				)
			}
		case EncounterApplyStatus:
			if _, exists := s.statusDefinitions[action.StatusID]; !exists {
				err = fmt.Errorf("unknown status %q", action.StatusID)
			} else {
				target := s.entities[targetID]
				if target == nil || target.dead ||
					target.config.Status == nil {
					err = fmt.Errorf(
						"target cannot receive status %q",
						action.StatusID,
					)
				}
			}
		default:
			err = fmt.Errorf(
				"unsupported encounter action %q",
				action.Type,
			)
		}
		if err != nil {
			return &encounterActionError{
				scope:       scope,
				waveID:      waveID,
				phaseID:     phaseID,
				actionIndex: index + 1,
				actionType:  action.Type,
				err:         err,
			}
		}
	}
	return nil
}

type encounterActionError struct {
	scope       string
	waveID      string
	phaseID     string
	actionIndex int
	actionType  EncounterActionType
	err         error
}

func (failure *encounterActionError) Error() string {
	return failure.err.Error()
}

func (failure *encounterActionError) Unwrap() error {
	return failure.err
}

func encounterWaveIndex(
	state *encounterRuntime,
	waveID string,
) int {
	if state == nil || waveID == "" {
		return 0
	}
	for index, wave := range state.definition.Waves {
		if wave.ID == waveID {
			return index + 1
		}
	}
	return 0
}

func (s *Simulation) failEncounter(
	state *encounterRuntime,
	err error,
) {
	state.status = EncounterFailed
	state.err = err.Error()
	event := Event{
		Type:         EventEncounterActionFailed,
		EncounterID:  state.definition.ID,
		DefinitionID: state.definition.DefinitionID,
		Reason:       state.err,
	}
	var actionFailure *encounterActionError
	if errors.As(err, &actionFailure) {
		event.WaveID = actionFailure.waveID
		event.WaveIndex = encounterWaveIndex(
			state,
			actionFailure.waveID,
		)
		event.PhaseID = actionFailure.phaseID
		event.Scope = actionFailure.scope
		event.ActionIndex = actionFailure.actionIndex
		event.ActionType = string(actionFailure.actionType)
	}
	s.emit(event)
}

func (s *Simulation) encounterSnapshots() []EncounterSnapshot {
	result := make(
		[]EncounterSnapshot,
		0,
		len(s.encounterOrder),
	)
	for _, id := range s.encounterOrder {
		state := s.encounters[id]
		snapshot := EncounterSnapshot{
			ID:             id,
			DefinitionID:   state.definition.DefinitionID,
			Status:         state.status,
			RemainingTicks: state.remaining,
			Error:          state.err,
		}
		if state.waveIndex >= 0 &&
			state.waveIndex < len(state.definition.Waves) {
			snapshot.WaveIndex = state.waveIndex + 1
			snapshot.WaveID =
				state.definition.Waves[state.waveIndex].ID
		}
		for _, entityID := range state.liveIDs {
			entity := s.entities[entityID]
			if entity != nil && !entity.dead {
				snapshot.Living++
			}
		}
		for phaseID := range state.enteredPhases {
			snapshot.EnteredPhases = append(
				snapshot.EnteredPhases,
				phaseID,
			)
		}
		sort.Strings(snapshot.EnteredPhases)
		result = append(result, snapshot)
	}
	return result
}

func cloneEncounterConfig(source EncounterConfig) EncounterConfig {
	result := source
	result.Waves = make([]EncounterWaveConfig, len(source.Waves))
	for waveIndex, wave := range source.Waves {
		copied := wave
		copied.Spawns = make(
			[]EncounterSpawnConfig,
			len(wave.Spawns),
		)
		for spawnIndex, spawn := range wave.Spawns {
			copied.Spawns[spawnIndex] = EncounterSpawnConfig{
				ID:     spawn.ID,
				Entity: cloneEntityConfig(spawn.Entity),
			}
		}
		copied.BossPhases = make(
			[]BossPhaseConfig,
			len(wave.BossPhases),
		)
		for phaseIndex, phase := range wave.BossPhases {
			copied.BossPhases[phaseIndex] = phase
			copied.BossPhases[phaseIndex].Actions = append(
				[]EncounterActionConfig(nil),
				phase.Actions...,
			)
		}
		copied.OnStart = append(
			[]EncounterActionConfig(nil),
			wave.OnStart...,
		)
		copied.OnComplete = append(
			[]EncounterActionConfig(nil),
			wave.OnComplete...,
		)
		result.Waves[waveIndex] = copied
	}
	result.OnComplete = append(
		[]EncounterActionConfig(nil),
		source.OnComplete...,
	)
	return result
}

func cloneEncounters(
	source map[string]*encounterRuntime,
) map[string]*encounterRuntime {
	result := make(map[string]*encounterRuntime, len(source))
	for id, state := range source {
		copied := *state
		copied.definition = cloneEncounterConfig(state.definition)
		copied.liveIDs = append([]string(nil), state.liveIDs...)
		copied.spawnEntities = make(
			map[string]string,
			len(state.spawnEntities),
		)
		for spawnID, entityID := range state.spawnEntities {
			copied.spawnEntities[spawnID] = entityID
		}
		copied.enteredPhases = cloneStringSet(state.enteredPhases)
		result[id] = &copied
	}
	return result
}
