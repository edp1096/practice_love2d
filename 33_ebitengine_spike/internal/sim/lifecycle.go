package sim

import (
	"errors"
	"fmt"
	"sort"
)

// SpawnEntity validates and atomically adds one renderer-independent preview
// entity. Authored IDs remain reserved after removal so a preview cannot
// silently replace content with a different definition. Spawned entities are
// runtime topology: constructing a new Simulation from Config removes them.
func (s *Simulation) SpawnEntity(definition EntityConfig) error {
	return s.SpawnEntityPreview(EntityPreviewConfig{Entity: definition})
}

// SpawnEntityPreview adds an entity and any missing interactable dependencies
// as one transaction. Definitions already present in the stage may be omitted.
// Supplied definitions must exactly match an existing definition with the same
// ID; a preview cannot shadow authored content.
func (s *Simulation) SpawnEntityPreview(preview EntityPreviewConfig) error {
	preview = cloneEntityPreviewConfig(preview)
	definition := preview.Entity
	if definition.ID == "" {
		return errors.New("entity ID is required")
	}
	if s.entities[definition.ID] != nil {
		return fmt.Errorf("duplicate entity %q", definition.ID)
	}
	if _, authored := s.authoredIDs[definition.ID]; authored {
		return fmt.Errorf(
			"entity ID %q is reserved by authored content",
			definition.ID,
		)
	}
	if definition.Controlled {
		return errors.New("preview entity cannot be controlled")
	}
	canonical, err := s.validatePreviewDefinition(preview)
	if err != nil {
		return err
	}

	// All fallible work is complete. Commit the detached definition and keep
	// every externally observable ordering lexicographic.
	if canonical.Dialogue != nil {
		s.dialogues[canonical.Dialogue.ID] = *canonical.Dialogue
	}
	if canonical.Quest != nil && s.quests[canonical.Quest.ID] == nil {
		status := QuestInactive
		if canonical.Quest.InitiallyActive {
			status = QuestActive
		}
		s.quests[canonical.Quest.ID] = &questRuntime{
			definition: *canonical.Quest,
			status:     status,
		}
		s.questOrder = append(s.questOrder, canonical.Quest.ID)
		sort.Strings(s.questOrder)
	}
	s.entities[definition.ID] = newEntityRuntime(definition)
	s.dynamicIDs[definition.ID] = struct{}{}
	s.previewDefs[definition.ID] = canonical
	s.interactionRange = maxCoord(
		s.interactionRange,
		canonical.InteractionRange,
	)
	s.entityOrder = append(s.entityOrder, definition.ID)
	sort.Strings(s.entityOrder)
	s.emit(Event{Type: EventEntitySpawned, EntityID: definition.ID})
	return nil
}

// RemoveEntity atomically removes one runtime entity. The controlled entity,
// camera target, and active dialogue speaker are strong runtime references and
// cannot be removed. Attack hit-target entries are historical per-instance
// references, so they are safely forgotten. Quest target IDs are stable
// content identities rather than pointers; debug removal retains them and
// neither completes nor advances a quest.
//
// Dead entities may be removed. Removal is topology cleanup, not a combat
// defeat, and therefore emits no kill event or quest progress.
func (s *Simulation) RemoveEntity(id string) error {
	if id == "" {
		return errors.New("entity ID is required")
	}
	entity := s.entities[id]
	if entity == nil {
		return fmt.Errorf("unknown entity %q", id)
	}
	if id == s.controlledID {
		return fmt.Errorf("cannot remove controlled entity %q", id)
	}
	if id == s.config.Camera.TargetEntityID {
		return fmt.Errorf("cannot remove camera target %q", id)
	}
	if s.dialogue.active && s.dialogue.npcID == id {
		return fmt.Errorf("cannot remove active dialogue speaker %q", id)
	}

	// Commit after every rejecting check. Removing stale per-attack identity
	// makes a later preview entity with the same dynamic ID a new instance.
	for _, sourceID := range s.entityOrder {
		source := s.entities[sourceID]
		if source.attack == nil {
			continue
		}
		if _, referenced := source.attack.hitTargets[id]; referenced {
			delete(source.attack.hitTargets, id)
			source.attack.hitCount--
		}
	}
	delete(s.entities, id)
	s.entityOrder = removeSortedID(s.entityOrder, id)
	if _, dynamic := s.dynamicIDs[id]; dynamic {
		delete(s.dynamicIDs, id)
		delete(s.previewDefs, id)
		s.rebuildPreviewDependencies()
	} else {
		s.removedIDs[id] = struct{}{}
	}
	s.emit(Event{Type: EventEntityRemoved, EntityID: id})
	return nil
}

// StartDialogue atomically opens a data-authored or draft dialogue with an
// optional speaker entity. Passing the full definition lets Maker preview
// content that is not registered in the current stage. The definition is
// stored in active runtime/session state but does not mutate Config, so a new
// stage/session starts from authored content again.
func (s *Simulation) StartDialogue(
	definition DialogueDefinition,
	speakerID string,
) error {
	return s.StartDialoguePreview(
		DialoguePreviewConfig{Dialogue: definition},
		speakerID,
	)
}

// StartDialoguePreview opens a draft dialogue and atomically registers its
// optional quest dependency. StartQuest distinguishes an entry-node action
// from a dependency used only by later dialogue choices. A non-authored quest
// remains temporary preview content after close and is cleared by constructing
// a new Simulation/resetting the stage.
func (s *Simulation) StartDialoguePreview(
	preview DialoguePreviewConfig,
	speakerID string,
) error {
	if s.dialogue.active {
		return errors.New("a dialogue is already active")
	}
	definition := preview.Dialogue
	if definition.ID == "" {
		return errors.New("dialogue ID is required")
	}
	if speakerID != "" {
		speaker := s.entities[speakerID]
		if speaker == nil {
			return fmt.Errorf("unknown dialogue speaker %q", speakerID)
		}
		if speaker.dead {
			return fmt.Errorf("dialogue speaker %q is dead", speakerID)
		}
	}
	if preview.StartQuest && preview.Quest == nil {
		return errors.New("dialogue StartQuest requires a quest definition")
	}
	if preview.Quest != nil {
		if err := validateQuestDefinition(*preview.Quest); err != nil {
			return err
		}
		if targetID := preview.Quest.TargetEntityID; targetID != "" &&
			!s.hasEntityIdentity(targetID) {
			return fmt.Errorf(
				"quest %q references unknown entity %q",
				preview.Quest.ID,
				targetID,
			)
		}
		if existing := s.quests[preview.Quest.ID]; existing != nil &&
			existing.definition != *preview.Quest {
			return fmt.Errorf(
				"quest %q conflicts with existing content",
				preview.Quest.ID,
			)
		}
	}

	if preview.Quest != nil {
		quest := s.quests[preview.Quest.ID]
		if quest == nil {
			status := QuestInactive
			if preview.Quest.InitiallyActive {
				status = QuestActive
			}
			quest = &questRuntime{
				definition: *preview.Quest,
				status:     status,
			}
			s.quests[preview.Quest.ID] = quest
			s.questOrder = append(s.questOrder, preview.Quest.ID)
			sort.Strings(s.questOrder)
		}
		if !s.isAuthoredQuest(preview.Quest.ID) {
			s.directQuestDefs[preview.Quest.ID] = *preview.Quest
		}
		if preview.StartQuest && quest.status == QuestInactive {
			quest.status = QuestActive
			s.emit(Event{
				Type:    EventQuestStarted,
				QuestID: preview.Quest.ID,
			})
		}
	}
	s.dialogue = dialogueRuntime{
		active:       true,
		definitionID: definition.ID,
		npcID:        speakerID,
		direct:       true,
		definition:   definition,
	}
	s.emit(Event{
		Type:       EventDialogueStarted,
		EntityID:   s.controlledID,
		TargetID:   speakerID,
		DialogueID: definition.ID,
	})
	return nil
}

// HasPreviewTopology reports whether runtime entity membership differs from
// authored Config. Durable player saves can use this to reject temporary Maker
// previews while Clone and SessionState can still round-trip them safely.
func (s *Simulation) HasPreviewTopology() bool {
	return len(s.dynamicIDs) != 0 || len(s.removedIDs) != 0
}

// HasTemporaryPreview also includes a directly supplied draft dialogue.
func (s *Simulation) HasTemporaryPreview() bool {
	return s.HasPreviewTopology() ||
		(s.dialogue.active && s.dialogue.direct) ||
		len(s.directQuestDefs) != 0
}

func (s *Simulation) validatePreviewDefinition(
	preview EntityPreviewConfig,
) (EntityPreviewConfig, error) {
	definition := preview.Entity
	if preview.InteractionRange < 0 ||
		!validCoord(preview.InteractionRange) {
		return EntityPreviewConfig{},
			errors.New("preview interaction range is invalid")
	}
	if preview.Dialogue != nil {
		if preview.Dialogue.ID == "" {
			return EntityPreviewConfig{}, errors.New("dialogue ID is required")
		}
		if definition.DialogueID != preview.Dialogue.ID {
			return EntityPreviewConfig{}, fmt.Errorf(
				"entity %q does not reference supplied dialogue %q",
				definition.ID,
				preview.Dialogue.ID,
			)
		}
		if existing, present := s.dialogues[preview.Dialogue.ID]; present &&
			existing != *preview.Dialogue {
			return EntityPreviewConfig{}, fmt.Errorf(
				"dialogue %q conflicts with existing content",
				preview.Dialogue.ID,
			)
		}
	}
	if preview.Quest != nil {
		if err := validateQuestDefinition(*preview.Quest); err != nil {
			return EntityPreviewConfig{}, err
		}
		if err := validatePreviewQuestAnchor(
			definition,
			preview.Quest.ID,
		); err != nil {
			return EntityPreviewConfig{}, err
		}
		if existing := s.quests[preview.Quest.ID]; existing != nil &&
			existing.definition != *preview.Quest {
			return EntityPreviewConfig{}, fmt.Errorf(
				"quest %q conflicts with existing content",
				preview.Quest.ID,
			)
		}
		if targetID := preview.Quest.TargetEntityID; targetID != "" &&
			targetID != definition.ID &&
			!s.hasEntityIdentity(targetID) {
			return EntityPreviewConfig{}, fmt.Errorf(
				"quest %q references unknown entity %q",
				preview.Quest.ID,
				targetID,
			)
		}
	}

	dialogues := make(map[string]struct{}, len(s.dialogues))
	for id := range s.dialogues {
		dialogues[id] = struct{}{}
	}
	if preview.Dialogue != nil {
		dialogues[preview.Dialogue.ID] = struct{}{}
	}
	quests := make(map[string]struct{}, len(s.quests))
	for id := range s.quests {
		quests[id] = struct{}{}
	}
	if preview.Quest != nil {
		quests[preview.Quest.ID] = struct{}{}
	}
	if err := validateEntityDefinition(
		s.config,
		definition,
		dialogues,
		quests,
	); err != nil {
		return EntityPreviewConfig{}, err
	}
	effectiveRange := maxCoord(s.interactionRange, preview.InteractionRange)
	if definition.DialogueID != "" && effectiveRange == 0 {
		return EntityPreviewConfig{}, errors.New(
			"interactable entities require a positive interaction range",
		)
	}
	if definition.DialogueID != "" &&
		s.config.InteractionRange == 0 &&
		preview.InteractionRange == 0 {
		preview.InteractionRange = effectiveRange
	}

	// Every preview entity retains the definitions it depends on when those
	// definitions are not authored. This makes dependency cleanup independent
	// of which preview entity introduced shared content first.
	if definition.DialogueID != "" &&
		!s.isAuthoredDialogue(definition.DialogueID) {
		resolved, present := s.dialogues[definition.DialogueID]
		if preview.Dialogue != nil {
			resolved, present = *preview.Dialogue, true
		}
		if !present {
			return EntityPreviewConfig{}, fmt.Errorf(
				"entity %q references unknown dialogue %q",
				definition.ID,
				definition.DialogueID,
			)
		}
		preview.Dialogue = &resolved
	} else {
		preview.Dialogue = nil
	}
	questDependencyID := previewQuestDependencyID(definition, preview.Quest)
	if questDependencyID != "" &&
		!s.isAuthoredQuest(questDependencyID) {
		current := s.quests[questDependencyID]
		var resolved QuestDefinition
		present := current != nil
		if present {
			resolved = current.definition
		}
		if preview.Quest != nil {
			resolved, present = *preview.Quest, true
		}
		if !present {
			return EntityPreviewConfig{}, fmt.Errorf(
				"entity %q references unknown quest %q",
				definition.ID,
				questDependencyID,
			)
		}
		preview.Quest = &resolved
	} else {
		preview.Quest = nil
	}
	return preview, nil
}

func newEntityRuntime(definition EntityConfig) *entityRuntime {
	facing := normalize(definition.Facing)
	if facing == (Vec{}) {
		facing = Vec{X: UnitsPerPixel}
	}
	return &entityRuntime{
		config:   cloneEntityConfig(definition),
		position: definition.Position,
		facing:   facing,
		health:   definition.MaxHealth,
	}
}

func removeSortedID(ids []string, removed string) []string {
	index := sort.SearchStrings(ids, removed)
	if index >= len(ids) || ids[index] != removed {
		return ids
	}
	copy(ids[index:], ids[index+1:])
	return ids[:len(ids)-1]
}

func cloneStringSet(source map[string]struct{}) map[string]struct{} {
	result := make(map[string]struct{}, len(source))
	for id := range source {
		result[id] = struct{}{}
	}
	return result
}

func cloneEntityPreviewConfig(source EntityPreviewConfig) EntityPreviewConfig {
	result := source
	result.Entity = cloneEntityConfig(source.Entity)
	if source.Dialogue != nil {
		definition := *source.Dialogue
		result.Dialogue = &definition
	}
	if source.Quest != nil {
		definition := *source.Quest
		result.Quest = &definition
	}
	return result
}

func clonePreviewDefinitions(
	source map[string]EntityPreviewConfig,
) map[string]EntityPreviewConfig {
	result := make(map[string]EntityPreviewConfig, len(source))
	for id, definition := range source {
		result[id] = cloneEntityPreviewConfig(definition)
	}
	return result
}

func (s *Simulation) isAuthoredDialogue(id string) bool {
	for _, definition := range s.config.Dialogues {
		if definition.ID == id {
			return true
		}
	}
	return false
}

func (s *Simulation) isAuthoredQuest(id string) bool {
	for _, definition := range s.config.Quests {
		if definition.ID == id {
			return true
		}
	}
	return false
}

func (s *Simulation) hasEntityIdentity(id string) bool {
	if s.entities[id] != nil {
		return true
	}
	_, authored := s.authoredIDs[id]
	return authored
}

func (s *Simulation) rebuildPreviewDependencies() {
	dialogues := make(map[string]DialogueDefinition, len(s.config.Dialogues))
	for _, definition := range s.config.Dialogues {
		dialogues[definition.ID] = definition
	}
	questDefinitions := make(map[string]QuestDefinition, len(s.config.Quests))
	for _, definition := range s.config.Quests {
		questDefinitions[definition.ID] = definition
	}
	for id, definition := range s.directQuestDefs {
		questDefinitions[id] = definition
	}
	interactionRange := s.config.InteractionRange
	for _, id := range sortedPreviewIDs(s.previewDefs) {
		preview := s.previewDefs[id]
		if preview.Dialogue != nil {
			dialogues[preview.Dialogue.ID] = *preview.Dialogue
		}
		if preview.Quest != nil {
			questDefinitions[preview.Quest.ID] = *preview.Quest
		}
		interactionRange = maxCoord(
			interactionRange,
			preview.InteractionRange,
		)
	}
	quests := make(map[string]*questRuntime, len(questDefinitions))
	questOrder := make([]string, 0, len(questDefinitions))
	for id, definition := range questDefinitions {
		if existing := s.quests[id]; existing != nil {
			copied := *existing
			copied.definition = definition
			quests[id] = &copied
		} else {
			status := QuestInactive
			if definition.InitiallyActive {
				status = QuestActive
			}
			quests[id] = &questRuntime{
				definition: definition,
				status:     status,
			}
		}
		questOrder = append(questOrder, id)
	}
	sort.Strings(questOrder)
	s.dialogues = dialogues
	s.quests = quests
	s.questOrder = questOrder
	s.interactionRange = interactionRange
}

func sortedPreviewIDs(definitions map[string]EntityPreviewConfig) []string {
	ids := make([]string, 0, len(definitions))
	for id := range definitions {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

func validateQuestDefinition(definition QuestDefinition) error {
	if definition.ID == "" || definition.Required <= 0 {
		return fmt.Errorf(
			"quest %q requires an ID and positive target count",
			definition.ID,
		)
	}
	return nil
}

func validatePreviewQuestAnchor(
	entity EntityConfig,
	questID string,
) error {
	switch {
	case entity.StartQuestID == questID:
		return nil
	case entity.StartQuestID != "":
		return fmt.Errorf(
			"entity %q starts quest %q, not supplied quest %q",
			entity.ID,
			entity.StartQuestID,
			questID,
		)
	case entity.DialogueID != "":
		// The quest is registered for a dialogue choice/action and is not
		// started merely by opening the dialogue.
		return nil
	default:
		return fmt.Errorf(
			"entity %q has an unanchored quest bundle %q",
			entity.ID,
			questID,
		)
	}
}

func previewQuestDependencyID(
	entity EntityConfig,
	quest *QuestDefinition,
) string {
	if entity.StartQuestID != "" {
		return entity.StartQuestID
	}
	if entity.DialogueID != "" && quest != nil {
		return quest.ID
	}
	return ""
}

func cloneQuestDefinitions(
	source map[string]QuestDefinition,
) map[string]QuestDefinition {
	result := make(map[string]QuestDefinition, len(source))
	for id, definition := range source {
		result[id] = definition
	}
	return result
}
