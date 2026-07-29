package gameapp

import (
	"bytes"
	"context"
	"encoding/json"
	"reflect"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestCampaignSaveRestoresDurableStateIntoFreshProcessWorld(t *testing.T) {
	saveRoot := t.TempDir()
	processA := newRuntimeAtSaveRoot(t, saveRoot)

	// These changes deliberately exercise every important class of transient
	// state. None may enter the player-save payload.
	callRuntime(
		t,
		processA,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{EntityID: "player", X: 310, Y: 240},
	)
	scheduleProtocolAction(t, processA, "interact")
	stepProtocol(t, processA, 1)
	dialogue, err := processA.DialogueState()
	if err != nil {
		t.Fatal(err)
	}
	if !dialogue.Active {
		t.Fatal("authored dialogue did not become active")
	}
	callRuntime(
		t,
		processA,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 1},
	)
	session := processA.simulation.SaveSession()
	session.Camera.ShakeMagnitude = sim.Pixels(7)
	session.Camera.ShakeDuration = 12
	session.Camera.ShakeRemaining = 12
	if err := processA.simulation.LoadSession(session); err != nil {
		t.Fatal(err)
	}
	processA.portalCooldownTicks = 11
	processA.automationPaused = true
	expected := seedVillageCampaignProgress(t, processA)

	rawResult, err := processA.save(context.Background(), "campaign")
	if err != nil {
		t.Fatal(err)
	}
	saveResult := rawResult.(campaignSaveResult)
	data, err := processA.store.Load("campaign")
	if err != nil {
		t.Fatal(err)
	}
	wantData, err := processA.campaign.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(data, wantData) {
		t.Fatalf(
			"stored data differs from Campaign.Marshal()\nstored: %s\nwant:   %s",
			data,
			wantData,
		)
	}
	if !saveResult.Saved ||
		saveResult.Stage != "stage.village" ||
		saveResult.Spawn != "default" ||
		saveResult.Locale != "locale.ko" ||
		saveResult.Bytes != len(data) {
		t.Fatalf("campaign save response = %#v", saveResult)
	}
	assertCampaignJSONExcludesTransientState(t, data)

	// A separately constructed Runtime and FileStore stand in for a process
	// restart. Seed unrelated live transients to prove load clears them while
	// preserving the automation clock gate.
	processB := newRuntimeAtSaveRoot(t, saveRoot)
	initialPlayer := entitySnapshot(t, processB, "player")
	callRuntime(
		t,
		processB,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{EntityID: "player", X: 700, Y: 300},
	)
	callRuntime(
		t,
		processB,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 2},
	)
	processB.virtual["move_left"] = virtualAction{
		value:     1,
		remaining: 20,
		fresh:     true,
	}
	processB.pendingAbilities["player"] = true
	processB.moving["player"] = true
	processB.portalCooldownTicks = 37
	processB.portalInside["transient"] = true
	processB.automationPaused = true
	beforeCampaign := processB.campaign
	beforeWorld := processB.simulation

	rawResult, err = processB.load(context.Background(), "campaign")
	if err != nil {
		t.Fatal(err)
	}
	loadResult := rawResult.(campaignLoadResult)
	if !loadResult.Loaded ||
		loadResult.Stage != "stage.village" ||
		loadResult.Spawn != "default" ||
		loadResult.Locale != "locale.ko" ||
		loadResult.Mode != campaign.ModePlaying ||
		loadResult.Bytes != len(data) {
		t.Fatalf("campaign load response = %#v", loadResult)
	}
	if processB.campaign == beforeCampaign ||
		processB.simulation == beforeWorld {
		t.Fatal("campaign load retained a pre-load candidate identity")
	}

	expected.Mode = campaign.ModePlaying
	assertDeepEqual(
		t,
		"durable campaign after process restart",
		processB.campaign.Snapshot(),
		expected,
	)
	loadedWorld := processB.simulation.Snapshot()
	loadedPlayer := entitySnapshot(t, processB, "player")
	if loadedWorld.Tick != 0 || loadedWorld.WorldTick != 0 ||
		loadedPlayer.Position != (sim.Vec{
			X: sim.Pixels(150),
			Y: sim.Pixels(270),
		}) ||
		loadedPlayer.Health != initialPlayer.MaxHealth ||
		loadedWorld.Dialogue.Active ||
		loadedWorld.Camera.ShakeTicks != 0 {
		t.Fatalf(
			"campaign load did not construct a fresh World: %#v player=%#v",
			loadedWorld,
			loadedPlayer,
		)
	}
	if len(processB.virtual) != 0 ||
		len(processB.pendingAbilities) != 0 ||
		len(processB.pendingRemovals) != 0 ||
		len(processB.moving) != 0 ||
		len(processB.previewEntities) != 0 ||
		processB.portalCooldownTicks != 0 {
		t.Fatal("campaign load retained stage-local input or preview state")
	}
	if !processB.automationPaused {
		t.Fatal("campaign load changed the automation pause gate")
	}
}

func TestCampaignSaveAfterPortalRestartsAtSavedEntry(t *testing.T) {
	saveRoot := t.TempDir()
	processA := newRuntimeAtSaveRoot(t, saveRoot)
	if err := processA.campaign.Transaction(func(state *campaign.State) error {
		state.Currency = 22
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	moveEntityToPortal(t, processA, "player", "to_field")
	stepProtocol(t, processA, 1)
	assertLocation(t, processA, "stage.world_hub", "village_entry")

	callRuntime(
		t,
		processA,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{EntityID: "player", X: 500, Y: 120},
	)
	callRuntime(
		t,
		processA,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 1},
	)
	rawResult, err := processA.save(context.Background(), "field")
	if err != nil {
		t.Fatal(err)
	}
	saveResult := rawResult.(campaignSaveResult)
	if saveResult.Stage != "stage.world_hub" ||
		saveResult.Spawn != "village_entry" {
		t.Fatalf("portal save response = %#v", saveResult)
	}

	processB := newRuntimeAtSaveRoot(t, saveRoot)
	processB.automationPaused = true
	rawResult, err = processB.load(context.Background(), "field")
	if err != nil {
		t.Fatal(err)
	}
	loadResult := rawResult.(campaignLoadResult)
	if loadResult.Stage != "stage.world_hub" ||
		loadResult.Spawn != "village_entry" {
		t.Fatalf("portal load response = %#v", loadResult)
	}
	assertLocation(t, processB, "stage.world_hub", "village_entry")
	assertFreshWorld(t, processB, 80, 288)
	if got := processB.campaign.Snapshot().Currency; got != 22 {
		t.Fatalf("restarted field campaign currency = %d", got)
	}
	if processB.portalCooldownTicks != 0 {
		t.Fatalf(
			"portal cooldown crossed process restart: %d",
			processB.portalCooldownTicks,
		)
	}
	if !processB.automationPaused {
		t.Fatal("portal campaign load changed automation pause")
	}
}

func TestCampaignLoadDerivesEndingModeFromDurableFlow(t *testing.T) {
	saveRoot := t.TempDir()
	processA := newRuntimeAtSaveRoot(t, saveRoot)
	if err := processA.campaign.Transaction(func(state *campaign.State) error {
		state.Flow.Completed = true
		// Title is a valid transient presentation choice for a completed
		// campaign, but it must not survive serialization.
		state.Mode = campaign.ModeTitle
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := processA.save(context.Background(), "ending"); err != nil {
		t.Fatal(err)
	}
	data, err := processA.store.Load("ending")
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(data, []byte(`"mode"`)) {
		t.Fatalf("transient campaign mode leaked into save: %s", data)
	}

	processB := newRuntimeAtSaveRoot(t, saveRoot)
	processB.automationPaused = true
	rawResult, err := processB.load(context.Background(), "ending")
	if err != nil {
		t.Fatal(err)
	}
	if result := rawResult.(campaignLoadResult); result.Mode != campaign.ModeEnding {
		t.Fatalf("completed flow load response = %#v", result)
	}
	state := processB.campaign.Snapshot()
	if state.Mode != campaign.ModeEnding || !state.Flow.Completed {
		t.Fatalf("completed flow restored as %#v", state)
	}
	if !processB.automationPaused {
		t.Fatal("ending load changed automation pause")
	}
}

func TestCampaignSaveAndLoadRejectPendingMakerRemoval(t *testing.T) {
	runtime := newRuntimeAtSaveRoot(t, t.TempDir())
	if _, err := runtime.save(context.Background(), "baseline"); err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.queueEntityRemoval(protocol.RemoveEntityParams{
		EntityID: "guide",
	}); err != nil {
		t.Fatal(err)
	}
	before := captureLoadAtomicState(t, runtime)

	if _, err := runtime.save(context.Background(), "blocked"); err == nil {
		t.Fatal("campaign save accepted a pending Maker removal")
	}
	if _, err := runtime.load(context.Background(), "baseline"); err == nil {
		t.Fatal("campaign load accepted a pending Maker removal")
	}
	assertLoadAtomicStateUnchanged(t, runtime, before)
}

func TestCampaignSaveRejectsUnstartedCampaign(t *testing.T) {
	runtime := newRuntimeAtSaveRoot(t, t.TempDir())
	title, err := campaign.NewTitle(runtime.campaignConfig)
	if err != nil {
		t.Fatal(err)
	}
	runtime.campaign = title

	if _, err := runtime.save(
		context.Background(),
		"unstarted",
	); err == nil {
		t.Fatal("campaign save accepted an unstarted title campaign")
	}
	if _, err := runtime.store.Load("unstarted"); err == nil {
		t.Fatal("rejected unstarted campaign created a save slot")
	}
}

func TestCampaignLoadFailuresAreFullyAtomic(t *testing.T) {
	tests := []struct {
		name       string
		makeData   func(*testing.T, *Runtime, []byte) []byte
		breakStage bool
	}{
		{
			name: "corrupt JSON",
			makeData: func(
				_ *testing.T,
				_ *Runtime,
				_ []byte,
			) []byte {
				return []byte(`{"schema":`)
			},
		},
		{
			name: "legacy Simulation session",
			makeData: func(
				t *testing.T,
				runtime *Runtime,
				_ []byte,
			) []byte {
				t.Helper()
				data, err := json.Marshal(runtime.simulation.SaveSession())
				if err != nil {
					t.Fatal(err)
				}
				return data
			},
		},
		{
			name: "foreign project",
			makeData: mutateCampaignEnvelope(func(save *campaign.SaveEnvelope) {
				save.Project = "other.project"
			}),
		},
		{
			name: "foreign content",
			makeData: mutateCampaignEnvelope(func(save *campaign.SaveEnvelope) {
				save.Content = "sha256:foreign"
			}),
		},
		{
			name: "future schema",
			makeData: mutateCampaignEnvelope(func(save *campaign.SaveEnvelope) {
				save.Schema++
			}),
		},
		{
			name: "unknown stage",
			makeData: mutateCampaignEnvelope(func(save *campaign.SaveEnvelope) {
				save.Location.Stage = "stage.missing"
			}),
		},
		{
			name: "unknown spawn",
			makeData: mutateCampaignEnvelope(func(save *campaign.SaveEnvelope) {
				save.Location.Spawn = "missing"
			}),
		},
		{
			name: "unstarted campaign",
			makeData: func(
				t *testing.T,
				runtime *Runtime,
				_ []byte,
			) []byte {
				t.Helper()
				title, err := campaign.NewTitle(runtime.campaignConfig)
				if err != nil {
					t.Fatal(err)
				}
				data, err := title.Marshal()
				if err != nil {
					t.Fatal(err)
				}
				return data
			},
		},
		{
			name: "invalid stage build target",
			makeData: func(
				_ *testing.T,
				_ *Runtime,
				valid []byte,
			) []byte {
				return valid
			},
			breakStage: true,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			saveRoot := t.TempDir()
			runtime := newRuntimeAtSaveRoot(t, saveRoot)
			valid, err := runtime.campaign.Marshal()
			if err != nil {
				t.Fatal(err)
			}
			data := test.makeData(t, runtime, valid)
			if err := runtime.store.Save("bad", data); err != nil {
				t.Fatal(err)
			}
			if test.breakStage {
				runtime.catalog = catalogWithInvalidVillageDimensions(
					t,
					runtime,
				)
			}

			callRuntime(
				t,
				runtime,
				protocol.MethodEntitySetPosition,
				protocol.SetPositionParams{
					EntityID: "player",
					X:        350,
					Y:        240,
				},
			)
			scheduleProtocolAction(t, runtime, "interact")
			stepProtocol(t, runtime, 1)
			if _, err := runtime.MoveDialogueSelection(1); err != nil {
				t.Fatal(err)
			}
			callRuntime(
				t,
				runtime,
				protocol.MethodEntitySetPosition,
				protocol.SetPositionParams{
					EntityID: "player",
					X:        410,
					Y:        330,
				},
			)
			runtime.virtual["move_right"] = virtualAction{
				value:     0.5,
				remaining: 9,
				fresh:     true,
			}
			runtime.pendingAbilities["player"] = true
			runtime.moving["player"] = true
			runtime.portalCooldownTicks = 8
			runtime.portalInside["sentinel"] = true
			runtime.automationPaused = true
			before := captureLoadAtomicState(t, runtime)

			if _, err := runtime.load(context.Background(), "bad"); err == nil {
				t.Fatal("invalid campaign save was accepted")
			}
			assertLoadAtomicStateUnchanged(t, runtime, before)
		})
	}
}

func newRuntimeAtSaveRoot(t *testing.T, root string) *Runtime {
	t.Helper()
	store, err := storage.NewFileStore(root)
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{Store: store})
	if err != nil {
		t.Fatal(err)
	}
	return runtime
}

func seedVillageCampaignProgress(
	t *testing.T,
	runtime *Runtime,
) campaign.State {
	t.Helper()
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Mode = campaign.ModePaused
		state.Currency = 63
		for index := range state.Flags {
			if state.Flags[index].ID == "quest.grove_guardian.rewarded" {
				state.Flags[index].Value = true
			}
		}
		for index := range state.Inventory {
			switch state.Inventory[index].ItemID {
			case "item.potion":
				state.Inventory[index].Quantity = 4
			case "item.training_sword":
				state.Inventory[index].Quantity = 1
			}
		}
		for index := range state.Equipment {
			if state.Equipment[index].SlotID == "weapon" {
				state.Equipment[index].ItemID = "item.training_sword"
			}
		}
		for questIndex := range state.Quests {
			quest := &state.Quests[questIndex]
			switch quest.ID {
			case "quest.slime_patrol":
				quest.Status = campaign.QuestActive
				for objectiveIndex := range quest.Objectives {
					if quest.Objectives[objectiveIndex].ID == "defeat_slimes" {
						quest.Objectives[objectiveIndex].Count = 1
					}
				}
			case "quest.grove_guardian":
				quest.Status = campaign.QuestCompleted
				for objectiveIndex := range quest.Objectives {
					switch quest.Objectives[objectiveIndex].ID {
					case "defeat_slimes":
						quest.Objectives[objectiveIndex].Count = 2
					case "defeat_guardian":
						quest.Objectives[objectiveIndex].Count = 1
					}
				}
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	return runtime.campaign.Snapshot()
}

func assertCampaignJSONExcludesTransientState(t *testing.T, data []byte) {
	t.Helper()
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{
		`"position"`,
		`"entities"`,
		`"health"`,
		`"combat"`,
		`"camera"`,
		`"dialogue"`,
		`"shop"`,
		`"portal"`,
		`"cooldown"`,
		`"preview"`,
		`"paused"`,
		`"mode"`,
		`"tick"`,
	} {
		if bytes.Contains(data, []byte(forbidden)) {
			t.Fatalf("campaign save contains transient key %s: %s", forbidden, data)
		}
	}
	wantKeys := []string{"content", "location", "project", "schema", "sections"}
	gotKeys := make([]string, 0, len(document))
	for key := range document {
		gotKeys = append(gotKeys, key)
	}
	if !reflect.DeepEqual(sortedStrings(gotKeys), wantKeys) {
		t.Fatalf("campaign save top-level keys = %q, want %q", gotKeys, wantKeys)
	}
}

func sortedStrings(values []string) []string {
	result := append([]string(nil), values...)
	for left := 0; left < len(result); left++ {
		for right := left + 1; right < len(result); right++ {
			if result[right] < result[left] {
				result[left], result[right] = result[right], result[left]
			}
		}
	}
	return result
}

func mutateCampaignEnvelope(
	mutate func(*campaign.SaveEnvelope),
) func(*testing.T, *Runtime, []byte) []byte {
	return func(t *testing.T, _ *Runtime, valid []byte) []byte {
		t.Helper()
		var save campaign.SaveEnvelope
		if err := json.Unmarshal(valid, &save); err != nil {
			t.Fatal(err)
		}
		mutate(&save)
		data, err := json.Marshal(save)
		if err != nil {
			t.Fatal(err)
		}
		return data
	}
}

func catalogWithInvalidVillageDimensions(
	t *testing.T,
	runtime *Runtime,
) *content.Catalog {
	t.Helper()
	raw, exists := runtime.catalog.Definition("stage.village")
	if !exists {
		t.Fatal("stage.village is missing")
	}
	var definition map[string]any
	if err := json.Unmarshal(raw, &definition); err != nil {
		t.Fatal(err)
	}
	definition["width"] = -1
	edited, err := json.Marshal(definition)
	if err != nil {
		t.Fatal(err)
	}
	catalog, err := runtime.catalog.WithDefinition("stage.village", edited)
	if err != nil {
		t.Fatal(err)
	}
	return catalog
}

type loadAtomicState struct {
	catalog          *content.Catalog
	campaignConfig   campaign.Config
	campaign         *campaign.Campaign
	contentRules     gamebuild.ContentRules
	ruleExecutor     *rulesruntime.Executor
	built            *gamebuild.Result
	simulation       *sim.Simulation
	dialogue         *rulesruntime.DialogueSession
	campaignJSON     []byte
	sessionJSON      []byte
	buildOverrides   gamebuild.Options
	buildOptions     gamebuild.Options
	virtual          map[string]virtualAction
	pendingAbilities map[string]bool
	pendingRemovals  map[string]bool
	moving           map[string]bool
	preview          map[string]previewEntity
	previewSequence  uint64
	dialogueSpeaker  string
	dialogueChoice   int
	activeShop       string
	shopSelected     int
	shopStatus       string
	portalCooldown   int
	portalInside     map[string]bool
	automationPaused bool
	quit             bool
	quitPending      bool
	revision         uint64
}

func captureLoadAtomicState(
	t *testing.T,
	runtime *Runtime,
) loadAtomicState {
	t.Helper()
	campaignJSON, err := runtime.campaign.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	sessionJSON, err := json.Marshal(runtime.simulation.SaveSession())
	if err != nil {
		t.Fatal(err)
	}
	return loadAtomicState{
		catalog:          runtime.catalog,
		campaignConfig:   runtime.campaignConfig.Clone(),
		campaign:         runtime.campaign,
		contentRules:     runtime.contentRules,
		ruleExecutor:     runtime.ruleExecutor,
		built:            runtime.built,
		simulation:       runtime.simulation,
		dialogue:         runtime.dialogue,
		campaignJSON:     campaignJSON,
		sessionJSON:      sessionJSON,
		buildOverrides:   runtime.buildOverrides,
		buildOptions:     runtime.buildOptions,
		virtual:          cloneVirtualActions(runtime.virtual),
		pendingAbilities: cloneBoolMap(runtime.pendingAbilities),
		pendingRemovals:  cloneBoolMap(runtime.pendingRemovals),
		moving:           cloneBoolMap(runtime.moving),
		preview:          clonePreviewEntities(runtime.previewEntities),
		previewSequence:  runtime.previewSequence,
		dialogueSpeaker:  runtime.dialogueSpeakerID,
		dialogueChoice:   runtime.dialogueChoiceIndex,
		activeShop:       runtime.activeShopID,
		shopSelected:     runtime.shopSelectedIndex,
		shopStatus:       runtime.shopStatus,
		portalCooldown:   runtime.portalCooldownTicks,
		portalInside:     cloneBoolMap(runtime.portalInside),
		automationPaused: runtime.automationPaused,
		quit:             runtime.quit,
		quitPending:      runtime.quitPending,
		revision:         runtime.revision,
	}
}

func assertLoadAtomicStateUnchanged(
	t *testing.T,
	runtime *Runtime,
	before loadAtomicState,
) {
	t.Helper()
	if runtime.catalog != before.catalog ||
		runtime.campaign != before.campaign ||
		runtime.ruleExecutor != before.ruleExecutor ||
		runtime.built != before.built ||
		runtime.simulation != before.simulation ||
		runtime.dialogue != before.dialogue {
		t.Fatal(
			"failed load changed live catalog, Campaign, build, or World identity",
		)
	}
	afterCampaign, err := runtime.campaign.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	afterSession, err := json.Marshal(runtime.simulation.SaveSession())
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(afterCampaign, before.campaignJSON) ||
		!bytes.Equal(afterSession, before.sessionJSON) {
		t.Fatal("failed load changed live campaign or World bytes")
	}
	if !reflect.DeepEqual(runtime.campaignConfig, before.campaignConfig) ||
		!reflect.DeepEqual(runtime.contentRules, before.contentRules) ||
		!reflect.DeepEqual(runtime.buildOverrides, before.buildOverrides) ||
		!reflect.DeepEqual(runtime.buildOptions, before.buildOptions) ||
		!reflect.DeepEqual(runtime.virtual, before.virtual) ||
		!reflect.DeepEqual(
			runtime.pendingAbilities,
			before.pendingAbilities,
		) ||
		!reflect.DeepEqual(runtime.pendingRemovals, before.pendingRemovals) ||
		!reflect.DeepEqual(runtime.moving, before.moving) ||
		!reflect.DeepEqual(runtime.previewEntities, before.preview) ||
		runtime.previewSequence != before.previewSequence ||
		runtime.dialogueSpeakerID != before.dialogueSpeaker ||
		runtime.dialogueChoiceIndex != before.dialogueChoice ||
		runtime.activeShopID != before.activeShop ||
		runtime.shopSelectedIndex != before.shopSelected ||
		runtime.shopStatus != before.shopStatus ||
		runtime.portalCooldownTicks != before.portalCooldown ||
		!reflect.DeepEqual(runtime.portalInside, before.portalInside) ||
		runtime.automationPaused != before.automationPaused ||
		runtime.quit != before.quit ||
		runtime.quitPending != before.quitPending ||
		runtime.revision != before.revision {
		t.Fatal("failed load changed live transient state or revision")
	}
}
