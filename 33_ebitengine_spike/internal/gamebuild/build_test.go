package gamebuild

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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
	if result.Stage.ID != "stage.rpg_village" ||
		len(result.Stage.SpawnPoints) != 2 ||
		len(result.Stage.Portals) != 1 {
		t.Fatalf("stage navigation = %#v", result.Stage)
	}
	portal := result.Stage.Portals[0]
	if portal.ID != "to_field" ||
		portal.TargetStageID != "stage.world_hub" ||
		portal.TargetSpawnID != "village_entry" ||
		portal.Rect.MaxX-portal.Rect.MinX != pixels(32) ||
		portal.Rect.MaxY-portal.Rect.MinY != pixels(128) ||
		len(portal.Points) != 0 {
		t.Fatalf("portal = %#v", portal)
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
	var guide sim.EntityConfig
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
			guide = entity
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
	if hero.PrimaryAbility() == nil ||
		hero.PrimaryAbility().ID != "ability.sword_slash" ||
		hero.PrimaryAbility().Damage != 34 {
		t.Fatalf("hero combat = %#v", hero.Combat)
	}
	if hero.Combat == nil || len(hero.Combat.Abilities) != 3 ||
		hero.Combat.AbilityForInput("special") == nil ||
		hero.Combat.AbilityForInput("special").ProjectileID !=
			"projectile.fire_bolt" ||
		hero.Combat.AbilityForInput("technique") == nil ||
		hero.Combat.AbilityForInput("technique").MaxHits != 3 ||
		hero.Combat.AbilityForInput("technique").RepeatIntervalTicks !=
			secondsToTicks(0.15) {
		t.Fatalf("hero authored loadout = %#v", hero.Combat)
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
	if guide.DialogueID != "dialogue.guide" ||
		guide.StartQuestID != "" {
		t.Fatalf("guide interaction = %#v", guide)
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

func TestBuildPreservesAuthoredTilemapAndImageManifest(t *testing.T) {
	t.Parallel()

	result, err := Build(loadCatalog(t), Options{
		StageID:  "stage.world_hub",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Presentation.Images) != 6 {
		t.Fatalf(
			"presentation images = %d, want 6",
			len(result.Presentation.Images),
		)
	}
	var world ImageAsset
	for _, asset := range result.Presentation.Images {
		if asset.ID == "image.world_tileset" {
			world = asset
			break
		}
	}
	if world.Path !=
		"assets/runtime/images/tilesets/tileset_area1.png" ||
		world.Width != 864 ||
		world.Height != 576 ||
		world.Filter != "nearest" {
		t.Fatalf("world tileset resource = %#v", world)
	}

	tilemap := result.Presentation.Tilemap
	if tilemap == nil ||
		tilemap.Source != "game/maps/world_hub.tmx" ||
		tilemap.TileWidth != 32 ||
		tilemap.TileHeight != 32 ||
		len(tilemap.Tilesets) != 1 ||
		len(tilemap.Layers) != 1 {
		t.Fatalf("world tilemap = %#v", tilemap)
	}
	tileset := tilemap.Tilesets[0]
	if tileset.ID != "world_tileset" ||
		tileset.AssetID != "image.world_tileset" ||
		tileset.FirstGID != 1 ||
		tileset.TileCount != 486 ||
		tileset.Columns != 27 ||
		tileset.TileWidth != 32 ||
		tileset.TileHeight != 32 {
		t.Fatalf("world tileset = %#v", tileset)
	}
	layer := tilemap.Layers[0]
	if layer.ID != "ground" ||
		layer.Width != 34 ||
		layer.Height != 18 ||
		!layer.Visible ||
		layer.Opacity != 1 ||
		len(layer.Data) != 34*18 ||
		layer.Data[0] != 29 {
		t.Fatalf("world ground layer = %#v", layer)
	}

	// Tile data returned by one build cannot mutate a later fresh build.
	layer.Data[0] = 0
	second, err := Build(loadCatalog(t), Options{
		StageID:  "stage.world_hub",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	if second.Presentation.Tilemap.Layers[0].Data[0] != 29 {
		t.Fatal("tilemap data leaked between independent builds")
	}
}

func TestBuildPublishesAuthoredSpriteClipsAndInstanceOverrides(t *testing.T) {
	t.Parallel()

	result, err := Build(loadCatalog(t), Options{
		StageID:  "stage.encounter_room",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Presentation.Sprites) != 4 {
		t.Fatalf(
			"presentation sprites = %d, want 4",
			len(result.Presentation.Sprites),
		)
	}
	var hero SpriteDefinition
	for _, sprite := range result.Presentation.Sprites {
		if sprite.ID == "sprite.hero" {
			hero = sprite
			break
		}
	}
	if hero.AssetID != "image.player_sheet" ||
		hero.FrameWidth != 48 ||
		hero.FrameHeight != 48 ||
		hero.OriginX != 24 ||
		hero.OriginY != 24 ||
		hero.Scale != 2 ||
		hero.DefaultClip != "idle_down" ||
		len(hero.Clips) != 12 ||
		len(hero.StateMap) != 12 {
		t.Fatalf("hero sprite = %#v", hero)
	}
	var attack SpriteClip
	for _, clip := range hero.Clips {
		if clip.ID == "attack_right" {
			attack = clip
			break
		}
	}
	if attack.FPS != 13 ||
		attack.Loop ||
		len(attack.Frames) != 4 ||
		attack.Frames[0] != (SpriteFrame{Column: 5, Row: 12}) {
		t.Fatalf("hero attack clip = %#v", attack)
	}
	if len(result.Presentation.Abilities) != 1 {
		t.Fatalf(
			"ability visuals = %#v",
			result.Presentation.Abilities,
		)
	}
	visual := result.Presentation.Abilities[0]
	if visual.AbilityID != "ability.sword_slash" ||
		visual.AssetID != "image.slash" ||
		visual.Distance != 31 ||
		visual.Scale != 1.2 ||
		visual.RotationOffset != 0 {
		t.Fatalf("sword slash visual = %#v", visual)
	}

	catalog := loadCatalog(t)
	raw, found := catalog.Definition("actor.grove_guardian")
	if !found {
		t.Fatal("guardian actor is missing")
	}
	var definition map[string]any
	if err := json.Unmarshal(raw, &definition); err != nil {
		t.Fatal(err)
	}
	components := definition["components"].(map[string]any)
	renderer := components["render.sprite"].(map[string]any)
	if renderer["scale"] != float64(4) {
		t.Fatalf("fixture renderer = %#v", renderer)
	}
	guardianResult, err := Build(catalog, Options{
		StageID:  "stage.world_grove",
		SpawnID:  "west_entry",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	metadata, found := guardianResult.Presentation.Instance(
		"boss.grove_guardian",
	)
	if !found ||
		metadata.SpriteScale != 4 ||
		!metadata.SpriteTintSet ||
		metadata.SpriteTint != ([4]float64{0.76, 0.42, 1, 1}) {
		t.Fatalf("guardian metadata = %#v, found=%v", metadata, found)
	}
}

func TestBuildAppliesNamedEntrySpawnToControlledActor(t *testing.T) {
	t.Parallel()

	result, err := Build(loadCatalog(t), Options{SpawnID: "field_return"})
	if err != nil {
		t.Fatal(err)
	}
	for _, entity := range result.Config.Entities {
		if !entity.Controlled {
			continue
		}
		if got, want := entity.Position, (sim.Vec{
			X: pixels(850),
			Y: pixels(270),
		}); got != want {
			t.Fatalf("controlled position = %#v, want %#v", got, want)
		}
		return
	}
	t.Fatal("controlled actor not found")
}

func TestBuildRejectsUnknownEntrySpawn(t *testing.T) {
	t.Parallel()

	if _, err := Build(loadCatalog(t), Options{SpawnID: "missing"}); err == nil {
		t.Fatal("unknown entry spawn was accepted")
	}
}

func TestBuildUsesAuthoredPlayerPositionForImplicitDefaultEntry(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	raw, exists := catalog.Definition("stage.rpg_village")
	if !exists {
		t.Fatal("stage.rpg_village missing")
	}
	var stage map[string]any
	if err := json.Unmarshal(raw, &stage); err != nil {
		t.Fatal(err)
	}
	delete(stage, "spawn_points")
	updated, err := json.Marshal(stage)
	if err != nil {
		t.Fatal(err)
	}
	catalog, err = catalog.WithDefinition("stage.rpg_village", updated)
	if err != nil {
		t.Fatal(err)
	}
	result, err := Build(catalog, Options{
		StageID: "stage.rpg_village",
		SpawnID: implicitEntrySpawnID,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, entity := range result.Config.Entities {
		if entity.Controlled {
			if got, want := entity.Position, (sim.Vec{
				X: pixels(150),
				Y: pixels(270),
			}); got != want {
				t.Fatalf("controlled position = %#v, want %#v", got, want)
			}
			return
		}
	}
	t.Fatal("controlled actor not found")
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
			if entity.PrimaryAbility() == nil ||
				entity.PrimaryAbility().Damage != 41 {
				t.Fatalf("mutated damage was not translated: %#v", entity.Combat)
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
		{float64(sim.MaxTickCount+1) / sim.TicksPerSecond, sim.MaxTickCount + 1},
	} {
		if got := secondsToTicks(test.seconds); got != test.want {
			t.Errorf("secondsToTicks(%v) = %d, want %d",
				test.seconds, got, test.want)
		}
	}
}

func TestBuildRejectsPortalCooldownOutsideSimulationRange(t *testing.T) {
	t.Parallel()

	catalog := mutateCampaignDefinition(
		t,
		loadCatalog(t),
		"stage.rpg_village",
		func(data map[string]any) {
			portals := data["portals"].([]any)
			portal := portals[0].(map[string]any)
			portal["cooldown"] =
				float64(sim.MaxTickCount+1) / sim.TicksPerSecond
		},
	)
	if _, err := Build(catalog, Options{}); err == nil ||
		!strings.Contains(err.Error(), "invalid portal") {
		t.Fatalf("Build error = %v, want invalid portal", err)
	}
}

func TestBuildRejectsPortalTagThatCannotSelectControlledActor(t *testing.T) {
	t.Parallel()

	catalog := mutateCampaignDefinition(
		t,
		loadCatalog(t),
		"stage.rpg_village",
		func(data map[string]any) {
			portals := data["portals"].([]any)
			portals[0].(map[string]any)["actor_tag"] = "npc"
		},
	)
	if _, err := Build(catalog, Options{}); err == nil ||
		!strings.Contains(err.Error(), "does not match controlled actor") {
		t.Fatalf(
			"Build error = %v, want controlled actor_tag mismatch",
			err,
		)
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
	if !fireBolt.SchemaValid || !fireBolt.FullyApplied ||
		len(fireBolt.Warnings) != 0 {
		t.Fatalf("fire bolt validation = %#v", fireBolt)
	}
	for _, id := range []string{
		"ability.sword_slash",
		"sprite.guide",
		"sprite.hero",
		"sprite.merchant",
		"sprite.slime",
	} {
		result, err := ValidateDefinition(catalog, id)
		if err != nil {
			t.Fatal(err)
		}
		if !result.SchemaValid || !result.FullyApplied ||
			len(result.Warnings) != 0 {
			t.Fatalf("%s presentation validation = %#v", id, result)
		}
	}
	for _, id := range []string{"projectile.fire_bolt", "status.burning"} {
		result, err := ValidateDefinition(catalog, id)
		if err != nil {
			t.Fatal(err)
		}
		if !result.SchemaValid || !result.FullyApplied ||
			len(result.Warnings) != 0 {
			t.Fatalf("%s validation = %#v", id, result)
		}
	}
	worldHub, err := ValidateDefinition(catalog, "stage.world_hub")
	if err != nil {
		t.Fatal(err)
	}
	if !worldHub.SchemaValid {
		t.Fatalf("world hub validation = %#v", worldHub)
	}
	for _, warning := range worldHub.Warnings {
		if strings.Contains(warning, `stage field "tilemap"`) ||
			strings.Contains(warning, "background color is not rendered") {
			t.Fatalf(
				"implemented tilemap/background reported unsupported: %q",
				warning,
			)
		}
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
