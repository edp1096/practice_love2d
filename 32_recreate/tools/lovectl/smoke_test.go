package main

import (
	"strings"
	"testing"
)

func validSmokeScenario(profile string) smokeScenario {
	scenario := smokeScenario{
		SchemaVersion: 1,
		Profile:       profile,
		Stage:         "stage.start",
		PlayerTag:     "player",
		Movement: smokeMovement{
			Action:       "move_right",
			Frames:       10,
			MinimumDelta: 1,
		},
	}
	if profile == "action" || profile == "action-rpg" {
		scenario.Combat = &smokeCombat{
			TargetTag:     "enemy",
			Action:        "attack",
			Frames:        20,
			MinimumDamage: 1,
		}
	}
	if profile == "rpg" || profile == "action-rpg" {
		scenario.Interaction = &smokeInteraction{
			TargetTag:    "npc",
			Action:       "interact",
			Frames:       2,
			ExpectedFlag: "smoke.done",
		}
		scenario.Persistence = &smokePersistence{Item: "item.potion"}
	}
	return scenario
}

func TestSmokeScenarioRequiresProfileCapabilities(t *testing.T) {
	for _, profile := range []string{"rpg", "action-rpg", "action"} {
		if err := validateSmokeScenario(
			validSmokeScenario(profile),
		); err != nil {
			t.Fatalf("%s: %v", profile, err)
		}
	}
	action := validSmokeScenario("action")
	action.Combat = nil
	if err := validateSmokeScenario(action); err == nil ||
		!strings.Contains(err.Error(), "requires combat") {
		t.Fatalf("expected combat requirement, got %v", err)
	}
	rpg := validSmokeScenario("rpg")
	rpg.Persistence = nil
	if err := validateSmokeScenario(rpg); err == nil ||
		!strings.Contains(err.Error(), "requires persistence") {
		t.Fatalf("expected persistence requirement, got %v", err)
	}
	rpg = validSmokeScenario("rpg")
	rpg.Interaction.ExpectedFlag = ""
	rpg.Interaction.ExpectedDialogue = "dialogue.guide"
	if err := validateSmokeScenario(rpg); err != nil {
		t.Fatalf("dialogue expectation should be valid: %v", err)
	}
	rpg.Interaction.ExpectedDialogue = ""
	if err := validateSmokeScenario(rpg); err == nil ||
		!strings.Contains(err.Error(), "expected_flag") {
		t.Fatalf("expected interaction assertion requirement, got %v", err)
	}
}

func TestStrictJSONRejectsUnknownFieldsAndTrailingValues(t *testing.T) {
	var scenario smokeScenario
	if err := decodeStrictJSON([]byte(
		`{"schema_version":1,"profile":"action",`+
			`"stage":"stage.start","player_tag":"player",`+
			`"movement":{"action":"right","frames":1,`+
			`"minimum_delta":1},"unknown":true}`,
	), &scenario); err == nil {
		t.Fatal("expected unknown field error")
	}
	if err := decodeStrictJSON(
		[]byte(`{"schema_version":1} {"schema_version":1}`),
		&scenario,
	); err == nil {
		t.Fatal("expected trailing JSON error")
	}
}

func TestSmokeJourneyRequiresBoundedStepsAndFinalFlow(t *testing.T) {
	scenario := validSmokeScenario("action")
	scenario.Journey = &smokeJourney{
		Steps: []smokeJourneyStep{
			{
				TargetTag: "enemy",
				Action:    "attack",
				Frames:    24,
				Repeat:    3,
			},
		},
		ExpectedFlow:      "ending",
		ExpectedEncounter: "training",
	}
	if err := validateSmokeScenario(scenario); err != nil {
		t.Fatal(err)
	}
	scenario.Journey.Steps[0].Repeat = 21
	if err := validateSmokeScenario(scenario); err == nil ||
		!strings.Contains(err.Error(), "repeat") {
		t.Fatalf("expected repeat limit, got %v", err)
	}
	scenario.Journey.Steps[0].Repeat = 1
	scenario.Journey.ExpectedFlow = "credits"
	if err := validateSmokeScenario(scenario); err == nil ||
		!strings.Contains(err.Error(), "expected_flow") {
		t.Fatalf("expected flow validation, got %v", err)
	}
}
