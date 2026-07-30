package gamebuild

import "testing"

func TestVillageArrivalCutsceneCompilesAsFullyAppliedTypedContent(
	t *testing.T,
) {
	catalog := loadCatalog(t)
	validation, err := ValidateDefinition(
		catalog,
		"cutscene.village_arrival",
	)
	if err != nil {
		t.Fatal(err)
	}
	if !validation.SchemaValid || !validation.FullyApplied ||
		validation.Kind != "cutscene" {
		t.Fatalf("cutscene validation = %#v", validation)
	}

	rules, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	cutscene, exists := rules.Cutscene("cutscene.village_arrival")
	if !exists || !cutscene.Skippable ||
		len(cutscene.Steps) != 2 ||
		cutscene.Steps[0].ID != "threat" ||
		cutscene.Steps[1].SpeakerKey != "npc.village_guide.name" ||
		len(cutscene.OnComplete) != 2 ||
		cutscene.OnComplete[0].Type != RuleActionSetFlag ||
		cutscene.OnComplete[0].FlagName !=
			"story.village_arrival_seen" ||
		cutscene.OnComplete[1].Type != RuleActionShowNotice {
		t.Fatalf("compiled cutscene = %#v, exists=%v", cutscene, exists)
	}

	built, err := Build(catalog, Options{
		StageID:  "stage.village",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(built.Stage.Triggers) == 0 {
		t.Fatal("village has no intro trigger")
	}
	intro := built.Stage.Triggers[0]
	if intro.Condition == nil ||
		intro.Condition.Type != RuleConditionNot ||
		intro.Condition.Condition == nil ||
		intro.Condition.Condition.Type != RuleConditionFlag ||
		intro.Condition.Condition.FlagName !=
			"story.village_arrival_seen" ||
		len(intro.Actions) != 1 ||
		intro.Actions[0].Type != RuleActionStartCutscene ||
		intro.Actions[0].CutsceneID != "cutscene.village_arrival" {
		t.Fatalf("compiled intro trigger = %#v", intro)
	}
}
