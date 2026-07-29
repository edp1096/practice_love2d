package gamebuild

import (
	"encoding/json"
	"reflect"
	"slices"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestBuildCampaignConfigTranslatesCompleteCatalog(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	got, err := BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if err := got.Validate(); err != nil {
		t.Fatalf("Config.Validate() error = %v", err)
	}
	if got.ProjectID != "recreate.maker_runtime" ||
		got.DefaultLocale != "locale.ko" ||
		got.InitialStageID != "stage.village" ||
		got.InitialEntrySpawnID != "default" {
		t.Fatalf("manifest translation = %#v", got)
	}
	if !strings.HasPrefix(got.ContentID, "sha256:") ||
		len(got.ContentID) != len("sha256:")+64 {
		t.Fatalf("content id = %q, want sha256 fingerprint", got.ContentID)
	}
	if want := []string{"locale.en", "locale.ko"}; !slices.Equal(
		got.Locales,
		want,
	) {
		t.Fatalf("locales = %q, want %q", got.Locales, want)
	}

	if len(got.Stages) != 7 {
		t.Fatalf("stages = %d, want 7: %#v", len(got.Stages), got.Stages)
	}
	assertCampaignStage(t, got, "stage.village", "default", "field_return")
	assertCampaignStage(
		t,
		got,
		"stage.world_hub",
		"default",
		"grove_return",
		"village_entry",
	)
	assertCampaignStage(t, got, "stage.world_grove", "west_entry")

	potion := campaignItem(t, got, "item.potion")
	if potion.MaxQuantity != 10 || potion.EquipmentSlot != "" {
		t.Fatalf("potion = %#v", potion)
	}
	sword := campaignItem(t, got, "item.training_sword")
	if sword.MaxQuantity != 1 || sword.EquipmentSlot != "weapon" {
		t.Fatalf("training sword = %#v", sword)
	}
	vest := campaignItem(t, got, "item.leather_vest")
	if vest.MaxQuantity != 1 || vest.EquipmentSlot != "armor" {
		t.Fatalf("leather vest = %#v", vest)
	}
	boots := campaignItem(t, got, "item.traveler_boots")
	if boots.MaxQuantity != 1 || boots.EquipmentSlot != "accessory" {
		t.Fatalf("traveler boots = %#v", boots)
	}
	if want := []string{"accessory", "armor", "weapon"}; !slices.Equal(
		got.EquipmentSlots,
		want,
	) {
		t.Fatalf(
			"equipment slots = %q, want %q",
			got.EquipmentSlots,
			want,
		)
	}

	grove := campaignQuest(t, got, "quest.grove_guardian")
	if grove.InitiallyActive {
		t.Fatal("grove quest unexpectedly starts active")
	}
	if len(grove.Objectives) != 2 {
		t.Fatalf("grove objectives = %#v", grove.Objectives)
	}
	assertCampaignObjective(t, grove, "defeat_slimes", 2)
	assertCampaignObjective(t, grove, "defeat_guardian", 1)
	if want := []string{
		"quest.grove_guardian.rewarded",
		"quest.slime_patrol.rewarded",
	}; !slices.Equal(got.Flags, want) {
		t.Fatalf("flags = %q, want %q", got.Flags, want)
	}

	again, err := BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(again, got) {
		t.Fatalf("same catalog produced different configs\nfirst: %#v\nagain: %#v",
			got, again)
	}
}

func TestBuildCampaignConfigPromotesControlledFixtureSpawnToDefault(
	t *testing.T,
) {
	t.Parallel()

	got, err := BuildCampaignConfig(loadCatalog(t))
	if err != nil {
		t.Fatal(err)
	}
	// These old showcase stages have no named spawn_points. Their single
	// authored control.player placement is promoted to the identity "default";
	// no synthetic coordinates are introduced by campaign configuration.
	for _, id := range []string{
		"stage.action_room",
		"stage.encounter_room",
		"stage.platformer_room",
	} {
		assertCampaignStage(t, got, id, "default")
	}
}

func TestBuildCampaignConfigCanonicalizesDefinitionLocalOrder(t *testing.T) {
	t.Parallel()

	baseCatalog := loadCatalog(t)
	base, err := BuildCampaignConfig(baseCatalog)
	if err != nil {
		t.Fatal(err)
	}

	reordered := mutateCampaignDefinition(
		t,
		baseCatalog,
		"quest.grove_guardian",
		func(data map[string]any) {
			slices.Reverse(data["objectives"].([]any))
		},
	)
	reordered = mutateCampaignDefinition(
		t,
		reordered,
		"stage.world_hub",
		func(data map[string]any) {
			slices.Reverse(data["spawn_points"].([]any))
		},
	)
	got, err := BuildCampaignConfig(reordered)
	if err != nil {
		t.Fatal(err)
	}
	if got.ContentID == base.ContentID {
		t.Fatal("distinct canonical catalog revisions share a fingerprint")
	}

	// Authored list order is retained in the content revision fingerprint, but
	// it cannot leak into durable campaign topology ordering.
	base.ContentID = ""
	got.ContentID = ""
	if !reflect.DeepEqual(got, base) {
		t.Fatalf("authored order changed campaign topology\nbase: %#v\ngot:  %#v",
			base, got)
	}
}

func TestBuildCampaignConfigDeduplicatesEquipmentSlots(t *testing.T) {
	t.Parallel()

	catalog := mutateCampaignDefinition(
		t,
		loadCatalog(t),
		"item.potion",
		func(data map[string]any) {
			data["equipment"] = map[string]any{
				"slot": "weapon",
				"modifiers": map[string]any{
					"attack": float64(1),
				},
			}
		},
	)
	got, err := BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"accessory", "armor", "weapon"}; !slices.Equal(
		got.EquipmentSlots,
		want,
	) {
		t.Fatalf(
			"equipment slots = %q, want deduplicated %q",
			got.EquipmentSlots,
			want,
		)
	}
}

func TestBuildCampaignConfigRejectsIncompleteDurableDefinitions(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name     string
		id       string
		mutate   func(map[string]any)
		contains string
	}{
		{
			name: "missing item stack limit",
			id:   "item.potion",
			mutate: func(data map[string]any) {
				delete(data, "stack_limit")
			},
			contains: "requires stack_limit",
		},
		{
			name: "missing objective count",
			id:   "quest.grove_guardian",
			mutate: func(data map[string]any) {
				objectives := data["objectives"].([]any)
				delete(objectives[0].(map[string]any), "count")
			},
			contains: "requires count",
		},
		{
			name: "invalid initially active",
			id:   "quest.grove_guardian",
			mutate: func(data map[string]any) {
				data["initially_active"] = "yes"
			},
			contains: "initially_active",
		},
		{
			name: "fixture without controlled player",
			id:   "stage.action_room",
			mutate: func(data map[string]any) {
				spawns := data["spawns"].([]any)
				spawns[0].(map[string]any)["actor"] = "actor.slime"
			},
			contains: "exactly one authored controlled player spawn",
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := mutateCampaignDefinition(
				t,
				loadCatalog(t),
				test.id,
				test.mutate,
			)
			if _, err := BuildCampaignConfig(catalog); err == nil ||
				!strings.Contains(err.Error(), test.contains) {
				t.Fatalf(
					"BuildCampaignConfig() error = %v, want %q",
					err,
					test.contains,
				)
			}
		})
	}
}

func TestBuildCampaignConfigRequiresExplicitManifestAndPortalEntries(
	t *testing.T,
) {
	t.Parallel()

	t.Run("manifest", func(t *testing.T) {
		catalog := loadCatalog(t)
		catalog.Manifest.Flow.StartSpawn = "missing"
		if _, err := BuildCampaignConfig(catalog); err == nil ||
			!strings.Contains(err.Error(), "start_spawn") {
			t.Fatalf(
				"BuildCampaignConfig() error = %v, want start_spawn error",
				err,
			)
		}
	})

	t.Run("portal", func(t *testing.T) {
		catalog := mutateCampaignDefinition(
			t,
			loadCatalog(t),
			"stage.world_hub",
			func(data map[string]any) {
				points := data["spawn_points"].([]any)
				filtered := make([]any, 0, len(points)-1)
				for _, raw := range points {
					point := raw.(map[string]any)
					if point["id"] != "village_entry" {
						filtered = append(filtered, point)
					}
				}
				data["spawn_points"] = filtered
			},
		)
		if _, err := BuildCampaignConfig(catalog); err == nil ||
			!strings.Contains(err.Error(), "target_spawn") {
			t.Fatalf(
				"BuildCampaignConfig() error = %v, want target_spawn error",
				err,
			)
		}
	})
}

func mutateCampaignDefinition(
	t *testing.T,
	catalog *content.Catalog,
	id string,
	mutate func(map[string]any),
) *content.Catalog {
	t.Helper()
	raw, exists := catalog.Definition(id)
	if !exists {
		t.Fatalf("definition %q not found", id)
	}
	var data map[string]any
	if err := json.Unmarshal(raw, &data); err != nil {
		t.Fatal(err)
	}
	mutate(data)
	updated, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := catalog.WithDefinition(id, updated)
	if err != nil {
		t.Fatalf("WithDefinition(%q) error = %v", id, err)
	}
	return candidate
}

func assertCampaignStage(
	t *testing.T,
	config campaign.Config,
	id string,
	want ...string,
) {
	t.Helper()
	for _, stage := range config.Stages {
		if stage.ID != id {
			continue
		}
		if !slices.Equal(stage.EntrySpawns, want) {
			t.Fatalf(
				"stage %q entries = %q, want %q",
				id,
				stage.EntrySpawns,
				want,
			)
		}
		return
	}
	t.Fatalf("stage %q not found", id)
}

func campaignItem(
	t *testing.T,
	config campaign.Config,
	id string,
) campaign.ItemDefinition {
	t.Helper()
	for _, item := range config.Items {
		if item.ID == id {
			return item
		}
	}
	t.Fatalf("item %q not found", id)
	return campaign.ItemDefinition{}
}

func campaignQuest(
	t *testing.T,
	config campaign.Config,
	id string,
) campaign.QuestDefinition {
	t.Helper()
	for _, quest := range config.Quests {
		if quest.ID == id {
			return quest
		}
	}
	t.Fatalf("quest %q not found", id)
	return campaign.QuestDefinition{}
}

func assertCampaignObjective(
	t *testing.T,
	quest campaign.QuestDefinition,
	id string,
	required int64,
) {
	t.Helper()
	for _, objective := range quest.Objectives {
		if objective.ID == id {
			if objective.Required != required {
				t.Fatalf(
					"quest %q objective %q required = %d, want %d",
					quest.ID,
					id,
					objective.Required,
					required,
				)
			}
			return
		}
	}
	t.Fatalf("quest %q objective %q not found", quest.ID, id)
}
