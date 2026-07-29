package gamebuild

import (
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestBuildUsesLegacyCameraDefaultWithoutClamping(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	result, err := Build(catalog, Options{
		StageID:  "stage.action_room",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Config.Camera.ViewportWidth != sim.Pixels(defaultViewportWidth) ||
		result.Config.Camera.ViewportHeight != sim.Pixels(defaultViewportHeight) {
		t.Fatalf("default camera = %#v", result.Config.Camera)
	}
	if result.Config.Camera.TargetEntityID != "player" {
		t.Fatalf(
			"default camera target = %q, want controlled player",
			result.Config.Camera.TargetEntityID,
		)
	}

	tooSmall := mutateCampaignDefinition(
		t,
		catalog,
		"stage.action_room",
		func(data map[string]any) {
			data["width"] = float64(defaultViewportWidth - 1)
		},
	)
	_, err = Build(tooSmall, Options{
		StageID:  "stage.action_room",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err == nil || !strings.Contains(err.Error(), "exceeds stage bounds") {
		t.Fatalf("Build() error = %v, want viewport bounds error", err)
	}
}
