package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func validCampaignScenario() campaignScenario {
	var scenario campaignScenario
	scenario.SchemaVersion = 1
	scenario.Project = "recreate.test"
	scenario.Profile = "action-rpg"
	scenario.SaveSlot = "campaign"
	scenario.Stages.Village = "stage.village"
	scenario.Stages.Home = "stage.home"
	scenario.Stages.Shop = "stage.shop"
	scenario.Stages.Field = "stage.field"
	scenario.Stages.Grove = "stage.grove"
	scenario.Entities.Guide = "guide"
	scenario.Entities.Merchant = "merchant"
	scenario.Entities.FieldEnemies = []string{"slime.1", "slime.2"}
	scenario.Entities.WorldItem = "world_item.potion"
	scenario.Entities.Guardian = "guardian"
	scenario.Content.Quest = "quest.guardian"
	scenario.Content.Equipment = "item.sword"
	scenario.Content.Potion = "item.potion"
	scenario.EquipmentSlot = "weapon"
	return scenario
}

func TestValidateCampaignScenarioRequiresCompleteRoute(t *testing.T) {
	scenario := validCampaignScenario()
	if err := validateCampaignScenario(scenario); err != nil {
		t.Fatal(err)
	}

	scenario.Entities.FieldEnemies = []string{"slime.1"}
	err := validateCampaignScenario(scenario)
	if err == nil || !strings.Contains(err.Error(), "two IDs") {
		t.Fatalf("expected route cardinality error, got %v", err)
	}
}

func TestLoadCampaignScenarioRejectsUnknownFields(t *testing.T) {
	project := t.TempDir()
	path := filepath.Join(project, "campaign.json")
	data := []byte(`{
  "schema_version": 1,
  "project": "recreate.test",
  "profile": "action-rpg",
  "save_slot": "campaign",
  "stages": {
    "village": "stage.village",
    "home": "stage.home",
    "shop": "stage.shop",
    "field": "stage.field",
    "grove": "stage.grove"
  },
  "entities": {
    "guide": "guide",
    "merchant": "merchant",
    "field_enemies": ["slime.1", "slime.2"],
    "world_item": "world_item.potion",
    "guardian": "guardian"
  },
  "content": {
    "quest": "quest.guardian",
    "equipment": "item.sword",
    "potion": "item.potion"
  },
  "equipment_slot": "weapon",
  "endingg": "typo"
}`)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}

	_, err := loadCampaignScenario(project, "campaign.json")
	if err == nil || !strings.Contains(err.Error(), "endingg") {
		t.Fatalf("expected strict campaign field error, got %v", err)
	}
}

func TestCampaignPortalCenterUsesInspectedAuthoredGeometry(t *testing.T) {
	var snapshot worldSnapshot
	snapshot.Stage.ID = "stage.test"
	snapshot.Navigation.Portals = []navigationPortalState{
		{
			ID: "rectangle",
			Shape: navigationShapeState{
				Type:   "rectangle",
				X:      240,
				Y:      400,
				Width:  96,
				Height: 32,
			},
		},
		{
			ID: "polygon",
			Shape: navigationShapeState{
				Type: "polygon",
				Points: []navigationPointState{
					{X: 10, Y: 20},
					{X: 40, Y: 20},
					{X: 25, Y: 50},
				},
			},
		},
	}
	snapshot.Navigation.Triggers = []navigationTriggerState{
		{
			ID: "rest_area",
			Shape: navigationShapeState{
				Type:   "rectangle",
				X:      144,
				Y:      144,
				Width:  160,
				Height: 96,
			},
		},
	}

	x, y, err := campaignPortalCenter(snapshot, "rectangle")
	if err != nil || x != 240 || y != 400 {
		t.Fatalf("rectangle center = (%v, %v), %v", x, y, err)
	}
	x, y, err = campaignPortalCenter(snapshot, "polygon")
	if err != nil || x != 25 || y != 30 {
		t.Fatalf("polygon center = (%v, %v), %v", x, y, err)
	}
	if _, _, err := campaignPortalCenter(snapshot, "missing"); err == nil ||
		!strings.Contains(err.Error(), "stage.test") {
		t.Fatalf("missing portal error = %v", err)
	}
	x, y, err = campaignTriggerCenter(snapshot, "rest_area")
	if err != nil || x != 144 || y != 144 {
		t.Fatalf("trigger center = (%v, %v), %v", x, y, err)
	}
}
