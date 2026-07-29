package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestProjectSlugIsSafeAndStable(t *testing.T) {
	tests := map[string]string{
		"My Action RPG": "my_action_rpg",
		"123-demo":      "game_123_demo",
		"___":           "game",
	}
	for input, expected := range tests {
		if actual := projectSlug(input); actual != expected {
			t.Fatalf(
				"projectSlug(%q) = %q, want %q",
				input,
				actual,
				expected,
			)
		}
	}
}

func TestInitCreatesEachIndependentProfileWithoutOverwrite(t *testing.T) {
	source, err := findProject("")
	if err != nil {
		t.Fatal(err)
	}
	for _, profile := range []string{"rpg", "action-rpg", "action"} {
		t.Run(profile, func(t *testing.T) {
			target := filepath.Join(t.TempDir(), "maker-"+profile)
			if err := runInit(source, []string{
				"--profile", profile,
				"--title", `Maker "Test"`,
				target,
			}); err != nil {
				t.Fatal(err)
			}
			if _, err := validateProject(target); err != nil {
				t.Fatal(err)
			}
			manifest, err := os.ReadFile(filepath.Join(
				target,
				"game",
				"game.lua",
			))
			if err != nil {
				t.Fatal(err)
			}
			text := string(manifest)
			for _, expected := range []string{
				`profile = "` + profile + `"`,
				`title = "Maker \"Test\""`,
				`initial_stage = "stage.start"`,
				`"engine.features.game_flow"`,
				`save_slot = "campaign"`,
				`start_stage = "stage.start"`,
				`pause = {`,
			} {
				if !strings.Contains(text, expected) {
					t.Fatalf("manifest lacks %q:\n%s", expected, text)
				}
			}
			if _, err := os.Stat(filepath.Join(
				target,
				"game",
				"tests",
				"smoke.json",
			)); err != nil {
				t.Fatal(err)
			}
			if _, err := os.Stat(filepath.Join(
				target,
				"engine",
				"core",
				"app.lua",
			)); err != nil {
				t.Fatal(err)
			}
			if err := runInit(source, []string{
				"--profile", profile,
				target,
			}); err == nil {
				t.Fatal("expected init to refuse an existing target")
			}
		})
	}
}

func TestInitRejectsInvalidProfileAndMultilineTitle(t *testing.T) {
	if _, err := parseInitOptions([]string{
		"--profile", "platformer",
		"game",
	}); err == nil {
		t.Fatal("expected invalid profile error")
	}
	if _, err := parseInitOptions([]string{
		"--profile", "rpg",
		"--title", "bad\ntitle",
		"game",
	}); err == nil {
		t.Fatal("expected multiline title error")
	}
}
