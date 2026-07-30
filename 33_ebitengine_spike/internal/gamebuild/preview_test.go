package gamebuild

import (
	"encoding/json"
	"math"
	"reflect"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func rawObject(t *testing.T, value any) json.RawMessage {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestBuildEntityPreviewAppliesInstanceOverrides(t *testing.T) {
	t.Parallel()

	tags := []string{"boss", "enemy", "boss"}
	result, err := BuildEntityPreview(
		loadCatalog(t),
		EntityPreviewOptions{
			ActorID:  "actor.slime",
			EntityID: "maker.preview.1",
			Name:     "Preview Boss",
			X:        321.5,
			Y:        210.25,
			Tags:     tags,
			Components: map[string]json.RawMessage{
				"action.health": rawObject(t, map[string]any{
					"max": 250,
				}),
				"movement.topdown": rawObject(t, map[string]any{
					"speed": 90,
				}),
				"action.combat": rawObject(t, map[string]any{
					"team": "preview",
				}),
				"action.behavior_ai": rawObject(t, map[string]any{
					"patterns": []any{
						map[string]any{
							"movement": map[string]any{
								"preferred_range": 44,
							},
							"attacks": []any{
								map[string]any{
									"maximum_range": 44,
								},
							},
						},
					},
				}),
			},
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	tags[0] = "mutated-after-build"

	if result.Entity.ID != "maker.preview.1" ||
		result.Entity.Kind != "actor.slime" ||
		result.Entity.Name != "Preview Boss" ||
		result.Entity.Position != (sim.Vec{
			X: pixels(321.5),
			Y: pixels(210.25),
		}) {
		t.Fatalf("entity identity/position = %#v", result.Entity)
	}
	if result.Entity.MaxHealth != 250 ||
		result.Entity.MovePerTick != rateToCoord(90) ||
		result.Entity.Team != "preview" {
		t.Fatalf("component overrides = %#v", result.Entity)
	}
	if result.Entity.Body.HalfWidth != pixels(13) ||
		result.Entity.PrimaryAbility() == nil ||
		result.Entity.PrimaryAbility().ID != "ability.slime_bump" {
		t.Fatalf("actor defaults were not retained: %#v", result.Entity)
	}
	if got, want := result.Metadata.Tags, []string{"boss", "enemy"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("metadata tags = %#v, want %#v", got, want)
	}
	if result.Metadata.SpriteID != "sprite.slime" ||
		result.Metadata.BehaviorAI == nil ||
		result.Metadata.BehaviorAI.TargetTag != "player" ||
		result.Metadata.BehaviorAI.AggroRange != 360 ||
		len(result.Metadata.BehaviorAI.Patterns) != 1 ||
		result.Metadata.BehaviorAI.Patterns[0].Movement.PreferredRange != 44 ||
		result.Metadata.BehaviorAI.Patterns[0].Attacks[0].MaximumRange != 44 {
		t.Fatalf("metadata = %#v", result.Metadata)
	}
	if result.Dialogue != nil || result.Quest != nil ||
		result.InteractionRange != 0 {
		t.Fatalf("unexpected RPG bundle = %#v", result)
	}
}

func TestBuildEntityPreviewIncludesInteractionDefinitions(t *testing.T) {
	t.Parallel()

	result, err := BuildEntityPreview(
		loadCatalog(t),
		EntityPreviewOptions{
			ActorID:  "actor.guide",
			EntityID: "maker.preview.guide",
			X:        480,
			Y:        270,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.Entity.DialogueID != "dialogue.guide" ||
		result.Entity.StartQuestID != "" {
		t.Fatalf("entity interaction = %#v", result.Entity)
	}
	if result.Dialogue == nil ||
		result.Dialogue.ID != "dialogue.guide" ||
		result.Dialogue.Speaker != "길드 안내인" ||
		result.Dialogue.Text == "" {
		t.Fatalf("dialogue = %#v", result.Dialogue)
	}
	if result.Quest == nil ||
		result.Quest.ID != "quest.slime_patrol" ||
		result.Quest.TargetKind != "actor.slime" ||
		result.Quest.Required != 2 {
		t.Fatalf("quest = %#v", result.Quest)
	}
	if result.InteractionRange != pixels(70) {
		t.Fatalf("interaction range = %d", result.InteractionRange)
	}
}

func TestBuildDialoguePreviewResolvesDialogueOutsideActiveStage(t *testing.T) {
	t.Parallel()

	result, err := BuildDialoguePreview(
		loadCatalog(t),
		DialoguePreviewOptions{
			DialogueID: "dialogue.village_guide",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.Dialogue.ID != "dialogue.village_guide" ||
		result.StartNodeID != "greeting" ||
		result.Dialogue.Speaker != "마을 안내인" ||
		result.Dialogue.Text == "" {
		t.Fatalf("dialogue = %#v", result.Dialogue)
	}
	if result.Quest == nil ||
		result.Quest.ID != "quest.grove_guardian" ||
		result.Quest.TargetKind != "actor.slime" ||
		result.Quest.Required != 2 {
		t.Fatalf("quest = %#v", result.Quest)
	}
	if result.StartQuestOnOpen {
		t.Fatal("choice quest was classified as a start-node action")
	}
}

func TestBuildDialoguePreviewDistinguishesEntryQuestAction(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	choiceOnly, err := BuildDialoguePreview(
		catalog,
		DialoguePreviewOptions{DialogueID: "dialogue.guide"},
	)
	if err != nil {
		t.Fatal(err)
	}
	if choiceOnly.Quest == nil ||
		choiceOnly.Quest.ID != "quest.slime_patrol" ||
		choiceOnly.StartQuestOnOpen {
		t.Fatalf("choice-only dialogue = %#v", choiceOnly)
	}

	raw, ok := catalog.Definition("dialogue.guide")
	if !ok {
		t.Fatal("guide dialogue definition missing")
	}
	var definition map[string]any
	if err := json.Unmarshal(raw, &definition); err != nil {
		t.Fatal(err)
	}
	nodes := definition["nodes"].(map[string]any)
	greeting := nodes["greeting"].(map[string]any)
	greeting["actions"] = []any{
		map[string]any{
			"type":  "start_quest",
			"quest": "quest.slime_patrol",
		},
	}
	updated, err := json.Marshal(definition)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := catalog.WithDefinition("dialogue.guide", updated)
	if err != nil {
		t.Fatal(err)
	}
	entryAction, err := BuildDialoguePreview(
		candidate,
		DialoguePreviewOptions{DialogueID: "dialogue.guide"},
	)
	if err != nil {
		t.Fatal(err)
	}
	if entryAction.Quest == nil ||
		entryAction.Quest.ID != "quest.slime_patrol" ||
		!entryAction.StartQuestOnOpen {
		t.Fatalf("entry-action dialogue = %#v", entryAction)
	}
	actor, err := BuildEntityPreview(
		candidate,
		EntityPreviewOptions{
			ActorID:  "actor.guide",
			EntityID: "maker.preview.entry-guide",
			X:        480,
			Y:        270,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if actor.Entity.StartQuestID != "quest.slime_patrol" ||
		actor.Quest == nil ||
		actor.Quest.ID != "quest.slime_patrol" {
		t.Fatalf("entry-action actor = %#v", actor)
	}
}

func TestBuildAndEntityPreviewShareInstanceTranslator(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	raw, ok := catalog.Definition("stage.rpg_village")
	if !ok {
		t.Fatal("stage definition missing")
	}
	var stage map[string]any
	if err := json.Unmarshal(raw, &stage); err != nil {
		t.Fatal(err)
	}
	for _, rawSpawn := range stage["spawns"].([]any) {
		spawn := rawSpawn.(map[string]any)
		if spawn["id"] != "quest.slime.1" {
			continue
		}
		spawn["name"] = "Stage Preview Boss"
		spawn["tags"] = []any{"boss"}
		spawn["components"] = map[string]any{
			"action.health": map[string]any{"max": float64(333)},
		}
	}
	updated, err := json.Marshal(stage)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := catalog.WithDefinition("stage.rpg_village", updated)
	if err != nil {
		t.Fatal(err)
	}
	built, err := Build(candidate, Options{})
	if err != nil {
		t.Fatal(err)
	}
	var entity sim.EntityConfig
	for _, candidate := range built.Config.Entities {
		if candidate.ID == "quest.slime.1" {
			entity = candidate
			break
		}
	}
	if entity.Name != "Stage Preview Boss" || entity.MaxHealth != 333 {
		t.Fatalf("stage instance override = %#v", entity)
	}
	metadata, ok := built.Presentation.Instance("quest.slime.1")
	if !ok || !reflect.DeepEqual(metadata.Tags, []string{"boss", "enemy"}) {
		t.Fatalf("stage instance metadata = %#v, found=%v", metadata, ok)
	}
}

func TestPreviewBuildersRejectInvalidBoundaryInputs(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	if _, err := BuildEntityPreview(
		nil,
		EntityPreviewOptions{},
	); err == nil {
		t.Fatal("nil catalog entity preview succeeded")
	}
	if _, err := BuildDialoguePreview(
		nil,
		DialoguePreviewOptions{},
	); err == nil {
		t.Fatal("nil catalog dialogue preview succeeded")
	}
	for name, options := range map[string]EntityPreviewOptions{
		"missing actor": {
			EntityID: "preview",
		},
		"missing entity": {
			ActorID: "actor.slime",
		},
		"unknown actor": {
			ActorID:  "actor.missing",
			EntityID: "preview",
		},
		"non-finite position": {
			ActorID:  "actor.slime",
			EntityID: "preview",
			X:        math.NaN(),
		},
		"non-object override": {
			ActorID:  "actor.slime",
			EntityID: "preview",
			Components: map[string]json.RawMessage{
				"action.health": json.RawMessage(`42`),
			},
		},
	} {
		options := options
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if _, err := BuildEntityPreview(catalog, options); err == nil {
				t.Fatalf("BuildEntityPreview(%#v) succeeded", options)
			}
		})
	}
	if _, err := BuildDialoguePreview(
		catalog,
		DialoguePreviewOptions{},
	); err == nil {
		t.Fatal("empty dialogue ID succeeded")
	}
	if _, err := BuildDialoguePreview(
		catalog,
		DialoguePreviewOptions{DialogueID: "dialogue.missing"},
	); err == nil {
		t.Fatal("unknown dialogue succeeded")
	}
}
