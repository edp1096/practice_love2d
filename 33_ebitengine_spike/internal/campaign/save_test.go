package campaign

import (
	"bytes"
	"encoding/json"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestPlayerSaveEnvelopeIsCanonicalAndExcludesTransientState(
	t *testing.T,
) {
	config := testConfig()
	game, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	applyProgress(t, game)

	first, err := game.Marshal()
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	second, err := game.Marshal()
	if err != nil {
		t.Fatalf("second Marshal() error = %v", err)
	}
	if !bytes.Equal(first, second) {
		t.Fatalf(
			"Marshal() is nondeterministic\nfirst:  %s\nsecond: %s",
			first,
			second,
		)
	}
	if bytes.Contains(first, []byte("null")) {
		t.Fatalf("save contains a null collection: %s", first)
	}
	for _, key := range []string{
		`"mode"`,
		`"notice"`,
		`"entity"`,
		`"entities"`,
		`"position"`,
		`"health"`,
		`"combat"`,
		`"camera"`,
		`"dialogue"`,
		`"portal"`,
		`"preview"`,
	} {
		if bytes.Contains(first, []byte(key)) {
			t.Fatalf("save leaked transient key %s: %s", key, first)
		}
	}

	var document map[string]any
	if err := json.Unmarshal(first, &document); err != nil {
		t.Fatalf("json.Unmarshal(save) error = %v", err)
	}
	assertMapKeys(
		t,
		document,
		"content",
		"location",
		"project",
		"schema",
		"sections",
	)
	location := objectAt(t, document, "location")
	assertMapKeys(t, location, "spawn", "stage")
	sections := objectAt(t, document, "sections")
	assertMapKeys(
		t,
		sections,
		"accessibility.settings",
		"game.flow",
		"rpg.economy",
		"rpg.equipment",
		"rpg.flags",
		"rpg.inventory",
		"rpg.locale",
		"rpg.quests",
		"rpg.turn_battles",
		"world.state",
	)
	for name, value := range sections {
		section, ok := value.(map[string]any)
		if !ok {
			t.Fatalf("section %q = %T, want object", name, value)
		}
		assertMapKeys(t, section, "data", "version")
		if section["version"] != float64(1) {
			t.Fatalf(
				"section %q version = %#v, want 1",
				name,
				section["version"],
			)
		}
		if _, ok := section["data"].(map[string]any); !ok {
			t.Fatalf(
				"section %q data = %T, want object",
				name,
				section["data"],
			)
		}
	}

	exported, err := game.Export()
	if err != nil {
		t.Fatalf("Export() error = %v", err)
	}
	exported.Sections.Flags.Data.Values[0].Value =
		!exported.Sections.Flags.Data.Values[0].Value
	exported.Sections.Quests.Data.Quests[0].Objectives[0].Count = 1
	if got := game.Snapshot(); got.Flags[0].Value ||
		got.Quests[0].Objectives[0].Count != 0 {
		t.Fatalf("Export() returned aliased data: %#v", got)
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
		t.Fatalf("NewGame(reordered) error = %v", err)
	}
	applyProgress(t, reorderedGame)
	reorderedJSON, err := reorderedGame.Marshal()
	if err != nil {
		t.Fatalf("Marshal(reordered) error = %v", err)
	}
	if !bytes.Equal(first, reorderedJSON) {
		t.Fatalf(
			"equivalent config order changed save JSON\nfirst: %s\n"+
				"other: %s",
			first,
			reorderedJSON,
		)
	}
}

func TestPlayerSaveProcessRestartRoundTrip(t *testing.T) {
	config := testConfig()
	live, err := NewGame(config)
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	applyProgress(t, live)
	before := live.Snapshot()
	if before.Mode != ModePaused {
		t.Fatalf("live mode = %q, want paused", before.Mode)
	}

	save, err := live.Marshal()
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}

	configJSON, err := json.Marshal(config)
	if err != nil {
		t.Fatalf("json.Marshal(config) error = %v", err)
	}
	var restartedConfig Config
	if err := json.Unmarshal(configJSON, &restartedConfig); err != nil {
		t.Fatalf("json.Unmarshal(config) error = %v", err)
	}
	restored, err := Decode(restartedConfig, save)
	if err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
	after := restored.Snapshot()
	want := before.Clone()
	want.Mode = ModePlaying
	if !reflect.DeepEqual(after, want) {
		t.Fatalf(
			"process restart changed durable state\n got: %#v\nwant: %#v",
			after,
			want,
		)
	}
	if after.CurrentStageID != "stage.field" ||
		after.EntrySpawnID != "village_entry" {
		t.Fatalf(
			"restored location = %q/%q",
			after.CurrentStageID,
			after.EntrySpawnID,
		)
	}
	roundTrip, err := restored.Marshal()
	if err != nil {
		t.Fatalf("restored Marshal() error = %v", err)
	}
	if !bytes.Equal(roundTrip, save) {
		t.Fatalf(
			"save round trip is not canonical\nfirst: %s\nagain: %s",
			save,
			roundTrip,
		)
	}
	if got := live.Snapshot(); !reflect.DeepEqual(got, before) {
		t.Fatalf("Decode() mutated live campaign: %#v", got)
	}
	if err := restored.Transaction(func(state *State) error {
		state.Currency--
		return nil
	}); err != nil {
		t.Fatalf("candidate Transaction() error = %v", err)
	}
	if got := live.Snapshot(); !reflect.DeepEqual(got, before) {
		t.Fatalf("candidate aliases live campaign: %#v", got)
	}
}

func TestPlayerSaveDerivesModeOnlyFromDurableFlow(t *testing.T) {
	for _, transient := range []Mode{
		ModePaused,
		ModeGameOver,
		ModeTitle,
	} {
		t.Run(string(transient), func(t *testing.T) {
			game, err := NewGame(testConfig())
			if err != nil {
				t.Fatalf("NewGame() error = %v", err)
			}
			applyProgress(t, game)
			if err := game.Transaction(func(state *State) error {
				state.Mode = transient
				return nil
			}); err != nil {
				t.Fatalf("Transaction(mode) error = %v", err)
			}
			save, err := game.Marshal()
			if err != nil {
				t.Fatalf("Marshal() error = %v", err)
			}
			if bytes.Contains(save, []byte(`"mode"`)) {
				t.Fatalf("save contains transient mode: %s", save)
			}
			restored, err := Decode(testConfig(), save)
			if err != nil {
				t.Fatalf("Decode() error = %v", err)
			}
			got := restored.Snapshot()
			if got.Mode != ModePlaying {
				t.Fatalf(
					"restored mode = %q, want %q",
					got.Mode,
					ModePlaying,
				)
			}
			if !got.Flow.Started || got.Flow.Completed {
				t.Fatalf("restored flow = %#v", got.Flow)
			}
			if got.Currency != 75 ||
				got.CurrentStageID != "stage.field" {
				t.Fatalf("durable progress was not preserved: %#v", got)
			}
		})
	}

	completed, err := NewGame(testConfig())
	if err != nil {
		t.Fatalf("NewGame(completed) error = %v", err)
	}
	if err := completed.Transaction(func(state *State) error {
		state.Flow.Completed = true
		state.Mode = ModeEnding
		return nil
	}); err != nil {
		t.Fatalf("Transaction(completed) error = %v", err)
	}
	completedSave, err := completed.Marshal()
	if err != nil {
		t.Fatalf("Marshal(completed) error = %v", err)
	}
	completedRestore, err := Decode(testConfig(), completedSave)
	if err != nil {
		t.Fatalf("Decode(completed) error = %v", err)
	}
	if got := completedRestore.Snapshot(); got.Mode != ModeEnding ||
		!got.Flow.Started || !got.Flow.Completed {
		t.Fatalf("completed restore = %#v", got)
	}

	title, err := NewTitle(testConfig())
	if err != nil {
		t.Fatalf("NewTitle() error = %v", err)
	}
	titleSave, err := title.Marshal()
	if err != nil {
		t.Fatalf("Marshal(title) error = %v", err)
	}
	titleRestore, err := Decode(testConfig(), titleSave)
	if err != nil {
		t.Fatalf("Decode(title) error = %v", err)
	}
	if got := titleRestore.Snapshot(); got.Mode != ModeTitle ||
		got.Flow.Started || got.Flow.Completed ||
		got.CurrentStageID != "" || got.EntrySpawnID != "" {
		t.Fatalf("title restore = %#v", got)
	}
}

func TestPlayerSaveDecodeRejectsMalformedForeignAndInvalidDataAtomically(
	t *testing.T,
) {
	live, err := NewGame(testConfig())
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	applyProgress(t, live)
	before := live.Snapshot()
	valid, err := live.Marshal()
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}

	cases := []struct {
		name string
		data []byte
	}{
		{name: "empty", data: nil},
		{name: "corrupt", data: []byte(`{"schema":`)},
		{
			name: "trailing document",
			data: append(append([]byte{}, valid...), []byte(` {}`)...),
		},
		{
			name: "unknown top-level field",
			data: replaceOnce(
				t,
				valid,
				`"schema":1`,
				`"schema":1,"runtime":{}`,
			),
		},
		{
			name: "unknown nested field",
			data: replaceOnce(
				t,
				valid,
				`"balance":75`,
				`"balance":75,"mode":"paused"`,
			),
		},
		{
			name: "duplicate field",
			data: replaceOnce(
				t,
				valid,
				`"schema":1`,
				`"schema":1,"schema":1`,
			),
		},
		{
			name: "missing required field",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				delete(document, "content")
			}),
		},
		{
			name: "missing section",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				delete(objectAt(t, document, "sections"), "rpg.locale")
			}),
		},
		{
			name: "missing section data",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				section := objectAt(
					t,
					objectAt(t, document, "sections"),
					"rpg.economy",
				)
				delete(section, "data")
			}),
		},
		{
			name: "future schema",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				document["schema"] = float64(CurrentSaveSchemaVersion + 1)
			}),
		},
		{
			name: "foreign project",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				document["project"] = "foreign.project"
			}),
		},
		{
			name: "foreign content",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				document["content"] = "catalog:foreign"
			}),
		},
		{
			name: "unknown stage",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				objectAt(t, document, "location")["stage"] =
					"stage.missing"
			}),
		},
		{
			name: "unknown spawn",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				objectAt(t, document, "location")["spawn"] = "missing"
			}),
		},
		{
			name: "completed without started",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				flow := sectionDataAt(t, document, "game.flow")
				flow["started"] = false
				flow["completed"] = true
			}),
		},
		{
			name: "started without location",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				objectAt(t, document, "location")["stage"] = ""
			}),
		},
		{
			name: "flag topology",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				flags := sectionDataAt(t, document, "rpg.flags")
				flags["values"] = flags["values"].([]any)[:1]
			}),
		},
		{
			name: "inventory topology",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				inventory := sectionDataAt(
					t,
					document,
					"rpg.inventory",
				)
				entries := inventory["entries"].([]any)
				entry := entries[0].(map[string]any)
				entry["item_id"] = "item.missing"
			}),
		},
		{
			name: "inventory limit",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				inventory := sectionDataAt(
					t,
					document,
					"rpg.inventory",
				)
				entry := inventory["entries"].([]any)[0].(map[string]any)
				entry["quantity"] = float64(100)
			}),
		},
		{
			name: "equipment topology",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				equipment := sectionDataAt(
					t,
					document,
					"rpg.equipment",
				)
				entry := equipment["entries"].([]any)[1].(map[string]any)
				entry["slot_id"] = "ring"
			}),
		},
		{
			name: "quest topology",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				quests := sectionDataAt(t, document, "rpg.quests")
				quest := quests["quests"].([]any)[0].(map[string]any)
				objective := quest["objectives"].([]any)[0].(map[string]any)
				objective["id"] = "missing"
			}),
		},
		{
			name: "invalid economy",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				sectionDataAt(t, document, "rpg.economy")["balance"] =
					float64(-1)
			}),
		},
		{
			name: "unknown locale",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				sectionDataAt(t, document, "rpg.locale")["selected"] = "ja"
			}),
		},
		{
			name: "invalid world day",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				sectionDataAt(t, document, "world.state")["day"] =
					float64(0)
			}),
		},
		{
			name: "invalid world minute",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				sectionDataAt(t, document, "world.state")["minute"] =
					float64(24 * 60)
			}),
		},
	}

	for _, section := range []string{
		"accessibility.settings",
		"game.flow",
		"rpg.flags",
		"rpg.inventory",
		"rpg.equipment",
		"rpg.quests",
		"rpg.economy",
		"rpg.locale",
		"rpg.turn_battles",
		"world.state",
	} {
		cases = append(cases, struct {
			name string
			data []byte
		}{
			name: "future " + section + " version",
			data: mutateSaveDocument(t, valid, func(document map[string]any) {
				entry := objectAt(
					t,
					objectAt(t, document, "sections"),
					section,
				)
				entry["version"] = float64(2)
			}),
		})
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if _, err := live.Decode(test.data); err == nil {
				t.Fatal("Decode() succeeded")
			}
			if got := live.Snapshot(); !reflect.DeepEqual(got, before) {
				t.Fatalf(
					"failed Decode() mutated live state\n got: %#v\nwant: %#v",
					got,
					before,
				)
			}
		})
	}
}

func TestPlayerSaveDecodeValidatesCurrentConfigTopology(t *testing.T) {
	game, err := NewGame(testConfig())
	if err != nil {
		t.Fatalf("NewGame() error = %v", err)
	}
	applyProgress(t, game)
	save, err := game.Marshal()
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}

	tests := []struct {
		name   string
		mutate func(*Config)
	}{
		{
			name: "stage removed",
			mutate: func(config *Config) {
				config.Stages = config.Stages[:1]
			},
		},
		{
			name: "spawn removed",
			mutate: func(config *Config) {
				config.Stages[1].EntrySpawns =
					[]string{"grove_return"}
			},
		},
		{
			name: "flag added",
			mutate: func(config *Config) {
				config.Flags = append(config.Flags, "new.flag")
			},
		},
		{
			name: "item maximum changed",
			mutate: func(config *Config) {
				config.Items[0].MaxQuantity = 1
			},
		},
		{
			name: "equipment slot added",
			mutate: func(config *Config) {
				config.EquipmentSlots =
					append(config.EquipmentSlots, "ring")
			},
		},
		{
			name: "objective requirement changed",
			mutate: func(config *Config) {
				config.Quests[1].Objectives[0].Required = 1
			},
		},
		{
			name: "locale removed",
			mutate: func(config *Config) {
				config.Locales = []string{"ko"}
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			config := testConfig()
			test.mutate(&config)
			if _, err := Decode(config, save); err == nil {
				t.Fatal("Decode() accepted incompatible config topology")
			}
		})
	}
}

func TestNilCampaignSaveOperationsFail(t *testing.T) {
	var campaign *Campaign
	if _, err := campaign.Export(); err == nil {
		t.Fatal("nil Campaign.Export() succeeded")
	}
	if _, err := campaign.Marshal(); err == nil {
		t.Fatal("nil Campaign.Marshal() succeeded")
	}
	if _, err := campaign.Decode([]byte(`{}`)); err == nil {
		t.Fatal("nil Campaign.Decode() succeeded")
	}
}

func mutateSaveDocument(
	t *testing.T,
	source []byte,
	mutate func(map[string]any),
) []byte {
	t.Helper()
	var document map[string]any
	if err := json.Unmarshal(source, &document); err != nil {
		t.Fatalf("json.Unmarshal(source) error = %v", err)
	}
	mutate(document)
	result, err := json.Marshal(document)
	if err != nil {
		t.Fatalf("json.Marshal(mutated) error = %v", err)
	}
	return result
}

func sectionDataAt(
	t *testing.T,
	document map[string]any,
	name string,
) map[string]any {
	t.Helper()
	sections := objectAt(t, document, "sections")
	section := objectAt(t, sections, name)
	return objectAt(t, section, "data")
}

func objectAt(
	t *testing.T,
	parent map[string]any,
	key string,
) map[string]any {
	t.Helper()
	value, exists := parent[key]
	if !exists {
		t.Fatalf("object has no key %q", key)
	}
	result, ok := value.(map[string]any)
	if !ok {
		t.Fatalf("%q = %T, want object", key, value)
	}
	return result
}

func assertMapKeys(
	t *testing.T,
	value map[string]any,
	want ...string,
) {
	t.Helper()
	got := make([]string, 0, len(value))
	for key := range value {
		got = append(got, key)
	}
	sort.Strings(got)
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("object keys = %v, want %v", got, want)
	}
}

func replaceOnce(
	t *testing.T,
	source []byte,
	old string,
	replacement string,
) []byte {
	t.Helper()
	if !strings.Contains(string(source), old) {
		t.Fatalf("source does not contain %q: %s", old, source)
	}
	return bytes.Replace(source, []byte(old), []byte(replacement), 1)
}
