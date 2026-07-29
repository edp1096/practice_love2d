package campaign

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

const (
	// CurrentSaveSchemaVersion is the supported player-save envelope.
	CurrentSaveSchemaVersion = 1
	// Section versions stay independent so one payload can evolve without
	// forcing unrelated migrations.
	CurrentGameFlowSectionVersion  = 1
	CurrentFlagsSectionVersion     = 1
	CurrentInventorySectionVersion = 1
	CurrentEquipmentSectionVersion = 1
	CurrentQuestsSectionVersion    = 1
	CurrentEconomySectionVersion   = 1
	CurrentLocaleSectionVersion    = 1
)

// SaveEnvelope is the complete versioned player-save contract. Its structs
// and canonical slices deliberately avoid maps, making JSON output stable.
type SaveEnvelope struct {
	Schema   int          `json:"schema"`
	Project  string       `json:"project"`
	Content  string       `json:"content"`
	Location SaveLocation `json:"location"`
	Sections SaveSections `json:"sections"`
}

// SaveLocation identifies an authored stage entry. It never stores an entity
// transform or any other per-stage simulation state.
type SaveLocation struct {
	Stage string `json:"stage"`
	Spawn string `json:"spawn"`
}

// SaveSection versions one independently migratable feature payload.
type SaveSection[T any] struct {
	Version int `json:"version"`
	Data    T   `json:"data"`
}

// SaveSections is intentionally a struct rather than a map. Besides producing
// deterministic output, it makes missing and unknown namespaces fail closed.
type SaveSections struct {
	GameFlow  SaveSection[FlowProgress]         `json:"game.flow"`
	Flags     SaveSection[FlagsSectionData]     `json:"rpg.flags"`
	Inventory SaveSection[InventorySectionData] `json:"rpg.inventory"`
	Equipment SaveSection[EquipmentSectionData] `json:"rpg.equipment"`
	Quests    SaveSection[QuestsSectionData]    `json:"rpg.quests"`
	Economy   SaveSection[EconomySectionData]   `json:"rpg.economy"`
	Locale    SaveSection[LocaleSectionData]    `json:"rpg.locale"`
}

// FlagsSectionData owns durable configured flag values.
type FlagsSectionData struct {
	Values []FlagState `json:"values"`
}

// InventorySectionData owns durable configured item quantities.
type InventorySectionData struct {
	Entries []InventoryEntry `json:"entries"`
}

// EquipmentSectionData owns the player's durable loadout.
type EquipmentSectionData struct {
	Entries []EquipmentEntry `json:"entries"`
}

// QuestsSectionData owns durable quest lifecycle and objective counters.
type QuestsSectionData struct {
	Quests []QuestState `json:"quests"`
}

// EconomySectionData owns durable player currency.
type EconomySectionData struct {
	Balance int64 `json:"balance"`
}

// LocaleSectionData owns the selected locale.
type LocaleSectionData struct {
	Selected string `json:"selected"`
}

// Export returns a detached player-save envelope. Transient Mode and all
// stage simulation state are intentionally absent.
func (campaign *Campaign) Export() (SaveEnvelope, error) {
	if campaign == nil {
		return SaveEnvelope{}, errors.New(
			"export campaign save: campaign is nil",
		)
	}

	campaign.mu.RLock()
	defer campaign.mu.RUnlock()

	state := campaign.state.Clone()
	if err := validateState(state, campaign.config); err != nil {
		return SaveEnvelope{}, fmt.Errorf(
			"export campaign save: %w",
			err,
		)
	}
	return envelopeFromState(state), nil
}

// Marshal encodes the canonical player-save envelope as deterministic JSON.
func (campaign *Campaign) Marshal() ([]byte, error) {
	envelope, err := campaign.Export()
	if err != nil {
		return nil, err
	}
	data, err := json.Marshal(envelope)
	if err != nil {
		return nil, fmt.Errorf("marshal campaign save: %w", err)
	}
	return data, nil
}

// Decode strictly decodes and validates a player save, returning a detached
// restore candidate. The caller's live Campaign is never mutated.
func Decode(config Config, data []byte) (*Campaign, error) {
	prepared, err := prepareConfig(config)
	if err != nil {
		return nil, fmt.Errorf("decode campaign save config: %w", err)
	}

	wire, err := decodeWireEnvelope(data)
	if err != nil {
		return nil, fmt.Errorf("decode campaign save: %w", err)
	}
	envelope, err := wire.toEnvelope()
	if err != nil {
		return nil, fmt.Errorf("decode campaign save: %w", err)
	}
	state, err := stateFromEnvelope(envelope, prepared)
	if err != nil {
		return nil, fmt.Errorf("decode campaign save: %w", err)
	}
	candidate, err := Restore(prepared, state)
	if err != nil {
		return nil, fmt.Errorf("decode campaign save: %w", err)
	}
	return candidate, nil
}

// Decode strictly decodes against the live campaign's immutable Config and
// returns a separate candidate. A failure cannot alter the receiver.
func (campaign *Campaign) Decode(data []byte) (*Campaign, error) {
	if campaign == nil {
		return nil, errors.New("decode campaign save: campaign is nil")
	}
	return Decode(campaign.Config(), data)
}

func envelopeFromState(state State) SaveEnvelope {
	return SaveEnvelope{
		Schema:  CurrentSaveSchemaVersion,
		Project: state.ProjectID,
		Content: state.ContentID,
		Location: SaveLocation{
			Stage: state.CurrentStageID,
			Spawn: state.EntrySpawnID,
		},
		Sections: SaveSections{
			GameFlow: SaveSection[FlowProgress]{
				Version: CurrentGameFlowSectionVersion,
				Data:    state.Flow,
			},
			Flags: SaveSection[FlagsSectionData]{
				Version: CurrentFlagsSectionVersion,
				Data: FlagsSectionData{
					Values: cloneSlice(state.Flags),
				},
			},
			Inventory: SaveSection[InventorySectionData]{
				Version: CurrentInventorySectionVersion,
				Data: InventorySectionData{
					Entries: cloneSlice(state.Inventory),
				},
			},
			Equipment: SaveSection[EquipmentSectionData]{
				Version: CurrentEquipmentSectionVersion,
				Data: EquipmentSectionData{
					Entries: cloneSlice(state.Equipment),
				},
			},
			Quests: SaveSection[QuestsSectionData]{
				Version: CurrentQuestsSectionVersion,
				Data: QuestsSectionData{
					Quests: cloneQuests(state.Quests),
				},
			},
			Economy: SaveSection[EconomySectionData]{
				Version: CurrentEconomySectionVersion,
				Data: EconomySectionData{
					Balance: state.Currency,
				},
			},
			Locale: SaveSection[LocaleSectionData]{
				Version: CurrentLocaleSectionVersion,
				Data: LocaleSectionData{
					Selected: state.Locale,
				},
			},
		},
	}
}

func stateFromEnvelope(
	envelope SaveEnvelope,
	config Config,
) (State, error) {
	if envelope.Schema != CurrentSaveSchemaVersion {
		return State{}, fmt.Errorf(
			"save schema version %d is unsupported",
			envelope.Schema,
		)
	}
	if envelope.Project != config.ProjectID {
		return State{}, fmt.Errorf(
			"save project %q does not match %q",
			envelope.Project,
			config.ProjectID,
		)
	}
	if envelope.Content != config.ContentID {
		return State{}, fmt.Errorf(
			"save content %q does not match %q",
			envelope.Content,
			config.ContentID,
		)
	}
	if err := validateSectionVersions(envelope.Sections); err != nil {
		return State{}, err
	}

	flow := envelope.Sections.GameFlow.Data
	state := State{
		Version:        CurrentStateVersion,
		ProjectID:      envelope.Project,
		ContentID:      envelope.Content,
		Flow:           flow,
		Mode:           modeFromFlow(flow),
		CurrentStageID: envelope.Location.Stage,
		EntrySpawnID:   envelope.Location.Spawn,
		Locale:         envelope.Sections.Locale.Data.Selected,
		Flags: cloneSlice(
			envelope.Sections.Flags.Data.Values,
		),
		Inventory: cloneSlice(
			envelope.Sections.Inventory.Data.Entries,
		),
		Equipment: cloneSlice(
			envelope.Sections.Equipment.Data.Entries,
		),
		Currency: envelope.Sections.Economy.Data.Balance,
		Quests: cloneQuests(
			envelope.Sections.Quests.Data.Quests,
		),
	}
	if err := validateState(state, config); err != nil {
		return State{}, err
	}
	return normalizeState(state), nil
}

func validateSectionVersions(sections SaveSections) error {
	versions := []struct {
		name string
		got  int
		want int
	}{
		{"game.flow", sections.GameFlow.Version,
			CurrentGameFlowSectionVersion},
		{"rpg.flags", sections.Flags.Version,
			CurrentFlagsSectionVersion},
		{"rpg.inventory", sections.Inventory.Version,
			CurrentInventorySectionVersion},
		{"rpg.equipment", sections.Equipment.Version,
			CurrentEquipmentSectionVersion},
		{"rpg.quests", sections.Quests.Version,
			CurrentQuestsSectionVersion},
		{"rpg.economy", sections.Economy.Version,
			CurrentEconomySectionVersion},
		{"rpg.locale", sections.Locale.Version,
			CurrentLocaleSectionVersion},
	}
	for _, version := range versions {
		if version.got != version.want {
			return fmt.Errorf(
				"save section %q version %d is unsupported",
				version.name,
				version.got,
			)
		}
	}
	return nil
}

func modeFromFlow(flow FlowProgress) Mode {
	if flow.Completed {
		return ModeEnding
	}
	if flow.Started {
		return ModePlaying
	}
	return ModeTitle
}

func cloneQuests(quests []QuestState) []QuestState {
	cloned := make([]QuestState, len(quests))
	for index, quest := range quests {
		cloned[index] = quest
		cloned[index].Objectives = cloneSlice(quest.Objectives)
	}
	return cloned
}

// The wire types use pointers for every required field. This prevents a valid
// zero value from making an omitted field indistinguishable from explicit
// data while keeping the public envelope convenient to construct and inspect.
type wireEnvelope struct {
	Schema   *int          `json:"schema"`
	Project  *string       `json:"project"`
	Content  *string       `json:"content"`
	Location *wireLocation `json:"location"`
	Sections *wireSections `json:"sections"`
}

type wireLocation struct {
	Stage *string `json:"stage"`
	Spawn *string `json:"spawn"`
}

type wireSection[T any] struct {
	Version *int `json:"version"`
	Data    *T   `json:"data"`
}

type wireSections struct {
	GameFlow  wireSection[wireFlowData]      `json:"game.flow"`
	Flags     wireSection[wireFlagsData]     `json:"rpg.flags"`
	Inventory wireSection[wireInventoryData] `json:"rpg.inventory"`
	Equipment wireSection[wireEquipmentData] `json:"rpg.equipment"`
	Quests    wireSection[wireQuestsData]    `json:"rpg.quests"`
	Economy   wireSection[wireEconomyData]   `json:"rpg.economy"`
	Locale    wireSection[wireLocaleData]    `json:"rpg.locale"`
}

type wireFlowData struct {
	Started   *bool `json:"started"`
	Completed *bool `json:"completed"`
}

type wireFlagsData struct {
	Values *[]FlagState `json:"values"`
}

type wireInventoryData struct {
	Entries *[]InventoryEntry `json:"entries"`
}

type wireEquipmentData struct {
	Entries *[]EquipmentEntry `json:"entries"`
}

type wireQuestsData struct {
	Quests *[]QuestState `json:"quests"`
}

type wireEconomyData struct {
	Balance *int64 `json:"balance"`
}

type wireLocaleData struct {
	Selected *string `json:"selected"`
}

func decodeWireEnvelope(data []byte) (wireEnvelope, error) {
	if len(bytes.TrimSpace(data)) == 0 {
		return wireEnvelope{}, errors.New("save JSON is empty")
	}
	if err := rejectDuplicateObjectKeys(data); err != nil {
		return wireEnvelope{}, err
	}

	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var wire wireEnvelope
	if err := decoder.Decode(&wire); err != nil {
		return wireEnvelope{}, err
	}
	if err := requireJSONEOF(decoder); err != nil {
		return wireEnvelope{}, err
	}
	return wire, nil
}

func (wire wireEnvelope) toEnvelope() (SaveEnvelope, error) {
	if wire.Schema == nil ||
		wire.Project == nil ||
		wire.Content == nil ||
		wire.Location == nil ||
		wire.Sections == nil {
		return SaveEnvelope{}, errors.New(
			"save requires schema, project, content, location, and sections",
		)
	}
	if wire.Location.Stage == nil || wire.Location.Spawn == nil {
		return SaveEnvelope{}, errors.New(
			"save location requires stage and spawn",
		)
	}

	gameFlowVersion, gameFlow, err :=
		wire.Sections.GameFlow.value("game.flow")
	if err != nil {
		return SaveEnvelope{}, err
	}
	flagsVersion, flags, err :=
		wire.Sections.Flags.value("rpg.flags")
	if err != nil {
		return SaveEnvelope{}, err
	}
	inventoryVersion, inventory, err :=
		wire.Sections.Inventory.value("rpg.inventory")
	if err != nil {
		return SaveEnvelope{}, err
	}
	equipmentVersion, equipment, err :=
		wire.Sections.Equipment.value("rpg.equipment")
	if err != nil {
		return SaveEnvelope{}, err
	}
	questsVersion, quests, err :=
		wire.Sections.Quests.value("rpg.quests")
	if err != nil {
		return SaveEnvelope{}, err
	}
	economyVersion, economy, err :=
		wire.Sections.Economy.value("rpg.economy")
	if err != nil {
		return SaveEnvelope{}, err
	}
	localeVersion, locale, err :=
		wire.Sections.Locale.value("rpg.locale")
	if err != nil {
		return SaveEnvelope{}, err
	}
	if gameFlow.Started == nil || gameFlow.Completed == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"game.flow\" requires started and completed",
		)
	}
	if flags.Values == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"rpg.flags\" requires values",
		)
	}
	if inventory.Entries == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"rpg.inventory\" requires entries",
		)
	}
	if equipment.Entries == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"rpg.equipment\" requires entries",
		)
	}
	if quests.Quests == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"rpg.quests\" requires quests",
		)
	}
	if economy.Balance == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"rpg.economy\" requires balance",
		)
	}
	if locale.Selected == nil {
		return SaveEnvelope{}, errors.New(
			"save section \"rpg.locale\" requires selected",
		)
	}

	return SaveEnvelope{
		Schema:  *wire.Schema,
		Project: *wire.Project,
		Content: *wire.Content,
		Location: SaveLocation{
			Stage: *wire.Location.Stage,
			Spawn: *wire.Location.Spawn,
		},
		Sections: SaveSections{
			GameFlow: SaveSection[FlowProgress]{
				Version: gameFlowVersion,
				Data: FlowProgress{
					Started:   *gameFlow.Started,
					Completed: *gameFlow.Completed,
				},
			},
			Flags: SaveSection[FlagsSectionData]{
				Version: flagsVersion,
				Data: FlagsSectionData{
					Values: cloneSlice(*flags.Values),
				},
			},
			Inventory: SaveSection[InventorySectionData]{
				Version: inventoryVersion,
				Data: InventorySectionData{
					Entries: cloneSlice(*inventory.Entries),
				},
			},
			Equipment: SaveSection[EquipmentSectionData]{
				Version: equipmentVersion,
				Data: EquipmentSectionData{
					Entries: cloneSlice(*equipment.Entries),
				},
			},
			Quests: SaveSection[QuestsSectionData]{
				Version: questsVersion,
				Data: QuestsSectionData{
					Quests: cloneQuests(*quests.Quests),
				},
			},
			Economy: SaveSection[EconomySectionData]{
				Version: economyVersion,
				Data: EconomySectionData{
					Balance: *economy.Balance,
				},
			},
			Locale: SaveSection[LocaleSectionData]{
				Version: localeVersion,
				Data: LocaleSectionData{
					Selected: *locale.Selected,
				},
			},
		},
	}, nil
}

func (section wireSection[T]) value(
	name string,
) (int, T, error) {
	if section.Version == nil || section.Data == nil {
		var zero T
		return 0, zero, fmt.Errorf(
			"save section %q requires version and data",
			name,
		)
	}
	return *section.Version, *section.Data, nil
}

func requireJSONEOF(decoder *json.Decoder) error {
	var extra any
	err := decoder.Decode(&extra)
	switch {
	case errors.Is(err, io.EOF):
		return nil
	case err == nil:
		return errors.New("save JSON contains trailing data")
	default:
		return fmt.Errorf("save JSON contains trailing data: %w", err)
	}
}

func rejectDuplicateObjectKeys(data []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := walkJSONValue(decoder, "$"); err != nil {
		return err
	}
	if err := requireJSONEOF(decoder); err != nil {
		return err
	}
	return nil
}

func walkJSONValue(decoder *json.Decoder, path string) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, isDelimiter := token.(json.Delim)
	if !isDelimiter {
		return nil
	}
	switch delimiter {
	case '{':
		seen := make(map[string]struct{})
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok {
				return fmt.Errorf("%s has a non-string object key", path)
			}
			if _, exists := seen[key]; exists {
				return fmt.Errorf(
					"%s contains duplicate field %q",
					path,
					key,
				)
			}
			seen[key] = struct{}{}
			if err := walkJSONValue(
				decoder,
				path+"."+key,
			); err != nil {
				return err
			}
		}
		end, err := decoder.Token()
		if err != nil {
			return err
		}
		if end != json.Delim('}') {
			return fmt.Errorf("%s object is not closed", path)
		}
	case '[':
		index := 0
		for decoder.More() {
			if err := walkJSONValue(
				decoder,
				fmt.Sprintf("%s[%d]", path, index),
			); err != nil {
				return err
			}
			index++
		}
		end, err := decoder.Token()
		if err != nil {
			return err
		}
		if end != json.Delim(']') {
			return fmt.Errorf("%s array is not closed", path)
		}
	default:
		return fmt.Errorf("%s starts with unexpected delimiter %q", path, delimiter)
	}
	return nil
}
