package gamebuild

import (
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestBuildTranslatesRectangleActorBodies(t *testing.T) {
	t.Parallel()

	result, err := Build(loadCatalog(t), Options{
		StageID:  "stage.action_room",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	var center sim.EntityConfig
	for _, entity := range result.Config.Entities {
		if entity.ID == "wall.center" {
			center = entity
			break
		}
	}
	if center.ID == "" {
		t.Fatal("wall.center is missing")
	}
	if center.Body.HalfWidth != sim.Pixels(38) ||
		center.Body.HalfHeight != sim.Pixels(90) ||
		!center.Body.Solid {
		t.Fatalf("wall.center body = %#v", center.Body)
	}
	if _, err := sim.New(result.Config); err != nil {
		t.Fatalf("rectangle body config is not runnable: %v", err)
	}
}

func TestBuildRoundsFractionalRectangleBodiesToFixedPoint(t *testing.T) {
	t.Parallel()

	catalog := mutateActionRoomWallBody(
		t,
		loadCatalog(t),
		func(body map[string]any) {
			body["width"] = 75.25
			body["height"] = 181.5
		},
	)
	result, err := Build(catalog, Options{
		StageID:  "stage.action_room",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	var got sim.Body
	for _, entity := range result.Config.Entities {
		if entity.ID == "wall.center" {
			got = entity.Body
			break
		}
	}
	if got.HalfWidth != pixels(75.25/2) ||
		got.HalfHeight != pixels(181.5/2) {
		t.Fatalf("fractional rectangle body = %#v", got)
	}
}

func TestBuildRejectsInvalidRectangleBodyDimensions(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		width  float64
		height float64
		want   string
	}{
		{
			name:   "zero width",
			width:  0,
			height: 10,
			want:   "requires positive width and height",
		},
		{
			name:   "negative height",
			width:  10,
			height: -1,
			want:   "requires positive width and height",
		},
		{
			name:   "fixed point overflow",
			width:  1 << 30,
			height: 10,
			want:   "outside deterministic range",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := mutateActionRoomWallBody(
				t,
				loadCatalog(t),
				func(body map[string]any) {
					body["width"] = test.width
					body["height"] = test.height
				},
			)
			_, err := Build(catalog, Options{
				StageID:  "stage.action_room",
				SpawnID:  "default",
				LocaleID: "locale.ko",
			})
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("Build() error = %v, want %q", err, test.want)
			}
		})
	}
}

func mutateActionRoomWallBody(
	t *testing.T,
	catalog *content.Catalog,
	mutate func(map[string]any),
) *content.Catalog {
	t.Helper()
	return mutateCampaignDefinition(
		t,
		catalog,
		"stage.action_room",
		func(data map[string]any) {
			spawns := data["spawns"].([]any)
			components := spawns[3].(map[string]any)["components"].(map[string]any)
			body := components["body"].(map[string]any)
			mutate(body)
		},
	)
}
