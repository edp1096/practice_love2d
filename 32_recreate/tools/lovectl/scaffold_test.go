package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestScaffoldCreatesOneAutoDiscoveredContentFile(t *testing.T) {
	root := t.TempDir()
	if err := runScaffold(root, []string{"actor", "training_dummy"}); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(
		root,
		"game",
		"content",
		"actors",
		"training_dummy.lua",
	)
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(contents), `id = "actor.training_dummy"`) {
		t.Fatalf("unexpected scaffold:\n%s", contents)
	}
	if err := runScaffold(
		root,
		[]string{"actor", "training_dummy"},
	); err == nil {
		t.Fatal("expected scaffold to refuse overwrite")
	}
}

func TestScaffoldRejectsUnsafeName(t *testing.T) {
	if err := runScaffold(
		t.TempDir(),
		[]string{"actor", "../bad"},
	); err == nil {
		t.Fatal("expected unsafe name to be rejected")
	}
}

func TestAbilityScaffoldUsesTemporalHitboxSchema(t *testing.T) {
	root := t.TempDir()
	if err := runScaffold(root, []string{"ability", "heavy_slash"}); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(
		root,
		"game",
		"content",
		"abilities",
		"heavy_slash.lua",
	)
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(contents)
	for _, expected := range []string{
		`hitbox = {`,
		`shape = "arc"`,
		`reach = 40`,
		`recovery = 0.15`,
	} {
		if !strings.Contains(text, expected) {
			t.Fatalf("ability scaffold lacks %q:\n%s", expected, text)
		}
	}
	if strings.Contains(text, "\n    range = ") {
		t.Fatalf("ability scaffold uses obsolete range field:\n%s", text)
	}
}

func TestRPGScaffoldsCreateTheExpectedContentKinds(t *testing.T) {
	tests := []struct {
		template  string
		directory string
		name      string
		expected  []string
	}{
		{
			template:  "item",
			directory: "items",
			name:      "ether",
			expected: []string{
				`kind = "item"`,
				`id = "item.ether"`,
				`stack_limit = 99`,
			},
		},
		{
			template:  "equipment",
			directory: "items",
			name:      "iron_sword",
			expected: []string{
				`kind = "item"`,
				`id = "item.iron_sword"`,
				`equipment = {`,
				`slot = "weapon"`,
			},
		},
		{
			template:  "dialogue",
			directory: "dialogues",
			name:      "blacksmith",
			expected: []string{
				`kind = "dialogue"`,
				`id = "dialogue.blacksmith"`,
				`start = "start"`,
			},
		},
		{
			template:  "quest",
			directory: "quests",
			name:      "find_ore",
			expected: []string{
				`kind = "quest"`,
				`id = "quest.find_ore"`,
				`event = "quest.find_ore.progress"`,
			},
		},
		{
			template:  "locale",
			directory: "locales",
			name:      "ja",
			expected: []string{
				`kind = "locale"`,
				`id = "locale.ja"`,
				`code = "ja"`,
			},
		},
	}

	for _, test := range tests {
		t.Run(test.template, func(t *testing.T) {
			root := t.TempDir()
			if err := runScaffold(
				root,
				[]string{test.template, test.name},
			); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(
				root,
				"game",
				"content",
				test.directory,
				test.name+".lua",
			)
			contents, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			text := string(contents)
			for _, expected := range test.expected {
				if !strings.Contains(text, expected) {
					t.Fatalf(
						"%s scaffold lacks %q:\n%s",
						test.template,
						expected,
						text,
					)
				}
			}
		})
	}
}

func TestReferenceScaffoldsRequireTheCorrectContentKind(t *testing.T) {
	tests := []struct {
		template  string
		reference string
		expected  string
	}{
		{"projectile", "actor.magic_orb", `actor = "actor.magic_orb"`},
		{"encounter", "actor.slime", `actor = "actor.slime"`},
		{"shop", "item.potion", `item = "item.potion"`},
	}

	for _, test := range tests {
		t.Run(test.template, func(t *testing.T) {
			root := t.TempDir()
			if err := runScaffold(
				root,
				[]string{test.template, "example", test.reference},
			); err != nil {
				t.Fatal(err)
			}
			template := contentTemplates[test.template]
			contents, err := os.ReadFile(filepath.Join(
				root,
				"game",
				"content",
				template.directory,
				"example.lua",
			))
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(contents), test.expected) {
				t.Fatalf("scaffold lacks %q:\n%s", test.expected, contents)
			}
		})
	}

	if err := runScaffold(
		t.TempDir(),
		[]string{"shop", "bad_shop", "actor.slime"},
	); err == nil || !strings.Contains(err.Error(), "item.*") {
		t.Fatalf("expected item reference error, got %v", err)
	}
	if err := runScaffold(
		t.TempDir(),
		[]string{"projectile", "missing_reference"},
	); err == nil || !strings.Contains(err.Error(), "ACTOR_ID") {
		t.Fatalf("expected projectile usage error, got %v", err)
	}
}

func TestStatusScaffoldUsesAValidNonPeriodicDefault(t *testing.T) {
	root := t.TempDir()
	if err := runScaffold(root, []string{"status", "slowed"}); err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(filepath.Join(
		root,
		"game",
		"content",
		"statuses",
		"slowed.lua",
	))
	if err != nil {
		t.Fatal(err)
	}
	text := string(contents)
	for _, expected := range []string{
		`duration = 1.0`,
		`stacking = "refresh"`,
		`move_speed = 0.9`,
	} {
		if !strings.Contains(text, expected) {
			t.Fatalf("status scaffold lacks %q:\n%s", expected, text)
		}
	}
}
