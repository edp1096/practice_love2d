package content

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"testing/fstest"
	"time"

	lua "github.com/yuin/gopher-lua"
)

func TestCompileRecreateCatalogAcceptance(t *testing.T) {
	t.Parallel()

	sourceProject := recreateProject(t)
	first, err := Compile(context.Background(), sourceProject)
	if err != nil {
		t.Fatalf("Compile first: %v", err)
	}
	second, err := Compile(context.Background(), sourceProject)
	if err != nil {
		t.Fatalf("Compile second: %v", err)
	}

	if got, want := first.DependencyGraph.Total, 56; got != want {
		t.Fatalf("definition total = %d, want %d", got, want)
	}
	if got, want := first.DependencyGraph.EdgeCount, 88; got != want {
		t.Fatalf("dependency paths = %d, want %d", got, want)
	}
	project := first.Project()
	if got, want := project.ID, "recreate.maker_runtime"; got != want {
		t.Fatalf("project id = %q, want %q", got, want)
	}
	if got, want := project.Profile, "action-rpg"; got != want {
		t.Fatalf("project profile = %q, want %q", got, want)
	}
	if got, want := project.Title, "고요한 숲의 수호자"; got != want {
		t.Fatalf("project title = %q, want %q", got, want)
	}
	if got, want := project.InitialStage, "stage.village"; got != want {
		t.Fatalf("initial stage = %q, want %q", got, want)
	}
	if got, want := project.FixedDT, 1.0/60.0; got != want {
		t.Fatalf("fixed_dt = %v, want %v", got, want)
	}
	if got, want := project.Locale, (ProjectLocale{
		Default:  "locale.ko",
		Fallback: "locale.en",
	}); got != want {
		t.Fatalf("locale = %#v, want %#v", got, want)
	}
	if got, want := project.Flow, (ProjectFlow{
		SaveSlot:   "campaign",
		StartStage: "stage.village",
		StartSpawn: "default",
		Title: ProjectFlowCopy{
			HeadingKey: "flow.title.heading",
			MessageKey: "flow.title.message",
		},
		GameOver: ProjectFlowCopy{
			HeadingKey: "flow.game_over.heading",
			MessageKey: "flow.game_over.message",
		},
		Ending: ProjectFlowCopy{
			HeadingKey: "flow.ending.heading",
			MessageKey: "flow.ending.message",
		},
	}); got != want {
		t.Fatalf("flow = %#v, want %#v", got, want)
	}
	if got, want := project.Font, (ProjectFont{
		Asset: "font.ui",
		Size:  16,
	}); got != want {
		t.Fatalf("font = %#v, want %#v", got, want)
	}
	if len(project.Input.Actions) != 20 ||
		!reflect.DeepEqual(project.Input.Actions[0], ProjectInputAction{
			ID:      "attack",
			Keys:    []string{"space", "z"},
			Buttons: []string{"x"},
		}) ||
		!reflect.DeepEqual(
			project.Input.Actions[len(project.Input.Actions)-1],
			ProjectInputAction{
				ID:      "technique",
				Keys:    []string{"q"},
				Buttons: []string{"rightshoulder"},
			},
		) {
		t.Fatalf("input = %#v", project.Input)
	}
	if project.Audio.MasterVolume != 0.8 ||
		project.Audio.MusicVolume != 0.45 ||
		project.Audio.SFXVolume != 0.8 ||
		len(project.Audio.Cues) != 9 ||
		len(project.Audio.StageMusic) != 7 ||
		project.Audio.Cues[0] != (ProjectAudioCue{
			Event:  "actor.killed",
			Asset:  "audio.kill",
			Volume: 0.9,
		}) ||
		project.Audio.StageMusic[0] != (ProjectStageMusic{
			Stage:  "stage.action_room",
			Asset:  "audio.forest_theme",
			Volume: 0.75,
		}) {
		t.Fatalf("audio = %#v", project.Audio)
	}
	if err := first.ValidateProjectReferences(); err != nil {
		t.Fatalf("project references: %v", err)
	}
	invalidReferences := *first
	invalidReferences.Manifest = first.Project()
	invalidReferences.Manifest.Flow.StartSpawn = "missing"
	if err := invalidReferences.ValidateProjectReferences(); err == nil {
		t.Fatal("missing project start spawn passed reference validation")
	}
	wantWarningPaths := []string{
		"content_roots",
		"features",
		"impact_feedback",
		"maximum_action_depth",
		"maximum_steps",
	}
	if got := warningPaths(project.Warnings); !reflect.DeepEqual(got, wantWarningPaths) {
		t.Fatalf("project warning paths = %#v, want %#v", got, wantWarningPaths)
	}
	inputCopy := first.Project()
	inputCopy.Input.Actions[0].Keys[0] = "mutated"
	if first.Project().Input.Actions[0].Keys[0] == "mutated" {
		t.Fatal("Project leaked mutable input binding storage")
	}
	firstJSON, err := MarshalCanonical(first)
	if err != nil {
		t.Fatalf("MarshalCanonical first: %v", err)
	}
	secondJSON, err := MarshalCanonical(second)
	if err != nil {
		t.Fatalf("MarshalCanonical second: %v", err)
	}
	if !bytes.Equal(firstJSON, secondJSON) {
		t.Fatal("two compilations of the same source were not byte-identical")
	}

	loaded, err := LoadBytes(firstJSON)
	if err != nil {
		t.Fatalf("LoadBytes: %v", err)
	}
	roundTrip, err := MarshalCanonical(loaded)
	if err != nil {
		t.Fatalf("MarshalCanonical loaded: %v", err)
	}
	if !bytes.Equal(firstJSON, roundTrip) {
		t.Fatal("canonical JSON did not survive a decode/encode round trip")
	}

	ids := loaded.IDs()
	if len(ids) != 56 || !sort.StringsAreSorted(ids) {
		t.Fatalf("IDs are not complete and sorted: %v", ids)
	}
	if ids[0] != "ability.fire_bolt" ||
		ids[len(ids)-1] != "status.enraged" {
		t.Fatalf("unexpected ID bounds: %q .. %q", ids[0], ids[len(ids)-1])
	}
	for _, definition := range loaded.Definitions {
		if filepath.IsAbs(definition.Source) ||
			strings.Contains(definition.Source, `\`) ||
			!strings.HasPrefix(definition.Source, "game/content/") {
			t.Fatalf("source is not portable/project-relative: %q", definition.Source)
		}
	}

	assertEdge(
		t,
		loaded.Graph(),
		"actor.hero",
		"ability.fire_bolt",
		"components.action.combat_input.bindings[2].ability",
	)
	assertEdge(
		t,
		loaded.Graph(),
		"stage.world_hub",
		"stage.world_grove",
		"portals[1].target_stage",
	)
	assertNoEdge(
		t,
		loaded.Graph(),
		"quest.slime_patrol",
		"actor.slime",
		"objectives[1].where.actor_id",
	)
}

func TestCatalogRuntimeLookupDecodeAndFSLoad(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	writeProjectManifest(t, project, strings.Replace(
		testProjectManifest,
		"return {",
		"return {\n    future_setting=true,",
		1,
	))
	writeDefinition(t, project, "b.lua", `
return {
    schema_version = 1,
    kind = "actor",
    id = "actor.hero",
    name = "Hero",
    abilities = {"ability.slash"},
}`)
	writeDefinition(t, project, "a.lua", `
return {
    schema_version = 1,
    kind = "ability",
    id = "ability.slash",
    damage = 12,
}`)
	catalog, err := Compile(context.Background(), project)
	if err != nil {
		t.Fatalf("Compile: %v", err)
	}

	if got, want := catalog.IDs(), []string{"ability.slash", "actor.hero"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("IDs = %#v, want %#v", got, want)
	}
	raw, found := catalog.Definition("ability.slash")
	if !found {
		t.Fatal("Definition did not find ability.slash")
	}
	if !json.Valid(raw) || !bytes.Contains(raw, []byte(`"damage":12`)) {
		t.Fatalf("Definition returned invalid/unexpected JSON: %s", raw)
	}
	raw[0] = '['
	fresh, found := catalog.Definition("ability.slash")
	if !found || fresh[0] != '{' {
		t.Fatal("Definition leaked mutable raw JSON storage")
	}

	var ability struct {
		SchemaVersion int    `json:"schema_version"`
		Kind          string `json:"kind"`
		ID            string `json:"id"`
		Damage        int    `json:"damage"`
	}
	if err := catalog.Decode("ability.slash", &ability); err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if ability.ID != "ability.slash" || ability.Damage != 12 {
		t.Fatalf("decoded ability = %+v", ability)
	}
	if err := catalog.Decode("missing.id", &ability); err == nil {
		t.Fatal("Decode accepted a missing ID")
	}
	if err := catalog.Decode("ability.slash", nil); err == nil {
		t.Fatal("Decode accepted a nil target")
	}

	graphCopy := catalog.Graph()
	graphCopy.Nodes[0].ID = "mutated"
	if catalog.Graph().Nodes[0].ID == "mutated" {
		t.Fatal("Graph leaked mutable node storage")
	}
	projectCopy := catalog.Project()
	projectCopy.Warnings[0].Path = "mutated"
	if catalog.Project().Warnings[0].Path == "mutated" {
		t.Fatal("Project leaked mutable warning storage")
	}

	data, err := MarshalCanonical(catalog)
	if err != nil {
		t.Fatalf("MarshalCanonical: %v", err)
	}
	memoryFS := fstest.MapFS{
		"game/catalog.json": &fstest.MapFile{Data: data},
	}
	loaded, err := LoadFS(memoryFS, "game/catalog.json")
	if err != nil {
		t.Fatalf("LoadFS: %v", err)
	}
	if got := loaded.IDs(); !reflect.DeepEqual(got, catalog.IDs()) {
		t.Fatalf("loaded IDs = %#v, want %#v", got, catalog.IDs())
	}

	output := filepath.Join(t.TempDir(), "nested", "catalog.json")
	if err := WriteCanonical(output, catalog); err != nil {
		t.Fatalf("WriteCanonical: %v", err)
	}
	fromFile, err := LoadFile(output)
	if err != nil {
		t.Fatalf("LoadFile: %v", err)
	}
	if !reflect.DeepEqual(fromFile.IDs(), catalog.IDs()) {
		t.Fatalf("LoadFile IDs = %#v", fromFile.IDs())
	}
	info, err := os.Stat(output)
	if err != nil {
		t.Fatalf("Stat output: %v", err)
	}
	if got := info.Mode().Perm(); got != 0o644 {
		t.Fatalf("catalog permissions = %o, want 644", got)
	}
}

func TestWithDefinitionIsTransactionalAndRebuildsGraph(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	writeDefinition(t, project, "slash.lua", `
return {
    schema_version = 1,
    kind = "ability",
    id = "ability.slash",
}`)
	writeDefinition(t, project, "guard.lua", `
return {
    schema_version = 1,
    kind = "ability",
    id = "ability.guard",
}`)
	writeDefinition(t, project, "hero.lua", `
return {
    schema_version = 1,
    kind = "actor",
    id = "actor.hero",
    primary = "ability.slash",
}`)
	catalog, err := Compile(context.Background(), project)
	if err != nil {
		t.Fatal(err)
	}
	assertEdge(t, catalog.Graph(), "actor.hero", "ability.slash", "primary")

	candidate, err := catalog.WithDefinition(
		"actor.hero",
		json.RawMessage(`{
            "schema_version": 1,
            "kind": "actor",
            "id": "actor.hero",
            "primary": "ability.guard"
        }`),
	)
	if err != nil {
		t.Fatal(err)
	}
	assertEdge(t, candidate.Graph(), "actor.hero", "ability.guard", "primary")
	assertNoEdge(t, candidate.Graph(), "actor.hero", "ability.slash", "primary")
	assertEdge(t, catalog.Graph(), "actor.hero", "ability.slash", "primary")
	assertNoEdge(t, catalog.Graph(), "actor.hero", "ability.guard", "primary")

	for _, invalid := range []json.RawMessage{
		json.RawMessage(`{"kind":"actor","id":"actor.other"}`),
		json.RawMessage(`{"kind":"quest","id":"actor.hero"}`),
		json.RawMessage(`{"kind":"actor","id":"actor.hero"} {}`),
	} {
		if _, err := catalog.WithDefinition("actor.hero", invalid); err == nil {
			t.Fatalf("WithDefinition accepted invalid draft: %s", invalid)
		}
	}
}

func TestCompileRejectsImpureOrMalformedLua(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		source   string
		contains string
	}{
		{
			name: "function value",
			source: `return {
schema_version=1, kind="test", id="test.bad", callback=function() end}`,
			contains: "forbidden function value",
		},
		{
			name: "global library",
			source: `return {
schema_version=1, kind="test", id="test.bad", home=os.getenv("HOME")}`,
			contains: "evaluate Lua",
		},
		{
			name: "require",
			source: `local x = require("anything")
return {schema_version=1, kind="test", id="test.bad", x=x}`,
			contains: "evaluate Lua",
		},
		{
			name: "mixed keys",
			source: `return {
schema_version=1, kind="test", id="test.bad", values={[1]="a", name="b"}}`,
			contains: "must not mix string and numeric keys",
		},
		{
			name: "gapped array",
			source: `return {
schema_version=1, kind="test", id="test.bad", values={[1]="a", [3]="b"}}`,
			contains: "contiguous 1-based array",
		},
		{
			name: "fractional array key",
			source: `return {
schema_version=1, kind="test", id="test.bad", values={[1.5]="a"}}`,
			contains: "contiguous 1-based array",
		},
		{
			name: "boolean key",
			source: `return {
schema_version=1, kind="test", id="test.bad", values={[true]="a"}}`,
			contains: "forbidden boolean key",
		},
		{
			name: "non finite number",
			source: `return {
schema_version=1, kind="test", id="test.bad", value=0/0}`,
			contains: "non-finite number",
		},
		{
			name: "multiple returns",
			source: `return {
schema_version=1, kind="test", id="test.bad"}, "extra"`,
			contains: "must return exactly one value",
		},
		{
			name:     "top level array",
			source:   `return {"not", "an", "object"}`,
			contains: "content file must return an object",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			project := newProject(t)
			writeDefinition(t, project, "bad.lua", test.source)
			_, err := Compile(context.Background(), project)
			if err == nil || !strings.Contains(err.Error(), test.contains) {
				t.Fatalf("Compile error = %v, want substring %q", err, test.contains)
			}
		})
	}
}

func TestCompileUsesIsolatedEnvironmentsAndDeadline(t *testing.T) {
	t.Parallel()

	t.Run("isolated environments", func(t *testing.T) {
		project := newProject(t)
		writeDefinition(t, project, "a.lua", `
secret = "leak"
return {schema_version=1, kind="test", id="test.a"}`)
		writeDefinition(t, project, "b.lua", `
return {
    schema_version=1,
    kind="test",
    id="test.b",
    leaked=secret .. "!"
}`)
		_, err := Compile(context.Background(), project)
		if err == nil || !strings.Contains(err.Error(), "evaluate Lua") {
			t.Fatalf("Compile error = %v, want isolated-global failure", err)
		}
	})

	t.Run("deadline", func(t *testing.T) {
		project := newProject(t)
		writeDefinition(t, project, "loop.lua", `
while true do end
return {schema_version=1, kind="test", id="test.loop"}`)
		_, err := (Compiler{
			EvaluationTimeout: 25 * time.Millisecond,
		}).Compile(context.Background(), project)
		if err == nil || !strings.Contains(err.Error(), "evaluation exceeded") {
			t.Fatalf("Compile error = %v, want evaluation deadline", err)
		}
	})

	t.Run("parent cancellation", func(t *testing.T) {
		project := newProject(t)
		writeDefinition(t, project, "safe.lua", `
return {schema_version=1, kind="test", id="test.safe"}`)
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		_, err := Compile(ctx, project)
		if err == nil || !strings.Contains(err.Error(), "context canceled") {
			t.Fatalf("Compile error = %v, want cancellation", err)
		}
	})
}

func TestCompileProjectManifestStrictValidation(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		source   string
		contains string
	}{
		{
			name:     "top level array",
			source:   `return {"not", "an", "object"}`,
			contains: "project manifest must return an object",
		},
		{
			name: "global access",
			source: `
return {
    id="test.project",
    title=os.getenv("HOME"),
}`,
			contains: "evaluate Lua",
		},
		{
			name: "missing fixed dt",
			source: strings.Replace(
				testProjectManifest,
				"    fixed_dt=1/60,\n",
				"",
				1,
			),
			contains: "fixed_dt is required",
		},
		{
			name: "bad fixed dt",
			source: strings.Replace(
				testProjectManifest,
				"fixed_dt=1/60",
				"fixed_dt=0",
				1,
			),
			contains: "fixed_dt must be 1/60",
		},
		{
			name: "unsupported fixed dt",
			source: strings.Replace(
				testProjectManifest,
				"fixed_dt=1/60",
				"fixed_dt=1/30",
				1,
			),
			contains: "runtime currently supports 60 TPS only",
		},
		{
			name: "stage mismatch",
			source: strings.Replace(
				testProjectManifest,
				`start_stage="stage.test"`,
				`start_stage="stage.other"`,
				1,
			),
			contains: "flow.start_stage must match initial_stage",
		},
		{
			name: "unknown locale field",
			source: strings.Replace(
				testProjectManifest,
				`fallback="locale.en"`,
				`fallback="locale.en", extra=true`,
				1,
			),
			contains: "locale.extra is not supported",
		},
		{
			name: "unknown flow copy field",
			source: strings.Replace(
				testProjectManifest,
				`message_key="flow.title.message"`,
				`message_key="flow.title.message", extra=true`,
				1,
			),
			contains: "flow.title.extra is not supported",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			project := newProject(t)
			writeProjectManifest(t, project, test.source)
			writeDefinition(
				t,
				project,
				"valid.lua",
				`return {schema_version=1, kind="test", id="test.valid"}`,
			)
			_, err := Compile(context.Background(), project)
			if err == nil || !strings.Contains(err.Error(), test.contains) {
				t.Fatalf(
					"Compile error = %v, want substring %q",
					err,
					test.contains,
				)
			}
		})
	}
}

func TestCompileProjectManifestSupportsOptionalGenreFeatures(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name         string
		locale       string
		wantDefault  string
		wantFallback string
	}{
		{
			name: "pure action without localization",
		},
		{
			name: "single locale is its own fallback",
			locale: `
    locale={
        default="locale.en",
    },`,
			wantDefault:  "locale.en",
			wantFallback: "locale.en",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			project := newProject(t)
			writeProjectManifest(t, project, `return {
    id="test.project",
    profile="action",
    title="Genre Project",
    initial_stage="stage.test",
    fixed_dt=1/60,`+test.locale+`
    flow={
        save_slot="campaign",
        start_stage="stage.test",
    },
}`)
			writeDefinition(
				t,
				project,
				"valid.lua",
				`return {schema_version=1, kind="test", id="test.valid"}`,
			)
			catalog, err := Compile(context.Background(), project)
			if err != nil {
				t.Fatal(err)
			}
			manifest := catalog.Project()
			if manifest.Locale.Default != test.wantDefault ||
				manifest.Locale.Fallback != test.wantFallback ||
				manifest.Flow.StartSpawn != "" ||
				manifest.Flow.Title != (ProjectFlowCopy{}) ||
				manifest.Flow.GameOver != (ProjectFlowCopy{}) ||
				manifest.Flow.Ending != (ProjectFlowCopy{}) ||
				manifest.Font != (ProjectFont{}) {
				t.Fatalf("optional manifest = %#v", manifest)
			}
		})
	}
}

func TestCompileProjectManifestWarningsAreExplicitAndDeterministic(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	writeProjectManifest(t, project, strings.Replace(
		testProjectManifest,
		"return {",
		"return {\n    z_future={enabled=true},\n    a_future=true,",
		1,
	))
	writeDefinition(
		t,
		project,
		"valid.lua",
		`return {schema_version=1, kind="test", id="test.valid"}`,
	)
	catalog, err := Compile(context.Background(), project)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := warningPaths(catalog.Project().Warnings), []string{
		"a_future",
		"z_future",
	}; !reflect.DeepEqual(got, want) {
		t.Fatalf("warning paths = %#v, want %#v", got, want)
	}
	for _, warning := range catalog.Project().Warnings {
		if warning.Code != unsupportedProjectFieldCode ||
			warning.Message != unsupportedProjectFieldText {
			t.Fatalf("unexpected warning: %#v", warning)
		}
	}
}

func TestCompileProjectInputContract(t *testing.T) {
	t.Parallel()

	const validInput = `
    input={
        actions={
            attack={keys={"z", "space"}, buttons={"x"}},
            debug_overlay={keys={"f1"}, buttons={}},
        },
    },
`
	tests := []struct {
		name       string
		input      string
		wantError  string
		wantAction []ProjectInputAction
	}{
		{
			name:  "canonical",
			input: validInput,
			wantAction: []ProjectInputAction{
				{
					ID:      "attack",
					Keys:    []string{"space", "z"},
					Buttons: []string{"x"},
				},
				{
					ID:      "debug_overlay",
					Keys:    []string{"f1"},
					Buttons: []string{},
				},
			},
		},
		{
			name: "duplicate key",
			input: `
    input={actions={attack={keys={"z", "z"}, buttons={"x"}}}},
`,
			wantError: `contains duplicate value "z"`,
		},
		{
			name: "missing buttons",
			input: `
    input={actions={attack={keys={"z"}}}},
`,
			wantError: "attack.buttons is required",
		},
		{
			name: "unknown binding field",
			input: `
    input={actions={attack={
        keys={"z"}, buttons={"x"}, axis="leftx",
    }}},
`,
			wantError: "attack.axis is not supported",
		},
		{
			name: "invalid action id",
			input: `
    input={actions={Attack={keys={"z"}, buttons={"x"}}}},
`,
			wantError: "input.actions[1].id is invalid",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			project := newProject(t)
			manifest := strings.Replace(
				testProjectManifest,
				"    font={",
				test.input+"    font={",
				1,
			)
			writeProjectManifest(t, project, manifest)
			writeDefinition(
				t,
				project,
				"valid.lua",
				`return {schema_version=1, kind="test", id="test.valid"}`,
			)
			catalog, err := Compile(context.Background(), project)
			if test.wantError != "" {
				if err == nil ||
					!strings.Contains(err.Error(), test.wantError) {
					t.Fatalf(
						"Compile error = %v, want %q",
						err,
						test.wantError,
					)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got := catalog.Project().Input.Actions; !reflect.DeepEqual(
				got,
				test.wantAction,
			) {
				t.Fatalf("input actions = %#v, want %#v", got, test.wantAction)
			}
		})
	}
}

func TestLoadNormalizesCatalogsBeforeCompiledInputManifest(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	writeDefinition(
		t,
		project,
		"valid.lua",
		`return {schema_version=1, kind="test", id="test.valid"}`,
	)
	catalog, err := Compile(context.Background(), project)
	if err != nil {
		t.Fatal(err)
	}
	data, err := MarshalCanonical(catalog)
	if err != nil {
		t.Fatal(err)
	}
	var legacy map[string]any
	if err := json.Unmarshal(data, &legacy); err != nil {
		t.Fatal(err)
	}
	projectData, ok := legacy["project"].(map[string]any)
	if !ok {
		t.Fatalf("project JSON = %#v", legacy["project"])
	}
	delete(projectData, "input")
	data, err = json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadBytes(data)
	if err != nil {
		t.Fatalf("LoadBytes legacy catalog: %v", err)
	}
	if got := loaded.Project().Input.Actions; got == nil || len(got) != 0 {
		t.Fatalf("normalized legacy input actions = %#v", got)
	}
}

func TestCompileRequiresRegularProjectManifest(t *testing.T) {
	t.Parallel()

	t.Run("missing", func(t *testing.T) {
		project := newProject(t)
		if err := os.Remove(filepath.Join(project, "game", "game.lua")); err != nil {
			t.Fatal(err)
		}
		writeDefinition(
			t,
			project,
			"valid.lua",
			`return {schema_version=1, kind="test", id="test.valid"}`,
		)
		_, err := Compile(context.Background(), project)
		if err == nil || !strings.Contains(err.Error(), "inspect project manifest") {
			t.Fatalf("Compile error = %v, want missing manifest rejection", err)
		}
	})

	t.Run("symlink", func(t *testing.T) {
		project := newProject(t)
		manifestPath := filepath.Join(project, "game", "game.lua")
		if err := os.Remove(manifestPath); err != nil {
			t.Fatal(err)
		}
		external := filepath.Join(t.TempDir(), "game.lua")
		if err := os.WriteFile(external, []byte(testProjectManifest), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(external, manifestPath); err != nil {
			t.Skipf("symlink unavailable: %v", err)
		}
		writeDefinition(
			t,
			project,
			"valid.lua",
			`return {schema_version=1, kind="test", id="test.valid"}`,
		)
		_, err := Compile(context.Background(), project)
		if err == nil || !strings.Contains(err.Error(), "symbolic links are not allowed") {
			t.Fatalf("Compile error = %v, want manifest symlink rejection", err)
		}
	})
}

func TestLuaValueInspectionRejectsMetatableCycleAndUserdata(t *testing.T) {
	t.Parallel()

	state := lua.NewState(lua.Options{SkipOpenLibs: true})
	defer state.Close()

	tests := []struct {
		name     string
		value    func() lua.LValue
		contains string
	}{
		{
			name: "metatable",
			value: func() lua.LValue {
				table := state.NewTable()
				state.SetMetatable(table, state.NewTable())
				return table
			},
			contains: "must not have a metatable",
		},
		{
			name: "cycle",
			value: func() lua.LValue {
				table := state.NewTable()
				table.RawSetString("self", table)
				return table
			},
			contains: "table cycle",
		},
		{
			name: "userdata",
			value: func() lua.LValue {
				table := state.NewTable()
				table.RawSetString("native", state.NewUserData())
				return table
			},
			contains: "forbidden userdata value",
		},
		{
			name: "table key",
			value: func() lua.LValue {
				table := state.NewTable()
				table.RawSet(state.NewTable(), lua.LString("value"))
				return table
			},
			contains: "forbidden table key",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			_, err := convertLuaValue(
				state,
				test.value(),
				"content",
				make(map[*lua.LTable]string),
			)
			if err == nil || !strings.Contains(err.Error(), test.contains) {
				t.Fatalf("convertLuaValue error = %v, want %q", err, test.contains)
			}
		})
	}
}

func TestCompileValidationFailures(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		definitions []string
		contains    string
	}{
		{
			name: "duplicate id",
			definitions: []string{
				`return {schema_version=1, kind="test", id="test.same"}`,
				`return {schema_version=1, kind="other", id="test.same"}`,
			},
			contains: "duplicate id",
		},
		{
			name: "schema version",
			definitions: []string{
				`return {schema_version=2, kind="test", id="test.bad"}`,
			},
			contains: "schema_version must be 1",
		},
		{
			name: "empty kind",
			definitions: []string{
				`return {schema_version=1, kind="", id="test.bad"}`,
			},
			contains: "kind must be a non-empty string",
		},
		{
			name: "bad id",
			definitions: []string{
				`return {schema_version=1, kind="test", id="Bad ID"}`,
			},
			contains: "id must match namespace.name",
		},
		{
			name: "oversized id",
			definitions: []string{
				`return {schema_version=1, kind="test", id="test.` +
					strings.Repeat("x", MaxContentIDBytes) + `"}`,
			},
			contains: "at most 128 bytes",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			project := newProject(t)
			for index, source := range test.definitions {
				writeDefinition(
					t,
					project,
					filepath.Join("nested", string(rune('a'+index))+".lua"),
					source,
				)
			}
			_, err := Compile(context.Background(), project)
			if err == nil || !strings.Contains(err.Error(), test.contains) {
				t.Fatalf("Compile error = %v, want substring %q", err, test.contains)
			}
		})
	}
}

func TestGraphMatchesExistingIDsWithoutTreatingRuntimeIDsAsEdges(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	writeDefinition(t, project, "target.lua", `
return {schema_version=1, kind="actor", id="actor.target"}`)
	writeDefinition(t, project, "source.lua", `
return {
    schema_version=1,
    kind="quest",
    id="quest.source",
    direct="actor.target",
    list={"actor.target"},
    where={actor_id="actor.target"},
    unrelated="actor.missing",
}`)
	catalog, err := Compile(context.Background(), project)
	if err != nil {
		t.Fatalf("Compile: %v", err)
	}
	if got, want := catalog.DependencyGraph.EdgeCount, 2; got != want {
		t.Fatalf("edge count = %d, want %d", got, want)
	}
	graph := catalog.Graph()
	assertEdge(t, graph, "quest.source", "actor.target", "direct")
	assertEdge(t, graph, "quest.source", "actor.target", "list[1]")
	assertNoEdge(t, graph, "quest.source", "actor.target", "where.actor_id")

	target := graphNode(t, graph, "actor.target")
	wantDependents := []Edge{
		{ID: "quest.source", Path: "direct"},
		{ID: "quest.source", Path: "list[1]"},
	}
	if !reflect.DeepEqual(target.Dependents, wantDependents) {
		t.Fatalf("dependents = %#v, want %#v", target.Dependents, wantDependents)
	}
}

func TestCompileRejectsSymlinkedContent(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	external := filepath.Join(t.TempDir(), "external.lua")
	if err := os.WriteFile(
		external,
		[]byte(`return {schema_version=1, kind="test", id="test.bad"}`),
		0o644,
	); err != nil {
		t.Fatalf("write external definition: %v", err)
	}
	link := filepath.Join(project, "game", "content", "linked.lua")
	if err := os.Symlink(external, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	_, err := Compile(context.Background(), project)
	if err == nil || !strings.Contains(err.Error(), "symbolic links are not allowed") {
		t.Fatalf("Compile error = %v, want symlink rejection", err)
	}
}

func TestLoadRejectsCorruptOrNonCanonicalGraphContract(t *testing.T) {
	t.Parallel()

	project := newProject(t)
	writeDefinition(t, project, "a.lua", `
return {schema_version=1, kind="test", id="test.a", target="test.b"}`)
	writeDefinition(t, project, "b.lua", `
return {schema_version=1, kind="test", id="test.b"}`)
	catalog, err := Compile(context.Background(), project)
	if err != nil {
		t.Fatalf("Compile: %v", err)
	}

	tests := []struct {
		name   string
		mutate func(*Catalog)
	}{
		{
			name: "invalid project source",
			mutate: func(candidate *Catalog) {
				candidate.Manifest.Source = "/tmp/game.lua"
			},
		},
		{
			name: "invalid project stage",
			mutate: func(candidate *Catalog) {
				candidate.Manifest.InitialStage = "stage.other"
			},
		},
		{
			name: "unsorted project warnings",
			mutate: func(candidate *Catalog) {
				candidate.Manifest.Warnings = []ProjectManifestWarning{
					{
						Code:    unsupportedProjectFieldCode,
						Path:    "z",
						Message: unsupportedProjectFieldText,
					},
					{
						Code:    unsupportedProjectFieldCode,
						Path:    "a",
						Message: unsupportedProjectFieldText,
					},
				}
			},
		},
		{
			name: "missing reverse edge",
			mutate: func(candidate *Catalog) {
				candidate.DependencyGraph.Nodes[1].Dependents = []Edge{}
			},
		},
		{
			name: "wrong node kind",
			mutate: func(candidate *Catalog) {
				candidate.DependencyGraph.Nodes[0].Kind = "wrong"
			},
		},
		{
			name: "duplicate edge",
			mutate: func(candidate *Catalog) {
				edge := candidate.DependencyGraph.Nodes[0].Dependencies[0]
				candidate.DependencyGraph.Nodes[0].Dependencies = append(
					candidate.DependencyGraph.Nodes[0].Dependencies,
					edge,
				)
				candidate.DependencyGraph.EdgeCount++
			},
		},
		{
			name: "absolute source",
			mutate: func(candidate *Catalog) {
				candidate.Definitions[0].Source = "/tmp/definition.lua"
				candidate.DependencyGraph.Nodes[0].Source = "/tmp/definition.lua"
			},
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			copyCatalog := cloneCatalog(t, catalog)
			test.mutate(copyCatalog)
			data, err := json.Marshal(copyCatalog)
			if err != nil {
				t.Fatalf("json.Marshal: %v", err)
			}
			if _, err := LoadBytes(data); err == nil {
				t.Fatal("LoadBytes accepted a corrupt catalog")
			}
		})
	}

	valid, err := MarshalCanonical(catalog)
	if err != nil {
		t.Fatalf("MarshalCanonical: %v", err)
	}
	if _, err := LoadBytes(append(valid, []byte(`{"extra":true}`)...)); err == nil {
		t.Fatal("LoadBytes accepted a trailing JSON value")
	}
	unknown := bytes.Replace(
		valid,
		[]byte(`"schema_version": 2,`),
		[]byte(`"schema_version": 2, "unknown": true,`),
		1,
	)
	if _, err := LoadBytes(unknown); err == nil {
		t.Fatal("LoadBytes accepted an unknown catalog field")
	}
	unknownProject := bytes.Replace(
		valid,
		[]byte(`"source": "game/game.lua",`),
		[]byte(`"source": "game/game.lua", "unknown": true,`),
		1,
	)
	if _, err := LoadBytes(unknownProject); err == nil {
		t.Fatal("LoadBytes accepted an unknown project field")
	}
}

func recreateProject(t *testing.T) string {
	t.Helper()
	workingDirectory, err := os.Getwd()
	if err != nil {
		t.Fatalf("get test working directory: %v", err)
	}
	project := filepath.Clean(filepath.Join(
		workingDirectory,
		"..",
		"..",
		"..",
		"32_recreate",
	))
	if _, err := os.Stat(filepath.Join(project, "game", "content")); err != nil {
		t.Fatalf("locate 32_recreate: %v", err)
	}
	return project
}

func newProject(t *testing.T) string {
	t.Helper()
	project := t.TempDir()
	if err := os.MkdirAll(
		filepath.Join(project, "game", "content"),
		0o755,
	); err != nil {
		t.Fatalf("create content directory: %v", err)
	}
	writeProjectManifest(t, project, testProjectManifest)
	return project
}

const testProjectManifest = `return {
    id="test.project",
    profile="test",
    title="Test Project",
    initial_stage="stage.test",
    fixed_dt=1/60,
    locale={
        default="locale.en",
        fallback="locale.en",
    },
    flow={
        save_slot="test",
        start_stage="stage.test",
        start_spawn="default",
        title={
            heading_key="flow.title.heading",
            message_key="flow.title.message",
        },
        game_over={
            heading_key="flow.game_over.heading",
            message_key="flow.game_over.message",
        },
        ending={
            heading_key="flow.ending.heading",
            message_key="flow.ending.message",
        },
    },
    font={
        asset="font.ui",
        size=16,
    },
}`

func writeProjectManifest(t *testing.T, project, source string) {
	t.Helper()
	path := filepath.Join(project, "game", "game.lua")
	if err := os.WriteFile(path, []byte(source), 0o644); err != nil {
		t.Fatalf("write project manifest: %v", err)
	}
}

func writeDefinition(t *testing.T, project, relative, source string) {
	t.Helper()
	path := filepath.Join(project, "game", "content", relative)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("create definition directory: %v", err)
	}
	if err := os.WriteFile(path, []byte(source), 0o644); err != nil {
		t.Fatalf("write definition: %v", err)
	}
}

func graphNode(t *testing.T, graph Graph, id string) Node {
	t.Helper()
	for _, node := range graph.Nodes {
		if node.ID == id {
			return node
		}
	}
	t.Fatalf("graph node %q not found", id)
	return Node{}
}

func assertEdge(t *testing.T, graph Graph, source, target, path string) {
	t.Helper()
	node := graphNode(t, graph, source)
	for _, edge := range node.Dependencies {
		if edge.ID == target && edge.Path == path {
			return
		}
	}
	t.Fatalf("%s -> %s at %s not found in %#v", source, target, path, node.Dependencies)
}

func assertNoEdge(t *testing.T, graph Graph, source, target, path string) {
	t.Helper()
	node := graphNode(t, graph, source)
	for _, edge := range node.Dependencies {
		if edge.ID == target && edge.Path == path {
			t.Fatalf("unexpected %s -> %s at %s", source, target, path)
		}
	}
}

func cloneCatalog(t *testing.T, catalog *Catalog) *Catalog {
	t.Helper()
	data, err := json.Marshal(catalog)
	if err != nil {
		t.Fatalf("json.Marshal catalog: %v", err)
	}
	var clone Catalog
	if err := json.Unmarshal(data, &clone); err != nil {
		t.Fatalf("json.Unmarshal catalog: %v", err)
	}
	return &clone
}

func warningPaths(warnings []ProjectManifestWarning) []string {
	paths := make([]string, len(warnings))
	for index, warning := range warnings {
		paths[index] = warning.Path
	}
	return paths
}
