package gamebuild

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func loadCatalog(t *testing.T) *content.Catalog {
	t.Helper()
	path := filepath.Join("..", "..", "game", "catalog.json")
	catalog, err := content.LoadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return catalog
}

func TestBuildUsesAuthoredActionRPGContent(t *testing.T) {
	t.Parallel()

	result, err := Build(loadCatalog(t), Options{})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := result.Presentation.StageID, "stage.rpg_village"; got != want {
		t.Fatalf("stage = %q, want %q", got, want)
	}
	if got, want := len(result.Config.Entities), 5; got != want {
		t.Fatalf("entities = %d, want %d", got, want)
	}
	if got, want := len(result.Config.Walls), 5; got != want {
		t.Fatalf("walls = %d, want %d", got, want)
	}
	var north *sim.Wall
	for index := range result.Config.Walls {
		if result.Config.Walls[index].ID == "north" {
			north = &result.Config.Walls[index]
			break
		}
	}
	if north == nil || north.Rect.MaxY-north.Rect.MinY != pixels(32) {
		t.Fatalf("north wall = %#v", north)
	}
	var hero sim.EntityConfig
	slimeCount := 0
	foundGuide, foundMerchant := false, false
	for _, entity := range result.Config.Entities {
		switch entity.Kind {
		case "actor.hero":
			hero = entity
		case "actor.slime":
			slimeCount++
		case "actor.guide":
			foundGuide = true
		case "actor.merchant":
			foundMerchant = true
		}
	}
	if !hero.Controlled || hero.MaxHealth != 100 {
		t.Fatalf("hero = %#v", hero)
	}
	if got, want := hero.MovePerTick, rateToCoord(190); got != want {
		t.Fatalf("hero speed = %d, want %d", got, want)
	}
	if hero.Ability == nil ||
		hero.Ability.ID != "ability.sword_slash" ||
		hero.Ability.Damage != 34 {
		t.Fatalf("hero ability = %#v", hero.Ability)
	}
	if hero.Parry == nil || hero.Dodge == nil {
		t.Fatal("hero parry/dodge were not authored")
	}
	if slimeCount != 2 || !foundGuide || !foundMerchant {
		t.Fatalf(
			"slimes=%d guide=%v merchant=%v",
			slimeCount,
			foundGuide,
			foundMerchant,
		)
	}
	if got, want := result.Config.Camera.ViewportWidth, pixels(800); got != want {
		t.Fatalf("camera width = %d, want %d", got, want)
	}
	if got, want := result.Config.Camera.TargetEntityID, "player"; got != want {
		t.Fatalf("camera target = %q, want %q", got, want)
	}
	if len(result.Config.Dialogues) != 1 ||
		result.Config.Dialogues[0].ID != "dialogue.guide" ||
		result.Config.Dialogues[0].Text == "" {
		t.Fatalf("dialogues = %#v", result.Config.Dialogues)
	}
	if len(result.Config.Quests) != 1 ||
		result.Config.Quests[0].ID != "quest.slime_patrol" ||
		result.Config.Quests[0].Required != 2 {
		t.Fatalf("quests = %#v", result.Config.Quests)
	}
	if metadata, ok := result.Presentation.Instance("player"); !ok ||
		metadata.SpriteID != "sprite.hero" ||
		metadata.PrimaryAbility != "ability.sword_slash" ||
		!metadata.Controlled {
		t.Fatalf("player metadata = %#v, %v", metadata, ok)
	}
	if metadata, ok := result.Presentation.Instance("quest.slime.1"); !ok ||
		metadata.PrimaryAbility != "ability.slime_bump" ||
		metadata.Chase == nil ||
		metadata.Chase.TargetTag != "player" ||
		metadata.Chase.AggroRange != 360 ||
		metadata.Chase.AttackDistance != 38 {
		t.Fatalf("slime metadata = %#v, %v", metadata, ok)
	}
	if _, err := sim.New(result.Config); err != nil {
		t.Fatalf("translated config is not runnable: %v", err)
	}
}

func TestBuildReflectsCatalogMutation(t *testing.T) {
	t.Parallel()

	data, err := os.ReadFile(filepath.Join("..", "..", "game", "catalog.json"))
	if err != nil {
		t.Fatal(err)
	}
	catalog, err := content.LoadBytes(data)
	if err != nil {
		t.Fatal(err)
	}
	for index := range catalog.Definitions {
		if catalog.Definitions[index].Data["id"] != "ability.sword_slash" {
			continue
		}
		effects := catalog.Definitions[index].Data["effects"].([]any)
		effects[0].(map[string]any)["amount"] = float64(41)
		break
	}
	result, err := Build(catalog, Options{})
	if err != nil {
		t.Fatal(err)
	}
	for _, entity := range result.Config.Entities {
		if entity.Kind == "actor.hero" {
			if entity.Ability == nil || entity.Ability.Damage != 41 {
				t.Fatalf("mutated damage was not translated: %#v", entity.Ability)
			}
			return
		}
	}
	t.Fatal("hero not found")
}

func TestSecondsToTicksUsesNearestNonzeroTick(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		seconds float64
		want    int
	}{
		{0, 0},
		{0.001, 1},
		{0.05, 3},
		{0.12, 7},
		{0.18, 11},
	} {
		if got := secondsToTicks(test.seconds); got != test.want {
			t.Errorf("secondsToTicks(%v) = %d, want %d",
				test.seconds, got, test.want)
		}
	}
}

func TestValidateDefinitionSeparatesSchemaFromRuntimeCoverage(t *testing.T) {
	t.Parallel()
	catalog := loadCatalog(t)

	slime, err := ValidateDefinition(catalog, "ability.slime_bump")
	if err != nil {
		t.Fatal(err)
	}
	if !slime.SchemaValid || !slime.FullyApplied ||
		len(slime.Warnings) != 0 {
		t.Fatalf("slime validation = %#v", slime)
	}
	fireBolt, err := ValidateDefinition(catalog, "ability.fire_bolt")
	if err != nil {
		t.Fatal(err)
	}
	if !fireBolt.SchemaValid || fireBolt.FullyApplied ||
		len(fireBolt.Warnings) == 0 {
		t.Fatalf("fire bolt validation = %#v", fireBolt)
	}

	raw, ok := catalog.Definition("ability.fire_bolt")
	if !ok {
		t.Fatal("fire bolt definition missing")
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	draft["duration"] = float64(-999)
	invalidRaw, err := json.Marshal(draft)
	if err != nil {
		t.Fatal(err)
	}
	invalid, err := catalog.WithDefinition("ability.fire_bolt", invalidRaw)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ValidateDefinition(invalid, "ability.fire_bolt"); err == nil {
		t.Fatal("negative duration passed semantic validation")
	}
}
