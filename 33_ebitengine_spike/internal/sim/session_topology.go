package sim

import (
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type sessionTopology struct {
	definitions      map[string]EntityConfig
	entityOrder      []string
	dynamicIDs       map[string]struct{}
	removedIDs       map[string]struct{}
	previewDefs      map[string]EntityPreviewConfig
	dialogues        map[string]DialogueDefinition
	questDefinitions map[string]QuestDefinition
	questOrder       []string
	interactionRange Coord
	directQuestDefs  map[string]QuestDefinition
}

type preparedSession struct {
	topology        sessionTopology
	entities        map[string]*entityRuntime
	quests          map[string]*questRuntime
	dialogue        dialogueRuntime
	camera          cameraRuntime
	projectiles     map[string]*projectileRuntime
	projectileOrder []string
	encounters      map[string]*encounterRuntime
	encounterOrder  []string
}

func (s *Simulation) prepareSession(
	state SessionState,
) (preparedSession, error) {
	if state.Version != SessionVersion &&
		state.Version != platformerSessionVersion &&
		state.Version != actionSessionVersion &&
		state.Version != topologySessionVersion &&
		state.Version != legacySessionVersion {
		return preparedSession{},
			fmt.Errorf("unsupported session version %d", state.Version)
	}
	if state.Version == legacySessionVersion &&
		(len(state.PreviewEntities) != 0 ||
			len(state.RemovedEntityIDs) != 0 ||
			len(state.PreviewQuests) != 0 ||
			state.Dialogue.Definition != nil) {
		return preparedSession{},
			errors.New("legacy session contains preview topology")
	}
	if state.Version < actionSessionVersion &&
		(state.ProjectileSequence != 0 || len(state.Projectiles) != 0) {
		return preparedSession{},
			errors.New("legacy session contains projectiles")
	}
	if state.WorldTick > state.Tick {
		return preparedSession{},
			errors.New("world tick cannot exceed raw tick")
	}
	if state.Hitstop < 0 {
		return preparedSession{}, errors.New("hitstop cannot be negative")
	}
	if !validTickCount(state.Hitstop) {
		return preparedSession{},
			errors.New("hitstop exceeds deterministic timer range")
	}
	encounters, encounterOrder, encounterDefinitions, err :=
		s.prepareSessionEncounters(state)
	if err != nil {
		return preparedSession{}, err
	}
	topology, err := s.prepareSessionTopology(
		state,
		encounterDefinitions,
	)
	if err != nil {
		return preparedSession{}, err
	}
	if len(state.Entities) != len(topology.entityOrder) {
		return preparedSession{},
			errors.New("session entity set does not match content")
	}

	// restoreEntitySession validates historical attack target IDs through its
	// receiver. Give it the candidate topology, never the currently live one.
	validator := *s
	validator.entities = make(
		map[string]*entityRuntime,
		len(topology.definitions),
	)
	for id, definition := range topology.definitions {
		validator.entities[id] = &entityRuntime{
			config: cloneEntityConfig(definition),
		}
	}
	entities := make(map[string]*entityRuntime, len(state.Entities))
	for _, saved := range state.Entities {
		definition, present := topology.definitions[saved.ID]
		if !present {
			return preparedSession{},
				fmt.Errorf("session contains unknown entity %q", saved.ID)
		}
		if entities[saved.ID] != nil {
			return preparedSession{},
				fmt.Errorf("session duplicates entity %q", saved.ID)
		}
		entity, err := validator.restoreEntitySession(
			definition,
			saved,
			state.WorldTick,
			state.Version,
		)
		if err != nil {
			return preparedSession{},
				fmt.Errorf("entity %q: %w", saved.ID, err)
		}
		entities[saved.ID] = entity
	}
	for _, id := range topology.entityOrder {
		if entities[id] == nil {
			return preparedSession{},
				fmt.Errorf("session is missing entity %q", id)
		}
	}
	if err := validatePreparedEncounterEntities(
		encounters,
		entities,
	); err != nil {
		return preparedSession{}, err
	}

	if len(state.Quests) != len(topology.questOrder) {
		return preparedSession{},
			errors.New("session quest set does not match content")
	}
	quests := make(map[string]*questRuntime, len(state.Quests))
	for _, saved := range state.Quests {
		definition, present := topology.questDefinitions[saved.ID]
		if !present || quests[saved.ID] != nil {
			return preparedSession{},
				fmt.Errorf("invalid or duplicate quest %q", saved.ID)
		}
		if saved.Status != QuestInactive &&
			saved.Status != QuestActive &&
			saved.Status != QuestCompleted {
			return preparedSession{},
				fmt.Errorf("quest %q has invalid status", saved.ID)
		}
		if saved.Progress < 0 || saved.Progress > definition.Required ||
			(saved.Status == QuestCompleted &&
				saved.Progress != definition.Required) ||
			(saved.Status != QuestCompleted &&
				saved.Progress == definition.Required) {
			return preparedSession{},
				fmt.Errorf("quest %q has invalid progress", saved.ID)
		}
		quests[saved.ID] = &questRuntime{
			definition: definition,
			status:     saved.Status,
			progress:   saved.Progress,
		}
	}

	dialogue, err := prepareSessionDialogue(
		state.Dialogue,
		topology.dialogues,
		entities,
	)
	if err != nil {
		return preparedSession{}, err
	}
	camera, err := s.prepareSessionCamera(state.Camera, entities)
	if err != nil {
		return preparedSession{}, err
	}
	projectiles, projectileOrder, err := s.prepareSessionProjectiles(
		state,
		entities,
	)
	if err != nil {
		return preparedSession{}, err
	}
	return preparedSession{
		topology:        topology,
		entities:        entities,
		quests:          quests,
		dialogue:        dialogue,
		camera:          camera,
		projectiles:     projectiles,
		projectileOrder: projectileOrder,
		encounters:      encounters,
		encounterOrder:  encounterOrder,
	}, nil
}

func (s *Simulation) prepareSessionProjectiles(
	state SessionState,
	entities map[string]*entityRuntime,
) (map[string]*projectileRuntime, []string, error) {
	result := make(map[string]*projectileRuntime, len(state.Projectiles))
	order := make([]string, 0, len(state.Projectiles))
	for _, saved := range state.Projectiles {
		definition, exists := s.projectileDefinitions[saved.DefinitionID]
		if !exists || saved.ID == "" || saved.AbilityID == "" ||
			saved.SourceID == "" || saved.Team == "" ||
			saved.Remaining <= 0 ||
			saved.Remaining > definition.LifetimeTicks ||
			saved.Hits < 0 || saved.Hits > definition.Pierce ||
			saved.Hits != len(saved.HitTargets) ||
			!validCoord(saved.Position.X) ||
			!validCoord(saved.Position.Y) ||
			!validCoord(saved.Previous.X) ||
			!validCoord(saved.Previous.Y) ||
			!containsRect(
				s.config.StageBounds,
				entityRect(saved.Position, definition.Body),
			) ||
			!containsRect(
				s.config.StageBounds,
				entityRect(saved.Previous, definition.Body),
			) {
			return nil, nil, fmt.Errorf(
				"projectile %q has invalid session state",
				saved.ID,
			)
		}
		if _, duplicate := result[saved.ID]; duplicate {
			return nil, nil, fmt.Errorf(
				"session duplicates projectile %q",
				saved.ID,
			)
		}
		separator := strings.LastIndex(saved.ID, ".projectile.")
		if separator <= 0 {
			return nil, nil, fmt.Errorf(
				"projectile %q has an invalid sequence",
				saved.ID,
			)
		}
		sequence, sequenceErr := strconv.ParseUint(
			saved.ID[separator+len(".projectile."):],
			10,
			64,
		)
		if sequenceErr != nil || sequence == 0 ||
			sequence > state.ProjectileSequence {
			return nil, nil, fmt.Errorf(
				"projectile %q has an invalid sequence",
				saved.ID,
			)
		}
		directionMagnitude := int64(integerSqrt(
			uint64(squaredMagnitude(saved.Direction)),
		))
		if saved.Direction == (Vec{}) ||
			directionMagnitude < int64(UnitsPerPixel)-2 ||
			directionMagnitude > int64(UnitsPerPixel)+2 {
			return nil, nil, fmt.Errorf(
				"projectile %q direction is invalid",
				saved.ID,
			)
		}
		hitTargets := make(map[string]struct{}, len(saved.HitTargets))
		for _, targetID := range saved.HitTargets {
			if targetID == "" {
				return nil, nil, fmt.Errorf(
					"projectile %q has an empty hit target",
					saved.ID,
				)
			}
			if _, duplicate := hitTargets[targetID]; duplicate {
				return nil, nil, fmt.Errorf(
					"projectile %q duplicates hit target %q",
					saved.ID,
					targetID,
				)
			}
			hitTargets[targetID] = struct{}{}
		}
		// A live source must retain its authored team. A removed preview source
		// remains a safe string identity and is allowed to be absent.
		if source := entities[saved.SourceID]; source != nil &&
			source.config.Team != saved.Team {
			return nil, nil, fmt.Errorf(
				"projectile %q source team is inconsistent",
				saved.ID,
			)
		}
		result[saved.ID] = &projectileRuntime{
			id:           saved.ID,
			definitionID: saved.DefinitionID,
			abilityID:    saved.AbilityID,
			sourceID:     saved.SourceID,
			team:         saved.Team,
			position:     saved.Position,
			previous:     saved.Previous,
			direction:    saved.Direction,
			remaining:    saved.Remaining,
			hits:         saved.Hits,
			hitTargets:   hitTargets,
		}
		order = append(order, saved.ID)
	}
	sort.Strings(order)
	return result, order, nil
}

func (s *Simulation) prepareSessionTopology(
	state SessionState,
	encounterDefinitions map[string]EntityConfig,
) (sessionTopology, error) {
	topology := sessionTopology{
		definitions:      make(map[string]EntityConfig),
		dynamicIDs:       make(map[string]struct{}),
		removedIDs:       make(map[string]struct{}),
		previewDefs:      make(map[string]EntityPreviewConfig),
		dialogues:        make(map[string]DialogueDefinition),
		questDefinitions: make(map[string]QuestDefinition),
		directQuestDefs:  make(map[string]QuestDefinition),
		interactionRange: s.config.InteractionRange,
	}
	for _, definition := range s.config.Dialogues {
		topology.dialogues[definition.ID] = definition
	}
	for _, definition := range s.config.Quests {
		topology.questDefinitions[definition.ID] = definition
	}
	for _, definition := range state.PreviewQuests {
		if err := validateQuestDefinition(definition); err != nil {
			return sessionTopology{}, err
		}
		if s.isAuthoredQuest(definition.ID) {
			return sessionTopology{}, fmt.Errorf(
				"preview quest %q uses an authored ID",
				definition.ID,
			)
		}
		if existing, duplicate :=
			topology.directQuestDefs[definition.ID]; duplicate {
			if existing == definition {
				return sessionTopology{}, fmt.Errorf(
					"session duplicates preview quest %q",
					definition.ID,
				)
			}
			return sessionTopology{}, fmt.Errorf(
				"preview quest %q conflicts with itself",
				definition.ID,
			)
		}
		topology.directQuestDefs[definition.ID] = definition
		topology.questDefinitions[definition.ID] = definition
	}
	for _, id := range state.RemovedEntityIDs {
		if id == "" {
			return sessionTopology{}, errors.New("removed entity ID is required")
		}
		if _, duplicate := topology.removedIDs[id]; duplicate {
			return sessionTopology{},
				fmt.Errorf("session duplicates removed entity %q", id)
		}
		if _, authored := s.authoredIDs[id]; !authored {
			return sessionTopology{},
				fmt.Errorf("session removes non-authored entity %q", id)
		}
		if id == s.controlledID {
			return sessionTopology{},
				fmt.Errorf("session removes controlled entity %q", id)
		}
		if id == s.config.Camera.TargetEntityID {
			return sessionTopology{},
				fmt.Errorf("session removes camera target %q", id)
		}
		topology.removedIDs[id] = struct{}{}
	}
	for _, definition := range s.config.Entities {
		if _, removed := topology.removedIDs[definition.ID]; removed {
			continue
		}
		topology.definitions[definition.ID] = cloneEntityConfig(definition)
	}
	for id, definition := range encounterDefinitions {
		if _, removed := topology.removedIDs[id]; removed {
			continue
		}
		topology.definitions[id] = cloneEntityConfig(definition)
	}

	// Collect dependencies before validating entities. Two bundles may share a
	// definition and their serialized order must not change resolution.
	for _, source := range state.PreviewEntities {
		preview := cloneEntityPreviewConfig(source)
		normalizeEntityCombat(&preview.Entity)
		id := preview.Entity.ID
		if id == "" {
			return sessionTopology{}, errors.New("preview entity ID is required")
		}
		if _, authored := s.authoredIDs[id]; authored {
			return sessionTopology{},
				fmt.Errorf("preview entity %q uses an authored ID", id)
		}
		if _, duplicate := topology.dynamicIDs[id]; duplicate {
			return sessionTopology{},
				fmt.Errorf("session duplicates preview entity %q", id)
		}
		if preview.Entity.Controlled {
			return sessionTopology{},
				fmt.Errorf("preview entity %q cannot be controlled", id)
		}
		if preview.InteractionRange < 0 ||
			!validCoord(preview.InteractionRange) {
			return sessionTopology{},
				fmt.Errorf("preview entity %q has invalid interaction range", id)
		}
		topology.dynamicIDs[id] = struct{}{}
		if preview.Dialogue != nil {
			if preview.Dialogue.ID == "" ||
				preview.Entity.DialogueID != preview.Dialogue.ID {
				return sessionTopology{}, fmt.Errorf(
					"preview entity %q has invalid dialogue bundle",
					id,
				)
			}
			if existing, present := topology.dialogues[preview.Dialogue.ID]; present && existing != *preview.Dialogue {
				return sessionTopology{}, fmt.Errorf(
					"preview dialogue %q conflicts with content",
					preview.Dialogue.ID,
				)
			}
			topology.dialogues[preview.Dialogue.ID] = *preview.Dialogue
		}
		if preview.Quest != nil {
			if err := validateQuestDefinition(*preview.Quest); err != nil {
				return sessionTopology{}, err
			}
			if err := validatePreviewQuestAnchor(
				preview.Entity,
				preview.Quest.ID,
			); err != nil {
				return sessionTopology{}, err
			}
			if existing, present :=
				topology.questDefinitions[preview.Quest.ID]; present && existing != *preview.Quest {
				return sessionTopology{}, fmt.Errorf(
					"preview quest %q conflicts with content",
					preview.Quest.ID,
				)
			}
			topology.questDefinitions[preview.Quest.ID] = *preview.Quest
		}
		topology.definitions[id] = cloneEntityConfig(preview.Entity)
		topology.interactionRange = maxCoord(
			topology.interactionRange,
			preview.InteractionRange,
		)
	}

	dialogueIDs := make(map[string]struct{}, len(topology.dialogues))
	for id := range topology.dialogues {
		dialogueIDs[id] = struct{}{}
	}
	questIDs := make(map[string]struct{}, len(topology.questDefinitions))
	for id := range topology.questDefinitions {
		questIDs[id] = struct{}{}
	}
	for _, source := range state.PreviewEntities {
		preview := cloneEntityPreviewConfig(source)
		normalizeEntityCombat(&preview.Entity)
		// Definition.Position is the original preview spawn. A wall may have
		// been edited over that vacated point; restoreEntitySession validates
		// the authoritative saved runtime position below.
		if err := validateEntityDefinitionWithPlacement(
			s.config,
			preview.Entity,
			dialogueIDs,
			questIDs,
			false,
		); err != nil {
			return sessionTopology{}, err
		}
		if preview.Entity.DialogueID != "" &&
			topology.interactionRange == 0 {
			return sessionTopology{},
				errors.New("preview interactable requires interaction range")
		}
		if preview.Entity.DialogueID != "" &&
			s.config.InteractionRange == 0 &&
			preview.InteractionRange == 0 {
			preview.InteractionRange = topology.interactionRange
		}
		if preview.Entity.DialogueID != "" &&
			!s.isAuthoredDialogue(preview.Entity.DialogueID) {
			definition, present :=
				topology.dialogues[preview.Entity.DialogueID]
			if !present {
				return sessionTopology{}, fmt.Errorf(
					"preview entity %q references unknown dialogue %q",
					preview.Entity.ID,
					preview.Entity.DialogueID,
				)
			}
			preview.Dialogue = &definition
		} else {
			preview.Dialogue = nil
		}
		questDependencyID := previewQuestDependencyID(
			preview.Entity,
			preview.Quest,
		)
		if questDependencyID != "" &&
			!s.isAuthoredQuest(questDependencyID) {
			definition, present :=
				topology.questDefinitions[questDependencyID]
			if !present {
				return sessionTopology{}, fmt.Errorf(
					"preview entity %q references unknown quest %q",
					preview.Entity.ID,
					questDependencyID,
				)
			}
			preview.Quest = &definition
		} else {
			preview.Quest = nil
		}
		topology.previewDefs[preview.Entity.ID] = preview
	}
	// Quest target IDs are stable content identities, not live pointers. A
	// preview target may have been removed after the quest was registered;
	// retaining that ID is safe and debug removal must not imply defeat.
	for id := range topology.definitions {
		topology.entityOrder = append(topology.entityOrder, id)
	}
	sort.Strings(topology.entityOrder)
	for id := range topology.questDefinitions {
		topology.questOrder = append(topology.questOrder, id)
	}
	sort.Strings(topology.questOrder)
	return topology, nil
}

func prepareSessionDialogue(
	state DialogueSessionState,
	dialogues map[string]DialogueDefinition,
	entities map[string]*entityRuntime,
) (dialogueRuntime, error) {
	if !state.Active {
		if state.DefinitionID != "" || state.NPCID != "" ||
			state.Definition != nil {
			return dialogueRuntime{},
				errors.New("inactive session dialogue contains references")
		}
		return dialogueRuntime{}, nil
	}
	direct := state.Definition != nil
	definition := dialogues[state.DefinitionID]
	if direct {
		definition = *state.Definition
		if definition.ID == "" || definition.ID != state.DefinitionID {
			return dialogueRuntime{},
				errors.New("direct session dialogue definition is invalid")
		}
	} else if definition.ID == "" {
		return dialogueRuntime{}, fmt.Errorf(
			"session references unknown dialogue %q",
			state.DefinitionID,
		)
	}
	if state.NPCID != "" {
		npc := entities[state.NPCID]
		if npc == nil || npc.dead ||
			(!direct && npc.config.DialogueID != state.DefinitionID) {
			return dialogueRuntime{},
				errors.New("session dialogue NPC is invalid")
		}
	} else if !direct {
		return dialogueRuntime{},
			errors.New("authored session dialogue requires an NPC")
	}
	return dialogueRuntime{
		active:       true,
		definitionID: state.DefinitionID,
		npcID:        state.NPCID,
		direct:       direct,
		definition:   definition,
	}, nil
}

func (s *Simulation) prepareSessionCamera(
	state CameraSessionState,
	entities map[string]*entityRuntime,
) (cameraRuntime, error) {
	if err := validateCameraSession(state); err != nil {
		return cameraRuntime{}, err
	}
	target := entities[s.config.Camera.TargetEntityID]
	if target == nil {
		return cameraRuntime{}, errors.New("session removes camera target")
	}
	expectedBase := clampCamera(
		target.position,
		s.config.StageBounds,
		s.config.Camera,
	)
	expectedCenter := clampCamera(
		Vec{
			X: expectedBase.X + state.Offset.X,
			Y: expectedBase.Y + state.Offset.Y,
		},
		s.config.StageBounds,
		s.config.Camera,
	)
	expectedOffset := Vec{
		X: expectedCenter.X - expectedBase.X,
		Y: expectedCenter.Y - expectedBase.Y,
	}
	if state.BaseCenter != expectedBase ||
		state.Center != expectedCenter ||
		state.Offset != expectedOffset {
		return cameraRuntime{},
			errors.New("camera session state is not canonical for target position")
	}
	return cameraRuntime{
		baseCenter:     state.BaseCenter,
		center:         state.Center,
		offset:         state.Offset,
		shakeMagnitude: state.ShakeMagnitude,
		shakeDuration:  state.ShakeDuration,
		shakeRemaining: state.ShakeRemaining,
		shakeSequence:  state.ShakeSequence,
	}, nil
}
