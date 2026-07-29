// Package campaign owns durable, stage-independent game progress.
//
// It deliberately contains no renderer or per-stage simulation state. A
// runtime can rebuild the current stage from content, then combine it with a
// Campaign snapshot containing only long-lived progress.
package campaign

import (
	"errors"
	"fmt"
	"sort"
	"sync"
)

const (
	// CurrentConfigVersion is the supported campaign definition schema.
	CurrentConfigVersion = 1
	// CurrentStateVersion is the supported durable campaign state schema.
	CurrentStateVersion = 1

	// MaxJSONInteger is the largest integer represented exactly by common JSON
	// consumers, including JavaScript-based Maker tooling.
	MaxJSONInteger int64 = 1<<53 - 1
)

// Mode is transient presentation flow. It controls the currently visible UI
// but is never part of the player-save contract.
type Mode string

const (
	ModeTitle    Mode = "title"
	ModePlaying  Mode = "playing"
	ModePaused   Mode = "paused"
	ModeGameOver Mode = "gameover"
	ModeEnding   Mode = "ending"
)

// FlowProgress is the durable game-flow state. Completed implies Started.
// A loaded campaign derives its transient Mode from these two values.
type FlowProgress struct {
	Started   bool `json:"started"`
	Completed bool `json:"completed"`
}

// StageDefinition lists the valid entry points for one authored stage. It
// contains identity only; geometry and entities belong to the stage builder.
type StageDefinition struct {
	ID          string   `json:"id"`
	EntrySpawns []string `json:"entry_spawns"`
}

// ItemDefinition describes the durable constraints needed by inventory and
// equipment. An empty EquipmentSlot makes the item non-equippable.
type ItemDefinition struct {
	ID            string `json:"id"`
	MaxQuantity   int64  `json:"max_quantity"`
	EquipmentSlot string `json:"equipment_slot,omitempty"`
}

// ObjectiveDefinition describes one independently counted quest objective.
type ObjectiveDefinition struct {
	ID       string `json:"id"`
	Required int64  `json:"required"`
}

// QuestDefinition describes the durable topology of a quest.
type QuestDefinition struct {
	ID              string                `json:"id"`
	InitiallyActive bool                  `json:"initially_active,omitempty"`
	Objectives      []ObjectiveDefinition `json:"objectives"`
}

// Config is the versioned, immutable definition used to validate a State.
// ProjectID identifies the game, while ContentID identifies the exact
// compatible content revision.
type Config struct {
	Version int `json:"version"`

	ProjectID string `json:"project_id"`
	ContentID string `json:"content_id"`

	DefaultLocale string   `json:"default_locale"`
	Locales       []string `json:"locales"`

	InitialStageID      string            `json:"initial_stage_id"`
	InitialEntrySpawnID string            `json:"initial_entry_spawn_id"`
	Stages              []StageDefinition `json:"stages"`

	Flags          []string          `json:"flags"`
	Items          []ItemDefinition  `json:"items"`
	EquipmentSlots []string          `json:"equipment_slots"`
	Quests         []QuestDefinition `json:"quests"`
}

// FlagState stores an explicitly declared boolean flag.
type FlagState struct {
	ID    string `json:"id"`
	Value bool   `json:"value"`
}

// InventoryEntry stores the owned quantity of one configured item.
type InventoryEntry struct {
	ItemID   string `json:"item_id"`
	Quantity int64  `json:"quantity"`
}

// EquipmentEntry stores one configured slot. An empty ItemID means unequipped.
type EquipmentEntry struct {
	SlotID string `json:"slot_id"`
	ItemID string `json:"item_id,omitempty"`
}

// ObjectiveState stores progress for one configured quest objective.
type ObjectiveState struct {
	ID    string `json:"id"`
	Count int64  `json:"count"`
}

// QuestStatus is the durable lifecycle of a quest.
type QuestStatus string

const (
	QuestInactive  QuestStatus = "inactive"
	QuestActive    QuestStatus = "active"
	QuestCompleted QuestStatus = "completed"
)

// QuestState stores all objective counters for one configured quest.
type QuestState struct {
	ID         string           `json:"id"`
	Status     QuestStatus      `json:"status"`
	Objectives []ObjectiveState `json:"objectives"`
}

// State is a detached runtime snapshot. Flow and all RPG fields are durable;
// Mode is transient presentation state. It intentionally excludes entity
// position, health, combat, camera, and all other per-stage simulation state.
type State struct {
	Version int `json:"version"`

	ProjectID string `json:"project_id"`
	ContentID string `json:"content_id"`

	Flow           FlowProgress `json:"flow"`
	Mode           Mode         `json:"mode"`
	CurrentStageID string       `json:"current_stage_id,omitempty"`
	EntrySpawnID   string       `json:"entry_spawn_id,omitempty"`
	Locale         string       `json:"locale"`

	Flags     []FlagState      `json:"flags"`
	Inventory []InventoryEntry `json:"inventory"`
	Equipment []EquipmentEntry `json:"equipment"`
	Currency  int64            `json:"currency"`
	Quests    []QuestState     `json:"quests"`
}

// Campaign serializes access to one validated Config and State pair.
type Campaign struct {
	mu     sync.RWMutex
	config Config
	state  State
}

// NewTitle creates a pristine campaign at the title screen.
func NewTitle(config Config) (*Campaign, error) {
	prepared, err := prepareConfig(config)
	if err != nil {
		return nil, fmt.Errorf("create title campaign: %w", err)
	}
	return &Campaign{
		config: prepared,
		state: newState(
			prepared,
			FlowProgress{},
			ModeTitle,
		),
	}, nil
}

// NewGame creates a pristine campaign at the configured initial stage and
// activates quests marked InitiallyActive.
func NewGame(config Config) (*Campaign, error) {
	prepared, err := prepareConfig(config)
	if err != nil {
		return nil, fmt.Errorf("create new campaign: %w", err)
	}
	return &Campaign{
		config: prepared,
		state: newState(
			prepared,
			FlowProgress{Started: true},
			ModePlaying,
		),
	}, nil
}

// Restore validates a detached save completely before accepting it.
func Restore(config Config, state State) (*Campaign, error) {
	prepared, err := prepareConfig(config)
	if err != nil {
		return nil, fmt.Errorf("restore campaign: %w", err)
	}
	if err := validateState(state, prepared); err != nil {
		return nil, fmt.Errorf("restore campaign: %w", err)
	}
	return &Campaign{
		config: prepared,
		state:  normalizeState(state.Clone()),
	}, nil
}

// Config returns a fully detached copy of the canonical configuration.
func (campaign *Campaign) Config() Config {
	if campaign == nil {
		return Config{}
	}
	campaign.mu.RLock()
	defer campaign.mu.RUnlock()
	return campaign.config.Clone()
}

// Snapshot returns a fully detached copy of the current state.
func (campaign *Campaign) Snapshot() State {
	if campaign == nil {
		return State{}
	}
	campaign.mu.RLock()
	defer campaign.mu.RUnlock()
	return campaign.state.Clone()
}

// Transaction runs a mutation against a detached candidate and commits only
// when the callback succeeds and the complete result validates. Callback
// errors and invalid candidates leave the campaign unchanged.
func (campaign *Campaign) Transaction(
	mutate func(*State) error,
) error {
	if campaign == nil {
		return errors.New("campaign transaction: campaign is nil")
	}
	if mutate == nil {
		return errors.New("campaign transaction: mutation is nil")
	}

	campaign.mu.Lock()
	defer campaign.mu.Unlock()

	candidate := campaign.state.Clone()
	if err := mutate(&candidate); err != nil {
		return fmt.Errorf("campaign transaction: %w", err)
	}
	if err := validateState(candidate, campaign.config); err != nil {
		return fmt.Errorf("campaign transaction: %w", err)
	}

	// Clone on commit so a callback that retained its argument cannot mutate
	// the committed state after Transaction returns.
	campaign.state = normalizeState(candidate.Clone())
	return nil
}

// Clone returns a detached copy, including all nested definition slices.
func (config Config) Clone() Config {
	cloned := config
	cloned.Locales = cloneSlice(config.Locales)
	cloned.Flags = cloneSlice(config.Flags)
	cloned.EquipmentSlots = cloneSlice(config.EquipmentSlots)
	cloned.Items = cloneSlice(config.Items)
	cloned.Stages = make([]StageDefinition, len(config.Stages))
	for index, stage := range config.Stages {
		cloned.Stages[index] = stage
		cloned.Stages[index].EntrySpawns = cloneSlice(stage.EntrySpawns)
	}
	cloned.Quests = make([]QuestDefinition, len(config.Quests))
	for index, quest := range config.Quests {
		cloned.Quests[index] = quest
		cloned.Quests[index].Objectives = cloneSlice(quest.Objectives)
	}
	return cloned
}

// Clone returns a detached copy, including all nested quest counters.
func (state State) Clone() State {
	cloned := state
	cloned.Flags = cloneSlice(state.Flags)
	cloned.Inventory = cloneSlice(state.Inventory)
	cloned.Equipment = cloneSlice(state.Equipment)
	cloned.Quests = make([]QuestState, len(state.Quests))
	for index, quest := range state.Quests {
		cloned.Quests[index] = quest
		cloned.Quests[index].Objectives = cloneSlice(quest.Objectives)
	}
	return cloned
}

func cloneSlice[T any](values []T) []T {
	if values == nil {
		return nil
	}
	cloned := make([]T, len(values))
	copy(cloned, values)
	return cloned
}

func prepareConfig(config Config) (Config, error) {
	if err := config.Validate(); err != nil {
		return Config{}, err
	}
	prepared := config.Clone()
	sort.Strings(prepared.Locales)
	sort.Strings(prepared.Flags)
	sort.Strings(prepared.EquipmentSlots)
	sort.Slice(prepared.Stages, func(left, right int) bool {
		return prepared.Stages[left].ID < prepared.Stages[right].ID
	})
	for index := range prepared.Stages {
		sort.Strings(prepared.Stages[index].EntrySpawns)
	}
	sort.Slice(prepared.Items, func(left, right int) bool {
		return prepared.Items[left].ID < prepared.Items[right].ID
	})
	sort.Slice(prepared.Quests, func(left, right int) bool {
		return prepared.Quests[left].ID < prepared.Quests[right].ID
	})
	for index := range prepared.Quests {
		sort.Slice(
			prepared.Quests[index].Objectives,
			func(left, right int) bool {
				return prepared.Quests[index].Objectives[left].ID <
					prepared.Quests[index].Objectives[right].ID
			},
		)
	}
	return normalizeConfig(prepared), nil
}

func newState(
	config Config,
	flow FlowProgress,
	mode Mode,
) State {
	state := State{
		Version:   CurrentStateVersion,
		ProjectID: config.ProjectID,
		ContentID: config.ContentID,
		Flow:      flow,
		Mode:      mode,
		Locale:    config.DefaultLocale,
		Flags:     make([]FlagState, len(config.Flags)),
		Inventory: make([]InventoryEntry, len(config.Items)),
		Equipment: make([]EquipmentEntry, len(config.EquipmentSlots)),
		Quests:    make([]QuestState, len(config.Quests)),
	}
	if flow.Started {
		state.CurrentStageID = config.InitialStageID
		state.EntrySpawnID = config.InitialEntrySpawnID
	}
	for index, id := range config.Flags {
		state.Flags[index].ID = id
	}
	for index, item := range config.Items {
		state.Inventory[index].ItemID = item.ID
	}
	for index, slot := range config.EquipmentSlots {
		state.Equipment[index].SlotID = slot
	}
	for questIndex, definition := range config.Quests {
		status := QuestInactive
		if flow.Started && definition.InitiallyActive {
			status = QuestActive
		}
		state.Quests[questIndex] = QuestState{
			ID:     definition.ID,
			Status: status,
			Objectives: make(
				[]ObjectiveState,
				len(definition.Objectives),
			),
		}
		for objectiveIndex, objective := range definition.Objectives {
			state.Quests[questIndex].
				Objectives[objectiveIndex].
				ID = objective.ID
		}
	}
	return state
}

func normalizeConfig(config Config) Config {
	if config.Locales == nil {
		config.Locales = []string{}
	}
	if config.Stages == nil {
		config.Stages = []StageDefinition{}
	}
	for index := range config.Stages {
		if config.Stages[index].EntrySpawns == nil {
			config.Stages[index].EntrySpawns = []string{}
		}
	}
	if config.Flags == nil {
		config.Flags = []string{}
	}
	if config.Items == nil {
		config.Items = []ItemDefinition{}
	}
	if config.EquipmentSlots == nil {
		config.EquipmentSlots = []string{}
	}
	if config.Quests == nil {
		config.Quests = []QuestDefinition{}
	}
	for index := range config.Quests {
		if config.Quests[index].Objectives == nil {
			config.Quests[index].Objectives = []ObjectiveDefinition{}
		}
	}
	return config
}

func normalizeState(state State) State {
	if state.Flags == nil {
		state.Flags = []FlagState{}
	}
	if state.Inventory == nil {
		state.Inventory = []InventoryEntry{}
	}
	if state.Equipment == nil {
		state.Equipment = []EquipmentEntry{}
	}
	if state.Quests == nil {
		state.Quests = []QuestState{}
	}
	for index := range state.Quests {
		if state.Quests[index].Objectives == nil {
			state.Quests[index].Objectives = []ObjectiveState{}
		}
	}
	return state
}
