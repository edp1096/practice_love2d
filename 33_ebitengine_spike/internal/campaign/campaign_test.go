package campaign

import (
	"bytes"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"
)

func TestNewTitleAndNewGameCreateCanonicalStates(t *testing.T) {
	config := testConfig()

	title, err := NewTitle(config)
	if err != nil {
		t.Fatalf("NewTitle() error = %v", err)
	}
	titleState := title.Snapshot()
	if titleState.Mode != ModeTitle {
		t.Fatalf("title mode = %q, want %q", titleState.Mode, ModeTitle)
	}
	if titleState.Flow.Started || titleState.Flow.Completed {
		t.Fatalf("title flow = %#v, want pristine", titleState.Flow)
	}
	if titleState.CurrentStageID != "" || titleState.EntrySpawnID != "" {
		t.Fatalf(
			"title location = %q/%q, want empty",
			titleState.CurrentStageID,
			titleState.EntrySpawnID,
		)
	}
	if err := titleState.Validate(config); err != nil {
		t.Fatalf("title State.Validate() error = %v", err)
	}
	for _, quest := range titleState.Quests {
		if quest.Status != QuestInactive {
			t.Fatalf(
				"title quest %q status = %q, want inactive",
				quest.ID,
				quest.Status,
			)
		}
	}

	game, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	state := game.Snapshot()
	if state.Version != CurrentStateVersion {
		t.Fatalf(
			"state version = %d, want %d",
			state.Version,
			CurrentStateVersion,
		)
	}
	if state.ProjectID != config.ProjectID ||
		state.ContentID != config.ContentID {
		t.Fatalf(
			"state identity = %q/%q, want %q/%q",
			state.ProjectID,
			state.ContentID,
			config.ProjectID,
			config.ContentID,
		)
	}
	if state.Mode != ModePlaying {
		t.Fatalf("game mode = %q, want %q", state.Mode, ModePlaying)
	}
	if !state.Flow.Started || state.Flow.Completed {
		t.Fatalf("game flow = %#v, want started", state.Flow)
	}
	if state.CurrentStageID != config.InitialStageID ||
		state.EntrySpawnID != config.InitialEntrySpawnID {
		t.Fatalf(
			"game location = %q/%q, want %q/%q",
			state.CurrentStageID,
			state.EntrySpawnID,
			config.InitialStageID,
			config.InitialEntrySpawnID,
		)
	}
	if state.Locale != config.DefaultLocale {
		t.Fatalf(
			"locale = %q, want %q",
			state.Locale,
			config.DefaultLocale,
		)
	}
	assertIDsSorted(t, state)
	if questState(t, &state, "quest.intro").Status != QuestActive {
		t.Fatal("initially active quest was not activated")
	}
	if questState(t, &state, "quest.guardian").Status != QuestInactive {
		t.Fatal("ordinary quest did not start inactive")
	}
	if err := state.Validate(config); err != nil {
		t.Fatalf("game State.Validate() error = %v", err)
	}
}

func TestConfigAndStateJSONRoundTripIsDeterministic(t *testing.T) {
	config := testConfig()
	game, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	applyProgress(t, game)

	canonicalConfig := game.Config()
	configJSON, err := json.Marshal(canonicalConfig)
	if err != nil {
		t.Fatalf("json.Marshal(config) error = %v", err)
	}
	var decodedConfig Config
	if err := json.Unmarshal(configJSON, &decodedConfig); err != nil {
		t.Fatalf("json.Unmarshal(config) error = %v", err)
	}
	if err := decodedConfig.Validate(); err != nil {
		t.Fatalf("decoded Config.Validate() error = %v", err)
	}
	if !reflect.DeepEqual(decodedConfig, canonicalConfig) {
		t.Fatalf(
			"config JSON round trip changed value\n got: %#v\nwant: %#v",
			decodedConfig,
			canonicalConfig,
		)
	}

	before := game.Snapshot()
	firstJSON, err := json.Marshal(before)
	if err != nil {
		t.Fatalf("json.Marshal(state) error = %v", err)
	}
	if bytes.Contains(firstJSON, []byte(`null`)) {
		t.Fatalf("canonical state contains null collection: %s", firstJSON)
	}
	if bytes.Contains(firstJSON, []byte(`entities`)) {
		t.Fatalf("campaign state leaked per-stage entities: %s", firstJSON)
	}

	var decoded State
	if err := json.Unmarshal(firstJSON, &decoded); err != nil {
		t.Fatalf("json.Unmarshal(state) error = %v", err)
	}
	restored, err := Restore(decodedConfig, decoded)
	if err != nil {
		t.Fatalf("Restore() error = %v", err)
	}
	after := restored.Snapshot()
	if !reflect.DeepEqual(after, before) {
		t.Fatalf(
			"state JSON round trip changed value\n got: %#v\nwant: %#v",
			after,
			before,
		)
	}
	secondJSON, err := json.Marshal(after)
	if err != nil {
		t.Fatalf("json.Marshal(restored state) error = %v", err)
	}
	if !bytes.Equal(secondJSON, firstJSON) {
		t.Fatalf(
			"state JSON is nondeterministic\nfirst:  %s\nsecond: %s",
			firstJSON,
			secondJSON,
		)
	}

	reordered := testConfig()
	reverseStrings(reordered.Locales)
	reverseStrings(reordered.Flags)
	reverseStrings(reordered.EquipmentSlots)
	reverseStages(reordered.Stages)
	reverseItems(reordered.Items)
	reverseQuests(reordered.Quests)
	reorderedGame, err := NewGame(reordered)
	if err != nil {
		t.Fatalf("NewGame(reordered config) error = %v", err)
	}
	reorderedJSON, err := json.Marshal(reorderedGame.Snapshot())
	if err != nil {
		t.Fatalf("json.Marshal(reordered state) error = %v", err)
	}
	pristineGame, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame(pristine config) error = %v", err)
	}
	pristineJSON, err := json.Marshal(pristineGame.Snapshot())
	if err != nil {
		t.Fatalf("json.Marshal(pristine state) error = %v", err)
	}
	if !bytes.Equal(reorderedJSON, pristineJSON) {
		t.Fatalf(
			"equivalent config order changed state JSON\nfirst:  %s\nsecond: %s",
			pristineJSON,
			reorderedJSON,
		)
	}
}

func TestEmptyConfiguredCollectionsRemainCanonicalJSONArrays(t *testing.T) {
	config := Config{
		Version:             CurrentConfigVersion,
		ProjectID:           "test.project",
		ContentID:           "content:v1",
		DefaultLocale:       "en",
		Locales:             []string{"en"},
		InitialStageID:      "stage.start",
		InitialEntrySpawnID: "default",
		Stages: []StageDefinition{
			{ID: "stage.start", EntrySpawns: []string{"default"}},
		},
	}
	game, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	for label, value := range map[string]any{
		"config": game.Config(),
		"state":  game.Snapshot(),
	} {
		data, err := json.Marshal(value)
		if err != nil {
			t.Fatalf("json.Marshal(%s) error = %v", label, err)
		}
		if bytes.Contains(data, []byte(`null`)) {
			t.Fatalf("%s contains null collection: %s", label, data)
		}
	}
}

func TestSnapshotConfigAndCommittedTransactionAreDetached(t *testing.T) {
	game, err := NewGame(testConfig())
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}

	config := game.Config()
	config.Locales[0] = "changed"
	config.Stages[0].EntrySpawns[0] = "changed"
	config.Quests[0].Objectives[0].ID = "changed"
	freshConfig := game.Config()
	if freshConfig.Locales[0] == "changed" ||
		freshConfig.Stages[0].EntrySpawns[0] == "changed" ||
		freshConfig.Quests[0].Objectives[0].ID == "changed" {
		t.Fatal("Config() returned aliased nested data")
	}

	state := game.Snapshot()
	state.Flags[0].Value = true
	state.Quests[0].Objectives[0].Count = 1
	freshState := game.Snapshot()
	if freshState.Flags[0].Value ||
		freshState.Quests[0].Objectives[0].Count != 0 {
		t.Fatal("Snapshot() returned aliased nested data")
	}

	var retained *State
	if err := game.Transaction(func(candidate *State) error {
		candidate.Currency = 7
		retained = candidate
		return nil
	}); err != nil {
		t.Fatalf("Transaction() error = %v", err)
	}
	retained.Currency = 99
	retained.Flags[0].Value = true
	if got := game.Snapshot(); got.Currency != 7 || got.Flags[0].Value {
		t.Fatalf(
			"retained candidate mutated committed state: %#v",
			got,
		)
	}
}

func TestTransactionCommitsAtomicallyAndRollsBack(t *testing.T) {
	game, err := NewGame(testConfig())
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}

	applyProgress(t, game)
	committed := game.Snapshot()
	if committed.Mode != ModePaused ||
		committed.Currency != 75 ||
		inventoryEntry(t, &committed, "item.potion").Quantity != 2 ||
		equipmentEntry(t, &committed, "weapon").ItemID !=
			"item.training_sword" {
		t.Fatalf("valid transaction was not committed: %#v", committed)
	}

	sentinel := errors.New("stop")
	err = game.Transaction(func(candidate *State) error {
		candidate.Currency = 1
		candidate.Inventory[0].Quantity = 0
		return sentinel
	})
	if !errors.Is(err, sentinel) {
		t.Fatalf("callback error = %v, want wrapped sentinel", err)
	}
	if got := game.Snapshot(); !reflect.DeepEqual(got, committed) {
		t.Fatalf(
			"callback error did not roll back\n got: %#v\nwant: %#v",
			got,
			committed,
		)
	}

	err = game.Transaction(func(candidate *State) error {
		candidate.Currency = -1
		return nil
	})
	if err == nil || !strings.Contains(err.Error(), "currency") {
		t.Fatalf("invalid transaction error = %v, want currency error", err)
	}
	if got := game.Snapshot(); !reflect.DeepEqual(got, committed) {
		t.Fatalf(
			"validation error did not roll back\n got: %#v\nwant: %#v",
			got,
			committed,
		)
	}

	if err := game.Transaction(nil); err == nil {
		t.Fatal("Transaction(nil) succeeded")
	}
	var nilCampaign *Campaign
	if err := nilCampaign.Transaction(func(*State) error {
		return nil
	}); err == nil {
		t.Fatal("nil Campaign.Transaction() succeeded")
	}
}

func TestConfigValidateRejectsInvalidDefinitions(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*Config)
	}{
		{
			name: "version",
			mutate: func(config *Config) {
				config.Version++
			},
		},
		{
			name: "empty project id",
			mutate: func(config *Config) {
				config.ProjectID = ""
			},
		},
		{
			name: "empty content id",
			mutate: func(config *Config) {
				config.ContentID = ""
			},
		},
		{
			name: "no locales",
			mutate: func(config *Config) {
				config.Locales = nil
			},
		},
		{
			name: "duplicate locale",
			mutate: func(config *Config) {
				config.Locales = append(config.Locales, config.Locales[0])
			},
		},
		{
			name: "unknown default locale",
			mutate: func(config *Config) {
				config.DefaultLocale = "ja"
			},
		},
		{
			name: "no stages",
			mutate: func(config *Config) {
				config.Stages = nil
			},
		},
		{
			name: "duplicate stage",
			mutate: func(config *Config) {
				config.Stages = append(
					config.Stages,
					config.Stages[0],
				)
			},
		},
		{
			name: "stage without entry spawn",
			mutate: func(config *Config) {
				config.Stages[0].EntrySpawns = nil
			},
		},
		{
			name: "duplicate entry spawn",
			mutate: func(config *Config) {
				config.Stages[0].EntrySpawns = append(
					config.Stages[0].EntrySpawns,
					config.Stages[0].EntrySpawns[0],
				)
			},
		},
		{
			name: "unknown initial stage",
			mutate: func(config *Config) {
				config.InitialStageID = "stage.missing"
			},
		},
		{
			name: "unknown initial entry spawn",
			mutate: func(config *Config) {
				config.InitialEntrySpawnID = "missing"
			},
		},
		{
			name: "duplicate flag",
			mutate: func(config *Config) {
				config.Flags = append(config.Flags, config.Flags[0])
			},
		},
		{
			name: "empty flag id",
			mutate: func(config *Config) {
				config.Flags[0] = ""
			},
		},
		{
			name: "duplicate equipment slot",
			mutate: func(config *Config) {
				config.EquipmentSlots = append(
					config.EquipmentSlots,
					config.EquipmentSlots[0],
				)
			},
		},
		{
			name: "duplicate item",
			mutate: func(config *Config) {
				config.Items = append(config.Items, config.Items[0])
			},
		},
		{
			name: "empty item id",
			mutate: func(config *Config) {
				config.Items[0].ID = ""
			},
		},
		{
			name: "zero item maximum",
			mutate: func(config *Config) {
				config.Items[0].MaxQuantity = 0
			},
		},
		{
			name: "unsafe item maximum",
			mutate: func(config *Config) {
				config.Items[0].MaxQuantity = MaxJSONInteger + 1
			},
		},
		{
			name: "unknown item equipment slot",
			mutate: func(config *Config) {
				config.Items[0].EquipmentSlot = "ring"
			},
		},
		{
			name: "duplicate quest",
			mutate: func(config *Config) {
				config.Quests = append(config.Quests, config.Quests[0])
			},
		},
		{
			name: "quest without objectives",
			mutate: func(config *Config) {
				config.Quests[0].Objectives = nil
			},
		},
		{
			name: "duplicate objective",
			mutate: func(config *Config) {
				config.Quests[0].Objectives = append(
					config.Quests[0].Objectives,
					config.Quests[0].Objectives[0],
				)
			},
		},
		{
			name: "empty objective id",
			mutate: func(config *Config) {
				config.Quests[0].Objectives[0].ID = ""
			},
		},
		{
			name: "zero objective requirement",
			mutate: func(config *Config) {
				config.Quests[0].Objectives[0].Required = 0
			},
		},
		{
			name: "unsafe objective requirement",
			mutate: func(config *Config) {
				config.Quests[0].Objectives[0].Required =
					MaxJSONInteger + 1
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			config := testConfig()
			test.mutate(&config)
			if err := config.Validate(); err == nil {
				t.Fatal("Config.Validate() succeeded")
			}
			if _, err := NewGame(config); err == nil {
				t.Fatal("NewGame() accepted invalid config")
			}
		})
	}
}

func TestStateValidateRejectsInvalidAndImpossibleStates(t *testing.T) {
	config := testConfig()
	game, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	base := game.Snapshot()

	tests := []struct {
		name   string
		mutate func(*State)
	}{
		{
			name: "version",
			mutate: func(state *State) {
				state.Version++
			},
		},
		{
			name: "project identity",
			mutate: func(state *State) {
				state.ProjectID = "other.project"
			},
		},
		{
			name: "content identity",
			mutate: func(state *State) {
				state.ContentID = "other-content"
			},
		},
		{
			name: "mode",
			mutate: func(state *State) {
				state.Mode = "cutscene"
			},
		},
		{
			name: "locale",
			mutate: func(state *State) {
				state.Locale = "ja"
			},
		},
		{
			name: "unstarted with location",
			mutate: func(state *State) {
				state.Flow = FlowProgress{}
				state.Mode = ModeTitle
			},
		},
		{
			name: "playing without stage",
			mutate: func(state *State) {
				state.CurrentStageID = ""
			},
		},
		{
			name: "playing without spawn",
			mutate: func(state *State) {
				state.EntrySpawnID = ""
			},
		},
		{
			name: "unknown stage",
			mutate: func(state *State) {
				state.CurrentStageID = "stage.missing"
			},
		},
		{
			name: "unknown stage spawn",
			mutate: func(state *State) {
				state.EntrySpawnID = "missing"
			},
		},
		{
			name: "negative currency",
			mutate: func(state *State) {
				state.Currency = -1
			},
		},
		{
			name: "unsafe currency",
			mutate: func(state *State) {
				state.Currency = MaxJSONInteger + 1
			},
		},
		{
			name: "missing flag",
			mutate: func(state *State) {
				state.Flags = state.Flags[:1]
			},
		},
		{
			name: "duplicate flag",
			mutate: func(state *State) {
				state.Flags[1].ID = state.Flags[0].ID
			},
		},
		{
			name: "missing inventory entry",
			mutate: func(state *State) {
				state.Inventory = state.Inventory[:1]
			},
		},
		{
			name: "duplicate inventory entry",
			mutate: func(state *State) {
				state.Inventory[1].ItemID =
					state.Inventory[0].ItemID
			},
		},
		{
			name: "negative inventory quantity",
			mutate: func(state *State) {
				state.Inventory[0].Quantity = -1
			},
		},
		{
			name: "inventory over maximum",
			mutate: func(state *State) {
				state.Inventory[0].Quantity = 11
			},
		},
		{
			name: "duplicate equipment slot",
			mutate: func(state *State) {
				state.Equipment[1].SlotID =
					state.Equipment[0].SlotID
			},
		},
		{
			name: "unknown equipped item",
			mutate: func(state *State) {
				state.Equipment[1].ItemID = "item.missing"
			},
		},
		{
			name: "item in incompatible slot",
			mutate: func(state *State) {
				state.Inventory[1].Quantity = 1
				state.Equipment[0].ItemID =
					"item.training_sword"
			},
		},
		{
			name: "equipped item absent from inventory",
			mutate: func(state *State) {
				state.Equipment[1].ItemID =
					"item.training_sword"
			},
		},
		{
			name: "missing quest",
			mutate: func(state *State) {
				state.Quests = state.Quests[:1]
			},
		},
		{
			name: "duplicate quest",
			mutate: func(state *State) {
				state.Quests[1].ID = state.Quests[0].ID
			},
		},
		{
			name: "invalid quest status",
			mutate: func(state *State) {
				state.Quests[0].Status = "failed"
			},
		},
		{
			name: "missing quest objective",
			mutate: func(state *State) {
				state.Quests[0].Objectives =
					state.Quests[0].Objectives[:1]
			},
		},
		{
			name: "duplicate quest objective",
			mutate: func(state *State) {
				state.Quests[0].Objectives[1].ID =
					state.Quests[0].Objectives[0].ID
			},
		},
		{
			name: "negative objective count",
			mutate: func(state *State) {
				state.Quests[0].Status = QuestActive
				state.Quests[0].Objectives[0].Count = -1
			},
		},
		{
			name: "objective count over requirement",
			mutate: func(state *State) {
				state.Quests[0].Status = QuestActive
				state.Quests[0].Objectives[0].Count = 2
			},
		},
		{
			name: "inactive quest with progress",
			mutate: func(state *State) {
				state.Quests[0].Objectives[1].Count = 1
			},
		},
		{
			name: "active quest with every objective complete",
			mutate: func(state *State) {
				state.Quests[0].Status = QuestActive
				state.Quests[0].Objectives[0].Count = 1
				state.Quests[0].Objectives[1].Count = 2
			},
		},
		{
			name: "completed quest with incomplete objective",
			mutate: func(state *State) {
				state.Quests[0].Status = QuestCompleted
			},
		},
		{
			name: "initially active quest made inactive",
			mutate: func(state *State) {
				state.Quests[1].Status = QuestInactive
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			state := base.Clone()
			test.mutate(&state)
			if err := state.Validate(config); err == nil {
				t.Fatal("State.Validate() succeeded")
			}
			if _, err := Restore(config, state); err == nil {
				t.Fatal("Restore() accepted invalid state")
			}
		})
	}
}

func TestTitleStateRejectsRetainedProgress(t *testing.T) {
	config := testConfig()
	title, err := NewTitle(config)
	if err != nil {
		t.Fatalf("NewTitle() error = %v", err)
	}
	base := title.Snapshot()
	tests := []struct {
		name   string
		mutate func(*State)
	}{
		{
			name: "currency",
			mutate: func(state *State) {
				state.Currency = 1
			},
		},
		{
			name: "flag",
			mutate: func(state *State) {
				state.Flags[0].Value = true
			},
		},
		{
			name: "inventory",
			mutate: func(state *State) {
				state.Inventory[0].Quantity = 1
			},
		},
		{
			name: "equipment",
			mutate: func(state *State) {
				state.Inventory[1].Quantity = 1
				state.Equipment[1].ItemID =
					"item.training_sword"
			},
		},
		{
			name: "quest",
			mutate: func(state *State) {
				state.Quests[0].Status = QuestActive
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			state := base.Clone()
			test.mutate(&state)
			if err := state.Validate(config); err == nil {
				t.Fatal("State.Validate() accepted title progress")
			}
		})
	}
}

func TestEveryGameplayModeIsValidWithLocation(t *testing.T) {
	config := testConfig()
	game, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	for _, mode := range []Mode{
		ModePlaying,
		ModePaused,
		ModeGameOver,
		ModeEnding,
	} {
		t.Run(string(mode), func(t *testing.T) {
			state := game.Snapshot()
			state.Mode = mode
			if mode == ModeEnding {
				state.Flow.Completed = true
			}
			if err := state.Validate(config); err != nil {
				t.Fatalf("State.Validate() error = %v", err)
			}
		})
	}
}

func applyProgress(t *testing.T, game *Campaign) {
	t.Helper()
	if err := game.Transaction(func(state *State) error {
		state.Mode = ModePaused
		state.CurrentStageID = "stage.field"
		state.EntrySpawnID = "village_entry"
		state.Locale = "en"
		flagState(t, state, "quest.guardian.rewarded").Value = true
		inventoryEntry(t, state, "item.potion").Quantity = 2
		inventoryEntry(
			t,
			state,
			"item.training_sword",
		).Quantity = 1
		equipmentEntry(
			t,
			state,
			"weapon",
		).ItemID = "item.training_sword"
		state.Currency = 75

		guardian := questState(t, state, "quest.guardian")
		guardian.Status = QuestActive
		objectiveState(t, guardian, "boss").Count = 0
		objectiveState(t, guardian, "slimes").Count = 2

		intro := questState(t, state, "quest.intro")
		intro.Status = QuestCompleted
		objectiveState(t, intro, "talk").Count = 1
		return nil
	}); err != nil {
		t.Fatalf("Transaction(progress) error = %v", err)
	}
}

func testConfig() Config {
	return Config{
		Version:             CurrentConfigVersion,
		ProjectID:           "recreate.maker_runtime",
		ContentID:           "catalog:sample-v1",
		DefaultLocale:       "ko",
		Locales:             []string{"ko", "en"},
		InitialStageID:      "stage.village",
		InitialEntrySpawnID: "default",
		Stages: []StageDefinition{
			{
				ID:          "stage.village",
				EntrySpawns: []string{"field_return", "default"},
			},
			{
				ID:          "stage.field",
				EntrySpawns: []string{"grove_return", "village_entry"},
			},
		},
		Flags: []string{
			"quest.guardian.rewarded",
			"grove.discovered",
		},
		Items: []ItemDefinition{
			{
				ID:          "item.potion",
				MaxQuantity: 10,
			},
			{
				ID:            "item.training_sword",
				MaxQuantity:   1,
				EquipmentSlot: "weapon",
			},
		},
		EquipmentSlots: []string{"weapon", "armor"},
		Quests: []QuestDefinition{
			{
				ID: "quest.intro",
				Objectives: []ObjectiveDefinition{
					{ID: "talk", Required: 1},
				},
				InitiallyActive: true,
			},
			{
				ID: "quest.guardian",
				Objectives: []ObjectiveDefinition{
					{ID: "slimes", Required: 2},
					{ID: "boss", Required: 1},
				},
			},
		},
	}
}

func assertIDsSorted(t *testing.T, state State) {
	t.Helper()
	if got := []string{state.Flags[0].ID, state.Flags[1].ID}; !reflect.DeepEqual(
		got,
		[]string{"grove.discovered", "quest.guardian.rewarded"},
	) {
		t.Fatalf("flag order = %v", got)
	}
	if got := []string{
		state.Inventory[0].ItemID,
		state.Inventory[1].ItemID,
	}; !reflect.DeepEqual(
		got,
		[]string{"item.potion", "item.training_sword"},
	) {
		t.Fatalf("inventory order = %v", got)
	}
	if got := []string{
		state.Equipment[0].SlotID,
		state.Equipment[1].SlotID,
	}; !reflect.DeepEqual(got, []string{"armor", "weapon"}) {
		t.Fatalf("equipment order = %v", got)
	}
	if got := []string{state.Quests[0].ID, state.Quests[1].ID}; !reflect.DeepEqual(
		got,
		[]string{"quest.guardian", "quest.intro"},
	) {
		t.Fatalf("quest order = %v", got)
	}
	if got := []string{
		state.Quests[0].Objectives[0].ID,
		state.Quests[0].Objectives[1].ID,
	}; !reflect.DeepEqual(got, []string{"boss", "slimes"}) {
		t.Fatalf("objective order = %v", got)
	}
}

func flagState(t *testing.T, state *State, id string) *FlagState {
	t.Helper()
	for index := range state.Flags {
		if state.Flags[index].ID == id {
			return &state.Flags[index]
		}
	}
	t.Fatalf("flag %q not found", id)
	return nil
}

func inventoryEntry(
	t *testing.T,
	state *State,
	id string,
) *InventoryEntry {
	t.Helper()
	for index := range state.Inventory {
		if state.Inventory[index].ItemID == id {
			return &state.Inventory[index]
		}
	}
	t.Fatalf("inventory item %q not found", id)
	return nil
}

func equipmentEntry(
	t *testing.T,
	state *State,
	id string,
) *EquipmentEntry {
	t.Helper()
	for index := range state.Equipment {
		if state.Equipment[index].SlotID == id {
			return &state.Equipment[index]
		}
	}
	t.Fatalf("equipment slot %q not found", id)
	return nil
}

func questState(t *testing.T, state *State, id string) *QuestState {
	t.Helper()
	for index := range state.Quests {
		if state.Quests[index].ID == id {
			return &state.Quests[index]
		}
	}
	t.Fatalf("quest %q not found", id)
	return nil
}

func objectiveState(
	t *testing.T,
	quest *QuestState,
	id string,
) *ObjectiveState {
	t.Helper()
	for index := range quest.Objectives {
		if quest.Objectives[index].ID == id {
			return &quest.Objectives[index]
		}
	}
	t.Fatalf("quest %q objective %q not found", quest.ID, id)
	return nil
}

func reverseStrings(values []string) {
	for left, right := 0, len(values)-1; left < right; left, right =
		left+1, right-1 {
		values[left], values[right] = values[right], values[left]
	}
}

func reverseStages(values []StageDefinition) {
	for index := range values {
		reverseStrings(values[index].EntrySpawns)
	}
	for left, right := 0, len(values)-1; left < right; left, right =
		left+1, right-1 {
		values[left], values[right] = values[right], values[left]
	}
}

func reverseItems(values []ItemDefinition) {
	for left, right := 0, len(values)-1; left < right; left, right =
		left+1, right-1 {
		values[left], values[right] = values[right], values[left]
	}
}

func reverseQuests(values []QuestDefinition) {
	for index := range values {
		for left, right := 0,
			len(values[index].Objectives)-1; left < right; left, right =
			left+1, right-1 {
			values[index].Objectives[left],
				values[index].Objectives[right] =
				values[index].Objectives[right],
				values[index].Objectives[left]
		}
	}
	for left, right := 0, len(values)-1; left < right; left, right =
		left+1, right-1 {
		values[left], values[right] = values[right], values[left]
	}
}
