package sim

import (
	"errors"
	"fmt"
	"reflect"
	"sort"
)

func (s *Simulation) prepareSessionEncounters(
	state SessionState,
) (
	map[string]*encounterRuntime,
	[]string,
	map[string]EntityConfig,
	error,
) {
	result := make(
		map[string]*encounterRuntime,
		len(s.config.Encounters),
	)
	order := make([]string, 0, len(s.config.Encounters))
	definitions := make(map[string]EntityConfig)
	if state.Version < SessionVersion {
		if len(state.Encounters) != 0 {
			return nil, nil, nil,
				errors.New("legacy session contains encounters")
		}
		for _, definition := range s.config.Encounters {
			runtime := &encounterRuntime{
				definition:    cloneEncounterConfig(definition),
				status:        EncounterIdle,
				waveIndex:     -1,
				spawnEntities: make(map[string]string),
				enteredPhases: make(map[string]struct{}),
			}
			if definition.AutoStart {
				runtime.status = EncounterPending
				runtime.remaining = definition.Waves[0].DelayTicks
			}
			result[definition.ID] = runtime
			order = append(order, definition.ID)
		}
		return result, order, definitions, nil
	}
	if len(state.Encounters) != len(s.config.Encounters) {
		return nil, nil, nil,
			errors.New("session encounter set does not match content")
	}
	configs := make(map[string]EncounterConfig, len(s.config.Encounters))
	for _, definition := range s.config.Encounters {
		configs[definition.ID] = definition
		order = append(order, definition.ID)
	}
	for _, saved := range state.Encounters {
		definition, exists := configs[saved.ID]
		if !exists || result[saved.ID] != nil {
			return nil, nil, nil,
				fmt.Errorf("invalid or duplicate encounter %q", saved.ID)
		}
		prepared, spawnedThrough, err :=
			prepareEncounterRuntime(definition, saved)
		if err != nil {
			return nil, nil, nil,
				fmt.Errorf("encounter %q: %w", saved.ID, err)
		}
		result[saved.ID] = prepared
		for waveIndex := 0; waveIndex <= spawnedThrough; waveIndex++ {
			for _, spawn := range definition.Waves[waveIndex].Spawns {
				definitions[spawn.Entity.ID] =
					cloneEntityConfig(spawn.Entity)
			}
		}
	}
	sort.Strings(order)
	return result, order, definitions, nil
}

func prepareEncounterRuntime(
	definition EncounterConfig,
	saved EncounterSessionState,
) (*encounterRuntime, int, error) {
	if saved.Remaining < 0 || saved.Remaining > MaxTickCount {
		return nil, -1, errors.New("remaining timer is invalid")
	}
	if saved.WaveIndex < -1 ||
		saved.WaveIndex >= len(definition.Waves) {
		return nil, -1, errors.New("wave index is invalid")
	}
	switch saved.Status {
	case EncounterIdle:
		if saved.WaveIndex != -1 || saved.Remaining != 0 ||
			len(saved.LiveIDs) != 0 ||
			len(saved.SpawnEntities) != 0 ||
			len(saved.EnteredPhases) != 0 ||
			saved.Error != "" {
			return nil, -1, errors.New("idle state contains progress")
		}
	case EncounterPending:
		next := saved.WaveIndex + 1
		if next < 0 || next >= len(definition.Waves) ||
			saved.Remaining > definition.Waves[next].DelayTicks ||
			saved.Error != "" {
			return nil, -1, errors.New("pending state is invalid")
		}
	case EncounterActive:
		if saved.WaveIndex < 0 || saved.Remaining != 0 ||
			saved.Error != "" {
			return nil, -1, errors.New("active state is invalid")
		}
	case EncounterCompleted:
		if saved.WaveIndex != len(definition.Waves)-1 ||
			saved.Remaining != 0 || saved.Error != "" {
			return nil, -1, errors.New("completed state is invalid")
		}
	case EncounterFailed:
		if saved.Remaining != 0 || saved.Error == "" {
			return nil, -1, errors.New("failed state requires an error")
		}
	default:
		return nil, -1, errors.New("status is invalid")
	}

	liveIDs := append([]string(nil), saved.LiveIDs...)
	if !sort.StringsAreSorted(liveIDs) {
		return nil, -1, errors.New("live entity IDs are not sorted")
	}
	for index, id := range liveIDs {
		if id == "" || (index > 0 && liveIDs[index-1] == id) {
			return nil, -1, errors.New("live entity IDs are invalid")
		}
	}
	spawnEntities := make(map[string]string, len(saved.SpawnEntities))
	orderedSpawns := append(
		[]EncounterSpawnSessionState(nil),
		saved.SpawnEntities...,
	)
	if !sort.SliceIsSorted(orderedSpawns, func(left, right int) bool {
		return orderedSpawns[left].SpawnID < orderedSpawns[right].SpawnID
	}) {
		return nil, -1, errors.New("spawn mappings are not sorted")
	}
	for _, mapping := range orderedSpawns {
		if mapping.SpawnID == "" || mapping.EntityID == "" {
			return nil, -1, errors.New("spawn mapping is invalid")
		}
		if _, duplicate := spawnEntities[mapping.SpawnID]; duplicate {
			return nil, -1, errors.New("spawn mapping is duplicated")
		}
		spawnEntities[mapping.SpawnID] = mapping.EntityID
	}
	entered := make(map[string]struct{}, len(saved.EnteredPhases))
	if !sort.StringsAreSorted(saved.EnteredPhases) {
		return nil, -1, errors.New("entered phases are not sorted")
	}
	for _, phaseID := range saved.EnteredPhases {
		if phaseID == "" {
			return nil, -1, errors.New("entered phase is invalid")
		}
		if _, duplicate := entered[phaseID]; duplicate {
			return nil, -1, errors.New("entered phase is duplicated")
		}
		entered[phaseID] = struct{}{}
	}

	if saved.WaveIndex >= 0 {
		wave := definition.Waves[saved.WaveIndex]
		expectedLive := make([]string, 0, len(wave.Spawns))
		expectedMappings := make(map[string]string, len(wave.Spawns))
		phaseIDs := make(map[string]struct{}, len(wave.BossPhases))
		for _, spawn := range wave.Spawns {
			expectedLive = append(expectedLive, spawn.Entity.ID)
			expectedMappings[spawn.ID] = spawn.Entity.ID
		}
		sort.Strings(expectedLive)
		for _, phase := range wave.BossPhases {
			phaseIDs[phase.ID] = struct{}{}
		}
		if !reflect.DeepEqual(liveIDs, expectedLive) ||
			!reflect.DeepEqual(spawnEntities, expectedMappings) {
			return nil, -1, errors.New("wave entity mapping is invalid")
		}
		for phaseID := range entered {
			if _, exists := phaseIDs[phaseID]; !exists {
				return nil, -1,
					errors.New("entered phase is unknown")
			}
		}
	} else if saved.WaveIndex < 0 &&
		(len(liveIDs) != 0 || len(spawnEntities) != 0 ||
			len(entered) != 0) {
		return nil, -1, errors.New("pre-wave state contains wave entities")
	}

	return &encounterRuntime{
		definition:    cloneEncounterConfig(definition),
		status:        saved.Status,
		waveIndex:     saved.WaveIndex,
		remaining:     saved.Remaining,
		liveIDs:       liveIDs,
		spawnEntities: spawnEntities,
		enteredPhases: entered,
		err:           saved.Error,
	}, saved.WaveIndex, nil
}

func validatePreparedEncounterEntities(
	encounters map[string]*encounterRuntime,
	entities map[string]*entityRuntime,
) error {
	for id, encounter := range encounters {
		if encounter.status != EncounterPending &&
			encounter.status != EncounterCompleted {
			continue
		}
		for _, entityID := range encounter.liveIDs {
			if entity := entities[entityID]; entity != nil && !entity.dead {
				return fmt.Errorf(
					"encounter %q in %s state retains living entity %q",
					id,
					encounter.status,
					entityID,
				)
			}
		}
	}
	return nil
}
