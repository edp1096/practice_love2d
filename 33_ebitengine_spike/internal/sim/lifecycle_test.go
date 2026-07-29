package sim

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestSpawnEntityPreviewIsAtomicSortedAndDetached(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Walls = []Wall{{
		ID: "wall",
		Rect: Rect{
			MinX: Pixels(100),
			MinY: Pixels(20),
			MaxX: Pixels(110),
			MaxY: Pixels(100),
		},
	}}
	simulation := mustNew(t, config)
	before := simulation.SaveSession()
	invalid := []EntityConfig{
		{
			ID:        "hero",
			Kind:      "npc",
			Position:  Vec{X: Pixels(80), Y: Pixels(80)},
			Body:      Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5)},
			MaxHealth: 1,
		},
		previewEntity("controlled", Pixels(80), Pixels(80)),
		previewEntity("outside", Pixels(500), Pixels(80)),
		previewEntity("in-wall", Pixels(105), Pixels(80)),
	}
	invalid[1].Controlled = true
	invalid[3].Body.Solid = true
	for _, definition := range invalid {
		if err := simulation.SpawnEntity(definition); err == nil {
			t.Fatalf("invalid spawn %q was accepted", definition.ID)
		}
		if got := simulation.SaveSession(); !reflect.DeepEqual(got, before) {
			t.Fatalf("rejected spawn %q mutated state", definition.ID)
		}
	}

	first := previewEntity("preview.z", Pixels(130), Pixels(80))
	second := previewEntity("preview.a", Pixels(150), Pixels(80))
	if err := simulation.SpawnEntity(first); err != nil {
		t.Fatalf("spawn first: %v", err)
	}
	if err := simulation.SpawnEntity(second); err != nil {
		t.Fatalf("spawn second: %v", err)
	}
	first.Name = "caller mutation"
	snapshot := simulation.Snapshot()
	want := []string{"enemy", "hero", "preview.a", "preview.z"}
	for index, id := range want {
		if snapshot.Entities[index].ID != id {
			t.Fatalf("entity order = %#v, want %#v", snapshot.Entities, want)
		}
	}
	if entityByID(t, snapshot, "preview.z").Name == "caller mutation" {
		t.Fatal("spawn retained caller-owned definition")
	}
	if !simulation.HasPreviewTopology() || !simulation.HasTemporaryPreview() {
		t.Fatal("preview topology was not reported")
	}
	requireEvent(t, snapshot.Events, EventEntitySpawned)
}

func TestInteractablePreviewBundleRegistersAndCleansDependencies(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Dialogues = nil
	config.Quests = nil
	config.InteractionRange = 0
	simulation := mustNew(t, config)
	dialogue := DialogueDefinition{
		ID:      "dialogue.preview",
		Speaker: "Preview",
		Text:    "Temporary",
	}
	quest := QuestDefinition{
		ID:             "quest.preview",
		TargetEntityID: "enemy",
		Required:       1,
	}
	preview := EntityPreviewConfig{
		Entity: EntityConfig{
			ID:           "preview.guide",
			Kind:         "npc",
			Name:         "Guide",
			Position:     Vec{X: Pixels(55), Y: Pixels(65)},
			Body:         Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5)},
			MaxHealth:    1,
			DialogueID:   dialogue.ID,
			StartQuestID: quest.ID,
		},
		Dialogue:         &dialogue,
		Quest:            &quest,
		InteractionRange: Pixels(30),
	}
	if err := simulation.SpawnEntityPreview(preview); err != nil {
		t.Fatalf("spawn interactable preview: %v", err)
	}
	events := simulation.Tick(Input{Interact: true})
	requireEvent(t, events, EventQuestStarted)
	requireEvent(t, events, EventDialogueStarted)
	if got := simulation.Snapshot().Dialogue; !got.Active ||
		got.ID != dialogue.ID ||
		got.NPCID != preview.Entity.ID {
		t.Fatalf("preview dialogue did not open: %#v", got)
	}

	before := simulation.SaveSession()
	if err := simulation.RemoveEntity(preview.Entity.ID); err == nil ||
		!strings.Contains(err.Error(), "active dialogue") {
		t.Fatalf("active speaker removal error = %v", err)
	}
	if got := simulation.SaveSession(); !reflect.DeepEqual(got, before) {
		t.Fatal("rejected active-speaker removal mutated state")
	}
	simulation.Tick(Input{Interact: true})
	if err := simulation.RemoveEntity(preview.Entity.ID); err != nil {
		t.Fatalf("remove closed preview speaker: %v", err)
	}
	if simulation.HasPreviewTopology() {
		t.Fatal("removed preview still changes entity topology")
	}
	if simulation.interactionRange != 0 {
		t.Fatalf("interaction range was not restored: %v", simulation.interactionRange)
	}
	if _, present := simulation.dialogues[dialogue.ID]; present {
		t.Fatal("unreferenced preview dialogue was retained")
	}
	if simulation.quests[quest.ID] != nil {
		t.Fatal("unreferenced preview quest was retained")
	}
}

func TestChoiceOnlyQuestBundleOpensDialogueWithoutStartingQuest(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Dialogues = nil
	config.Quests = nil
	config.InteractionRange = 0
	source := mustNew(t, config)
	dialogue := DialogueDefinition{
		ID:      "dialogue.choice-preview",
		Speaker: "Choice Guide",
		Text:    "Choose before the quest starts.",
	}
	quest := QuestDefinition{
		ID:       "quest.choice-preview",
		Required: 1,
	}
	preview := EntityPreviewConfig{
		Entity: EntityConfig{
			ID:         "preview.choice-guide",
			Kind:       "npc",
			Name:       "Choice Guide",
			Position:   Vec{X: Pixels(55), Y: Pixels(65)},
			Body:       Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5)},
			MaxHealth:  1,
			DialogueID: dialogue.ID,
			// StartQuestID intentionally remains empty: Quest is referenced
			// only by a later dialogue choice.
		},
		Dialogue:         &dialogue,
		Quest:            &quest,
		InteractionRange: Pixels(30),
	}
	if err := source.SpawnEntityPreview(preview); err != nil {
		t.Fatalf("spawn choice-only quest preview: %v", err)
	}
	events := source.Tick(Input{Interact: true})
	requireEvent(t, events, EventDialogueStarted)
	if hasEvent(events, EventQuestStarted) {
		t.Fatalf("opening choice-only dialogue started quest: %#v", events)
	}
	snapshot := source.Snapshot()
	if !snapshot.Dialogue.Active ||
		snapshot.Dialogue.ID != dialogue.ID {
		t.Fatalf("choice-only dialogue did not open: %#v", snapshot.Dialogue)
	}
	if got := snapshot.Quests[0]; got.ID != quest.ID ||
		got.Status != QuestInactive ||
		got.Progress != 0 {
		t.Fatalf("choice-only quest changed on open: %#v", got)
	}

	saved := source.SaveSession()
	target := mustNew(t, config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load choice-only preview session: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf(
			"choice-only preview session differs:\n got=%#v\nwant=%#v",
			got,
			saved,
		)
	}
	target.Tick(Input{Interact: true})
	if err := target.RemoveEntity(preview.Entity.ID); err != nil {
		t.Fatalf("remove choice-only preview: %v", err)
	}
	if target.quests[quest.ID] != nil ||
		target.dialogues[dialogue.ID].ID != "" ||
		target.HasPreviewTopology() {
		t.Fatal("choice-only preview dependencies were not cleaned")
	}

	unanchored := mustNew(t, config)
	unanchoredEntity := previewEntity(
		"preview.unanchored",
		Pixels(120),
		Pixels(120),
	)
	before := unanchored.SaveSession()
	if err := unanchored.SpawnEntityPreview(EntityPreviewConfig{
		Entity: unanchoredEntity,
		Quest:  &quest,
	}); err == nil || !strings.Contains(err.Error(), "unanchored") {
		t.Fatalf("unanchored quest bundle error = %v", err)
	}
	if got := unanchored.SaveSession(); !reflect.DeepEqual(got, before) {
		t.Fatal("rejected unanchored quest bundle mutated simulation")
	}
}

func TestRemoveEntityProtectsStrongReferencesAndCleansWeakOnes(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Entities[0].Ability = &AbilityConfig{
		ID:          "tap",
		ActiveTicks: 2,
		Reach:       Pixels(30),
		ArcDegrees:  180,
		Damage:      1,
	}
	config.Quests = []QuestDefinition{{
		ID:              "quest.enemy",
		TargetEntityID:  "enemy",
		Required:        1,
		InitiallyActive: true,
	}}
	simulation := mustNew(t, config)
	if err := simulation.RemoveEntity("missing"); err == nil {
		t.Fatal("unknown removal was accepted")
	}
	if err := simulation.RemoveEntity("hero"); err == nil ||
		!strings.Contains(err.Error(), "controlled") {
		t.Fatalf("controlled removal error = %v", err)
	}

	simulation.Tick(Input{Attack: true})
	attack := simulation.entities["hero"].attack
	if _, hit := attack.hitTargets["enemy"]; !hit {
		t.Fatal("test setup did not create hit-target reference")
	}
	if err := simulation.RemoveEntity("enemy"); err != nil {
		t.Fatalf("remove weakly referenced enemy: %v", err)
	}
	if _, hit := attack.hitTargets["enemy"]; hit || attack.hitCount != 0 {
		t.Fatalf("attack retained removed target: %#v", attack)
	}
	quest := simulation.Snapshot().Quests[0]
	if quest.Status != QuestActive || quest.Progress != 0 {
		t.Fatalf("debug removal changed quest semantics: %#v", quest)
	}
	if _, present := simulation.removedIDs["enemy"]; !present {
		t.Fatal("authored removal was not represented in topology")
	}

	cameraConfig := baseConfig()
	cameraConfig.Camera.TargetEntityID = "enemy"
	cameraSimulation := mustNew(t, cameraConfig)
	if err := cameraSimulation.RemoveEntity("enemy"); err == nil ||
		!strings.Contains(err.Error(), "camera target") {
		t.Fatalf("camera target removal error = %v", err)
	}
}

func TestSharedPreviewDependenciesRemainUntilLastEntityIsRemoved(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.InteractionRange = 0
	dialogue := DialogueDefinition{ID: "dialogue.shared", Text: "Shared"}
	quest := QuestDefinition{ID: "quest.shared", Required: 1}
	makeEntity := func(id string, x Coord) EntityConfig {
		entity := previewEntity(id, x, Pixels(100))
		entity.DialogueID = dialogue.ID
		entity.StartQuestID = quest.ID
		return entity
	}
	simulation := mustNew(t, config)
	if err := simulation.SpawnEntityPreview(EntityPreviewConfig{
		Entity:           makeEntity("preview.owner", Pixels(100)),
		Dialogue:         &dialogue,
		Quest:            &quest,
		InteractionRange: Pixels(25),
	}); err != nil {
		t.Fatalf("spawn dependency owner: %v", err)
	}
	if err := simulation.SpawnEntityPreview(EntityPreviewConfig{
		Entity: makeEntity("preview.dependent", Pixels(120)),
	}); err != nil {
		t.Fatalf("spawn dependency consumer: %v", err)
	}
	if err := simulation.RemoveEntity("preview.owner"); err != nil {
		t.Fatalf("remove dependency owner: %v", err)
	}
	if simulation.dialogues[dialogue.ID].ID == "" ||
		simulation.quests[quest.ID] == nil ||
		simulation.interactionRange != Pixels(25) {
		t.Fatalf(
			"shared dependencies were dropped early: dialogue=%#v quest=%#v range=%v",
			simulation.dialogues[dialogue.ID],
			simulation.quests[quest.ID],
			simulation.interactionRange,
		)
	}
	if err := simulation.RemoveEntity("preview.dependent"); err != nil {
		t.Fatalf("remove final dependency consumer: %v", err)
	}
	if _, present := simulation.dialogues[dialogue.ID]; present ||
		simulation.quests[quest.ID] != nil ||
		simulation.interactionRange != 0 {
		t.Fatal("final dependency cleanup retained preview content")
	}
}

func TestRemoveDeadEntityIsCleanupNotDefeat(t *testing.T) {
	t.Parallel()
	simulation := mustNew(t, baseConfig())
	enemy := simulation.entities["enemy"]
	enemy.health = 0
	enemy.dead = true
	if err := simulation.RemoveEntity("enemy"); err != nil {
		t.Fatalf("remove dead entity: %v", err)
	}
	events := simulation.Snapshot().Events
	requireEvent(t, events, EventEntityRemoved)
	if hasEvent(events, EventActorKilled) || hasEvent(events, EventQuestProgress) {
		t.Fatalf("dead cleanup emitted combat semantics: %#v", events)
	}
}

func TestStartDialoguePreviewSupportsOptionalArbitrarySpeakerAndQuest(t *testing.T) {
	t.Parallel()
	simulation := mustNew(t, baseConfig())
	dialogue := DialogueDefinition{
		ID:      "dialogue.draft",
		Speaker: "Draft",
		Text:    "Preview text",
	}
	quest := QuestDefinition{
		ID:       "quest.draft",
		Required: 2,
	}
	if err := simulation.StartDialoguePreview(
		DialoguePreviewConfig{Dialogue: dialogue, Quest: &quest},
		"enemy",
	); err != nil {
		t.Fatalf("start dialogue with arbitrary speaker: %v", err)
	}
	snapshot := simulation.Snapshot()
	if got := snapshot.Dialogue; !got.Active ||
		got.ID != dialogue.ID ||
		got.NPCID != "enemy" ||
		got.Text != dialogue.Text {
		t.Fatalf("direct dialogue snapshot = %#v", got)
	}
	if got := snapshot.Quests[0]; got.ID != quest.ID ||
		got.Status != QuestInactive ||
		got.Progress != 0 {
		t.Fatalf("dialogue preview started quest dependency: %#v", got)
	}
	before := simulation.SaveSession()
	if err := simulation.StartDialogue(
		DialogueDefinition{ID: "other"},
		"",
	); err == nil {
		t.Fatal("second active dialogue was accepted")
	}
	if got := simulation.SaveSession(); !reflect.DeepEqual(got, before) {
		t.Fatal("rejected second dialogue mutated state")
	}

	speakerless := mustNew(t, baseConfig())
	if err := speakerless.StartDialogue(dialogue, ""); err != nil {
		t.Fatalf("start speakerless dialogue: %v", err)
	}
	if got := speakerless.Snapshot().Dialogue; got.NPCID != "" ||
		!got.Active {
		t.Fatalf("speakerless dialogue = %#v", got)
	}

	onOpen := mustNew(t, baseConfig())
	onOpenQuest := QuestDefinition{ID: "quest.on-open", Required: 1}
	if err := onOpen.StartDialoguePreview(DialoguePreviewConfig{
		Dialogue:   DialogueDefinition{ID: "dialogue.on-open"},
		Quest:      &onOpenQuest,
		StartQuest: true,
	}, ""); err != nil {
		t.Fatalf("start entry-action dialogue: %v", err)
	}
	onOpenSnapshot := onOpen.Snapshot()
	requireEvent(t, onOpenSnapshot.Events, EventQuestStarted)
	requireEvent(t, onOpenSnapshot.Events, EventDialogueStarted)
	if got := onOpenSnapshot.Quests[0]; got.Status != QuestActive {
		t.Fatalf("entry-action quest was not started: %#v", got)
	}

	invalid := mustNew(t, baseConfig())
	beforeInvalid := invalid.SaveSession()
	if err := invalid.StartDialoguePreview(DialoguePreviewConfig{
		Dialogue:   dialogue,
		StartQuest: true,
	}, ""); err == nil {
		t.Fatal("StartQuest without a quest definition was accepted")
	}
	if got := invalid.SaveSession(); !reflect.DeepEqual(got, beforeInvalid) {
		t.Fatal("rejected StartQuest bundle mutated state")
	}
	if err := invalid.StartDialogue(dialogue, "missing"); err == nil {
		t.Fatal("unknown dialogue speaker was accepted")
	}
	invalid.entities["enemy"].dead = true
	invalid.entities["enemy"].health = 0
	if err := invalid.StartDialogue(dialogue, "enemy"); err == nil ||
		!strings.Contains(err.Error(), "dead") {
		t.Fatalf("dead dialogue speaker error = %v", err)
	}
}

func TestKillingActiveDialogueSpeakerClosesDialogueCanonically(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Entities[0].Ability = &AbilityConfig{
		ID:          "lethal",
		ActiveTicks: 1,
		Reach:       Pixels(30),
		ArcDegrees:  180,
		Damage:      100,
	}
	source := mustNew(t, config)
	if err := source.StartDialogue(
		DialogueDefinition{ID: "dialogue.combat"},
		"enemy",
	); err != nil {
		t.Fatalf("start combat dialogue: %v", err)
	}
	events := source.Tick(Input{Attack: true})
	requireEvent(t, events, EventActorKilled)
	closed := requireEvent(t, events, EventDialogueClosed)
	if closed.Reason != "speaker killed" {
		t.Fatalf("dialogue close reason = %q", closed.Reason)
	}
	if source.Snapshot().Dialogue.Active {
		t.Fatal("dead speaker left dialogue active")
	}
	saved := source.SaveSession()
	target := mustNew(t, config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load session after speaker death: %v", err)
	}
}

func TestPreviewTopologySessionRoundTripIntoFreshSimulation(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	source := mustNew(t, config)
	dialogue := DialogueDefinition{
		ID:      "dialogue.preview",
		Speaker: "Preview",
		Text:    "Round trip",
	}
	quest := QuestDefinition{
		ID:       "quest.preview",
		Required: 1,
	}
	preview := EntityPreviewConfig{
		Entity: EntityConfig{
			ID:           "preview.actor",
			Kind:         "npc",
			Name:         "Preview Actor",
			Position:     Vec{X: Pixels(120), Y: Pixels(80)},
			Body:         Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5)},
			MaxHealth:    10,
			MovePerTick:  Pixels(3),
			DialogueID:   dialogue.ID,
			StartQuestID: quest.ID,
		},
		Dialogue:         &dialogue,
		Quest:            &quest,
		InteractionRange: Pixels(40),
	}
	if err := source.SpawnEntityPreview(preview); err != nil {
		t.Fatalf("spawn preview: %v", err)
	}
	source.Tick(Input{Commands: []EntityInput{{
		EntityID: preview.Entity.ID,
		MoveX:    1,
	}}})
	if err := source.RemoveEntity("enemy"); err != nil {
		t.Fatalf("remove authored enemy: %v", err)
	}
	directQuest := QuestDefinition{ID: "quest.dialogue", Required: 3}
	if err := source.StartDialoguePreview(DialoguePreviewConfig{
		Dialogue: DialogueDefinition{
			ID:      "dialogue.direct",
			Speaker: "Narrator",
			Text:    "Detached",
		},
		Quest: &directQuest,
	}, ""); err != nil {
		t.Fatalf("start direct dialogue: %v", err)
	}
	source.Tick(Input{})
	saved := source.SaveSession()
	encoded, err := json.Marshal(saved)
	if err != nil {
		t.Fatalf("marshal dynamic session: %v", err)
	}
	var decoded SessionState
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal dynamic session: %v", err)
	}
	target := mustNew(t, config)
	if err := target.LoadSession(decoded); err != nil {
		t.Fatalf("load dynamic session into fresh simulation: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("dynamic session differs:\n got=%#v\nwant=%#v", got, saved)
	}
	if !reflect.DeepEqual(target.Snapshot(), source.Snapshot()) {
		t.Fatal("dynamic session snapshot did not round-trip")
	}
	if !target.HasPreviewTopology() || !target.HasTemporaryPreview() {
		t.Fatal("restored preview state was not reported")
	}

	clone := source.Clone()
	if !reflect.DeepEqual(clone.SaveSession(), source.SaveSession()) {
		t.Fatal("Clone lost preview topology")
	}
}

func TestLegacyStaticSessionStillLoadsAndCorruptTopologyIsTransactional(
	t *testing.T,
) {
	t.Parallel()
	source := mustNew(t, baseConfig())
	source.Tick(Input{MoveX: 1})
	legacy := source.SaveSession()
	legacy.Version = legacySessionVersion
	target := mustNew(t, baseConfig())
	if err := target.LoadSession(legacy); err != nil {
		t.Fatalf("load legacy static session: %v", err)
	}
	if !reflect.DeepEqual(target.Snapshot(), source.Snapshot()) {
		t.Fatal("legacy session restored different runtime state")
	}

	before := target.SaveSession()
	corrupt := deepCopySession(t, before)
	corrupt.RemovedEntityIDs = []string{"hero"}
	if err := target.LoadSession(corrupt); err == nil {
		t.Fatal("session removing controlled entity was accepted")
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, before) {
		t.Fatal("rejected topology load mutated simulation")
	}
}

func TestLegacyActiveAuthoredDialogueSessionStillLoads(t *testing.T) {
	t.Parallel()
	source := NewDemo()
	source.Tick(Input{Interact: true})
	expected := source.SaveSession()
	legacy := deepCopySession(t, expected)
	legacy.Version = legacySessionVersion
	target := NewDemo()
	if err := target.LoadSession(legacy); err != nil {
		t.Fatalf("load legacy active dialogue: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, expected) {
		t.Fatalf("legacy active dialogue differs:\n got=%#v\nwant=%#v", got, expected)
	}
}

func TestDynamicSessionUsesSavedPositionAfterWallEdit(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Walls = []Wall{{
		ID: "editable",
		Rect: Rect{
			MinX: Pixels(200),
			MinY: Pixels(100),
			MaxX: Pixels(210),
			MaxY: Pixels(180),
		},
	}}
	source := mustNew(t, config)
	definition := previewEntity(
		"preview.mover",
		Pixels(120),
		Pixels(120),
	)
	definition.MovePerTick = Pixels(4)
	if err := source.SpawnEntity(definition); err != nil {
		t.Fatalf("spawn mover: %v", err)
	}
	for range 10 {
		source.Tick(Input{Commands: []EntityInput{{
			EntityID: definition.ID,
			MoveX:    1,
		}}})
	}
	replacement := Rect{
		MinX: Pixels(115),
		MinY: Pixels(110),
		MaxX: Pixels(125),
		MaxY: Pixels(130),
	}
	if err := source.SetWall("editable", replacement); err != nil {
		t.Fatalf("edit wall over vacated preview spawn: %v", err)
	}
	saved := source.SaveSession()
	target := mustNew(t, source.config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load after wall edit over original spawn: %v", err)
	}
	if got, want := target.SaveSession(), saved; !reflect.DeepEqual(got, want) {
		t.Fatalf("wall-edited dynamic session differs:\n got=%#v\nwant=%#v", got, want)
	}
}

func TestRemovedDynamicQuestTargetRemainsSafeSessionIdentity(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	source := mustNew(t, config)
	targetID := "preview.target"
	if err := source.SpawnEntity(
		previewEntity(targetID, Pixels(120), Pixels(120)),
	); err != nil {
		t.Fatalf("spawn quest target: %v", err)
	}
	quest := QuestDefinition{
		ID:             "quest.dynamic-target",
		TargetEntityID: targetID,
		Required:       1,
	}
	if err := source.StartDialoguePreview(DialoguePreviewConfig{
		Dialogue: DialogueDefinition{ID: "dialogue.quest-owner"},
		Quest:    &quest,
	}, ""); err != nil {
		t.Fatalf("register target quest: %v", err)
	}
	source.Tick(Input{Interact: true})
	if err := source.RemoveEntity(targetID); err != nil {
		t.Fatalf("remove dynamic quest target: %v", err)
	}
	saved := source.SaveSession()
	target := mustNew(t, config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load retained quest target identity: %v", err)
	}
	if got := target.Snapshot().Quests[0]; got.ID != quest.ID ||
		got.Status != QuestInactive ||
		got.Progress != 0 {
		t.Fatalf("retained quest changed semantics: %#v", got)
	}
}

func TestPreviewOperationOrderDoesNotChangeCanonicalSession(t *testing.T) {
	t.Parallel()
	dialogue := DialogueDefinition{ID: "dialogue.shared", Text: "Shared"}
	quest := QuestDefinition{ID: "quest.shared", Required: 1}
	makePreview := func(id string, x Coord) EntityPreviewConfig {
		return EntityPreviewConfig{
			Entity: EntityConfig{
				ID:           id,
				Kind:         "npc",
				Position:     Vec{X: x, Y: Pixels(120)},
				Body:         Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5)},
				MaxHealth:    1,
				DialogueID:   dialogue.ID,
				StartQuestID: quest.ID,
			},
			Dialogue:         &dialogue,
			Quest:            &quest,
			InteractionRange: Pixels(20),
		}
	}
	a := makePreview("preview.a", Pixels(100))
	b := makePreview("preview.b", Pixels(120))
	left := mustNew(t, baseConfig())
	right := mustNew(t, baseConfig())
	for _, operation := range []struct {
		simulation *Simulation
		previews   []EntityPreviewConfig
	}{
		{left, []EntityPreviewConfig{b, a}},
		{right, []EntityPreviewConfig{a, b}},
	} {
		for _, preview := range operation.previews {
			if err := operation.simulation.SpawnEntityPreview(preview); err != nil {
				t.Fatalf("spawn %q: %v", preview.Entity.ID, err)
			}
		}
		operation.simulation.Tick(Input{})
	}
	leftJSON, _ := json.Marshal(left.SaveSession())
	rightJSON, _ := json.Marshal(right.SaveSession())
	if string(leftJSON) != string(rightJSON) {
		t.Fatalf(
			"preview order changed canonical session:\nleft=%s\nright=%s",
			leftJSON,
			rightJSON,
		)
	}
}

func previewEntity(id string, x, y Coord) EntityConfig {
	return EntityConfig{
		ID:        id,
		Kind:      "npc",
		Name:      id,
		Position:  Vec{X: x, Y: y},
		Body:      Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5)},
		MaxHealth: 1,
		Facing:    Vec{X: UnitsPerPixel},
	}
}
