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
	scenario.Stages.Field = "stage.field"
	scenario.Stages.Grove = "stage.grove"
	scenario.Entities.Guide = "guide"
	scenario.Entities.Merchant = "merchant"
	scenario.Entities.FieldEnemies = []string{"slime.1", "slime.2"}
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
    "field": "stage.field",
    "grove": "stage.grove"
  },
  "entities": {
    "guide": "guide",
    "merchant": "merchant",
    "field_enemies": ["slime.1", "slime.2"],
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
