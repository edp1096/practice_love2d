package projectcheck

import (
	"bytes"
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func TestValidateChecksEveryStageEntryAndLocaleDeterministically(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadProjectCatalog(t)
	got, err := Validate(catalog)
	if err != nil {
		t.Fatal(err)
	}
	want := Report{
		DefinitionCount: 44,
		StageCount:      7,
		EntryBuildCount: 22,
		LocaleCount:     2,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("report = %#v, want %#v", got, want)
	}

	again, err := Validate(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(again, got) {
		t.Fatalf("report changed between runs: %#v then %#v", got, again)
	}
}

func TestValidateRejectsLongDurableIdentifiers(t *testing.T) {
	t.Parallel()

	longID := strings.Repeat("x", 129)
	tests := []struct {
		name       string
		definition string
		mutate     func(map[string]any)
		want       string
	}{
		{
			name:       "flag",
			definition: "quest.grove_guardian",
			mutate: func(data map[string]any) {
				actions := data["on_complete"].([]any)
				actions[2].(map[string]any)["name"] = longID
			},
			want: "flag",
		},
		{
			name:       "equipment slot",
			definition: "item.training_sword",
			mutate: func(data map[string]any) {
				equipment := data["equipment"].(map[string]any)
				equipment["slot"] = longID
			},
			want: "equipment slot",
		},
		{
			name:       "objective",
			definition: "quest.grove_guardian",
			mutate: func(data map[string]any) {
				objectives := data["objectives"].([]any)
				objectives[0].(map[string]any)["id"] = longID
			},
			want: "objective id",
		},
		{
			name:       "entry spawn",
			definition: "stage.rpg_village",
			mutate: func(data map[string]any) {
				spawns := data["spawn_points"].([]any)
				spawns[1].(map[string]any)["id"] = longID
			},
			want: "entry spawn",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := mutateProjectDefinition(
				t,
				loadProjectCatalog(t),
				test.definition,
				test.mutate,
			)
			_, err := Validate(catalog)
			assertProjectError(
				t,
				err,
				`project "recreate.maker_runtime"`,
				"campaign topology",
				test.want,
			)
		})
	}
}

func TestValidateRejectsCatalogAndManifestReferenceFailures(t *testing.T) {
	t.Parallel()

	t.Run("catalog envelope", func(t *testing.T) {
		t.Parallel()
		catalog := loadProjectCatalog(t)
		catalog.DependencyGraph.Total++
		_, err := Validate(catalog)
		assertProjectError(
			t,
			err,
			`project "recreate.maker_runtime"`,
			"catalog",
			"catalog totals disagree",
		)
	})

	t.Run("manifest reference", func(t *testing.T) {
		t.Parallel()
		catalog := loadProjectCatalog(t)
		catalog.Manifest.Flow.StartSpawn = "missing"
		_, err := Validate(catalog)
		assertProjectError(
			t,
			err,
			`project "recreate.maker_runtime"`,
			"manifest references",
			"game/game.lua.flow.start_spawn",
			`missing spawn point "missing"`,
		)
	})
}

func TestValidateChecksSemanticValidityOfEveryDefinition(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"status.enraged",
		func(data map[string]any) {
			// status.enraged is the final canonical definition. Checking it
			// prevents a current-stage-only or early-exit validation loop.
			data["duration"] = json.Number("0")
		},
	)
	_, err := Validate(catalog)
	assertProjectError(
		t,
		err,
		`definition "status.enraged"`,
		`from "game/content/statuses/enraged.lua"`,
		"status.enraged.duration must be positive",
	)
}

func TestValidateRejectsMalformedGeometryInLaterStage(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"stage.world_grove",
		func(data map[string]any) {
			walls := data["walls"].([]any)
			shape := walls[len(walls)-1].(map[string]any)["shape"].(map[string]any)
			points := shape["points"].([]any)
			points[len(points)-1] = cloneJSONValue(t, points[0])
		},
	)
	_, err := Validate(catalog)
	assertProjectError(
		t,
		err,
		`project "recreate.maker_runtime"`,
		`stage "stage.world_grove"`,
		`from "game/content/stages/generated/world_grove.lua"`,
		`entry "west_entry"`,
		`locale "locale.en"`,
		"polygon repeats point",
	)
}

func TestValidateRejectsCampaignRulesTopologyMismatch(t *testing.T) {
	t.Parallel()

	base := loadProjectCatalog(t)
	staleRules, err := gamebuild.BuildContentRules(base)
	if err != nil {
		t.Fatal(err)
	}
	candidate := mutateProjectDefinition(
		t,
		base,
		"item.potion",
		func(data map[string]any) {
			data["stack_limit"] = json.Number("9")
		},
	)

	deps := productionDependencies
	deps.buildContentRules = func(
		*content.Catalog,
	) (gamebuild.ContentRules, error) {
		// Model a stale or independently changed rule compiler result. The
		// project validator must compare it with the freshly translated
		// campaign topology instead of accepting both in isolation.
		return staleRules, nil
	}
	_, err = validate(candidate, deps)
	assertProjectError(
		t,
		err,
		`project "recreate.maker_runtime"`,
		"campaign/rules topology",
		`item "item.potion" stack limit 10`,
		"campaign maximum 9",
	)
}

func TestValidateRejectsNilCatalog(t *testing.T) {
	t.Parallel()

	_, err := Validate(nil)
	assertProjectError(t, err, "catalog is nil")
}

func loadProjectCatalog(t *testing.T) *content.Catalog {
	t.Helper()
	catalog, err := content.LoadBytes(gamecatalog.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	return catalog
}

func mutateProjectDefinition(
	t *testing.T,
	catalog *content.Catalog,
	id string,
	mutate func(map[string]any),
) *content.Catalog {
	t.Helper()
	raw, exists := catalog.Definition(id)
	if !exists {
		t.Fatalf("definition %q is missing", id)
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var data map[string]any
	if err := decoder.Decode(&data); err != nil {
		t.Fatal(err)
	}
	mutate(data)
	updated, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	result, err := catalog.WithDefinition(id, updated)
	if err != nil {
		t.Fatalf("mutate definition %q: %v", id, err)
	}
	return result
}

func cloneJSONValue(t *testing.T, value any) any {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	var result any
	if err := decoder.Decode(&result); err != nil {
		t.Fatal(err)
	}
	return result
}

func assertProjectError(t *testing.T, err error, fragments ...string) {
	t.Helper()
	if err == nil {
		t.Fatal("Validate() error = nil")
	}
	for _, fragment := range fragments {
		if !strings.Contains(err.Error(), fragment) {
			t.Fatalf(
				"Validate() error = %q, want fragment %q",
				err,
				fragment,
			)
		}
	}
}
