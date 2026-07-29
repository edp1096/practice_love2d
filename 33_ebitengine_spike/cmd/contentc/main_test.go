package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestRunValidatesCompleteProjectBeforeWriting(t *testing.T) {
	t.Parallel()

	output := filepath.Join(t.TempDir(), "catalog.json")
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	status := run([]string{
		"-source", sourceProject(t),
		"-output", output,
	}, &stdout, &stderr)
	if status != 0 {
		t.Fatalf("run() status = %d, stderr = %s", status, stderr.String())
	}
	if !strings.Contains(
		stdout.String(),
		"7 stages, 22 entry builds and 44 derived campaign builds "+
			"across 2 locales",
	) {
		t.Fatalf("run() stdout = %q", stdout.String())
	}
	catalog, err := content.LoadFile(output)
	if err != nil {
		t.Fatalf("written catalog: %v", err)
	}
	if catalog.Project().ID != "recreate.maker_runtime" {
		t.Fatalf("written project = %#v", catalog.Project())
	}
}

func TestRunDoesNotReplaceOutputWhenProjectValidationFails(t *testing.T) {
	t.Parallel()

	const maximum = "9007199254740991"
	tests := []struct {
		name      string
		mutations []projectSourceMutation
		want      []string
	}{
		{
			name: "fractional equipment modifier",
			mutations: []projectSourceMutation{{
				path: "game/content/items/training_sword.lua",
				old:  "attack = 5,",
				new:  "attack = 1.5,",
			}},
			want: []string{
				`definition "item.training_sword"`,
				"equipment.modifiers.attack must be an integer",
			},
		},
		{
			name: "invalid equipment topology",
			mutations: []projectSourceMutation{{
				path: "game/content/items/training_sword.lua",
				old:  `slot = "weapon",`,
				new: `slot = "` +
					strings.Repeat("x", 129) + `",`,
			}},
			want: []string{
				"campaign topology",
				"equipment slot",
				"is invalid",
			},
		},
		{
			name: "later equipment masked negative final damage",
			mutations: []projectSourceMutation{
				{
					path: "game/content/items/potion.lua",
					old:  "    value = 25,",
					new: "    equipment = {\n" +
						`        slot = "armor",` + "\n" +
						"        modifiers = {\n" +
						"            attack = 100,\n" +
						"        },\n" +
						"    },\n" +
						"    value = 25,",
				},
				{
					path: "game/content/items/training_sword.lua",
					old:  "attack = 5,",
					new:  "attack = -34,",
				},
			},
			want: []string{
				`campaign profile "item.training_sword" build`,
				"effective attack damage must be positive",
			},
		},
		{
			name: "later equipment effective damage overflow",
			mutations: []projectSourceMutation{
				{
					path: "game/content/items/potion.lua",
					old:  "    value = 25,",
					new: "    equipment = {\n" +
						`        slot = "weapon",` + "\n" +
						"        modifiers = {\n" +
						"            attack = 0,\n" +
						"        },\n" +
						"    },\n" +
						"    value = 25,",
				},
				{
					path: "game/content/items/training_sword.lua",
					old:  "attack = 5,",
					new:  "attack = " + maximum + ",",
				},
			},
			want: []string{
				`campaign profile "maximal" build`,
				"effective attack damage",
				"JSON-safe integer range",
			},
		},
		{
			name: "aggregate modifier overflow",
			mutations: []projectSourceMutation{
				{
					path: "game/content/items/training_sword.lua",
					old:  "attack = 5,",
					new:  "attack = " + maximum + ",",
				},
				{
					path: "game/content/items/potion.lua",
					old:  "    value = 25,",
					new: "    equipment = {\n" +
						`        slot = "armor",` + "\n" +
						"        modifiers = {\n" +
						"            attack = " + maximum + ",\n" +
						"        },\n" +
						"    },\n" +
						"    value = 25,",
				},
			},
			want: []string{
				`campaign profile "maximal" build`,
				"aggregate attack modifier",
				"JSON-safe integer range",
			},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			project := copySourceProject(t)
			for _, mutation := range test.mutations {
				replaceProjectSource(t, project, mutation)
			}

			output := filepath.Join(t.TempDir(), "catalog.json")
			sentinel := []byte("reviewed catalog must survive")
			if err := os.WriteFile(output, sentinel, 0o644); err != nil {
				t.Fatal(err)
			}
			var stdout bytes.Buffer
			var stderr bytes.Buffer
			status := run([]string{
				"-source", project,
				"-output", output,
			}, &stdout, &stderr)
			if status != 1 {
				t.Fatalf(
					"run() status = %d, stdout = %q, stderr = %q",
					status,
					stdout.String(),
					stderr.String(),
				)
			}
			for _, fragment := range append(
				[]string{`project "recreate.maker_runtime"`},
				test.want...,
			) {
				if !strings.Contains(stderr.String(), fragment) {
					t.Fatalf(
						"run() stderr = %q, want %q",
						stderr.String(),
						fragment,
					)
				}
			}
			got, err := os.ReadFile(output)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(got, sentinel) {
				t.Fatalf(
					"failed validation replaced output with %q",
					got,
				)
			}
		})
	}
}

type projectSourceMutation struct {
	path string
	old  string
	new  string
}

func copySourceProject(t *testing.T) string {
	t.Helper()
	project := t.TempDir()
	if err := os.CopyFS(project, os.DirFS(sourceProject(t))); err != nil {
		t.Fatal(err)
	}
	return project
}

func replaceProjectSource(
	t *testing.T,
	project string,
	mutation projectSourceMutation,
) {
	t.Helper()
	path := filepath.Join(project, filepath.FromSlash(mutation.path))
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	updated := strings.Replace(string(source), mutation.old, mutation.new, 1)
	if updated == string(source) {
		t.Fatalf("%s did not contain mutation target %q", path, mutation.old)
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		t.Fatal(err)
	}
}

func sourceProject(t *testing.T) string {
	t.Helper()
	result, err := filepath.Abs(filepath.Join("..", "..", "..", "32_recreate"))
	if err != nil {
		t.Fatal(err)
	}
	return result
}
