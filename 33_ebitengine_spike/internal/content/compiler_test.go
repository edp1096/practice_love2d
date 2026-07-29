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

	if got, want := first.DependencyGraph.Total, 44; got != want {
		t.Fatalf("definition total = %d, want %d", got, want)
	}
	if got, want := first.DependencyGraph.EdgeCount, 86; got != want {
		t.Fatalf("dependency paths = %d, want %d", got, want)
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
	if len(ids) != 44 || !sort.StringsAreSorted(ids) {
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
		[]byte(`"schema_version": 1,`),
		[]byte(`"schema_version": 1, "unknown": true,`),
		1,
	)
	if _, err := LoadBytes(unknown); err == nil {
		t.Fatal("LoadBytes accepted an unknown catalog field")
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
	return project
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
